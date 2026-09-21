// CPU-A stage 1: the unit harness for the atomic backend and the V2 bridge -- three masters on one real node,
// a memory manager with real storage, scripted scenarios, and one event line per thing that happens, so that
// score.py can re-derive every expected value from the order that was actually observed.
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config._
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.tilelink._
import freechips.rocketchip.unittest._
import testchipip.TLHelper

// ---- a memory manager with storage: Get / PutFull / PutPartial of 1..16 bytes (up to two 8-byte beats),
// programmable response latency and A stalls, an error region (addresses matching errorMask): reads there
// return error, writes there are refused (not applied) and answered with error. One transaction at a time.
// writeErrMask: addresses matching it refuse *writes* only (reads succeed) -- the AMO read-ok/write-error case.
// atomics: advertise Arithmetic/Logical support itself (an MMIO device behind the peripheral-bus automata): the
// bridge must still refuse atomics there because the address is outside the DRAM window.
class AtomicManager(base: Long, words: Int, latency: Int, aStall: Int, errorMask: BigInt, tag: String,
                    writeErrMask: BigInt = 0, atomics: Boolean = false, dStall: Int = 0)(implicit p: Parameters) extends LazyModule {
  val device = new MemoryDevice
  val node = TLManagerNode(Seq(TLManagerPortParameters(Seq(TLManagerParameters(
    address = Seq(AddressSet(base, words * 8L - 1)), resources = device.reg, regionType = RegionType.UNCACHED,
    supportsGet = TransferSizes(1, 16), supportsPutFull = TransferSizes(1, 16), supportsPutPartial = TransferSizes(1, 16),
    supportsArithmetic = if (atomics) TransferSizes(4, 8) else TransferSizes.none,
    supportsLogical = if (atomics) TransferSizes(4, 8) else TransferSizes.none,
    fifoId = Some(0))), beatBytes = 8, minLatency = 1)))
  lazy val module = new LazyModuleImp(this) {
    val (tl, edge) = node.in(0)
    val cyc = RegInit(0.U(32.W)); cyc := cyc + 1.U
    val mem = Mem(words, UInt(64.W))
    val sIdle :: sBeats :: sWait :: sD :: Nil = Enum(4)
    val state = RegInit(sIdle)
    val src = Reg(UInt(tl.a.bits.source.getWidth.W)); val sz = Reg(UInt(tl.a.bits.size.getWidth.W))
    val isGet = Reg(Bool()); val addr = Reg(UInt(32.W)); val err = Reg(Bool()); val due = Reg(UInt(32.W))
    val dBeat = RegInit(0.U(2.W)); val nBeatsD = Reg(UInt(2.W))
    val stallN = RegInit(0.U(32.W))
    val stalling = (aStall > 0).B && tl.a.valid && (stallN < aStall.U)
    when (tl.a.valid && (stallN < aStall.U)) { stallN := stallN + 1.U }
    when (tl.a.fire()) { stallN := 0.U }
    val aFirst = edge.first(tl.a); val aLast = edge.last(tl.a)
    val aBeat = RegInit(0.U(2.W)); when (tl.a.fire()) { aBeat := Mux(aLast, 0.U, aBeat + 1.U) }
    tl.a.ready := ((state === sIdle) || (state === sBeats)) && !stalling
    def inErr(x: UInt): Bool = if (errorMask == 0) false.B else ((x & errorMask.U) === errorMask.U)
    def inWErr(x: UInt): Bool = if (writeErrMask == 0) false.B else ((x & writeErrMask.U) === writeErrMask.U)
    def widx(x: UInt): UInt = (x - base.U)(log2Ceil(words) + 2, 3)
    when (tl.a.fire()) {
      val e = inErr(tl.a.bits.address) || (tl.a.bits.opcode =/= TLMessages.Get && inWErr(tl.a.bits.address))
      when (aFirst) { src := tl.a.bits.source; sz := tl.a.bits.size; isGet := tl.a.bits.opcode === TLMessages.Get; addr := tl.a.bits.address; err := e
                      nBeatsD := Mux(tl.a.bits.opcode === TLMessages.Get && tl.a.bits.size === 4.U, 2.U, 1.U) }
      // beat n of a multi-beat Put lands at base + 8n (the A address is the base of the whole transfer; the
      // first version wrote every beat to the base -- found by the real memory in the subsystem harness)
      val wAddr = tl.a.bits.address + Cat(aBeat, 0.U(3.W))
      when (tl.a.bits.opcode =/= TLMessages.Get && !e) {
        val old = mem(widx(wAddr)); val m = FillInterleaved(8, tl.a.bits.mask)
        val nw = (old & (~m).asUInt) | (tl.a.bits.data & m)
        mem(widx(wAddr)) := nw
        printf(p"AT ${cyc} MGR_WRITE $tag addr=0x${Hexadecimal(wAddr)} data=0x${Hexadecimal(tl.a.bits.data)} mask=0x${Hexadecimal(tl.a.bits.mask)} new=0x${Hexadecimal(nw)}\n")
      }
      when (tl.a.bits.opcode =/= TLMessages.Get && e) { printf(p"AT ${cyc} MGR_REFUSE $tag addr=0x${Hexadecimal(tl.a.bits.address)}\n") }
      when (aLast) { state := sWait; due := cyc + latency.U; dBeat := 0.U } .otherwise { state := sBeats }
    }
    when (state === sWait && cyc >= due) { state := sD }
    val rdAddr = addr + Cat(dBeat, 0.U(3.W))
    val rdata = Mux(err, 0.U, mem(widx(rdAddr)))
    // an optional stall on the D side: the response is offered only every (dStall+1)-th cycle
    // (once offered, the beat stays offered until it is taken -- a registered flag, not a self-reference)
    val dTick = RegInit(0.U(8.W)); dTick := Mux(dTick >= dStall.U, 0.U, dTick + 1.U)
    val dOffered = RegInit(false.B)
    when (tl.d.fire()) { dOffered := false.B } .elsewhen ((state === sD) && (dTick === 0.U)) { dOffered := true.B }
    tl.d.valid := (state === sD) && (dOffered || (dTick === 0.U))
    tl.d.bits := Mux(isGet, edge.AccessAck(src, sz, rdata, err), edge.AccessAck(src, sz, err))
    when (tl.d.fire()) {
      printf(p"AT ${cyc} MGR_D $tag src=${src} get=${isGet} addr=0x${Hexadecimal(rdAddr)} data=0x${Hexadecimal(rdata)} err=${err}\n")
      when (dBeat + 1.U >= nBeatsD) { state := sIdle } .otherwise { dBeat := dBeat + 1.U }
    }
    tl.b.valid := false.B; tl.c.ready := true.B; tl.e.ready := true.B
  }
}

// ---- a scripted TileLink master standing in for the TSI adapter or the block-device DMA.
// Each step: trigger (0 = at cycle `arg`, 1 = after the CPU bridge's A has fired `arg` times, 2 = while the
// CPU transaction number `arg` is outstanding), op (0 Get, 1 PutFull, 2 PutPartial), addr, lgSize (3 or 4),
// data (beat 0; beat 1 = data + 1), mask.
case class PutStep(trig: Int, arg: Int, op: Int, addr: Long, size: Int, data: BigInt, mask: Int)
class TLPutter(name: String, steps: Seq[PutStep], dStallN: Int = 0)(implicit p: Parameters) extends LazyModule {
  val node = TLHelper.makeClientNode(name, IdRange(0, 1))
  lazy val module = new LazyModuleImp(this) {
    val io = IO(new Bundle { val cpuAFires = Input(UInt(32.W)); val cpuTxid = Input(UInt(32.W)); val cpuOutstanding = Input(Bool()); val done = Output(Bool()) })
    val (tl, edge) = node.out(0)
    val cyc = RegInit(0.U(32.W)); cyc := cyc + 1.U
    // an empty script: the master exists (it is a real crossbar port) but never speaks
    val stepsP = if (steps.isEmpty) Seq(PutStep(0, Int.MaxValue, 0, 0x80000000L, 3, 0, 0xff)) else steps
    val n = steps.size
    val idx = RegInit(0.U(8.W)); val beat = RegInit(0.U(1.W)); val busy = RegInit(false.B); val outst = RegInit(false.B)
    val trigV = VecInit(stepsP.map(_.trig.U(2.W))); val argV = VecInit(stepsP.map(_.arg.U(32.W)))
    val opV = VecInit(stepsP.map(_.op.U(2.W))); val addrV = VecInit(stepsP.map(_.addr.U(32.W)))
    val sizeV = VecInit(stepsP.map(_.size.U(3.W))); val dataV = VecInit(stepsP.map(s => s.data.U(64.W))); val maskV = VecInit(stepsP.map(_.mask.U(8.W)))
    val cur = Mux(idx < stepsP.size.U, idx, (stepsP.size - 1).U)
    val fireCond = MuxLookup(trigV(cur), false.B, Seq(
      0.U -> (cyc >= argV(cur)), 1.U -> (io.cpuAFires >= argV(cur)), 2.U -> (io.cpuOutstanding && io.cpuTxid === argV(cur))))
    val active = (idx < n.U) && !outst
    when (active && !busy && fireCond) { busy := true.B; beat := 0.U }
    val addrNow = addrV(cur) + Cat(beat, 0.U(3.W))
    val dataNow = dataV(cur) + beat
    val (_, g) = edge.Get(0.U, addrV(cur), sizeV(cur))
    val (_, pf) = edge.Put(0.U, addrV(cur), sizeV(cur), dataNow)
    val (_, pp) = edge.Put(0.U, addrV(cur), sizeV(cur), dataNow, maskV(cur))
    tl.a.valid := busy
    tl.a.bits := MuxLookup(opV(cur), g, Seq(1.U -> pf, 2.U -> pp))
    tl.a.bits.data := dataNow
    val twoBeats = (opV(cur) =/= 0.U) && (sizeV(cur) === 4.U)
    when (tl.a.fire()) {
      printf(p"AT ${cyc} EXT_A $name op=${opV(cur)} addr=0x${Hexadecimal(addrNow)} size=${sizeV(cur)} data=0x${Hexadecimal(dataNow)} mask=0x${Hexadecimal(tl.a.bits.mask)}\n")
      when (twoBeats && beat === 0.U) { beat := 1.U } .otherwise { busy := false.B; outst := true.B }
    }
    val dHold = RegInit(0.U(4.W)); dHold := Mux(tl.d.valid && !tl.d.ready, dHold + 1.U, 0.U)
    tl.d.ready := (dStallN == 0).B || (dHold >= dStallN.U)     // return-side backpressure from the external master
    when (tl.d.fire() && edge.last(tl.d)) { outst := false.B; idx := idx + 1.U
      printf(p"AT ${cyc} EXT_D $name data=0x${Hexadecimal(tl.d.bits.data)} err=${tl.d.bits.error}\n") }
    io.done := idx >= n.U
    tl.b.ready := false.B; tl.c.valid := false.B; tl.e.valid := false.B
  }
}

// ---- the scripted CPU stand-in on PHYSICAL_PORT_V2.
// kinds: 0 load, 1 store, 2 AMO, 3 LR, 4 SC, 5 trap pulse (resvClear), 6 wait `arg` cycles, 7 a request with the
// reserved lrsc = 3 (must be refused locally). respStall: the CPU takes a response only every (respStall+1)-th cycle;
// respRandom: the CPU's resp.ready follows an LFSR (return-side backpressure).
case class CpuStep(kind: Int, addr: Long = 0, size: Int = 3, data: BigInt = 0, amo: Int = 0, arg: Int = 0)
class V2Driver(steps: Seq[CpuStep], respStall: Int = 0, respRandom: Boolean = false) extends Module {
  val io = IO(new Bundle { val phys = new PhysPortV2IO; val hold = Input(Bool()); val finished = Output(Bool()); val nResp = Output(UInt(32.W)) })
  val n = steps.size
  val cyc = RegInit(0.U(32.W)); cyc := cyc + 1.U
  val idx = RegInit(0.U(8.W)); val inFlight = RegInit(false.B); val waitN = RegInit(0.U(32.W)); val nResp = RegInit(0.U(32.W))
  val kindV = VecInit(steps.map(_.kind.U(3.W))); val addrV = VecInit(steps.map(_.addr.U(32.W)))
  val sizeV = VecInit(steps.map(_.size.U(2.W))); val dataV = VecInit(steps.map(s => s.data.U(64.W)))
  val amoV = VecInit(steps.map(_.amo.U(4.W))); val argV = VecInit(steps.map(_.arg.U(32.W)))
  val k = kindV(idx); val done = idx >= n.U
  val lanes = PhysPort.laneMask(sizeV(idx), addrV(idx)(2, 0))
  val shift = Cat(addrV(idx)(2, 0), 0.U(3.W))
  val isMem = (k <= 4.U) || (k === 7.U)
  io.phys.req.valid := !done && isMem && !inFlight && !io.hold
  io.phys.req.bits.addr  := addrV(idx)
  io.phys.req.bits.write := (k === 1.U) || (k === 2.U) || (k === 4.U)
  io.phys.req.bits.size  := sizeV(idx)
  io.phys.req.bits.wdata := (dataV(idx) << shift)(63, 0)
  io.phys.req.bits.wmask := Mux(k === 0.U || k === 3.U, 0.U, lanes)
  io.phys.req.bits.amo   := Mux(k === 2.U, amoV(idx), 0.U)
  io.phys.req.bits.lrsc  := Mux(k === 3.U, LrSc.LR.U, Mux(k === 4.U, LrSc.SC.U, Mux(k === 7.U, 3.U, 0.U)))
  io.phys.resvClear := !done && (k === 5.U)
  val lf = RegInit(0x2545F491L.U(32.W)); lf := Cat(lf(30, 0), lf(31) ^ lf(21) ^ lf(1) ^ lf(0))
  val rTick = RegInit(0.U(8.W)); rTick := Mux(io.phys.resp.valid && !io.phys.resp.ready, rTick + 1.U, 0.U)
  io.phys.resp.ready := (if (respRandom) lf(2) else ((respStall == 0).B || (rTick >= respStall.U)))
  when (io.phys.req.fire()) { inFlight := true.B }
  when (io.phys.resp.fire()) { inFlight := false.B; idx := idx + 1.U; nResp := nResp + 1.U }
  // a held CPU is a CPU in reset: whatever it had in flight is gone, and it re-issues the step when released
  when (io.hold) { inFlight := false.B }
  when (io.hold && !RegNext(io.hold, false.B)) { printf(p"AT ${cyc} CPU_HELD step=${idx}\n") }
  when (!done && k === 5.U) { printf(p"AT ${cyc} CPU_TRAP\n"); idx := idx + 1.U }
  when (!done && k === 6.U) { when (waitN >= argV(idx)) { waitN := 0.U; idx := idx + 1.U } .otherwise { waitN := waitN + 1.U } }
  io.finished := done
  io.nResp := nResp
}

// ---- the harness: three masters, one backend, the memory manager and a read-only manager without atomics
class AtomicHarness(cpu: Seq[CpuStep], ext0: Seq[PutStep], ext1: Seq[PutStep], latency: Int, aStall: Int, errorMask: BigInt,
                    bridgeFault: Int, fReadErr: Boolean, fNoKill: Boolean, fWrongSrc: Boolean,
                    drainTrig: Int, resetLen: Int, delayQ: Double = 0.0, respStall: Int = 0, respRandom: Boolean = false,
                    extDStall: Int = 0, mgrDStall: Int = 0, writeErrMask: BigInt = 0)(implicit p: Parameters) extends LazyModule {
  val memBase = 0x80000000L; val romBase = 0x10000L; val mmioBase = 0x60000000L
  val mgr     = LazyModule(new AtomicManager(memBase, 512, latency, aStall, errorMask, "dram", writeErrMask, false, mgrDStall))
  val rom     = LazyModule(new AtomicManager(romBase, 64, 2, 0, 0, "rom"))
  val mmio    = LazyModule(new AtomicManager(mmioBase, 64, 2, 0, 0, "mmio", 0, atomics = true))   // capable but outside the DRAM window
  val backend = LazyModule(new AtomicBackend(fReadErr, fNoKill, fWrongSrc))
  val bridge  = LazyModule(new RD2BridgeV2(bridgeFault))
  val put0    = LazyModule(new TLPutter("ext-tsi", ext0, extDStall))
  val put1    = LazyModule(new TLPutter("ext-dma", ext1, extDStall))
  val xbar    = LazyModule(new TLXbar)
  val tap     = TLIdentityNode()
  // delayers (rocket-chip's own random stall insertion on every channel) between the bridge and the crossbar and
  // between the crossbar and the backend: the side-band must survive buffering on both sides
  if (delayQ > 0.0) {
    mgr.node := backend.node := TLDelayer(delayQ) := xbar.node
    xbar.node := tap := TLDelayer(delayQ) := bridge.node
  } else {
    mgr.node := backend.node := xbar.node
    xbar.node := tap := bridge.node
  }
  rom.node := xbar.node
  mmio.node := xbar.node
  xbar.node := put0.node
  xbar.node := put1.node
  lazy val module = new LazyModuleImp(this) with UnitTestModule {
    val cyc = RegInit(0.U(32.W)); cyc := cyc + 1.U
    val drv = Module(new V2Driver(cpu, respStall, respRandom))
    bridge.module.io.phys <> drv.io.phys
    drv.io.hold := bridge.module.io.drain.cpuResetHold
    backend.module.io.sb <> bridge.module.io.sb
    val (tlb, _) = tap.in(0)
    val aFires = RegInit(0.U(32.W)); when (tlb.a.fire()) { aFires := aFires + 1.U }
    val outst = RegInit(false.B); when (tlb.a.fire()) { outst := true.B }; when (tlb.d.fire()) { outst := false.B }
    for (pm <- Seq(put0.module, put1.module)) { pm.io.cpuAFires := aFires; pm.io.cpuTxid := bridge.module.io.drain.txid; pm.io.cpuOutstanding := outst }
    // a ROM-targeted atomic must produce zero TileLink requests from the bridge
    val offDram = (tlb.a.bits.address < memBase.U) || (tlb.a.bits.address >= (memBase + 512 * 8).U)
    when (tlb.a.fire() && offDram && (tlb.a.bits.opcode === TLMessages.ArithmeticData || tlb.a.bits.opcode === TLMessages.LogicalData)) {
      printf(p"AT ${cyc} VIOLATION atomic request left the DRAM window addr=0x${Hexadecimal(tlb.a.bits.address)}\n")
    }
    // the drain scenario: a soft reset while the backend is in the chosen AMO phase (3 GetD, 5 PutD, 7 Resp)
    val bs = backend.module.io.dbg.state
    val fired = RegInit(false.B); val pulse = RegInit(0.U(8.W))
    val hit = (drainTrig != 0).B && !fired && (bs === drainTrig.U)
    when (hit) { fired := true.B; pulse := resetLen.U; printf(p"AT ${cyc} HIT backend_state=${bs}\n") }
    when (!hit && pulse > 0.U) { pulse := pulse - 1.U }
    bridge.module.io.drain.softReset := hit || (pulse > 0.U)
    val d = bridge.module.io.drain
    when (d.drainDone) { printf(p"AT ${cyc} DRAIN_DONE epoch=${d.epoch} nDrained=${d.nDrained} nBuf=${d.nBufDisc}\n") }
    val nDr = RegNext(d.nDrained, 0.U); val nLo = RegNext(d.nLocalDisc, 0.U); val nBu = RegNext(d.nBufDisc, 0.U)
    when (d.nDrained =/= nDr)   { printf(p"AT ${cyc} DRAIN_DISCARD txid=${d.txid} n=${d.nDrained}\n") }
    when (d.nLocalDisc =/= nLo) { printf(p"AT ${cyc} LOCAL_DISCARD txid=${d.txid} n=${d.nLocalDisc}\n") }
    when (d.nBufDisc =/= nBu)   { printf(p"AT ${cyc} BUFFERED_DISCARD txid=${d.txid} n=${d.nBufDisc}\n") }
    val holdD = RegNext(d.cpuResetHold, false.B)
    when (d.cpuResetHold && !holdD) { printf(p"AT ${cyc} HOLD_ASSERT\n") }
    when (!d.cpuResetHold && holdD) { printf(p"AT ${cyc} HOLD_RELEASE epoch=${d.epoch}\n") }
    val allDone = drv.io.finished && put0.module.io.done && put1.module.io.done && !backend.module.io.dbg.busy
    val settle = RegInit(0.U(8.W)); when (allDone) { settle := settle + 1.U }
    io.finished := allDone && (settle > 20.U)
    when (io.finished && !RegNext(io.finished, false.B)) {
      printf(p"AT ${cyc} FINISHED cpuResp=${drv.io.nResp} amo=${backend.module.io.dbg.nAmo} scOk=${backend.module.io.dbg.nScOk} scFail=${backend.module.io.dbg.nScFail} kills=${backend.module.io.dbg.nKill} bridgeIllegal=${bridge.module.io.dbg.illegal} tlErr=${bridge.module.io.dbg.tlErrors}\n")
    }
  }
}

object AtomicScen {
  val B = 0x80000000L; val X = B + 0x100; val Y = B + 0x108; val Z = B + 0x200; val E = B + 0x800   // E: the error region (mask 0x800)
  val W = B + 0x400      // the write-only error region (mask 0x400): reads fine, writes refused
  val ROM = 0x10000L; val MMIO = 0x60000008L
  val lrsc3 = CpuStep(7, X, 3, 0)
  def amo(op: Int, a: Long, d: BigInt, sz: Int = 3) = CpuStep(2, a, sz, d, op)
  def ld(a: Long, sz: Int = 3) = CpuStep(0, a, sz); def st(a: Long, d: BigInt, sz: Int = 3) = CpuStep(1, a, sz, d)
  def lr(a: Long, sz: Int = 3) = CpuStep(3, a, sz); def sc(a: Long, d: BigInt, sz: Int = 3) = CpuStep(4, a, sz, d)
  val trap = CpuStep(5); def wait(n: Int) = CpuStep(6, arg = n)
  val ops = Seq(AmoOp.SWAP, AmoOp.ADD, AmoOp.XOR, AmoOp.AND, AmoOp.OR, AmoOp.MIN, AmoOp.MAX, AmoOp.MINU, AmoOp.MAXU)
  // 1: every AMO w and d, no contention; the .w forms on both halves of a word; a neighbouring byte must survive
  val s1cpu: Seq[CpuStep] = Seq(st(X, BigInt("F0F0F0F080000005", 16)), st(Y, BigInt("0000000000000007", 16))) ++
    ops.map(o => amo(o, X, BigInt("0000000000000003", 16))) ++ ops.map(o => amo(o, X, BigInt("FFFFFFFF", 16), 2)) ++
    ops.map(o => amo(o, X + 4, BigInt("00000001", 16), 2)) ++ Seq(ld(X), ld(Y), amo(AmoOp.ADD, Y, BigInt("FFFFFFFFFFFFFFFF", 16)), ld(Y))
  // 2: AMOs on X while TSI writes X and DMA writes Y (same word / other word), with backpressure from the manager
  val s2cpu: Seq[CpuStep] = Seq(st(X, 1), st(Y, 100)) ++ (1 to 8).flatMap(_ => Seq(amo(AmoOp.ADD, X, 1), amo(AmoOp.SWAP, Y, 7), ld(X), ld(Y)))
  val s2ext0 = (0 until 8).map(i => PutStep(1, 3 + 2 * i, 1, X, 3, BigInt(1000 + i), 0xff))
  val s2ext1 = (0 until 8).map(i => PutStep(1, 4 + 2 * i, 1, Y, 3, BigInt(5000 + i), 0xff))
  // 3: partial masks and two-beat writes covering X..X+15 from the others while the CPU does AMOs and LR/SC on X
  val s3cpu: Seq[CpuStep] = Seq(st(X, 0), st(Y, 0)) ++ (1 to 6).flatMap(_ => Seq(amo(AmoOp.ADD, X, 1), amo(AmoOp.ADD, X + 4, 1, 2), lr(X), sc(X, 42), ld(X), ld(Y)))
  val s3ext0 = (0 until 6).map(i => PutStep(1, 4 + 3 * i, 2, X, 3, BigInt("1111111111111111", 16) * (i + 1) % BigInt(2).pow(64), if (i % 2 == 0) 0x0f else 0xf0))
  val s3ext1 = (0 until 4).map(i => PutStep(1, 6 + 4 * i, 1, X, 4, BigInt("2222222222222222", 16), 0xff))
  // 4: the reservation lifecycle without contention
  val s4cpu: Seq[CpuStep] = Seq(st(X, 5), st(Y, 6), st(Z, 9),
    lr(X), sc(X, 10),            // ok
    sc(X, 11),                   // consumed: fail
    lr(X), lr(Y), sc(X, 12),     // replaced by the newer LR: fail
    sc(Y, 13),                   // the SC consumed the Y reservation? no: the failed SC to X consumed it -> fail
    lr(Y), sc(Y, 14),            // ok
    lr(X), st(X, 15), sc(X, 16), // own store to the word: fail
    lr(X), trap, sc(X, 17),      // trap clears: fail
    lr(X), ld(X), ld(Z), sc(X, 18),  // plain reads keep it: ok
    lr(X, 2), sc(X, 19, 2),      // .w on the low half: ok
    lr(X + 4, 2), sc(X + 4, 20, 2),  // .w on the high half: ok
    lr(X), sc(Y, 21),            // an SC to a different word: fail, and X's reservation is gone
    sc(X, 22),                   // fail
    ld(X), ld(Y))
  // 5: races -- writes from the others during the LR's pending read (long latency) and while the SC waits (stall)
  val s5cpu: Seq[CpuStep] = Seq(st(X, 1), st(Y, 2),
    lr(X), sc(X, 10),            // TSI writes X while the LR's read is pending (trig 2 on txid 3): fail
    lr(X), sc(X, 11),            // DMA writes Y (other word) during the LR: ok
    lr(X), sc(X, 12),            // TSI writes X while the SC waits for ready (a stall): fail
    lr(X), sc(X, 13),            // TSI PutPartial on the upper half only: fail
    lr(X), sc(X, 14),            // DMA two-beat Put covering X: fail
    lr(X), sc(X, 15),            // nobody writes: ok
    ld(X), ld(Y))
  val s5ext0 = Seq(PutStep(2, 3, 1, X, 3, BigInt(777), 0xff), PutStep(2, 7, 1, X, 3, BigInt(778), 0xff),
                   PutStep(2, 9, 2, X, 3, BigInt("AA00000000000000", 16), 0xf0))
  val s5ext1 = Seq(PutStep(2, 5, 1, Y, 3, BigInt(999), 0xff), PutStep(2, 11, 1, X, 4, BigInt("3333333333333333", 16), 0xff))
  // 6: errors -- AMO / LR / SC into the error region and onto the ROM (no atomic support)
  val s6cpu: Seq[CpuStep] = Seq(st(X, 3), st(E, 9), amo(AmoOp.ADD, E, 1), ld(X), lr(E), sc(E, 5), lr(X), sc(X, 6),
    amo(AmoOp.SWAP, ROM + 8, 1), lr(ROM + 8), sc(ROM + 8, 1), ld(ROM + 8), amo(AmoOp.ADD, X, 1, 1), amo(AmoOp.ADD, X + 2, 1, 2), ld(X),
    ld(W), amo(AmoOp.ADD, W, 1), ld(W), lr(W), sc(W, 7), ld(W),          // read ok, the AMO's write half fails once, the SC's write fails once
    amo(AmoOp.ADD, MMIO, 1), lr(MMIO), sc(MMIO, 1), ld(MMIO), lrsc3, ld(X))
  // 7: progress -- a bounded LR/SC loop alone, then under a storm on X that stops, then again
  val s7cpu: Seq[CpuStep] = Seq(st(X, 0)) ++ (1 to 16).flatMap(i => Seq(lr(X), sc(X, i))) ++ Seq(wait(400)) ++
    (1 to 16).flatMap(i => Seq(lr(X), sc(X, 100 + i))) ++ Seq(ld(X))
  val s7ext0 = (0 until 30).map(i => PutStep(0, 300 + 6 * i, 1, X, 3, BigInt(2000 + i), 0xff))
  // 8: the drain -- AMOs back to back; the soft reset lands in the chosen backend phase
  val s8cpu: Seq[CpuStep] = Seq(st(X, 1)) ++ (1 to 6).map(_ => amo(AmoOp.ADD, X, 1)) ++ Seq(ld(X))
}

class AtomicTest(scen: Int, latency: Int, aStall: Int, errorMask: BigInt, bridgeFault: Int, fReadErr: Boolean, fNoKill: Boolean,
                 fWrongSrc: Boolean, drainTrig: Int, resetLen: Int, timeout: Int, delayQ: Double, respStall: Int, respRandom: Boolean,
                 extDStall: Int, mgrDStall: Int, writeErrMask: BigInt)(implicit p: Parameters) extends UnitTest(timeout) {
  import AtomicScen._
  val (cpu, e0, e1) = scen match {
    case 1 => (s1cpu, Nil, Nil); case 2 => (s2cpu, s2ext0, s2ext1); case 3 => (s3cpu, s3ext0, s3ext1)
    case 4 => (s4cpu, Nil, Nil); case 5 => (s5cpu, s5ext0, s5ext1); case 6 => (s6cpu, Nil, Nil)
    case 7 => (s7cpu, s7ext0, Nil); case 8 => (s8cpu, Nil, Nil)
  }
  val dut = Module(LazyModule(new AtomicHarness(cpu, e0, e1, latency, aStall, errorMask, bridgeFault, fReadErr, fNoKill, fWrongSrc, drainTrig, resetLen,
                                                delayQ, respStall, respRandom, extDStall, mgrDStall, writeErrMask)).module)
  dut.io.start := io.start
  io.finished := dut.io.finished
}
class WithAtomic(scen: Int, latency: Int = 4, aStall: Int = 0, errorMask: BigInt = 0x800, bridgeFault: Int = 0,
                 fReadErr: Boolean = false, fNoKill: Boolean = false, fWrongSrc: Boolean = false, drainTrig: Int = 0, resetLen: Int = 2,
                 timeout: Int = 400000, delayQ: Double = 0.0, respStall: Int = 0, respRandom: Boolean = false, extDStall: Int = 0,
                 mgrDStall: Int = 0, writeErrMask: BigInt = 0x400) extends Config((site, here, up) => {
  case UnitTests => (q: Parameters) => { implicit val p = q
    Seq(Module(new AtomicTest(scen, latency, aStall, errorMask, bridgeFault, fReadErr, fNoKill, fWrongSrc, drainTrig, resetLen, timeout,
                              delayQ, respStall, respRandom, extDStall, mgrDStall, writeErrMask))) }
})
class AtomicAmoBasicConfig    extends Config(new WithAtomic(1) ++ new Base)
class AtomicAmoRaceConfig     extends Config(new WithAtomic(2, latency = 6, aStall = 3) ++ new Base)
class AtomicAmoPartialConfig  extends Config(new WithAtomic(3, latency = 5, aStall = 2) ++ new Base)
class AtomicLrscBasicConfig   extends Config(new WithAtomic(4) ++ new Base)
class AtomicLrscRaceConfig    extends Config(new WithAtomic(5, latency = 30, aStall = 12) ++ new Base)
class AtomicErrorsConfig      extends Config(new WithAtomic(6) ++ new Base)
class AtomicProgressConfig    extends Config(new WithAtomic(7, latency = 3) ++ new Base)
class AtomicDrainGetConfig    extends Config(new WithAtomic(8, latency = 8, drainTrig = 4) ++ new Base)   // sGetD = 4
class AtomicDrainPutConfig    extends Config(new WithAtomic(8, latency = 8, drainTrig = 6) ++ new Base)   // sPutD = 6
class AtomicDrainRespConfig   extends Config(new WithAtomic(8, latency = 8, drainTrig = 7) ++ new Base)   // sResp = 7
// return-side backpressure and buffering: the same scenarios with delayers, CPU response stalls, external D stalls, manager D stalls
class AtomicBpAmoConfig       extends Config(new WithAtomic(2, latency = 6, aStall = 3, delayQ = 0.3, respStall = 5, extDStall = 4, mgrDStall = 3) ++ new Base)
class AtomicBpLrscConfig      extends Config(new WithAtomic(5, latency = 30, aStall = 12, delayQ = 0.3, respRandom = true, extDStall = 3, mgrDStall = 2) ++ new Base)
class AtomicBpLrscBasicConfig extends Config(new WithAtomic(4, delayQ = 0.4, respRandom = true, mgrDStall = 4) ++ new Base)
class AtomicBpErrorsConfig    extends Config(new WithAtomic(6, delayQ = 0.3, respStall = 3, mgrDStall = 2) ++ new Base)
class AtomicBpDrainConfig     extends Config(new WithAtomic(8, latency = 8, drainTrig = 6, delayQ = 0.3, respStall = 4) ++ new Base)
// negatives
class AtomicNegReadErrConfig  extends Config(new WithAtomic(6, fReadErr = true) ++ new Base)
class AtomicNegNoKillConfig   extends Config(new WithAtomic(5, latency = 30, aStall = 12, fNoKill = true) ++ new Base)
class AtomicNegWrongSrcConfig extends Config(new WithAtomic(4, fWrongSrc = true) ++ new Base)
class AtomicNegScEarlyConfig  extends Config(new WithAtomic(5, latency = 30, aStall = 12, bridgeFault = 8) ++ new Base)
// request-semantics negatives: the bridge is internally consistent (its A, the memory and the response all
// agree) but no longer says what the CPU asked for -- only a checker that binds the CPU request's own fields
// to the TileLink mapping can see these
class AtomicNegAmoMapConfig     extends Config(new WithAtomic(1, bridgeFault = 9) ++ new Base)   // ADD emitted as SWAP
class AtomicNegAmoOperandConfig extends Config(new WithAtomic(1, bridgeFault = 10) ++ new Base)  // operand halves swapped
