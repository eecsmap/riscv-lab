// RD1: the M1 bridge regression, re-pointed at the RD1 bridge with its soft reset tied low.
//
// BusTest.scala and BusTester.scala are untouched: this file only adds a second harness that instantiates
// RD1Bridge instead of ReqRespToTL and drives the same BusTester against the same managers, so the two
// implementations can be compared on exactly the same 13 scenarios. With softReset low, the drain logic
// must cost nothing: every scenario has to land where it lands for the production bridge.
package teaching

import chisel3._
import freechips.rocketchip.config.{Config, Parameters}
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.devices.tilelink.{TLError, ErrorParams}
import freechips.rocketchip.tilelink._
import freechips.rocketchip.unittest._

class RD1PhysBridgeHarness(faultMode: Int, delay: Double, gapMask: Int, respMask: Int, nRandom: Int, seed: Int,
                           zeroLatency: Boolean = false, legacyDReady: Boolean = false)
                          (implicit p: Parameters) extends LazyModule {
  val ramBase   = if (zeroLatency) 0x6000L else 0x0L
  val ramBytes  = if (zeroLatency) 0x200L  else 0x400L
  val errBase   = 0x3000L
  val smallBase = 0x5000L
  val unmapped  = 0x40000L

  val bridge = LazyModule(new RD1Bridge(faultMode, legacyDReady))
  val err    = LazyModule(new TLError(ErrorParams(Seq(AddressSet(errBase, 0xfff)), maxAtomic = 8, maxTransfer = 64), beatBytes = 8))
  val small  = LazyModule(new TeachingWideOnlyRAM(AddressSet(smallBase, 0xfff)))
  val xbar   = LazyModule(new TLXbar)
  if (zeroLatency) {
    val zram = LazyModule(new TeachingZeroLatRAM(AddressSet(ramBase, ramBytes - 1)))
    zram.node := xbar.node
  } else {
    val ram = LazyModule(new TLRAM(AddressSet(ramBase, ramBytes - 1), beatBytes = 8))
    ram.node := xbar.node
  }
  err.node := xbar.node
  small.node := xbar.node
  if (delay > 0.0) { xbar.node := TLDelayer(delay) := bridge.node } else { xbar.node := bridge.node }

  lazy val module = new LazyModuleImp(this) with UnitTestModule {
    val tester = Module(new BusTester(ramBase, (ramBytes / 8).toInt, errBase, unmapped, smallBase,
                                      nRandom, gapMask, respMask, seed, narrowReadUnsupported = true))
    bridge.module.io.phys <> tester.io.phys
    bridge.module.io.drain.softReset := false.B      // the non-reset path, which must be unchanged
    tester.io.dbg <> bridge.module.io.dbg
    io.finished := tester.io.finished
    assert(!(tester.io.finished && tester.io.failed), "RD1PhysBridgeHarness: bus tester reported failures")
  }
}

class RD1PhysBridgeTest(faultMode: Int = 0, delay: Double = 0.0, gapMask: Int = 0, respMask: Int = 0xff,
                        nRandom: Int = 400, seed: Int = 1, zeroLatency: Boolean = false,
                        legacyDReady: Boolean = false, timeout: Int = 400000)(implicit p: Parameters)
  extends UnitTest(timeout) {
  val dut = Module(LazyModule(new RD1PhysBridgeHarness(faultMode, delay, gapMask, respMask, nRandom, seed,
                                                       zeroLatency, legacyDReady)).module)
  dut.io.start := io.start
  io.finished := dut.io.finished
}

class WithRD1PhysBridgeTest(faultMode: Int, delay: Double, gapMask: Int, respMask: Int, nRandom: Int, seed: Int,
                            zeroLatency: Boolean = false, legacyDReady: Boolean = false, timeout: Int = 400000)
  extends Config((site, here, up) => {
    case UnitTests => (q: Parameters) => {
      implicit val p = q
      Seq(Module(new RD1PhysBridgeTest(faultMode, delay, gapMask, respMask, nRandom, seed, zeroLatency,
                                       legacyDReady, timeout)))
    }
  })

class RD1PhysBridgeCleanConfig       extends Config(new WithRD1PhysBridgeTest(0, 0.0,  0x00, 0xff, 400, 1) ++ new Base)
class RD1PhysBridgeDelayConfig       extends Config(new WithRD1PhysBridgeTest(0, 0.25, 0x07, 0x99, 600, 7) ++ new Base)
class RD1PhysBridgeBackpressConfig   extends Config(new WithRD1PhysBridgeTest(0, 0.1,  0x03, 0x11, 600, 3) ++ new Base)
class RD1PhysBridgeZeroLatConfig     extends Config(new WithRD1PhysBridgeTest(0, 0.0,  0x00, 0xff, 300, 11, zeroLatency = true) ++ new Base)
class RD1PhysBridgeZeroLatBpConfig   extends Config(new WithRD1PhysBridgeTest(0, 0.0,  0x03, 0x11, 300, 13, zeroLatency = true) ++ new Base)
class RD1PhysBridgeZeroLatLegacyConfig extends Config(new WithRD1PhysBridgeTest(0, 0.0, 0x00, 0xff, 50, 11, zeroLatency = true, legacyDReady = true, timeout = 60000) ++ new Base)
class RD1PhysBridgeFault1Config      extends Config(new WithRD1PhysBridgeTest(1, 0.25, 0x03, 0xff, 200, 5) ++ new Base)
class RD1PhysBridgeFault2Config      extends Config(new WithRD1PhysBridgeTest(2, 0.0,  0x00, 0xff, 100, 5) ++ new Base)
class RD1PhysBridgeFault3Config      extends Config(new WithRD1PhysBridgeTest(3, 0.0,  0x00, 0xff, 100, 5) ++ new Base)
class RD1PhysBridgeFault4Config      extends Config(new WithRD1PhysBridgeTest(4, 0.25, 0x00, 0xff, 100, 5) ++ new Base)
class RD1PhysBridgeFault5Config      extends Config(new WithRD1PhysBridgeTest(5, 0.0,  0x00, 0xff, 100, 5) ++ new Base)
class RD1PhysBridgeFault6Config      extends Config(new WithRD1PhysBridgeTest(6, 0.0,  0x00, 0x11, 100, 5) ++ new Base)
class RD1PhysBridgeFault7Config      extends Config(new WithRD1PhysBridgeTest(7, 0.0,  0x00, 0x11, 100, 5) ++ new Base)
