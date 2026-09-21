// CPU-A stage 1: the V2 bridge -- the RD1 drain bridge's contract (soft reset / drain / hold, unchanged) plus
// PHYSICAL_PORT_V2: AMOs as TileLink Arithmetic/Logical, LR as a marked Get, SC as a marked Put, the SC result
// and the reservation-clear pulse on the transaction-bound side-band to the AtomicBackend.
// Legality (before any TL request; `error` back and nothing on the bus otherwise): an AMO needs size 2/3,
// alignment, wmask = exactly the lanes, and a target that supports Arithmetic/Logical of that size (only the
// backend's managers -- the declared DRAM region -- do); LR/SC need the same size/alignment and the same
// target class; everything else is the V1 rule.
// faultMode 8 (negative control): the SC decision is taken here, before the serialisation point, from a local
// reservation that only the CPU's own stores and traps clear; the Put goes out unmarked.
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config.Parameters
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.tilelink._
import testchipip.TLHelper

// atomicRegion: the only addresses an AMO / LR / SC may target (the declared DRAM window, CODEX_DECISIONS A3);
// a target inside it must also advertise Arithmetic/Logical (the backend's managers do). Capability alone is
// not enough: the peripheral bus has an atomics automata too and is not allowed.
class RD2BridgeV2(faultMode: Int = 0, applyCycles: Int = 2, drainTimeout: Int = 50000,
                  atomicRegion: Seq[AddressSet] = Seq(AddressSet(0x80000000L, 0x0FFFFFFFL)),
                  // trace: the CPU_REQ / CPU_RESP event lines, on for the scored configurations
                  trace: Boolean = true)(implicit p: Parameters) extends LazyModule {
  require(Seq(0, 8, 9, 10).contains(faultMode),
          "RD2BridgeV2: faultMode 0, 8 (SC decided early), 9 (ADD mapped as SWAP) or 10 (operand halves swapped)")
  val node = TLHelper.makeClientNode("teaching-phys", IdRange(0, 1))

  lazy val module = new LazyModuleImp(this) {
    val io = IO(new Bundle {
      val phys  = Flipped(new PhysPortV2IO)
      val dbg   = new BridgeDebug
      val drain = new BridgeDrainIO
      val sb    = new AtomicSideband
    })
    val (tl, edge) = node.out(0)
    require(edge.bundle.dataBits == 64, s"bridge needs a 64-bit beat, got ${edge.bundle.dataBits}")
    val cyc = RegInit(0.U(32.W)); cyc := cyc + 1.U

    val sIdle :: sIllegal :: sA :: sD :: sResp :: Nil = Enum(5)
    val state = RegInit(sIdle)
    val req   = Reg(new PhysReqV2)
    val rdata = Reg(UInt(64.W))
    val err   = Reg(Bool())
    val scFail = RegInit(false.B)
    val scSeen = RegInit(false.B)          // the side-band result for the outstanding SC has arrived
    val aFires = RegInit(0.U(32.W)); val dFires = RegInit(0.U(32.W))
    val aWaits = RegInit(0.U(32.W)); val sameCyc = RegInit(0.U(32.W))
    val nIllegal = RegInit(0.U(32.W)); val nErr = RegInit(0.U(32.W))
    when (tl.a.valid && !tl.a.ready) { aWaits := aWaits + 1.U }

    // ---- reset / drain phases (RD1 contract, verbatim) --------------------------------------------------
    val rIdle :: rDrain :: rApply :: Nil = Enum(3)
    val phase        = RegInit(rIdle)
    val resetPending = RegInit(false.B)
    val applied      = RegInit(0.U(8.W))
    val epoch        = RegInit(0.U(16.W))
    val txid         = RegInit(0.U(32.W))
    val nDrained     = RegInit(0.U(32.W))
    val nLocalDisc   = RegInit(0.U(32.W))
    val nBufDisc     = RegInit(0.U(32.W))
    val drainCycles  = RegInit(0.U(32.W))
    val timeoutSticky= RegInit(false.B)
    when (io.drain.softReset) { resetPending := true.B }
    val aFire = tl.a.fire()
    val dFire = tl.d.fire()
    val pendingA    = state === sA
    val outstanding = state === sD
    val nextPendingA    = pendingA && !aFire
    val nextOutstanding = (outstanding && !dFire) || (pendingA && aFire && !dFire)
    val pendingWorkNext = nextPendingA || nextOutstanding
    assert(!(dFire && !(outstanding || (pendingA && aFire))), "RD2BridgeV2: D handshake with no A outstanding")
    val effReset = io.drain.softReset || resetPending
    val cpuResetHold = effReset || (phase =/= rIdle)
    val discardNow = effReset
    io.drain.cpuResetHold := cpuResetHold

    // ---- request acceptance and legality ----------------------------------------------------------------
    io.phys.req.ready := (state === sIdle) && !resetPending && !io.drain.softReset
    val in      = io.phys.req.bits
    val allowed = PhysPort.laneMask(in.size, in.addr(2, 0))
    val okAlign = PhysPort.aligned(in.size, in.addr(2, 0))
    val isAmo   = in.amo =/= 0.U
    val isLR    = in.lrsc === LrSc.LR.U
    val isSC    = in.lrsc === LrSc.SC.U
    val atomicClass = isAmo || isLR || isSC
    val okSizeAt = (in.size === 2.U) || (in.size === 3.U)
    val okMask  = Mux(isAmo || isSC, in.wmask === allowed,
                  Mux(in.write, in.wmask =/= 0.U && (in.wmask & (~allowed).asUInt) === 0.U, true.B))
    val okKind  = Mux(isAmo, in.write && (in.amo <= AmoOp.MAXU.U), Mux(isLR, !in.write, Mux(isSC, in.write, true.B))) &&
                  !(isAmo && (isLR || isSC)) && (in.lrsc =/= 3.U)          // lrsc = 3 is not a thing
    val inRegion = atomicRegion.map(_.contains(in.addr)).reduce(_ || _)
    val atomicTarget = inRegion && edge.manager.supportsArithmeticSafe(in.addr, in.size) && edge.manager.supportsLogicalSafe(in.addr, in.size)
    val tlLegal = Mux(atomicClass, atomicTarget && okSizeAt,
                  Mux(in.write, edge.manager.supportsPutPartialSafe(in.addr, in.size), edge.manager.supportsGetSafe(in.addr, in.size)))
    val legal = okAlign && okMask && okKind && tlLegal

    // ---- TL A from the held request -------------------------------------------------------------------------
    // faultMode 9 (negative control): a single mapping defect -- ADD is emitted as a Logical SWAP. Everything
    // else about the request (address, size, operand, lanes) is untouched, and the backend, the memory and the
    // response all agree with each other; only the CPU's request says something different.
    val amoIsLogical = (if (faultMode == 9) req.amo === AmoOp.ADD.U else false.B) ||
                       req.amo === AmoOp.SWAP.U || req.amo === AmoOp.XOR.U || req.amo === AmoOp.AND.U || req.amo === AmoOp.OR.U
    val amoParam = MuxLookup(req.amo, 0.U, Seq(
      (if (faultMode == 9) AmoOp.ADD.U -> TLAtomics.SWAP else AmoOp.ADD.U -> TLAtomics.ADD),
      AmoOp.SWAP.U -> TLAtomics.SWAP, AmoOp.XOR.U -> TLAtomics.XOR, AmoOp.AND.U -> TLAtomics.AND, AmoOp.OR.U -> TLAtomics.OR,
      AmoOp.MIN.U -> TLAtomics.MIN, AmoOp.MAX.U -> TLAtomics.MAX,
      AmoOp.MINU.U -> TLAtomics.MINU, AmoOp.MAXU.U -> TLAtomics.MAXU))
    val (_, getBits)  = edge.Get(0.U, req.addr, req.size)
    val (_, putBits)  = edge.Put(0.U, req.addr, req.size, req.wdata, req.wmask)
    // faultMode 10 (negative control): a single operand defect -- the operand's two 32-bit halves are swapped
    // on the way out (the classic lane slip). Opcode, param, address, size and lanes stay correct.
    val amoOperand = if (faultMode == 10) Cat(req.wdata(31, 0), req.wdata(63, 32)) else req.wdata
    val (_, arBits)   = edge.Arithmetic(0.U, req.addr, req.size, amoOperand, amoParam)
    val (_, lgBits)   = edge.Logical(0.U, req.addr, req.size, amoOperand, amoParam)
    val reqIsAmo = req.amo =/= 0.U
    val reqIsLR  = req.lrsc === LrSc.LR.U
    val reqIsSC  = req.lrsc === LrSc.SC.U
    // faultMode 8: a local reservation decides the SC here; a failing SC is answered without any TL request
    val localResv = RegInit(false.B); val localWord = Reg(UInt(29.W))
    val scEarlyFail = (faultMode == 8).B && reqIsSC && !(localResv && localWord === req.addr(31, 3))
    tl.a.valid := state === sA
    tl.a.bits  := Mux(reqIsAmo, Mux(amoIsLogical, lgBits, arBits), Mux(req.write, putBits, getBits))
    tl.d.ready := (state === sA || state === sD)
    tl.b.ready := false.B; tl.c.valid := false.B; tl.e.valid := false.B

    // ---- the side-band ----------------------------------------------------------------------------------------
    // The mark is pushed when the request is *accepted from the CPU* (one outstanding transaction, so the
    // marked A is the next A this bridge offers), never as a function of a.ready: a mark derived from the A
    // handshake would make the backend's decision depend on the manager's ready, a combinational loop.
    val markNow = io.phys.req.fire() && legal && (isLR || (isSC && (faultMode != 8).B))
    io.sb.mark.valid := markNow
    io.sb.mark.bits.lr := isLR
    io.sb.mark.bits.sc := isSC && (faultMode != 8).B
    io.sb.resvClear := io.phys.resvClear
    when (io.sb.scResult.valid) {
      assert(reqIsSC && (state === sA || state === sD), "RD2BridgeV2: an SC result arrived with no SC outstanding")
      scFail := io.sb.scResult.bits; scSeen := true.B
    }
    if (faultMode == 8) {
      when (aFire && reqIsLR) { localResv := true.B; localWord := req.addr(31, 3) }
      when (aFire && req.write && !reqIsSC && localResv && localWord === req.addr(31, 3)) { localResv := false.B }
      when (io.phys.resvClear) { localResv := false.B }
    }

    when (dFire) {
      dFires := dFires + 1.U
      assert(tl.d.bits.source === 0.U, "RD2BridgeV2: D response with an unknown source")
      assert(tl.d.bits.opcode === Mux(req.write && !reqIsAmo, TLMessages.AccessAck, TLMessages.AccessAckData),
             "RD2BridgeV2: unexpected D opcode for this request type")
      when (tl.d.bits.error) { nErr := nErr + 1.U }
      when (!discardNow) {
        rdata := Mux((req.write && !reqIsAmo) || tl.d.bits.error, 0.U, tl.d.bits.data)
        err   := tl.d.bits.error
      }
    }

    // ---- state machine -------------------------------------------------------------------------------------------
    when (io.phys.req.fire()) {
      req := in; rdata := 0.U; err := !legal; scFail := false.B; scSeen := false.B
      txid := txid + 1.U
      state := Mux(legal, sA, sIllegal)
      when (!legal) { nIllegal := nIllegal + 1.U }
      if (trace) printf(p"AT ${cyc} CPU_REQ txid=${txid + 1.U} addr=0x${Hexadecimal(in.addr)} write=${in.write} size=${in.size} amo=${in.amo} lrsc=${in.lrsc} data=0x${Hexadecimal(in.wdata)} mask=0x${Hexadecimal(in.wmask)} legal=${legal}\n")
    }
    when (state === sIllegal) {
      when (discardNow) { state := sIdle; nLocalDisc := nLocalDisc + 1.U }
      .otherwise          { state := sResp }
    }
    when (state === sA) {
      when (scEarlyFail) {                                        // faultMode 8 only: answered locally, no TL request
        scFail := true.B; scSeen := true.B; localResv := false.B; state := sResp
      } .elsewhen (aFire) {
        aFires := aFires + 1.U
        if (faultMode == 8) { when (reqIsSC) { localResv := false.B } }
        when (dFire) {
          sameCyc := sameCyc + 1.U
          when (discardNow) { state := sIdle; nDrained := nDrained + 1.U } .otherwise { state := sResp }
        } .otherwise { state := sD }
      }
    }
    when (state === sD && dFire) {
      when (discardNow) { state := sIdle; nDrained := nDrained + 1.U } .otherwise { state := sResp }
    }
    // an SC's response is complete only when its side-band result has been bound (same cycle as its D, or earlier)
    val respPending = (state === sResp) && (!reqIsSC || scSeen || err || (faultMode == 8).B)
    io.phys.resp.valid := respPending && !effReset
    val laneBits = FillInterleaved(8, PhysPort.laneMask(req.size, req.addr(2, 0)))
    io.phys.resp.bits.rdata  := Mux(err || (req.write && !reqIsAmo), 0.U, rdata & laneBits)
    io.phys.resp.bits.error  := err
    io.phys.resp.bits.scFail := reqIsSC && scFail
    when (state === sResp && io.phys.resp.fire()) {
      state := sIdle
      if (trace) printf(p"AT ${cyc} CPU_RESP txid=${txid} data=0x${Hexadecimal(io.phys.resp.bits.rdata)} err=${err} scfail=${io.phys.resp.bits.scFail}\n")
    }
    when (discardNow && (state === sResp)) { state := sIdle; nBufDisc := nBufDisc + 1.U }

    // ---- phase machine (RD1, verbatim) ------------------------------------------------------------------------
    val drainDonePulse = WireInit(false.B)
    switch (phase) {
      is (rIdle) { when (io.drain.softReset) { phase := rDrain; drainCycles := 0.U } }
      is (rDrain) {
        drainCycles := drainCycles + 1.U
        when (drainCycles >= drainTimeout.U) { timeoutSticky := true.B }
        when (!pendingWorkNext && !(state === sIllegal) && !(state === sResp)) {
          phase := rApply; applied := 0.U; drainDonePulse := true.B
        }
      }
      is (rApply) {
        applied := applied + 1.U
        when (io.drain.softReset) { applied := 0.U }
        when (applied >= (applyCycles - 1).U && !io.drain.softReset) { phase := rIdle; resetPending := false.B; epoch := epoch + 1.U }
      }
    }
    io.drain.resetPending := resetPending; io.drain.effReset := effReset; io.drain.respBuffered := respPending
    io.drain.draining := phase === rDrain; io.drain.applying := phase === rApply; io.drain.drainDone := drainDonePulse
    io.drain.pendingA := pendingA; io.drain.outstanding := outstanding
    io.drain.pendingANext := nextPendingA; io.drain.outstandingNext := nextOutstanding
    io.drain.timeout := timeoutSticky; io.drain.epoch := epoch; io.drain.txid := txid
    io.drain.nDrained := nDrained; io.drain.nLocalDisc := nLocalDisc; io.drain.nBufDisc := nBufDisc
    io.dbg.aFires := aFires; io.dbg.dFires := dFires; io.dbg.aWaits := aWaits
    io.dbg.sameCyc := sameCyc; io.dbg.illegal := nIllegal; io.dbg.tlErrors := nErr
  }
}
