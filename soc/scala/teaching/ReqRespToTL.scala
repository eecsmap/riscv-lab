// M1-b: PHYSICAL_PORT_V1 -> TileLink-UL bridge, for the legacy rocket-chip checkout
// (TLBundleD carries `error`, not denied/corrupt; edge.Get/Put take lgSize; TLHelper lives in testchipip).
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config.Parameters
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.tilelink._
import testchipip.TLHelper

class BridgeDebug extends Bundle {
  val aFires   = Output(UInt(32.W))   // TL A handshakes; a locally rejected request must not change this
  val dFires   = Output(UInt(32.W))   // TL D handshakes; a write may not be reported complete before this increments
  val aWaits   = Output(UInt(32.W))   // cycles the A payload was offered but not accepted (req-side backpressure)
  val sameCyc  = Output(UInt(32.W))   // transactions whose D arrived in the very cycle A fired (zero-latency manager)
  val illegal  = Output(UInt(32.W))
  val tlErrors = Output(UInt(32.W))
}

// faultMode: deliberate defects, used as positive controls for the tester (0 = correct).
//   1 mutate the write payload while the TL request waits for ready
//   2 drop the first read response
//   3 duplicate a response (valid for one extra cycle)
//   4 report a write complete on the A handshake, before AccessAck
//   5 swallow the error bit
//   6 withdraw resp.valid for a cycle while the consumer is not ready, then re-assert
//   7 mutate the response payload while the consumer is not ready
// legacyDReady reproduces the first version of this bridge, which only accepted D after leaving the A state
// and therefore deadlocks against a legal combinational manager whose a.ready depends on d.ready.
class ReqRespToTL(faultMode: Int = 0, legacyDReady: Boolean = false)(implicit p: Parameters) extends LazyModule {
  val node = TLHelper.makeClientNode("teaching-phys", IdRange(0, 1))

  lazy val module = new LazyModuleImp(this) {
    val io = IO(new Bundle {
      val phys = Flipped(new PhysPortIO)
      val dbg  = new BridgeDebug
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

    // Accept only when idle; the state leaves sResp the cycle after the response handshake, so a new request
    // is never accepted in the response handshake cycle (PHYSICAL_PORT_V1's conservative turnaround).
    io.phys.req.ready := state === sIdle

    // ---- local legality. edge.Get/Put return the *Fast* flag, which only checks the transfer size and
    // assumes the address is mapped; the address and the per-manager size limits need the Safe helpers.
    val in      = io.phys.req.bits
    val allowed = PhysPort.laneMask(in.size, in.addr(2, 0))
    val okAlign = PhysPort.aligned(in.size, in.addr(2, 0))
    val okMask  = Mux(in.write, in.wmask =/= 0.U && (in.wmask & (~allowed).asUInt) === 0.U, true.B)
    val tlLegal = Mux(in.write, edge.manager.supportsPutPartialSafe(in.addr, in.size),
                                edge.manager.supportsGetSafe(in.addr, in.size))
    val legal = okAlign && okMask && tlLegal

    // ---- TL A, built from the held request so the payload is stable until a.fire
    val (_, getBits) = edge.Get(0.U, req.addr, req.size)
    val (_, putBits) = edge.Put(0.U, req.addr, req.size, req.wdata, req.wmask)   // PutPartialData
    tl.a.valid := state === sA
    tl.a.bits  := Mux(req.write, putBits, getBits)
    if (faultMode == 1) {
      val waited = RegNext(tl.a.valid && !tl.a.ready, false.B)
      when (state === sA && waited) { tl.a.bits.data := (~req.wdata).asUInt }
    }

    // ---- TL D. Accepting D while still in sA is what makes a combinational (minLatency 0) manager work:
    // d.ready is a function of the state only, never of a.ready, so no combinational loop is created.
    // An orphan is a D beat that arrives when this bridge has no request outstanding. It happens on hardware
    // when the subsystem is reset while a fetch is in flight on the PS memory port: the CPU and this bridge
    // restart in sIdle, but the DDR read they issued still completes, and TLToAXI4 forwards its response
    // here. With d.ready low in sIdle that beat parks in the converter's single D slot and blocks every
    // other client's responses -- the serial adapter's ELF load never gets its B, so the next program
    // never starts. Accepting and discarding it costs nothing and is legal TileLink (ready may be high at
    // any time). It is not a fault-injection knob and it is never taken during a real transaction.
    val orphanState = state === sIdle || state === sIllegal || state === sResp || state === sDup
    tl.d.ready := (if (legacyDReady) (state === sD || state === sDiscard || orphanState)
                   else (state === sA || state === sD || state === sDiscard || orphanState))
    tl.b.ready := false.B; tl.c.valid := false.B; tl.e.valid := false.B

    val dropFirstRead = RegInit((faultMode == 2).B)
    val nOrphan = RegInit(0.U(32.W))
    when (tl.d.fire() && orphanState) {   // nothing was asked for: swallow it, and leave the CPU's view alone
      nOrphan := nOrphan + 1.U
    }
    when (tl.d.fire() && !orphanState) {
      dFires := dFires + 1.U
      // Protocol errors are testbench failures, never normalised into a clean response.
      assert(tl.d.bits.source === 0.U, "ReqRespToTL: D response with an unknown source")
      assert(tl.d.bits.opcode === Mux(req.write, TLMessages.AccessAck, TLMessages.AccessAckData),
             "ReqRespToTL: unexpected D opcode for this request type")
      when (tl.d.bits.error) { nErr := nErr + 1.U }
      when (state =/= sDiscard) {          // sDiscard: fault 4 already answered, this D is thrown away
        rdata := Mux(req.write || tl.d.bits.error, 0.U, tl.d.bits.data)
        err   := (if (faultMode == 5) false.B else tl.d.bits.error)
      }
    }

    // ---- state machine
    when (io.phys.req.fire()) {
      req   := in
      rdata := 0.U
      err   := !legal
      state := Mux(legal, sA, sIllegal)
      when (!legal) { nIllegal := nIllegal + 1.U }
    }
    when (state === sIllegal) { state := sResp }
    when (state === sA) {
      when (tl.a.fire()) {
        aFires := aFires + 1.U
        val dropIt = if (faultMode == 2) (dropFirstRead && !req.write) else false.B
        when (tl.d.fire()) {                                   // zero-latency manager: A and D in one cycle
          sameCyc := sameCyc + 1.U
          if (faultMode == 2) { when (dropIt) { dropFirstRead := false.B } }
          state := Mux(dropIt, sIdle, sResp)
        } .otherwise {
          if (faultMode == 4) { when (req.write) { rdata := 0.U; err := false.B } }
          state := (if (faultMode == 4) Mux(req.write, sDiscard, sD) else sD)
        }
      }
    }
    when (state === sD && tl.d.fire()) {
      if (faultMode == 2) {
        when (dropFirstRead && !req.write) { dropFirstRead := false.B; state := sIdle } .otherwise { state := sResp }
      } else { state := sResp }
    }
    when (state === sDiscard && tl.d.fire()) { state := sIdle }

    // ---- response, held until the consumer takes it; read data limited to the requested lanes
    val laneBits = FillInterleaved(8, PhysPort.laneMask(req.size, req.addr(2, 0)))
    val respPending = (state === sResp) || (state === sDup) ||
                      (if (faultMode == 4) (state === sDiscard && req.write) else false.B)
    val withdrawOnce = RegInit((faultMode == 6).B)
    val holdBlocked = RegNext(io.phys.resp.valid && !io.phys.resp.ready, false.B)
    if (faultMode == 6) {
      // withdraw once, in a cycle where the consumer was not ready on the previous cycle
      io.phys.resp.valid := respPending && !(withdrawOnce && holdBlocked)
      when (respPending && holdBlocked && withdrawOnce) { withdrawOnce := false.B }
    } else {
      io.phys.resp.valid := respPending
    }
    io.phys.resp.bits.rdata := Mux(err || req.write, 0.U, rdata & laneBits)
    io.phys.resp.bits.error := err
    if (faultMode == 7) {
      when (holdBlocked) { io.phys.resp.bits.rdata := (~(rdata & laneBits)).asUInt }
    }
    when (state === sResp && io.phys.resp.fire()) { state := (if (faultMode == 3) sDup else sIdle) }
    when (state === sDup) { state := sIdle }

    io.dbg.aFires := aFires; io.dbg.dFires := dFires; io.dbg.aWaits := aWaits
    io.dbg.sameCyc := sameCyc; io.dbg.illegal := nIllegal; io.dbg.tlErrors := nErr
  }
}
