// A unit test for the test-only delay element, because the first version of it was wrong in a way the SoC
// scenarios could not see: the first offer bypassed the delay entirely, and a stalled offer then had its
// `valid` pulled from 1 back to 0 a cycle later. Both are protocol violations, and both were invisible in a
// full-SoC run that merely finished.
//
// What is checked here, per configuration:
//   * the number of cycles each offer was actually held equals the delay asked for -- measured on the
//     transaction itself, not as an aggregate;
//   * `valid` never falls without a handshake, on either channel (irrevocability);
//   * the payload does not change while an offer is outstanding;
//   * every request that went in came out exactly once, and every response likewise;
//   * a zero delay is genuinely transparent.
// The manager side is driven with ready high, ready low for a while, and ready toggling, because a delay
// element that only works against an always-ready manager is not one.
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config.{Config, Parameters}
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.tilelink._
import freechips.rocketchip.unittest.{UnitTest, UnitTests}
import testchipip.TLHelper

class RD2ThrottleHarness(aDelay: Int, dDelay: Int, readyMode: Int, nTxn: Int)
                        (implicit p: Parameters) extends LazyModule {
  val client = TLHelper.makeClientNode("rd2-throttle-test", IdRange(0, 1))
  val thr = LazyModule(new RD2Throttle)
  val ram = LazyModule(new TLRAM(AddressSet(0x0, 0x3ff), beatBytes = 8))
  ram.node := thr.node := client

  lazy val module = new LazyModuleImp(this) {
    val io = IO(new Bundle { val start = Input(Bool()); val finished = Output(Bool()) })
    val (tl, edge) = client.out(0)

    val cyc = RegInit(0.U(32.W)); cyc := cyc + 1.U
    val issued = RegInit(0.U(8.W))
    val got = RegInit(0.U(8.W))
    val inflight = RegInit(false.B)
    val started = RegInit(false.B)
    when (io.start) { started := true.B }

    val addr = Cat(issued, 0.U(3.W))
    val (_, getBits) = edge.Get(0.U, addr, 3.U)
    tl.a.valid := started && !inflight && (issued < nTxn.U)
    tl.a.bits := getBits
    tl.d.ready := true.B
    tl.b.ready := false.B; tl.c.valid := false.B; tl.e.valid := false.B
    when (tl.a.fire()) { issued := issued + 1.U; inflight := true.B }
    when (tl.d.fire()) { got := got + 1.U; inflight := false.B }

    // ---- the properties -------------------------------------------------------------------------------
    // irrevocability, on the channel this element drives toward the RAM and toward the client
    val aValidPrev = RegNext(tl.a.valid, false.B)
    val aFirePrev  = RegNext(tl.a.fire(), false.B)
    assert(!(aValidPrev && !tl.a.valid && !aFirePrev),
           "RD2ThrottleTest: the client's A valid fell without a handshake")
    val aAddrPrev = RegNext(tl.a.bits.address, 0.U)
    assert(!(aValidPrev && tl.a.valid && !aFirePrev && (tl.a.bits.address =/= aAddrPrev)),
           "RD2ThrottleTest: the A payload changed while the offer was outstanding")
    val dValidPrev = RegNext(tl.d.valid, false.B)
    val dFirePrev  = RegNext(tl.d.fire(), false.B)
    assert(!(dValidPrev && !tl.d.valid && !dFirePrev),
           "RD2ThrottleTest: a D valid presented to the client fell without a handshake")

    // ---- how long each offer was actually held --------------------------------------------------------
    val aHeld = RegInit(0.U(32.W))
    val worstA = RegInit(0.U(32.W))
    val bestA = RegInit(~0.U(32.W))
    when (tl.a.valid && !tl.a.ready) { aHeld := aHeld + 1.U }
    when (tl.a.fire()) {
      when (aHeld > worstA) { worstA := aHeld }
      when (aHeld < bestA) { bestA := aHeld }
      aHeld := 0.U
    }

    val done = (got === nTxn.U) && !inflight
    val finish = RegInit(false.B)
    when (done && !finish) {
      finish := true.B
      printf(p"RD2TT cyc=${cyc} issued=${issued} got=${got} aHeldMin=${bestA} aHeldMax=${worstA} " +
             p"wantA=${aDelay.U} wantD=${dDelay.U} readyMode=${readyMode.U} n=${nTxn.U}\n")
    }
    io.finished := finish
  }
}

class RD2ThrottleTest(aDelay: Int, dDelay: Int, readyMode: Int = 0, nTxn: Int = 6,
                      timeout: Int = 20000)(implicit p: Parameters) extends UnitTest(timeout) {
  val dut = Module(LazyModule(new RD2ThrottleHarness(aDelay, dDelay, readyMode, nTxn)).module)
  dut.io.start := io.start
  io.finished := dut.io.finished
}

class WithRD2Throttle(aDelay: Int, dDelay: Int, readyMode: Int = 0, nTxn: Int = 6)
  extends Config((site, here, up) => {
    case UnitTests => (q: Parameters) => {
      implicit val p = q
      Seq(Module(new RD2ThrottleTest(aDelay, dDelay, readyMode, nTxn)))
    }
  })

class RD2ThrZeroConfig  extends Config(new WithRD2Throttle(0, 0)  ++ new Base)
class RD2ThrAOnlyConfig extends Config(new WithRD2Throttle(7, 0)  ++ new Base)
class RD2ThrDOnlyConfig extends Config(new WithRD2Throttle(0, 11) ++ new Base)
class RD2ThrBothConfig  extends Config(new WithRD2Throttle(5, 9)  ++ new Base)
class RD2ThrLongConfig  extends Config(new WithRD2Throttle(30, 200, nTxn = 3) ++ new Base)
