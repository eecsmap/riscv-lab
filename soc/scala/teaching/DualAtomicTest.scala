// MC-M2a: two protocol drivers standing in for two harts, one shared atomic backend, external writers.
//
// Everything the single-hart unit harness (AtomicTest.scala) has, twice on the CPU side: two V2Drivers,
// two V2 bridges each with its OWN exact client name ("teaching-phys-0", "teaching-phys-1"), the same
// scripted TSI/DMA stand-ins, one TLXbar, the backend bound to the two names, the memory manager with real
// storage. Every event line carries the hart it belongs to, so score2.py can bind each request to its hart
// and re-derive every expected effect from the ORDER the backend actually accepted things in.
//
// Topologies (MC-M0 ruling D4 / TESTPLAN T2.7): `swapOrder` connects hart 1's bridge to the crossbar before
// hart 0's (their source ranges change); `extraClient` adds a third non-CPU master. Logical results must not
// change. Random scenarios are generated at elaboration from a seed with scala.util.Random -- the script is
// a ROM, the scorer never needs the seed, and the same seed reproduces the same run.
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config._
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.tilelink._
import freechips.rocketchip.unittest._
import testchipip.TLHelper

case class DualParams(
  cpu0: Seq[CpuStep], cpu1: Seq[CpuStep], ext0: Seq[PutStep] = Nil, ext1: Seq[PutStep] = Nil,
  extra: Option[Seq[PutStep]] = None, swapOrder: Boolean = false,
  latency: Int = 4, aStall: Int = 0, errorMask: BigInt = 0x800, writeErrMask: BigInt = 0x400,
  bridgeFault0: Int = 0, bridgeFault1: Int = 0,
  fReadErr: Boolean = false, fNoKill: Boolean = false, fWrongSrc: Boolean = false,
  fNoCrossKill: Boolean = false, fSwapSideband: Boolean = false, fSwapDSource: Boolean = false, fAmoInterleave: Boolean = false,
  drainAt: Int = 0, resetLen: Int = 2, delayQ: Double = 0.0,
  respStall0: Int = 0, respStall1: Int = 0, respRandom0: Boolean = false, respRandom1: Boolean = false,
  extDStall: Int = 0, mgrDStall: Int = 0, withdraw0: Boolean = false, timeout: Int = 400000,
  // the names the BACKEND binds (the bridges are always "teaching-phys-0"/"-1"): the refusal configs below
  // hand the backend a name that resolves to nothing, one that leaves a hart-like client unbound, or a duplicate
  backendNames: Seq[String] = Seq("teaching-phys-0", "teaching-phys-1"))

class DualAtomicHarness(pp: DualParams)(implicit p: Parameters) extends LazyModule {
  import pp._
  val memBase = 0x80000000L; val romBase = 0x10000L; val mmioBase = 0x60000000L
  val mgr     = LazyModule(new AtomicManager(memBase, 512, latency, aStall, errorMask, "dram", writeErrMask, false, mgrDStall))
  val rom     = LazyModule(new AtomicManager(romBase, 64, 2, 0, 0, "rom"))
  val mmio    = LazyModule(new AtomicManager(mmioBase, 64, 2, 0, 0, "mmio", 0, atomics = true))
  val names   = Seq("teaching-phys-0", "teaching-phys-1")
  val backend = LazyModule(new AtomicBackend(fReadErr, fNoKill, fWrongSrc, backendNames,
                                             faultNoCrossKill = fNoCrossKill, faultSwapSideband = fSwapSideband,
                                             faultSwapDSource = fSwapDSource, faultAmoInterleave = fAmoInterleave))
  val bridge0 = LazyModule(new RD2BridgeV2(bridgeFault0, clientName = names(0), hartId = 0))
  val bridge1 = LazyModule(new RD2BridgeV2(bridgeFault1, clientName = names(1), hartId = 1))
  val put0    = LazyModule(new TLPutter("ext-tsi", ext0, extDStall))
  val put1    = LazyModule(new TLPutter("ext-dma", ext1, extDStall))
  val putX    = extra.map(s => LazyModule(new TLPutter("ext-extra", s, extDStall)))
  val xbar    = LazyModule(new TLXbar)
  val tap0    = TLIdentityNode(); val tap1 = TLIdentityNode()
  if (delayQ > 0.0) mgr.node := backend.node := TLDelayer(delayQ) := xbar.node
  else              mgr.node := backend.node := xbar.node
  rom.node := xbar.node
  mmio.node := xbar.node
  // the tap sits on the BRIDGE side of the delayer: the irrevocability monitor judges the bridge's own A,
  // not the delayer's output (a TLDelayer gates valid at random, which is legal for it and not a withdrawal)
  def attach(t: TLIdentityNode, b: RD2BridgeV2): Unit =
    if (delayQ > 0.0) xbar.node := TLDelayer(delayQ) := t := b.node else xbar.node := t := b.node
  // the connection order decides the source ranges; the binding must not care
  putX.foreach { x => if (swapOrder) xbar.node := x.node }
  if (swapOrder) { attach(tap1, bridge1); attach(tap0, bridge0) } else { attach(tap0, bridge0); attach(tap1, bridge1) }
  xbar.node := put0.node
  xbar.node := put1.node
  putX.foreach { x => if (!swapOrder) xbar.node := x.node }

  lazy val module = new LazyModuleImp(this) with UnitTestModule {
    val cyc = RegInit(0.U(32.W)); cyc := cyc + 1.U
    val drv0 = Module(new V2Driver(cpu0, respStall0, respRandom0, hartId = 0, withdraw = withdraw0))
    val drv1 = Module(new V2Driver(cpu1, respStall1, respRandom1, hartId = 1))
    bridge0.module.io.phys <> drv0.io.phys
    bridge1.module.io.phys <> drv1.io.phys
    drv0.io.hold := bridge0.module.io.drain.cpuResetHold
    drv1.io.hold := bridge1.module.io.drain.cpuResetHold
    backend.module.io.sb(0) <> bridge0.module.io.sb
    backend.module.io.sb(1) <> bridge1.module.io.sb
    // ---- monitors: irrevocability on both sides of each bridge (a withdrawn request is a VIOLATION the scorer rejects)
    for ((b, d, h) <- Seq((bridge0, drv0, 0), (bridge1, drv1, 1))) {
      val v = d.io.phys.req.valid; val r = d.io.phys.req.ready
      val held = RegNext(v && !r, false.B)
      when (held && !v) { printf(p"AT ${cyc} VIOLATION phys request withdrawn hart=${h.U}\n") }
      val bitsPrev = RegNext(d.io.phys.req.bits)
      when (held && v && (d.io.phys.req.bits.asUInt =/= bitsPrev.asUInt)) { printf(p"AT ${cyc} VIOLATION phys payload changed while offered hart=${h.U}\n") }
    }
    val (tl0, _) = tap0.in(0); val (tl1, _) = tap1.in(0)
    for ((tl, h) <- Seq((tl0, 0), (tl1, 1))) {
      val held = RegNext(tl.a.valid && !tl.a.ready, false.B)
      when (held && !tl.a.valid) { printf(p"AT ${cyc} VIOLATION tl A withdrawn hart=${h.U}\n") }
    }
    // external masters take their cues from hart 0's bridge, as the single-hart harness did
    val aFires = RegInit(0.U(32.W)); when (tl0.a.fire()) { aFires := aFires + 1.U }
    val outst = RegInit(false.B); when (tl0.a.fire()) { outst := true.B }; when (tl0.d.fire()) { outst := false.B }
    for (pm <- Seq(put0.module, put1.module) ++ putX.map(_.module)) { pm.io.cpuAFires := aFires; pm.io.cpuTxid := bridge0.module.io.drain.txid; pm.io.cpuOutstanding := outst }
    val offDram = (tl0.a.bits.address < memBase.U) || (tl0.a.bits.address >= (memBase + 512 * 8).U)
    when (tl0.a.fire() && offDram && (tl0.a.bits.opcode === TLMessages.ArithmeticData || tl0.a.bits.opcode === TLMessages.LogicalData)) {
      printf(p"AT ${cyc} VIOLATION atomic request left the DRAM window addr=0x${Hexadecimal(tl0.a.bits.address)}\n")
    }
    // ---- the drain: one soft reset to BOTH bridges at a chosen cycle (both may have work in flight).
    // CONTRACT C7.1: the SoC holds the reset request until EVERY bridge is applying (applying_all), so no hart
    // leaves reset while another is still draining; cpuRestartSafe = applying_all && !pendingWork. The harness
    // stands in for the SoC here: softReset stays high from the hit until applying_all has been observed.
    val fired = RegInit(false.B); val pulse = RegInit(0.U(8.W)); val applyingAllSeen = RegInit(false.B)
    val hit = (drainAt != 0).B && !fired && (cyc === drainAt.U)
    when (hit) { fired := true.B; pulse := resetLen.U; printf(p"AT ${cyc} HIT drain both harts\n") }
    when (!hit && pulse > 0.U) { pulse := pulse - 1.U }
    val applyingAll = bridge0.module.io.drain.applying && bridge1.module.io.drain.applying
    val pendingWorkAny = Seq(bridge0, bridge1).map(_.module.io.drain).map(d => d.pendingA || d.outstanding).reduce(_ || _)
    when (applyingAll && !applyingAllSeen) { applyingAllSeen := true.B; printf(p"AT ${cyc} APPLYING_ALL pendingWork=${pendingWorkAny}\n") }
    val restartSafe = applyingAll && !pendingWorkAny
    when (restartSafe && !RegNext(restartSafe, false.B)) { printf(p"AT ${cyc} RESTART_SAFE\n") }
    for ((b, h) <- Seq((bridge0, 0), (bridge1, 1))) {
      val d = b.module.io.drain
      d.softReset := hit || (pulse > 0.U) || (fired && !applyingAllSeen && !applyingAll)
      when (d.drainDone) { printf(p"AT ${cyc} DRAIN_DONE hart=${h.U} epoch=${d.epoch} nDrained=${d.nDrained} nBuf=${d.nBufDisc}\n") }
      val nDr = RegNext(d.nDrained, 0.U); val nLo = RegNext(d.nLocalDisc, 0.U); val nBu = RegNext(d.nBufDisc, 0.U)
      when (d.nDrained =/= nDr)   { printf(p"AT ${cyc} DRAIN_DISCARD hart=${h.U} txid=${d.txid} n=${d.nDrained}\n") }
      when (d.nLocalDisc =/= nLo) { printf(p"AT ${cyc} LOCAL_DISCARD hart=${h.U} txid=${d.txid} n=${d.nLocalDisc}\n") }
      when (d.nBufDisc =/= nBu)   { printf(p"AT ${cyc} BUFFERED_DISCARD hart=${h.U} txid=${d.txid} n=${d.nBufDisc}\n") }
      val holdD = RegNext(d.cpuResetHold, false.B)
      when (d.cpuResetHold && !holdD) { printf(p"AT ${cyc} HOLD_ASSERT hart=${h.U}\n") }
      when (!d.cpuResetHold && holdD) { printf(p"AT ${cyc} HOLD_RELEASE hart=${h.U} epoch=${d.epoch}\n") }
    }
    val extDone = put0.module.io.done && put1.module.io.done && putX.map(_.module.io.done).getOrElse(true.B)
    val allDone = drv0.io.finished && drv1.io.finished && extDone && !backend.module.io.dbg.busy
    val settle = RegInit(0.U(8.W)); when (allDone) { settle := settle + 1.U }
    io.finished := allDone && (settle > 20.U)
    when (io.finished && !RegNext(io.finished, false.B)) {
      printf(p"AT ${cyc} FINISHED cpuResp=${drv0.io.nResp + drv1.io.nResp} cpuResp0=${drv0.io.nResp} cpuResp1=${drv1.io.nResp} amo=${backend.module.io.dbg.nAmo} scOk=${backend.module.io.dbg.nScOk} scFail=${backend.module.io.dbg.nScFail} kills=${backend.module.io.dbg.nKill} bridgeIllegal=${bridge0.module.io.dbg.illegal + bridge1.module.io.dbg.illegal} tlErr=${bridge0.module.io.dbg.tlErrors + bridge1.module.io.dbg.tlErrors}\n")
    }
  }
}

object DualScen {
  def pause(n: Int) = CpuStep(6, arg = n)   // not `wait`: inside an object that name is AnyRef.wait
  import AtomicScen._
  val X4 = X + 4; val Y4 = Y + 4
  // ---- directed (TESTPLAN T2.5 and the hard-acceptance list). `wait` separates the harts' steps so that
  // the intended order is the likely one; the scorer derives the truth from the ORDER THAT HAPPENED, and
  // the per-scenario count floors assert that the intended interleaving was reached.
  // d1: both LR the same word; hart 0's SC first (ok), hart 1's SC after (fail)
  val d1cpu0 = Seq(st(X, 1), st(Y, 2), lr(X), pause(60), sc(X, 10), ld(X))
  val d1cpu1 = Seq(pause(30), lr(X), pause(60), sc(X, 20), ld(X))
  // d2: hart 0 LR X; hart 1 plain-stores X; hart 0's SC fails
  val d2cpu0 = Seq(st(X, 1), lr(X), pause(60), sc(X, 10), ld(X))
  val d2cpu1 = Seq(pause(30), st(X, 77), ld(X))
  // d3: different granules: both SCs succeed
  val d3cpu0 = Seq(st(X, 1), st(Y, 2), lr(X), pause(40), sc(X, 10), ld(X))
  val d3cpu1 = Seq(pause(20), lr(Y), pause(40), sc(Y, 20), ld(Y))
  // d5: hart 0 traps (its reservation only); hart 1's stands
  val d5cpu0 = Seq(st(X, 1), st(Y, 2), lr(X), pause(20), trap, pause(40), sc(X, 10), ld(X))
  val d5cpu1 = Seq(pause(10), lr(Y), pause(80), sc(Y, 20), ld(Y))
  // d6: a DMA write to X during hart 0's reservation kills it; hart 1 unaffected on Y
  val d6cpu0 = Seq(st(X, 1), st(Y, 2), lr(X), pause(80), sc(X, 10), ld(X))
  val d6cpu1 = Seq(pause(10), lr(Y), pause(80), sc(Y, 20), ld(Y))
  val d6ext1 = Seq(PutStep(0, 50, 1, X, 3, BigInt(555), 0xff))   // lands between hart 0's LR (~cycle 17) and its SC (~cycle 100)
  // d7: hart 1's ONE-BYTE partial store into X kills hart 0's reservation
  val d7cpu0 = Seq(st(X, 1), lr(X), pause(60), sc(X, 10), ld(X))
  val d7cpu1 = Seq(pause(30), st(X + 3, 0xAB, 0), ld(X))
  // d8: a failed SC must not hurt the other hart: hart 1 SCs X with no reservation (fail), hart 0's stands
  val d8cpu0 = Seq(st(X, 1), lr(X), pause(60), sc(X, 10), ld(X))
  val d8cpu1 = Seq(pause(30), sc(X, 99), ld(X))
  // d9: both harts' own-store / trap / error paths, .W and .D, LR error, AMO read error, AMO write error once
  val d9cpu0 = Seq(st(X, 5), lr(X), st(X, 15), sc(X, 16), lr(X, 2), sc(X, 19, 2), lr(X4, 2), sc(X4, 20, 2), ld(X),
                   st(E, 9), amo(AmoOp.ADD, E, 1), lr(E), sc(E, 5), ld(W), amo(AmoOp.ADD, W, 1), lr(W), sc(W, 7), ld(W))
  val d9cpu1 = Seq(pause(5), st(Y, 6), lr(Y), trap, sc(Y, 17), lr(Y), ld(Y), sc(Y, 18), lr(Y, 2), sc(Y, 21, 2), lr(Y4, 2), sc(Y4, 22, 2), ld(Y),
                   amo(AmoOp.SWAP, ROM + 8, 1), lr(ROM + 8), sc(ROM + 8, 1), amo(AmoOp.ADD, MMIO, 1), lrsc3, ld(Y))
  // d10: every AMO on both harts against the same word (contention) and different words
  val d10cpu0 = Seq(st(X, BigInt("F0F0F0F080000005", 16))) ++ ops.map(o => amo(o, X, 3)) ++ ops.map(o => amo(o, X, BigInt("FFFFFFFF", 16), 2)) ++ Seq(ld(X))
  val d10cpu1 = Seq(st(Y, 7)) ++ ops.map(o => amo(o, X, 5)) ++ ops.map(o => amo(o, Y, 1)) ++ Seq(ld(X), ld(Y))
  // d11: the drain -- both harts stream AMOs; the reset lands with both in flight (drainAt picked by cycle)
  val d11cpu0 = Seq(st(X, 1)) ++ (1 to 8).map(_ => amo(AmoOp.ADD, X, 1)) ++ Seq(ld(X))
  val d11cpu1 = Seq(st(Y, 1)) ++ (1 to 8).map(_ => amo(AmoOp.ADD, Y, 1)) ++ Seq(ld(Y))
  // d12: fairness -- hart 0 streams without pause, hart 1 is intermittent; Dmax bounds the manager
  val d12cpu0 = Seq(st(X, 0)) ++ (1 to 60).flatMap(_ => Seq(amo(AmoOp.ADD, X, 1), ld(X)))
  val d12cpu1 = Seq(st(Y, 0)) ++ (1 to 12).flatMap(_ => Seq(pause(25), amo(AmoOp.ADD, Y, 1), ld(Y)))
  // d13-d17 (codex-mc-m2a-simultaneous-kill-fix): several VALID reservations cleared in ONE cycle. Both harts
  // hold reservations (X and X, or X and Y), then one event clears both: an external plain write (d13), an
  // external partial write (d14), both cores' resvClear in the same cycle (d15: `until` aligns the traps), one
  // two-beat write whose first beat's size covers both granules (d16: both kills fall in the acceptance cycle).
  // d17: the SAME hart cleared for two reasons in one cycle (its trap and an external write to its word): one
  // reservation, so the count must be exactly one, and the other hart's reservation must survive. The oracle
  // counts cleared VALID reservations from its own state; the floors ask for the exact count and the SC results.
  val d13cpu0 = Seq(st(X, 1), lr(X), until(120), sc(X, 10), ld(X))
  val d13cpu1 = Seq(pause(20), lr(X), until(120), sc(X, 20), ld(X))
  val d13ext1 = Seq(PutStep(0, 80, 1, X, 3, BigInt(555), 0xff))
  val d14ext1 = Seq(PutStep(0, 80, 2, X, 3, BigInt(555), 0x0f))
  val d15cpu0 = Seq(st(X, 1), st(Y, 2), lr(X), until(80), trap, sc(X, 10), ld(X))
  val d15cpu1 = Seq(pause(20), lr(Y), until(80), trap, sc(Y, 20), ld(Y))
  val d16cpu0 = Seq(st(X, 1), st(Y, 2), lr(X), until(120), sc(X, 10), ld(X))
  val d16cpu1 = Seq(pause(20), lr(Y), until(120), sc(Y, 20), ld(Y))
  val d16ext1 = Seq(PutStep(0, 80, 1, X, 4, BigInt(777), 0xff))            // X is 16-byte aligned: beats cover X and Y
  val d17cpu0 = Seq(st(X, 1), lr(X), until(80), trap, until(120), sc(X, 10), ld(X))
  val d17cpu1 = Seq(pause(20), lr(Y), until(120), sc(Y, 20), ld(Y))
  val d17ext1 = Seq(PutStep(0, 80, 1, X, 3, BigInt(555), 0xff))

  // ---- random: a seeded script per hart plus seeded external writers. Deterministic at elaboration.
  val pool = Seq(X, X4, Y, Y4, Z)
  def randomScript(seed: Int, hart: Int, n: Int, pauses: Boolean): Seq[CpuStep] = {
    val r = new scala.util.Random(seed * 7919 + hart * 104729)
    val out = scala.collection.mutable.ArrayBuffer[CpuStep](st(X, 0), st(Y, 0), st(Z, 0))
    var haveLr = false
    while (out.size < n) {
      val w = pool(r.nextInt(pool.size)); val sz = if (w == X4 || w == Y4) 2 else (if (r.nextBoolean()) 3 else 2)
      val k = r.nextInt(100)
      if (k < 25) out += ld(w, sz)
      else if (k < 42) out += st(w, BigInt(r.nextInt(1 << 30)), sz)
      else if (k < 62) out += amo(ops(r.nextInt(ops.size)), w, BigInt(r.nextInt(1 << 30)), sz)
      else if (k < 78) { out += lr(w, sz); haveLr = true }
      else if (k < 94) { out += sc(w, BigInt(r.nextInt(1 << 30)), sz); haveLr = false }
      else if (k < 97) out += trap
      else if (pauses) out += pause(1 + r.nextInt(12))
    }
    out.toSeq :+ ld(X) :+ ld(Y)
  }
  def randomPuts(seed: Int, who: Int, n: Int, spanCycles: Int): Seq[PutStep] = {
    val r = new scala.util.Random(seed * 31337 + who * 7)
    (0 until n).map { i =>
      val at = 50 + (spanCycles.toLong * i / n).toInt + r.nextInt(40)
      // TileLink alignment: a two-beat (size 4) Put only at a 16-byte-aligned word (X, Z); a size-3 Put only at
      // an 8-byte-aligned word; the 4-byte-aligned X4/Y4 get size-2 Puts (the mask is then the low or high lanes)
      val w = pool(r.nextInt(pool.size)); val two = (w == X || w == Z) && r.nextInt(6) == 0
      val sz = if (two) 4 else if (w == X4 || w == Y4) 2 else 3
      val mask = if (sz == 2) (if ((w & 4) != 0) 0xf0 else 0x0f) else if (r.nextInt(3) == 0) 0x0f else 0xff
      PutStep(0, at, if (r.nextInt(3) == 0) 2 else 1, w, sz, BigInt(r.nextInt(1 << 30)), mask)
    }.sortBy(_.arg)
  }
}

class DualAtomicTest(pp: DualParams)(implicit p: Parameters) extends UnitTest(pp.timeout) {
  val dut = Module(LazyModule(new DualAtomicHarness(pp)).module)
  dut.io.start := io.start
  io.finished := dut.io.finished
}
class WithDual(pp: DualParams) extends Config((site, here, up) => {
  case UnitTests => (q: Parameters) => { implicit val p = q; Seq(Module(new DualAtomicTest(pp))) }
})
object DualCfg {
  import DualScen._
  def directed(c0: Seq[CpuStep], c1: Seq[CpuStep], e0: Seq[PutStep] = Nil, e1: Seq[PutStep] = Nil, latency: Int = 4, aStall: Int = 0) =
    DualParams(c0, c1, e0, e1, latency = latency, aStall = aStall)
  // random with backpressure varied by seed; ~6000 CPU steps per hart, external writers over the run
  def random(seed: Int, n: Int = 6000, swap: Boolean = false, extra: Boolean = false, faults: DualParams => DualParams = identity): DualParams = {
    val lat = 2 + (seed % 5); val st = seed % 3; val mds = (seed / 2) % 3; val dq = if (seed % 2 == 0) 0.0 else 0.25
    val span = n * 40
    val base = DualParams(randomScript(seed, 0, n, pauses = true), randomScript(seed, 1, n, pauses = true),
                          randomPuts(seed, 0, n / 8, span), randomPuts(seed, 1, n / 8, span),
                          extra = if (extra) Some(randomPuts(seed, 2, n / 16, span)) else None, swapOrder = swap,
                          latency = lat, aStall = st, mgrDStall = mds, delayQ = dq,
                          respRandom0 = seed % 2 == 1, respStall1 = seed % 4, extDStall = seed % 3,
                          timeout = n * 400)
    faults(base)
  }
}
import DualScen._
class Dual01LrScRaceConfig    extends Config(new WithDual(DualCfg.directed(d1cpu0, d1cpu1)) ++ new Base)
class Dual02StoreKillsConfig  extends Config(new WithDual(DualCfg.directed(d2cpu0, d2cpu1)) ++ new Base)
class Dual03GranulesConfig    extends Config(new WithDual(DualCfg.directed(d3cpu0, d3cpu1)) ++ new Base)
class Dual05TrapLocalConfig   extends Config(new WithDual(DualCfg.directed(d5cpu0, d5cpu1)) ++ new Base)
class Dual06DmaKillsConfig    extends Config(new WithDual(DualCfg.directed(d6cpu0, d6cpu1, Nil, d6ext1)) ++ new Base)
class Dual07PartialKillsConfig extends Config(new WithDual(DualCfg.directed(d7cpu0, d7cpu1)) ++ new Base)
class Dual08FailedScHarmlessConfig extends Config(new WithDual(DualCfg.directed(d8cpu0, d8cpu1)) ++ new Base)
class Dual09PathsConfig       extends Config(new WithDual(DualCfg.directed(d9cpu0, d9cpu1)) ++ new Base)
class Dual10AmoContendConfig  extends Config(new WithDual(DualCfg.directed(d10cpu0, d10cpu1, latency = 6, aStall = 3)) ++ new Base)
class Dual11DrainConfig       extends Config(new WithDual(DualCfg.directed(d11cpu0, d11cpu1, latency = 8).copy(drainAt = 260, resetLen = 3)) ++ new Base)
class Dual12FairConfig        extends Config(new WithDual(DualCfg.directed(d12cpu0, d12cpu1, latency = 6, aStall = 2).copy(mgrDStall = 2)) ++ new Base)
// random seeds 1..10, plus the two topology variants of seed 1
class Dual13ExtKillsBothConfig     extends Config(new WithDual(DualCfg.directed(d13cpu0, d13cpu1, Nil, d13ext1)) ++ new Base)
class Dual14PartialKillsBothConfig extends Config(new WithDual(DualCfg.directed(d13cpu0, d13cpu1, Nil, d14ext1)) ++ new Base)
class Dual15ClearBothConfig        extends Config(new WithDual(DualCfg.directed(d15cpu0, d15cpu1)) ++ new Base)
class Dual16TwoBeatBothConfig      extends Config(new WithDual(DualCfg.directed(d16cpu0, d16cpu1, Nil, d16ext1)) ++ new Base)
class Dual17SameHartTwoReasonsConfig extends Config(new WithDual(DualCfg.directed(d17cpu0, d17cpu1, Nil, d17ext1)) ++ new Base)
class Dual13ExtKillsBothSwapConfig     extends Config(new WithDual(DualCfg.directed(d13cpu0, d13cpu1, Nil, d13ext1).copy(swapOrder = true)) ++ new Base)
class Dual14PartialKillsBothSwapConfig extends Config(new WithDual(DualCfg.directed(d13cpu0, d13cpu1, Nil, d14ext1).copy(swapOrder = true)) ++ new Base)
class Dual15ClearBothSwapConfig        extends Config(new WithDual(DualCfg.directed(d15cpu0, d15cpu1).copy(swapOrder = true)) ++ new Base)
class Dual16TwoBeatBothSwapConfig      extends Config(new WithDual(DualCfg.directed(d16cpu0, d16cpu1, Nil, d16ext1).copy(swapOrder = true)) ++ new Base)
class Dual17SameHartTwoReasonsSwapConfig extends Config(new WithDual(DualCfg.directed(d17cpu0, d17cpu1, Nil, d17ext1).copy(swapOrder = true)) ++ new Base)
class DualRnd1Config  extends Config(new WithDual(DualCfg.random(1))  ++ new Base)
class DualRnd1SmokeConfig extends Config(new WithDual(DualCfg.random(1, n = 300)) ++ new Base)   // fast reproduction of seed 1's topology
class DualRnd2Config  extends Config(new WithDual(DualCfg.random(2))  ++ new Base)
class DualRnd3Config  extends Config(new WithDual(DualCfg.random(3))  ++ new Base)
class DualRnd4Config  extends Config(new WithDual(DualCfg.random(4))  ++ new Base)
class DualRnd5Config  extends Config(new WithDual(DualCfg.random(5))  ++ new Base)
class DualRnd6Config  extends Config(new WithDual(DualCfg.random(6))  ++ new Base)
class DualRnd7Config  extends Config(new WithDual(DualCfg.random(7))  ++ new Base)
class DualRnd8Config  extends Config(new WithDual(DualCfg.random(8))  ++ new Base)
class DualRnd9Config  extends Config(new WithDual(DualCfg.random(9))  ++ new Base)
class DualRnd10Config extends Config(new WithDual(DualCfg.random(10)) ++ new Base)
class DualRnd1SwapConfig  extends Config(new WithDual(DualCfg.random(1, swap = true))  ++ new Base)
class DualRnd1ExtraConfig extends Config(new WithDual(DualCfg.random(1, extra = true)) ++ new Base)
class DualRnd1SwapExtraConfig extends Config(new WithDual(DualCfg.random(1, swap = true, extra = true)) ++ new Base)
// negatives: one defect each; the scorer (or a harness VIOLATION / an assertion) must reject it for its reason
// must REFUSE at elaboration (D4: exact-name binding; no stray hart-like client; unique names)
class DualRefuseMissingConfig extends Config(new WithDual(DualCfg.directed(d1cpu0, d1cpu1).copy(backendNames = Seq("teaching-phys-0", "teaching-phys-9"))) ++ new Base)
class DualRefuseStrayConfig   extends Config(new WithDual(DualCfg.directed(d1cpu0, d1cpu1).copy(backendNames = Seq("teaching-phys-0"))) ++ new Base)
class DualRefuseDupConfig     extends Config(new WithDual(DualCfg.directed(d1cpu0, d1cpu1).copy(backendNames = Seq("teaching-phys-0", "teaching-phys-0"))) ++ new Base)
class DualNegNoCrossKillConfig  extends Config(new WithDual(DualCfg.directed(d2cpu0, d2cpu1).copy(fNoCrossKill = true)) ++ new Base)
class DualNegSwapSidebandConfig extends Config(new WithDual(DualCfg.directed(d5cpu0, d5cpu1).copy(fSwapSideband = true)) ++ new Base)
class DualNegSwapDSourceConfig  extends Config(new WithDual(DualCfg.directed(d10cpu0, d10cpu1).copy(fSwapDSource = true)) ++ new Base)
class DualNegInterleaveConfig   extends Config(new WithDual(DualCfg.random(3, n = 400).copy(fAmoInterleave = true)) ++ new Base)
class DualNegTlWithdrawConfig   extends Config(new WithDual(DualCfg.directed(d10cpu0, d10cpu1, latency = 6, aStall = 3).copy(bridgeFault0 = 11)) ++ new Base)
class DualNegPhysWithdrawConfig extends Config(new WithDual(DualCfg.directed(d1cpu0, d1cpu1).copy(withdraw0 = true)) ++ new Base)
class DualNegWrongSrcConfig     extends Config(new WithDual(DualCfg.directed(d1cpu0, d1cpu1).copy(fWrongSrc = true)) ++ new Base)
class DualNegNoKillConfig       extends Config(new WithDual(DualCfg.directed(d6cpu0, d6cpu1, Nil, d6ext1).copy(fNoKill = true)) ++ new Base)
