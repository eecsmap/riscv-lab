// M1-b: synthesizable unit test -- BusTester -> ReqRespToTL -> [TLDelayer] -> TLXbar -> managers.
// Managers: a RAM (minLatency 1), an error slave, a read-only slave that serves 8-byte reads only,
// and -- in the zero-latency configuration -- a register device with concurrency = 0, whose a.ready
// depends on d.ready. TileLink monitors stay enabled.
package teaching

import chisel3._
import freechips.rocketchip.config.{Config, Parameters}
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.devices.tilelink.{TLError, ErrorParams}
import freechips.rocketchip.regmapper.RegField
import freechips.rocketchip.tilelink._
import freechips.rocketchip.unittest._

// Byte-granular register file behind a TLRegisterNode with concurrency = 0: minLatency 0, and
// RegMapper wires front.ready (hence A.ready) through to the output ready (hence D.ready).
class TeachingZeroLatRAM(address: AddressSet, beatBytes: Int = 8)(implicit p: Parameters) extends LazyModule {
  val device = new SimpleDevice("teaching-zerolat", Seq("teaching,zerolat"))
  val node = TLRegisterNode(Seq(address), device, "reg", concurrency = 0, beatBytes = beatBytes)
  val nBytes = (address.mask + 1).toInt
  lazy val module = new LazyModuleImp(this) {
    val bytes = Seq.fill(nBytes)(RegInit(0.U(8.W)))
    node.regmap(bytes.zipWithIndex.map { case (r, i) => i -> Seq(RegField(8, r)) }: _*)
  }
}

// A manager that is mapped but only supports 8-byte reads: writes and narrow reads to it are legal TileLink
// requests that no manager can serve, so the bridge must reject them locally. (A manager whose maxTransfer is
// smaller than the link's beatBytes is rejected by diplomacy, so "supports nothing below 8 bytes" is the way
// to express a size restriction here.)
class TeachingWideOnlyRAM(address: AddressSet, beatBytes: Int = 8)(implicit p: Parameters) extends LazyModule {
  val device = new MemoryDevice
  val node = TLManagerNode(Seq(TLManagerPortParameters(Seq(TLManagerParameters(
    address = Seq(address), resources = device.reg, regionType = RegionType.UNCACHED,
    supportsGet = TransferSizes(beatBytes, beatBytes), fifoId = Some(0))), beatBytes = beatBytes, minLatency = 1)))
  lazy val module = new LazyModuleImp(this) {
    val (tl, edge) = node.in(0)
    val busy = RegInit(false.B); val src = Reg(UInt(tl.d.bits.source.getWidth.W)); val sz = Reg(UInt(tl.d.bits.size.getWidth.W))
    tl.a.ready := !busy
    when (tl.a.fire()) { busy := true.B; src := tl.a.bits.source; sz := tl.a.bits.size }
    .elsewhen (tl.d.fire()) { busy := false.B }
    tl.d.valid := busy
    tl.d.bits  := edge.AccessAck(src, sz, "hDEADBEEFDEADBEEF".U(64.W))
    tl.b.valid := false.B; tl.c.ready := true.B; tl.e.ready := true.B
  }
}

class PhysBridgeHarness(faultMode: Int, delay: Double, gapMask: Int, respMask: Int, nRandom: Int, seed: Int,
                        zeroLatency: Boolean = false, legacyDReady: Boolean = false)
                       (implicit p: Parameters) extends LazyModule {
  val ramBase   = if (zeroLatency) 0x6000L else 0x0L
  val ramBytes  = if (zeroLatency) 0x200L  else 0x400L      // 64 or 128 64-bit words
  val errBase   = 0x3000L                                    // error slave, same address as the SoC's
  val smallBase = 0x5000L                                    // mapped, but serves only 8-byte reads (no writes)
  val unmapped  = 0x40000L                                   // covered by no manager at all

  val bridge = LazyModule(new ReqRespToTL(faultMode, legacyDReady))
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
    tester.io.dbg <> bridge.module.io.dbg
    io.finished := tester.io.finished
    assert(!(tester.io.finished && tester.io.failed), "PhysBridgeHarness: bus tester reported failures")
  }
}

class PhysBridgeTest(faultMode: Int = 0, delay: Double = 0.0, gapMask: Int = 0, respMask: Int = 0xff,
                     nRandom: Int = 400, seed: Int = 1, zeroLatency: Boolean = false, legacyDReady: Boolean = false,
                     timeout: Int = 400000)(implicit p: Parameters) extends UnitTest(timeout) {
  val dut = Module(LazyModule(new PhysBridgeHarness(faultMode, delay, gapMask, respMask, nRandom, seed,
                                                    zeroLatency, legacyDReady)).module)
  // chisel3 (not the Chisel._ compat layer) does not auto-invalidate unconnected inputs: drive start explicitly
  dut.io.start := io.start
  io.finished := dut.io.finished
}

// One scenario per config, so a failure names itself. FAULT>0 and the legacy-bridge config must fail.
class WithPhysBridgeTest(faultMode: Int, delay: Double, gapMask: Int, respMask: Int, nRandom: Int, seed: Int,
                         zeroLatency: Boolean = false, legacyDReady: Boolean = false, timeout: Int = 400000)
  extends Config((site, here, up) => {
    case UnitTests => (q: Parameters) => {
      implicit val p = q
      Seq(Module(new PhysBridgeTest(faultMode, delay, gapMask, respMask, nRandom, seed, zeroLatency, legacyDReady, timeout)))
    }
  })

class Base extends freechips.rocketchip.subsystem.BaseSubsystemConfig
class PhysBridgeCleanConfig       extends Config(new WithPhysBridgeTest(0, 0.0,  0x00, 0xff, 400, 1) ++ new Base)
class PhysBridgeDelayConfig       extends Config(new WithPhysBridgeTest(0, 0.25, 0x07, 0x99, 600, 7) ++ new Base)
class PhysBridgeBackpressConfig   extends Config(new WithPhysBridgeTest(0, 0.1,  0x03, 0x11, 600, 3) ++ new Base)
// zero-latency manager (a.ready depends on d.ready): the fixed bridge must complete, the legacy one deadlocks
class PhysBridgeZeroLatConfig     extends Config(new WithPhysBridgeTest(0, 0.0,  0x00, 0xff, 300, 11, zeroLatency = true) ++ new Base)
class PhysBridgeZeroLatBpConfig   extends Config(new WithPhysBridgeTest(0, 0.0,  0x03, 0x11, 300, 13, zeroLatency = true) ++ new Base)
class PhysBridgeZeroLatLegacyConfig extends Config(new WithPhysBridgeTest(0, 0.0, 0x00, 0xff, 50, 11, zeroLatency = true, legacyDReady = true, timeout = 60000) ++ new Base)
class PhysBridgeFault1Config      extends Config(new WithPhysBridgeTest(1, 0.25, 0x03, 0xff, 200, 5) ++ new Base)
class PhysBridgeFault2Config      extends Config(new WithPhysBridgeTest(2, 0.0,  0x00, 0xff, 100, 5) ++ new Base)
class PhysBridgeFault3Config      extends Config(new WithPhysBridgeTest(3, 0.0,  0x00, 0xff, 100, 5) ++ new Base)
class PhysBridgeFault4Config      extends Config(new WithPhysBridgeTest(4, 0.25, 0x00, 0xff, 100, 5) ++ new Base)
class PhysBridgeFault5Config      extends Config(new WithPhysBridgeTest(5, 0.0,  0x00, 0xff, 100, 5) ++ new Base)
class PhysBridgeFault6Config      extends Config(new WithPhysBridgeTest(6, 0.0,  0x00, 0x11, 100, 5) ++ new Base)
class PhysBridgeFault7Config      extends Config(new WithPhysBridgeTest(7, 0.0,  0x00, 0x11, 100, 5) ++ new Base)
