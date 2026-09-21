// RD1: the experimental bridge -- ReqRespToTL plus the soft-reset / drain contract.
//
// The production bridge (ReqRespToTL.scala) is NOT touched. This is a separate class, used only by the RD1
// harness and by the RD1 copies of the M1 regression configurations, so the default board build and the
// accepted attempt-2 bitstream keep the behaviour they were verified with.
//
// The contract implemented here is codex-rd1-bridge-drain-unit, items 1-6:
//   * softReset is a *signal*, not a reset: this module's own registers are in the cold domain, so a soft
//     reset cannot erase a record of work that is already in flight.
//   * The cycle softReset is sampled, no new CPU request may be accepted.
//   * A request the bridge has already accepted is settled, never abandoned: if its A has not been offered
//     yet the payload is kept and the A is still issued; if a.valid is already high it stays high with a
//     stable payload until a.ready (TileLink irrevocability); once the A has fired, the *real* D is waited
//     for and then discarded.
//   * A locally rejected request and a response already buffered for the CPU may be dropped, because the
//     CPU is being reset -- but each is counted and logged as its own kind of event, never as a TL D.
//   * A/D in the same cycle is resolved by computing next-pendingA / next-outstanding combinationally from
//     both handshakes, not by a priority branch.
//   * Any single sampled cycle of softReset latches resetPending; cpuResetHold is released only after the
//     drain finishes, the buffered response is cleared, and the CPU has actually been held in reset for at
//     least `applyCycles` cycles. softReset having returned to 0 does not excuse any of that.
//   * Nothing is ever force-cleared: with no response and no a.ready, the record and the hold stay, and a
//     timeout is only a status bit.
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config.Parameters
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.tilelink._
import testchipip.TLHelper

class BridgeDrainIO extends Bundle {
  val softReset    = Input(Bool())    // level; one sampled cycle is enough
  val cpuResetHold = Output(Bool())   // the CPU endpoint must be held in reset while this is high
  val resetPending = Output(Bool())
  val effReset     = Output(Bool())   // a soft reset is in effect this very cycle
  val respBuffered = Output(Bool())   // a response is held for the CPU, before any reset masking
  val draining     = Output(Bool())
  val drainDone    = Output(Bool())   // pulse: the cycle the drain phase completes
  val applying     = Output(Bool())
  val pendingA     = Output(Bool())   // registered, this cycle
  val outstanding  = Output(Bool())   // registered, this cycle
  val pendingANext = Output(Bool())   // after this cycle's handshakes: what the drain decides on
  val outstandingNext = Output(Bool())
  val timeout      = Output(Bool())   // sticky
  val epoch        = Output(UInt(16.W))
  val txid         = Output(UInt(32.W))
  val nDrained     = Output(UInt(32.W))  // real TL D discarded because the CPU was being reset
  val nLocalDisc   = Output(UInt(32.W))  // locally rejected request dropped (never had a TL transaction)
  val nBufDisc     = Output(UInt(32.W))  // response already buffered for the CPU, dropped
}

// legacyDrain models today's production behaviour inside this harness: a soft reset simply clears the
// bridge's own state, the CPU is released as soon as the reset level drops, and nothing is drained. It is a
// *model* of the old behaviour, not the production RTL; the production RTL is exercised unchanged by the
// M1 13-case regression instead.
class RD1Bridge(faultMode: Int = 0, legacyDReady: Boolean = false,
                applyCycles: Int = 2, drainTimeout: Int = 50000,
                legacyDrain: Boolean = false)(implicit p: Parameters) extends LazyModule {
  val node = TLHelper.makeClientNode("teaching-phys", IdRange(0, 1))

  lazy val module = new LazyModuleImp(this) {
    val io = IO(new Bundle {
      val phys  = Flipped(new PhysPortIO)
      val dbg   = new BridgeDebug
      val drain = new BridgeDrainIO
    })
    val (tl, edge) = node.out(0)
    require(edge.bundle.dataBits == 64, s"bridge needs a 64-bit beat, got ${edge.bundle.dataBits}")

    val sIdle :: sIllegal :: sA :: sD :: sResp :: sDiscard :: sDup :: Nil = Enum(7)
    val state = RegInit(sIdle)
    val req   = Reg(new PhysReq)
    val rdata = Reg(UInt(64.W))
    val err   = Reg(Bool())
    val aFires = RegInit(0.U(32.W)); val dFires = RegInit(0.U(32.W))
    val aWaits = RegInit(0.U(32.W)); val sameCyc = RegInit(0.U(32.W))
    val nIllegal = RegInit(0.U(32.W)); val nErr = RegInit(0.U(32.W))
    when (tl.a.valid && !tl.a.ready) { aWaits := aWaits + 1.U }

    // ---- reset / drain phases -------------------------------------------------------------------------
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

    // one sampled cycle of softReset is enough, and it cannot be un-requested
    when (io.drain.softReset) { resetPending := true.B }

    // ---- pending work, from both handshakes in the same cycle ------------------------------------------
    val aFire = tl.a.fire()
    val dFire = tl.d.fire()
    val pendingA    = state === sA                                  // A offered (or about to be), not accepted
    val outstanding = (state === sD) || (state === sDiscard)        // A accepted, D not yet returned
    val nextPendingA    = pendingA && !aFire
    val nextOutstanding = (outstanding && !dFire) || (pendingA && aFire && !dFire)
    val pendingWorkNext = nextPendingA || nextOutstanding
    // a D with nothing outstanding is not something this bridge may ever normalise into a response
    // In the drain design this is a design invariant. In the legacy model it is the fault being reproduced,
    // so there it is left to the scoreboard to report rather than aborting the run.
    if (!legacyDrain) {
      assert(!(dFire && !(outstanding || (pendingA && aFire))),
             "RD1Bridge: D handshake with no A outstanding")
    }

    val srDelayed = RegNext(io.drain.softReset, false.B)
    // effReset is the contract's "a soft reset is in effect": the sampled level itself, plus the latched
    // request. Both the hold and the response mask use it, so neither is a cycle late.
    val effReset = io.drain.softReset || resetPending
    val cpuResetHold = if (legacyDrain) (io.drain.softReset || srDelayed) else (effReset || (phase =/= rIdle))
    // discardNow is the *drain contract's* action: accept the beat that is already owed, account for it and
    // drop it as its own event. Today's bridge has no such action -- a reset simply wipes the state below,
    // so the CPU's request leaves no terminal at all. Keeping that distinction is the whole point of the
    // comparison, so none of the accounted discards below may run in the legacy model.
    val discardNow = if (legacyDrain) false.B else effReset
    io.drain.cpuResetHold := cpuResetHold

    // ---- CPU request acceptance -------------------------------------------------------------------------
    // The cycle softReset is sampled, no new request is accepted: ready is low for the reset level itself and
    // for the whole pending window, so req.fire cannot race the reset.
    io.phys.req.ready := (if (legacyDrain) ((state === sIdle) && !io.drain.softReset)
                         else ((state === sIdle) && !resetPending && !io.drain.softReset))

    val in      = io.phys.req.bits
    val allowed = PhysPort.laneMask(in.size, in.addr(2, 0))
    val okAlign = PhysPort.aligned(in.size, in.addr(2, 0))
    val okMask  = Mux(in.write, in.wmask =/= 0.U && (in.wmask & (~allowed).asUInt) === 0.U, true.B)
    val tlLegal = Mux(in.write, edge.manager.supportsPutPartialSafe(in.addr, in.size),
                                edge.manager.supportsGetSafe(in.addr, in.size))
    val legal = okAlign && okMask && tlLegal

    // ---- TL A ------------------------------------------------------------------------------------------
    val (_, getBits) = edge.Get(0.U, req.addr, req.size)
    val (_, putBits) = edge.Put(0.U, req.addr, req.size, req.wdata, req.wmask)
    tl.a.valid := state === sA          // held stable across a soft reset: `state` is in the cold domain
    tl.a.bits  := Mux(req.write, putBits, getBits)
    if (faultMode == 1) {
      val waited = RegNext(tl.a.valid && !tl.a.ready, false.B)
      when (state === sA && waited) { tl.a.bits.data := (~req.wdata).asUInt }
    }

    tl.d.ready := (if (legacyDReady) (state === sD || state === sDiscard)
                   else (state === sA || state === sD || state === sDiscard))
    tl.b.ready := false.B; tl.c.valid := false.B; tl.e.valid := false.B

    val dropFirstRead = RegInit((faultMode == 2).B)
    when (dFire) {
      dFires := dFires + 1.U
      assert(tl.d.bits.source === 0.U, "RD1Bridge: D response with an unknown source")
      when (tl.d.bits.error) { nErr := nErr + 1.U }
      when (state =/= sDiscard && !discardNow) {
        rdata := Mux(req.write || tl.d.bits.error, 0.U, tl.d.bits.data)
        err   := (if (faultMode == 5) false.B else tl.d.bits.error)
      }
    }

    // ---- state machine ---------------------------------------------------------------------------------
    when (io.phys.req.fire()) {
      req   := in
      rdata := 0.U
      err   := !legal
      txid  := txid + 1.U
      state := Mux(legal, sA, sIllegal)
      when (!legal) { nIllegal := nIllegal + 1.U }
    }
    // a locally rejected request never had a TL transaction: under reset it is dropped as its own event
    when (state === sIllegal) {
      when (discardNow) { state := sIdle; nLocalDisc := nLocalDisc + 1.U }
      .otherwise          { state := sResp }
    }
    when (state === sA) {
      when (aFire) {
        aFires := aFires + 1.U
        val dropIt = if (faultMode == 2) (dropFirstRead && !req.write) else false.B
        when (dFire) {                                   // zero-latency manager: A and D in one cycle
          sameCyc := sameCyc + 1.U
          if (faultMode == 2) { when (dropIt) { dropFirstRead := false.B } }
          when (discardNow) { state := sIdle; nDrained := nDrained + 1.U }   // real D, discarded
          .otherwise          { state := Mux(dropIt, sIdle, sResp) }
        } .otherwise {
          if (faultMode == 4) { when (req.write) { rdata := 0.U; err := false.B } }
          state := (if (faultMode == 4) Mux(req.write, sDiscard, sD) else sD)
        }
      }
    }
    when (state === sD && dFire) {
      when (discardNow) { state := sIdle; nDrained := nDrained + 1.U }           // the real D, then discarded
      .otherwise {
        if (faultMode == 2) {
          when (dropFirstRead && !req.write) { dropFirstRead := false.B; state := sIdle } .otherwise { state := sResp }
        } else { state := sResp }
      }
    }
    when (state === sDiscard && dFire) { state := sIdle }

    // ---- response to the CPU ---------------------------------------------------------------------------
    val laneBits = FillInterleaved(8, PhysPort.laneMask(req.size, req.addr(2, 0)))
    val respPending = (state === sResp) || (state === sDup) ||
                      (if (faultMode == 4) (state === sDiscard && req.write) else false.B)
    val withdrawOnce = RegInit((faultMode == 6).B)
    val holdBlocked = RegNext(io.phys.resp.valid && !io.phys.resp.ready, false.B)
    // never offer a response to a CPU that is being reset
    if (faultMode == 6) {
      io.phys.resp.valid := respPending && !effReset && !(withdrawOnce && holdBlocked)
      when (respPending && holdBlocked && withdrawOnce) { withdrawOnce := false.B }
    } else {
      io.phys.resp.valid := respPending && !effReset
    }
    io.phys.resp.bits.rdata := Mux(err || req.write, 0.U, rdata & laneBits)
    io.phys.resp.bits.error := err
    if (faultMode == 7) {
      when (holdBlocked) { io.phys.resp.bits.rdata := (~(rdata & laneBits)).asUInt }
    }
    when (state === sResp && io.phys.resp.fire()) { state := (if (faultMode == 3) sDup else sIdle) }
    when (state === sDup) { state := sIdle }
    // a response already buffered for the CPU is dropped, as its own event, when the CPU is being reset
    when (discardNow && (state === sResp || state === sDup)) {
      state := sIdle; nBufDisc := nBufDisc + 1.U
    }

    // ---- phase machine ---------------------------------------------------------------------------------
    val drainDonePulse = WireInit(false.B)
    if (legacyDrain) {
      // today's behaviour: the reset clears the bridge, the CPU is let go the cycle the level drops, and
      // nothing is drained or confirmed. No phase machine at all.
      phase := rIdle
    } else switch (phase) {
      is (rIdle) {
        when (io.drain.softReset) { phase := rDrain; drainCycles := 0.U }
      }
      is (rDrain) {
        drainCycles := drainCycles + 1.U
        when (drainCycles >= drainTimeout.U) { timeoutSticky := true.B }   // status only: nothing is cleared
        // the drain is over when no work remains *and* nothing is left buffered for the CPU
        when (!pendingWorkNext && !(state === sIllegal) && !(state === sResp) && !(state === sDup)) {
          phase := rApply; applied := 0.U; drainDonePulse := true.B
        }
      }
      is (rApply) {
        applied := applied + 1.U
        when (io.drain.softReset) { applied := 0.U }                        // a new request re-arms the hold
        when (applied >= (applyCycles - 1).U && !io.drain.softReset) {
          phase := rIdle; resetPending := false.B; epoch := epoch + 1.U     // the real CPU restart boundary
        }
      }
    }

    if (legacyDrain) {
      // what a reset does today: the record of work in flight is erased, the CPU is let go immediately
      when (io.drain.softReset) { state := sIdle; rdata := 0.U; err := false.B; resetPending := false.B }
      when (!io.drain.softReset && srDelayed) { epoch := epoch + 1.U }
    }

    io.drain.resetPending := resetPending
    io.drain.effReset     := effReset
    io.drain.respBuffered := respPending
    io.drain.draining     := phase === rDrain
    io.drain.applying     := phase === rApply
    io.drain.drainDone    := drainDonePulse
    io.drain.pendingA     := pendingA
    io.drain.outstanding  := outstanding
    io.drain.pendingANext := nextPendingA
    io.drain.outstandingNext := nextOutstanding
    io.drain.timeout      := timeoutSticky
    io.drain.epoch        := epoch
    io.drain.txid         := txid
    io.drain.nDrained     := nDrained
    io.drain.nLocalDisc   := nLocalDisc
    io.drain.nBufDisc     := nBufDisc

    io.dbg.aFires := aFires; io.dbg.dFires := dFires; io.dbg.aWaits := aWaits
    io.dbg.sameCyc := sameCyc; io.dbg.illegal := nIllegal; io.dbg.tlErrors := nErr
  }
}
