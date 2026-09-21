// CPU-A stage 1: the atomic / reservation backend -- a TileLink adapter placed on the DRAM path after every
// PL master has merged, so an AMO is serialised against the CPU, the TSI adapter and the block-device DMA
// alike. Strictly serial: one transaction of any kind at a time. Design: cpu-atomic-backend/DESIGN.md §2.
//
// Not rocket-chip's TLAtomicAutomata (which keeps going after a read error and only ORs the error at the end):
// here a Get that returns an error ends the AMO with one error response and no Put (CODEX_DECISIONS.md, 1).
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config.Parameters
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.tilelink._

class AtomicBackendDebug extends Bundle {
  val state     = Output(UInt(4.W))
  val resvValid = Output(Bool())
  val resvWord  = Output(UInt(29.W))
  val nAmo      = Output(UInt(32.W))
  val nScOk     = Output(UInt(32.W))
  val nScFail   = Output(UInt(32.W))
  val nKill     = Output(UInt(32.W))
  val busy      = Output(Bool())
}

// faultReadErrWrites: the rocket-chip behaviour -- a read error still issues the Put (negative control)
// faultNoKill: an external write does not clear the reservation (negative control)
// faultWrongSource: the CPU is identified by a hard-coded source (the wrong one) instead of by client name
class AtomicBackend(faultReadErrWrites: Boolean = false, faultNoKill: Boolean = false,
                    faultWrongSource: Boolean = false, cpuClientName: String = "teaching-phys",
                    dramRegion: Seq[AddressSet] = Seq(AddressSet(0x80000000L, 0x0FFFFFFFL)),
                    // NOTE on how these are gated: use `if (trace)`, a Scala conditional, and never
                    // `when (trace.B)`. The Chisel form still elaborates the printf with a constant-false
                    // condition, so twelve $fwrite calls survived into a board netlist that is meant to
                    // have none. A printf inside an enclosing `when` is already emitted under that
                    // condition, so the two forms are identical at run time and differ only in whether the
                    // logic exists at all.
                    // trace: the per-transaction "AT ..." event lines. True for every configuration that
                    // scores them; false for an OS-length run, where they would cost ~80 bytes per cycle.
                    trace: Boolean = true)
                   (implicit p: Parameters) extends LazyModule {
  val atomicSizes = TransferSizes(4, 8)
  // atomics are added only to managers that lie entirely inside the declared DRAM window and can do Get+PutFull
  val node = TLAdapterNode(
    clientFn  = { cp => cp },
    managerFn = { mp => mp.copy(managers = mp.managers.map { m =>
      val inDram = m.address.forall(a => dramRegion.exists(d => d.contains(a)))
      val can = inDram && m.supportsGet.contains(atomicSizes) && m.supportsPutFull.contains(atomicSizes)
      if (can) m.copy(supportsArithmetic = atomicSizes, supportsLogical = atomicSizes) else m }) })

  lazy val module = new LazyModuleImp(this) {
    val io = IO(new Bundle {
      val sb  = Flipped(new AtomicSideband)
      val dbg = new AtomicBackendDebug
    })
    val (in, edgeIn)   = node.in(0)
    val (out, edgeOut) = node.out(0)
    require(edgeIn.bundle.dataBits == 64, "AtomicBackend: 64-bit beats only")
    val cyc = RegInit(0.U(32.W)); cyc := cyc + 1.U

    // ---- who is the CPU: by client name, never by a typed-in number ----------------------------------
    val cpuClient = edgeIn.client.clients.find(_.name == cpuClientName)
    require(cpuClient.isDefined, s"AtomicBackend: no client named $cpuClientName on the inner edge; clients = " +
            edgeIn.client.clients.map(_.name).mkString(","))
    val cpuLo = cpuClient.get.sourceId.start; val cpuHi = cpuClient.get.sourceId.end
    val started = RegInit(false.B)
    when (!started) { started := true.B; if (trace) { printf(p"AT ${cyc} CPU_SOURCE lo=${cpuLo.U} hi=${cpuHi.U} clients=${edgeIn.client.clients.size.U}\n") } }
    val wrongLo = if (faultWrongSource) (cpuHi + 1) else cpuLo
    val wrongHi = if (faultWrongSource) (cpuHi + 2) else cpuHi
    def isCpuSrc(s: UInt): Bool = (s >= wrongLo.U) && (s < wrongHi.U)

    // ---- the mark queue (depth 1: the CPU has one transaction outstanding) ------------------------------
    // The bridge pushes the mark when it accepts the CPU's request, at least one cycle before it offers the A,
    // so a registered queue is enough (a flow-through queue would tie the backend's decision to the bridge's A
    // handshake and, through the manager's ready, form a combinational loop).
    val markQ = Module(new Queue(new AtomicMark, 1))
    markQ.io.enq.valid := io.sb.mark.valid
    markQ.io.enq.bits  := io.sb.mark.bits
    assert(!(io.sb.mark.valid && !markQ.io.enq.ready), "AtomicBackend: mark pushed while one is pending")

    // ---- state ------------------------------------------------------------------------------------------
    val sIdle :: sPass :: sPassD :: sGet :: sGetD :: sPut :: sPutD :: sResp :: sScFail :: Nil = Enum(9)
    val state = RegInit(sIdle)
    val req     = Reg(new TLBundleA(edgeIn.bundle))
    val kindLR  = RegInit(false.B); val kindSC = RegInit(false.B); val kindAMO = RegInit(false.B)
    val oldData = Reg(UInt(64.W)); val errAcc = RegInit(false.B)
    val nAmo = RegInit(0.U(32.W)); val nScOk = RegInit(0.U(32.W)); val nScFail = RegInit(0.U(32.W)); val nKill = RegInit(0.U(32.W))

    val resvValid = RegInit(false.B)
    val resvWord  = Reg(UInt(29.W))
    def killResv(why: String): Unit = {
      when (resvValid) { if (trace) { printf(p"AT ${cyc} RESV kill word=0x${Hexadecimal(Cat(resvWord, 0.U(3.W)))} why=$why\n") }; nKill := nKill + 1.U }
      resvValid := false.B
    }

    // ---- classify the A offered by the inner side -------------------------------------------------------
    val a = in.a.bits
    val aIsCpu   = isCpuSrc(a.source)
    val aIsAmo   = a.opcode === TLMessages.ArithmeticData || a.opcode === TLMessages.LogicalData
    val aIsPut   = a.opcode === TLMessages.PutFullData || a.opcode === TLMessages.PutPartialData
    val aIsGet   = a.opcode === TLMessages.Get
    val aWrites  = aIsAmo || aIsPut
    val aMark    = markQ.io.deq.valid && aIsCpu
    val aIsLR    = aMark && markQ.io.deq.bits.lr && aIsGet
    val aIsSC    = aMark && markQ.io.deq.bits.sc && aIsPut
    assert(!(in.a.valid && aIsCpu && markQ.io.deq.valid && !(aIsLR || aIsSC)),
           "AtomicBackend: a marked CPU transaction is neither an LR Get nor an SC Put")
    val aFirst = edgeIn.first(in.a); val aLast = edgeIn.last(in.a)
    // byte range of the offered A (single or multi-beat: size covers the whole transfer)
    val aLo = a.address; val aHi = a.address + (1.U << a.size)
    val wLo = Cat(resvWord, 0.U(3.W)); val wHi = wLo + 8.U
    val aOverlaps = (aLo < wHi) && (aHi > wLo)

    // accept one transaction at a time; a multi-beat Put streams its beats in sPass
    val acceptNew = state === sIdle
    // an AMO or an SC is accepted without being forwarded (the backend issues its own downstream transactions);
    // a plain transfer streams through and needs the outward ready; during an SC's own forward no inner beat
    // may be taken
    in.a.ready := Mux(acceptNew, Mux(aIsAmo || aIsSC, true.B, out.a.ready), (state === sPass) && !kindSC && out.a.ready)
    markQ.io.deq.ready := in.a.fire() && aFirst && aIsCpu && acceptNew && aMark

    // ---- reservation events on acceptance ----------------------------------------------------------------
    when (in.a.fire() && aFirst && acceptNew) {
      if (trace) printf(p"AT ${cyc} A_ACC src=${a.source} cpu=${aIsCpu} op=${a.opcode} param=${a.param} addr=0x${Hexadecimal(a.address)} size=${a.size} " +
             p"data=0x${Hexadecimal(a.data)} mask=0x${Hexadecimal(a.mask)} kind=${Mux(aIsLR, 1.U, Mux(aIsSC, 2.U, Mux(aIsAmo, 3.U, 0.U)))}\n")
      when (aIsLR) {
        resvValid := true.B; resvWord := a.address(31, 3)
        if (trace) printf(p"AT ${cyc} RESV set word=0x${Hexadecimal(Cat(a.address(31, 3), 0.U(3.W)))}\n")
      } .elsewhen (aIsSC) {
        // consumed whatever happens; the success decision is below
      } .elsewhen (aWrites && aIsCpu && resvValid && aOverlaps) {
        killResv("cpu-write")
      } .elsewhen (aWrites && !aIsCpu && resvValid && aOverlaps && !faultNoKill.B) {
        killResv("external-write")
      }
    }
    // beats of a multi-beat transfer after the first: the range was already covered by the first beat's size
    when (in.a.fire() && !aFirst) { if (trace) { printf(p"AT ${cyc} A_BEAT src=${a.source} addr=0x${Hexadecimal(a.address)} data=0x${Hexadecimal(a.data)} mask=0x${Hexadecimal(a.mask)}\n") } }
    when (io.sb.resvClear) { killResv("core-clear") }

    // ---- the AMO ALU ------------------------------------------------------------------------------------------
    val shift  = Cat(req.address(2, 0), 0.U(3.W))
    val is32   = req.size === 2.U
    val oldLane = (oldData >> shift)(63, 0)
    val opdLane = (req.data >> shift)(63, 0)
    val oldV = Mux(is32, oldLane(31, 0).asSInt.pad(64).asUInt, oldLane)   // sign-extended views for signed compare
    val opdV = Mux(is32, opdLane(31, 0).asSInt.pad(64).asUInt, opdLane)
    val oldU = Mux(is32, oldLane(31, 0).pad(64), oldLane)
    val opdU = Mux(is32, opdLane(31, 0).pad(64), opdLane)
    val isArith = req.opcode === TLMessages.ArithmeticData
    val prm = req.param
    val resArith = MuxLookup(prm, oldU, Seq(
      TLAtomics.MIN  -> Mux(oldV.asSInt < opdV.asSInt, oldU, opdU),
      TLAtomics.MAX  -> Mux(oldV.asSInt > opdV.asSInt, oldU, opdU),
      TLAtomics.MINU -> Mux(oldU < opdU, oldU, opdU),
      TLAtomics.MAXU -> Mux(oldU > opdU, oldU, opdU),
      TLAtomics.ADD  -> (oldU + opdU)))
    val resLogic = MuxLookup(prm, oldU, Seq(
      TLAtomics.XOR  -> (oldU ^ opdU), TLAtomics.OR -> (oldU | opdU), TLAtomics.AND -> (oldU & opdU), TLAtomics.SWAP -> opdU))
    val res = Mux(isArith, resArith, resLogic)
    val laneBits = Mux(is32, "hFFFFFFFF".U(64.W), "hFFFFFFFFFFFFFFFF".U(64.W)) << shift
    val newData = ((oldData & (~laneBits).asUInt) | ((res << shift)(63, 0) & laneBits))(63, 0)

    // ---- outward A ----------------------------------------------------------------------------------------------
    val (_, getBits) = edgeOut.Get(req.source, req.address, req.size)
    val (_, putBits) = edgeOut.Put(req.source, req.address, req.size, newData)
    out.a.valid := false.B; out.a.bits := in.a.bits
    when (state === sIdle)      { out.a.valid := in.a.valid && !aIsAmo && !aIsSC; out.a.bits := in.a.bits }   // plain / LR pass straight through
    when (state === sPass)      { out.a.valid := in.a.valid; out.a.bits := in.a.bits }
    when (state === sGet)       { out.a.valid := true.B; out.a.bits := getBits }
    when (state === sPut)       { out.a.valid := true.B; out.a.bits := putBits }
    // an SC that passes is forwarded from the latched request (its single beat) in sPass as well
    val scPassBits = Wire(new TLBundleA(edgeOut.bundle)); scPassBits := req

    // ---- inward D: pass-through or synthesised --------------------------------------------------------------
    val dPass = state === sPass || state === sPassD || state === sIdle
    in.d.valid := false.B; in.d.bits := out.d.bits; out.d.ready := false.B
    when (dPass) { in.d.valid := out.d.valid; out.d.ready := in.d.ready }
    when (state === sGetD || state === sPutD) { out.d.ready := true.B }   // consumed internally
    val (_, respOkBits)   = (0, edgeIn.AccessAck(req.source, req.size, oldData, errAcc))
    val (_, respFailBits) = (0, edgeIn.AccessAck(req.source, req.size, true.B))
    when (state === sResp)   { in.d.valid := true.B; in.d.bits := edgeIn.AccessAck(req.source, req.size, Mux(errAcc, 0.U, oldData), errAcc) }
    when (state === sScFail) { in.d.valid := true.B; in.d.bits := edgeIn.AccessAck(req.source, req.size) }
    io.sb.scResult.valid := false.B; io.sb.scResult.bits := false.B

    // ---- the state machine ---------------------------------------------------------------------------------------
    val dLast = edgeOut.last(out.d)
    switch (state) {
      is (sIdle) {
        when (in.a.valid) {
          req := in.a.bits; kindLR := aIsLR; kindSC := aIsSC; kindAMO := aIsAmo; errAcc := false.B
          when (aIsAmo) {
            when (in.a.ready) { state := sGet; nAmo := nAmo + 1.U; if (trace) { printf(p"AT ${cyc} AMO_START\n") } }   // accepted, not forwarded
          } .elsewhen (aIsSC) {
            when (in.a.ready) {
              val ok = resvValid && (resvWord === a.address(31, 3))
              resvValid := false.B
              when (ok) { state := sPass; if (trace) { printf(p"AT ${cyc} SC_OK word=0x${Hexadecimal(a.address)}\n") }; nScOk := nScOk + 1.U }
              .otherwise { state := sScFail; if (trace) { printf(p"AT ${cyc} SC_FAIL word=0x${Hexadecimal(a.address)} resv=${resvValid}\n") }; nScFail := nScFail + 1.U }
            }
          } .elsewhen (in.a.fire()) {
            state := Mux(aLast, sPassD, sPass)
          }
        }
      }
      is (sPass) {           // remaining A beats of a multi-beat transfer, or the SC's own single Put
        when (kindSC) {
          out.a.valid := true.B; out.a.bits := scPassBits
          when (out.a.fire()) { state := sPassD }
        } .otherwise {
          when (in.a.fire() && aLast) { state := sPassD }
        }
      }
      is (sPassD) {
        when (out.d.fire() && dLast) {
          if (trace) printf(p"AT ${cyc} D_OUT src=${out.d.bits.source} data=0x${Hexadecimal(out.d.bits.data)} err=${out.d.bits.error} kind=${Mux(kindLR, 1.U, Mux(kindSC, 2.U, 0.U))}\n")
          when (kindLR && out.d.bits.error) { killResv("lr-error") }
          when (kindSC) { io.sb.scResult.valid := true.B; io.sb.scResult.bits := false.B }
          state := sIdle
        }
      }
      is (sGet)  { when (out.a.fire()) { state := sGetD; if (trace) { printf(p"AT ${cyc} AMO_GET addr=0x${Hexadecimal(req.address)}\n") } } }
      is (sGetD) {
        when (out.d.fire()) {
          assert(out.d.bits.opcode === TLMessages.AccessAckData, "AtomicBackend: the AMO's Get was not answered with data")
          oldData := out.d.bits.data; errAcc := out.d.bits.error
          when (out.d.bits.error && !faultReadErrWrites.B) { state := sResp; if (trace) { printf(p"AT ${cyc} AMO_READ_ERROR no-put\n") } }
          .otherwise { state := sPut }
        }
      }
      is (sPut)  { when (out.a.fire()) { state := sPutD; if (trace) { printf(p"AT ${cyc} AMO_PUT addr=0x${Hexadecimal(req.address)} data=0x${Hexadecimal(newData)}\n") } } }
      is (sPutD) {
        when (out.d.fire()) {
          assert(out.d.bits.opcode === TLMessages.AccessAck, "AtomicBackend: the AMO's Put was not answered with AccessAck")
          errAcc := errAcc || out.d.bits.error
          state := sResp
        }
      }
      is (sResp) {
        when (in.d.fire()) {
          if (trace) printf(p"AT ${cyc} D_OUT src=${req.source} data=0x${Hexadecimal(Mux(errAcc, 0.U, oldData))} err=${errAcc} kind=3\n")
          state := sIdle
        }
      }
      is (sScFail) {
        when (in.d.fire()) {
          if (trace) printf(p"AT ${cyc} D_OUT src=${req.source} data=0x0 err=0 kind=2 scfail=1\n")
          io.sb.scResult.valid := true.B; io.sb.scResult.bits := true.B
          state := sIdle
        }
      }
    }
    // a Put that is not accepted by the manager (a stuck a.ready) keeps its beat offered: TileLink irrevocability
    // is preserved by driving out.a from the *same* inner beat / latched request every cycle.
    in.b.valid := false.B; in.c.ready := true.B; in.e.ready := true.B
    out.b.ready := true.B; out.c.valid := false.B; out.e.valid := false.B

    io.dbg.state := state; io.dbg.resvValid := resvValid; io.dbg.resvWord := resvWord
    io.dbg.nAmo := nAmo; io.dbg.nScOk := nScOk; io.dbg.nScFail := nScFail; io.dbg.nKill := nKill
    io.dbg.busy := state =/= sIdle
  }
}
