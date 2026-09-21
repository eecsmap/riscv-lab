// M1 integration: the M1-b transaction generator driving the *real* legacy SoC bus, with no Rocket tile.
// Path under test: BusTester -> PHYSICAL_PORT_V1 -> ReqRespToTL -> sbus -> mbus -> TL/AXI4 converter -> SimAXIMem.
// Everything else in the subsystem (BootROM, CLINT, PLIC, error slave, TSI serial adapter, block device,
// AXI4 memory port) is kept exactly as the Rocket configuration has it; no peripheral is removed.
package teaching

import chisel3._
import freechips.rocketchip.config.{Config, Field, Parameters}
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.interrupts._
import freechips.rocketchip.subsystem._
import freechips.rocketchip.devices.tilelink._

import freechips.rocketchip.tilelink._
import freechips.rocketchip.util.DontTouch
import testchipip._

case object TeachingSocTestKey extends Field[TeachingSocTestParams](TeachingSocTestParams())
case class TeachingSocTestParams(
  ramBase: Long = 0x80000000L,   // inside the real DRAM window served over AXI4
  ramWords: Int = 128,
  errBase: Long = 0x3000L,       // the subsystem's own error slave (HasSystemErrorSlave)
  romBase: Long = 0x10000L,      // BootROM: mapped, read-only -> writes are "mapped but unsupported operation"
  unmapped: Long = 0x50000000L,  // no manager claims this (verified by the elaboration dump, see the report)
  nRandom: Int = 300,
  gapMask: Int = 0,
  respMask: Int = 0xff,
  seed: Int = 1,
  faultMode: Int = 0,
  extraDelay: Boolean = false)   // put a TLDelayer in the teaching master's own path to create A-side waiting

class TeachingBusTestZynqTop(implicit p: Parameters) extends RocketSubsystem   // RocketTilesKey = Nil: no CPU
    with HasMasterAXI4MemPort
    with HasSystemErrorSlave
    with HasPeripheryBootROM
    with HasSyncExtInterrupts
    with HasNoDebug
    with HasPeripherySerial
    with HasPeripheryBlockDevice {
  val cfg = p(TeachingSocTestKey)
  val bridge = LazyModule(new ReqRespToTL(cfg.faultMode))
  // Same attachment idiom as testchipip's block device master.
  if (cfg.extraDelay) sbus.fromPort(Some("teaching"))() := TLDelayer(0.25) := bridge.node
  else                sbus.fromPort(Some("teaching"))() := bridge.node

  // The PLIC requires at least one interrupt destination (require(nHarts > 0)) and with zero tiles there is
  // none. This test configuration therefore attaches a dummy sink that stands in for the missing tile, so the
  // PLIC and CLINT stay in the design instead of being deleted. It is tied off and proves nothing about CPU
  // interrupt wiring -- that is M2/M3 work.
  val dummyIntSink = IntSinkNode(IntSinkPortSimple(1, 1))
  dummyIntSink := plic.intnode
  val dummyClintSink = IntSinkNode(IntSinkPortSimple(1, 2))
  dummyClintSink := clint.intnode
  // Same for the debug module: with no tile it has zero interrupt components and Vec.fill(0) fails a require.
  val dummyDebugSink = IntSinkNode(IntSinkPortSimple(1, 1))
  dummyDebugSink := IntSyncCrossingSink(3) := debug.intnode

  override lazy val module = new TeachingBusTestZynqTopModule(this)
}

class TeachingBusTestZynqTopModule(outer: TeachingBusTestZynqTop) extends RocketSubsystemModuleImp(outer)
    with HasRTCModuleImp
    with HasMasterAXI4MemPortModuleImp
    with HasPeripheryBootROMModuleImp
    with HasExtInterruptsModuleImp
    with HasNoDebugModuleImp
    with HasPeripherySerialModuleImp
    with HasPeripheryBlockDeviceModuleImp
    with DontTouch {
  // With no tiles, HasTilesModuleImp.resetVectorBits reads tiles.head and throws. The reset-vector wire is
  // still declared (HasPeripheryBootROM drives it) but nothing consumes it here, so give it a fixed width.
  override def resetVectorBits: Int = 32
  val cfg = outer.p(TeachingSocTestKey)
  val done   = IO(Output(Bool()))
  val failed = IO(Output(Bool()))
  val axiStats = IO(Output(new Bundle { val ar = UInt(32.W); val r = UInt(32.W); val aw = UInt(32.W); val w = UInt(32.W); val b = UInt(32.W) }))

  val tester = Module(new BusTester(cfg.ramBase, cfg.ramWords, cfg.errBase, cfg.unmapped, cfg.romBase,
                                    cfg.nRandom, cfg.gapMask, cfg.respMask, cfg.seed,
                                    narrowReadUnsupported = false))   // the BootROM does serve narrow reads
  outer.bridge.module.io.phys <> tester.io.phys
  tester.io.dbg <> outer.bridge.module.io.dbg
  done := tester.io.finished
  failed := tester.io.failed

  // Count the AXI4 handshakes on the memory port: this is what proves the DRAM window is really reached
  // through the TL/AXI converter. The channels handshake independently, so each is counted separately.
  val axi = mem_axi4.head
  val nAr = RegInit(0.U(32.W)); val nR = RegInit(0.U(32.W)); val nAw = RegInit(0.U(32.W))
  val nW  = RegInit(0.U(32.W)); val nB = RegInit(0.U(32.W))
  when (axi.ar.fire()) { nAr := nAr + 1.U }
  when (axi.r.fire())  { nR  := nR  + 1.U }
  when (axi.aw.fire()) { nAw := nAw + 1.U }
  when (axi.w.fire())  { nW  := nW  + 1.U }
  when (axi.b.fire())  { nB  := nB  + 1.U }
  axiStats.ar := nAr; axiStats.r := nR; axiStats.aw := nAw; axiStats.w := nW; axiStats.b := nB
  val reported = RegInit(false.B)
  when (done && !reported) {
    reported := true.B
    printf(p"AXI ar=$nAr r=$nR aw=$nAw w=$nW b=$nB outstandingAr=${nAr - nR} outstandingAw=${nAw - nB}\n")
  }
}

// Dedicated harness: done/failed straight out, SimAXIMem for the DRAM, every unused SoC port tied off.
class TeachingSocHarness(implicit p: Parameters) extends Module {
  val io = IO(new Bundle { val done = Output(Bool()); val failed = Output(Bool()) })
  val dut = Module(LazyModule(new TeachingBusTestZynqTop).module)
  dut.connectSimAXIMem()
  dut.dontTouchPorts()
  dut.tieOffInterrupts()
  dut.debug := DontCare
  // The TSI serial link and the block device are present but idle in this test: nothing here says anything
  // about HTIF or DMA concurrency.
  dut.serial.in.valid := false.B
  dut.serial.in.bits  := 0.U
  dut.serial.out.ready := true.B
  dut.bdev.req.ready := false.B
  dut.bdev.data.ready := false.B
  dut.bdev.resp.valid := false.B
  dut.bdev.resp.bits  := DontCare
  dut.bdev.info.nsectors := 0.U
  dut.bdev.info.max_req_len := 0.U
  io.done := dut.done
  io.failed := dut.failed
}

class WithTeachingSocTest(p0: TeachingSocTestParams) extends Config((site, here, up) => {
  case TeachingSocTestKey => p0
  case RocketTilesKey => Nil            // no CPU in this configuration; the Rocket configs are untouched
})
class TeachingSocBase extends Config(new zynq.WithZynqAdapter ++ new zynq.WithBootROM ++
  new freechips.rocketchip.system.DefaultConfig)
class TeachingSocBasicConfig extends Config(
  new WithTeachingSocTest(TeachingSocTestParams(seed = 1)) ++ new TeachingSocBase)
class TeachingSocBackpressConfig extends Config(
  new WithTeachingSocTest(TeachingSocTestParams(seed = 7, gapMask = 0x03, respMask = 0x11, extraDelay = true)) ++ new TeachingSocBase)
class TeachingSocFaultConfig extends Config(
  new WithTeachingSocTest(TeachingSocTestParams(seed = 3, faultMode = 1, extraDelay = true)) ++ new TeachingSocBase)
