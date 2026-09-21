// RD2: a protocol-correct, test-only delay point in a master's TileLink path.
//
// Three of the cases the review asks for cannot be reached without one: a reset while a write is offered and
// not yet accepted, a reset after acceptance but before the write reaches memory, and a reset after it has
// reached memory but before the response comes back. In the SoC as it stands the system bus accepts this
// master's A immediately and DRAM answers on its own schedule, so those windows are a cycle wide or do not
// exist -- which is why `cpuAWaits` read 0. That is missing coverage, not a property of the design, and this
// is how the coverage is obtained.
//
// Protocol correctness matters more than convenience here:
//   * A is held by *not raising* out.a.valid until the delay has expired. The decision is taken when in.a
//     first goes valid, so out.a.valid never falls once raised -- irrevocability is preserved toward the
//     manager, and the client sees ordinary backpressure.
//   * D is held the same way, and in the direction this module is the consumer: out.d.ready is simply low
//     while the delay runs, which is legal at any time.
// Nothing is reordered, dropped or duplicated; the only effect is *when* a handshake happens.
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config.Parameters
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.tilelink._
import freechips.rocketchip.util.PlusArg

class RD2Throttle(implicit p: Parameters) extends LazyModule {
  val node = TLAdapterNode()
  lazy val module = new LazyModuleImp(this) {
    //   +rd2_a_delay=<n>   cycles to hold each A before offering it to the bus
    //   +rd2_d_delay=<n>   cycles to hold each D before handing it to the master
    //   +rd2_throttle_from=<k>  start at the k-th transaction (0 = from the first)
    val aDelay = PlusArg("rd2_a_delay", 0, "cycles to hold each A offered by this master")
    val dDelay = PlusArg("rd2_d_delay", 0, "cycles to hold each D returned to this master")
    val from   = PlusArg("rd2_throttle_from", 0, "throttle from this transaction onwards")

    (node.in zip node.out).foreach { case ((in, edgeIn), (out, edgeOut)) =>
      out <> in
      val nA = RegInit(0.U(32.W))
      val armed = nA >= from

      // ---- A: the decision is combinational on the very first cycle the request appears.
      // The first version latched `aSeen` and only consulted it on the *next* cycle, so the first offer went
      // straight through, and if it was stalled the delay then pulled valid from 1 back to 0 a cycle later --
      // the exact violation this module claims not to commit. Now: while the delay runs, out.a.valid is low
      // from the first cycle, and once it rises it follows in.a.valid, which the master holds stable.
      val aCnt  = RegInit(0.U(32.W))
      val aSeen = RegInit(false.B)
      val aWant = Mux(armed, aDelay, 0.U)
      val aFresh = in.a.valid && !aSeen                  // the cycle the request first appears
      val aLeft = Mux(aFresh, aWant, aCnt)               // cycles still to wait, this cycle
      val aHold = aLeft =/= 0.U
      when (in.a.valid) {
        aSeen := true.B
        // one less on the fresh cycle: that cycle is itself the first held one, so storing the full delay
        // held everything a cycle too long (asked 7, held 8 -- the unit test measured it)
        aCnt  := Mux(aFresh, Mux(aWant === 0.U, 0.U, aWant - 1.U), Mux(aCnt === 0.U, 0.U, aCnt - 1.U))
      }
      when (out.a.fire()) { aSeen := false.B; aCnt := 0.U; nA := nA + 1.U }
      out.a.valid := in.a.valid && !aHold
      in.a.ready  := out.a.ready && !aHold

      // ---- D: same shape. Holding `ready` low is legal at any time, and in.d.valid is withheld from the
      // first cycle rather than withdrawn after it.
      val dCnt  = RegInit(0.U(32.W))
      val dSeen = RegInit(false.B)
      val dWant = Mux(armed, dDelay, 0.U)
      val dFresh = out.d.valid && !dSeen
      val dLeft = Mux(dFresh, dWant, dCnt)
      val dHold = dLeft =/= 0.U
      when (out.d.valid) {
        dSeen := true.B
        dCnt  := Mux(dFresh, Mux(dWant === 0.U, 0.U, dWant - 1.U), Mux(dCnt === 0.U, 0.U, dCnt - 1.U))
      }
      when (in.d.fire()) { dSeen := false.B; dCnt := 0.U }
      in.d.valid  := out.d.valid && !dHold
      out.d.ready := in.d.ready && !dHold

      // measured, per transaction: how many cycles each offer was actually held. An aggregate counter is not
      // evidence that *this* transaction was delayed by the amount the scenario asked for.
      val aHeld = RegInit(0.U(32.W))
      val dHeld = RegInit(0.U(32.W))
      when (in.a.valid && aHold) { aHeld := aHeld + 1.U }
      when (out.d.valid && dHold) { dHeld := dHeld + 1.U }
      val traceOn = PlusArg("rd2_trace_masters", 0, "log throttle decisions") =/= 0.U
      val tcyc = RegInit(0.U(48.W)); tcyc := tcyc + 1.U
      when (traceOn && out.a.fire()) {
        printf(p"RD2T ${tcyc} A held=${aHeld} want=${aWant} addr=0x${Hexadecimal(out.a.bits.address)} " +
               p"op=${out.a.bits.opcode}\n")
        aHeld := 0.U
      }
      when (traceOn && in.d.fire()) {
        printf(p"RD2T ${tcyc} D held=${dHeld} want=${dWant}\n")
        dHeld := 0.U
      }
    }
  }
}
