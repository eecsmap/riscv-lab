// CPU-A stage 1 (R2): the backend on the real subsystem path, driven by transactions. A RocketSubsystem with
// the AXI4 memory port, error slave, BootROM and the atomic hub; the V2 bridge and two scripted external
// masters attached exactly where the CPU bridge, the TSI adapter and the block-device DMA attach in the
// RD2/teaching SoC (sbus.fromPort). The chain under test is therefore the generated one:
//   bridge -> sbus TLXbar (with buffers) -> AtomicBackend -> TLBroadcast -> TLWidthWidget -> MemoryBus -> TLToAXI4 -> SimAXIMem
// No CPU instruction executes here (that is the next stage); TSI and the block device are represented by
// TLPutter clients of the same kind (one source id each) -- their source transformation through the
// crossbar and the hub is the same in kind as the real adapters'.
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config._
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.interrupts._
import freechips.rocketchip.subsystem._
import freechips.rocketchip.devices.tilelink._
import freechips.rocketchip.tilelink._
import testchipip._

case class AtomicSocParams(scen: Int = 2, bridgeFault: Int = 0, respStall: Int = 0, respRandom: Boolean = false)
case object AtomicSocKey extends Field[AtomicSocParams](AtomicSocParams())

class AtomicZynqTop(implicit p: Parameters) extends RocketSubsystem
    with HasMasterAXI4MemPort
    with HasSystemErrorSlave
    with HasPeripheryBootROM
    with HasSyncExtInterrupts
    with HasNoDebug {
  val cfg = p(AtomicSocKey)
  import AtomicScen._
  val (cpuScript, e0, e1) = cfg.scen match {
    case 1 => (s1cpu, Nil, Nil); case 2 => (s2cpu, s2ext0, s2ext1); case 3 => (s3cpu, s3ext0, s3ext1)
    case 4 => (s4cpu, Nil, Nil); case 5 => (s5cpu, s5ext0, s5ext1); case 6 => (s6cpu, Nil, Nil)
    case 7 => (s7cpu, s7ext0, Nil)
  }
  val bridge = LazyModule(new RD2BridgeV2(cfg.bridgeFault, atomicRegion = Seq(AddressSet(p(ExtMem).base, p(ExtMem).size - 1))))
  val put0   = LazyModule(new TLPutter("ext-tsi", e0))
  val put1   = LazyModule(new TLPutter("ext-dma", e1))
  val tap    = TLIdentityNode()
  sbus.fromPort(Some("teaching-cpu"))() := tap := bridge.node
  sbus.fromPort(Some("ext-tsi"))() := put0.node
  sbus.fromPort(Some("ext-dma"))() := put1.node
  val backend = AtomicHub.last.getOrElse(throw new Exception("AtomicZynqTop needs WithAtomicHub"))
  // the interrupt fabric is kept as in the teaching SoC (one hart's CLINT/PLIC/debug sinks) so the subsystem
  // elaborates unchanged; nothing here consumes an interrupt
  val clintSink = IntSinkNode(IntSinkPortSimple(1, 2)); clintSink := clint.intnode
  val plicSink  = IntSinkNode(IntSinkPortSimple(1, 1)); plicSink := plic.intnode
  val dummyDebugSink = IntSinkNode(IntSinkPortSimple(1, 1)); dummyDebugSink := IntSyncCrossingSink(3) := debug.intnode
  override lazy val module = new AtomicZynqTopModule(this)
}
class AtomicZynqTopModule(outer: AtomicZynqTop) extends RocketSubsystemModuleImp(outer)
    with HasRTCModuleImp
    with HasMasterAXI4MemPortModuleImp
    with HasPeripheryBootROMModuleImp
    with HasExtInterruptsModuleImp
    with HasNoDebugModuleImp {
  override def resetVectorBits: Int = 32   // no tiles: the same override the teaching/RD2 tops use
  val cfg = outer.cfg
  val io_success = IO(Output(Bool()))
  val cyc = RegInit(0.U(32.W)); cyc := cyc + 1.U
  val drv = Module(new V2Driver(outer.cpuScript, cfg.respStall, cfg.respRandom))
  outer.bridge.module.io.phys <> drv.io.phys
  drv.io.hold := outer.bridge.module.io.drain.cpuResetHold
  outer.bridge.module.io.drain.softReset := false.B
  outer.backend.module.io.sb <> outer.bridge.module.io.sb
  val (tlb, _) = outer.tap.in(0)
  val aFires = RegInit(0.U(32.W)); when (tlb.a.fire()) { aFires := aFires + 1.U }
  val outst = RegInit(false.B); when (tlb.a.fire()) { outst := true.B }; when (tlb.d.fire()) { outst := false.B }
  for (pm <- Seq(outer.put0.module, outer.put1.module)) { pm.io.cpuAFires := aFires; pm.io.cpuTxid := outer.bridge.module.io.drain.txid; pm.io.cpuOutstanding := outst }
  val allDone = drv.io.finished && outer.put0.module.io.done && outer.put1.module.io.done && !outer.backend.module.io.dbg.busy
  val settle = RegInit(0.U(8.W)); when (allDone) { settle := settle + 1.U }
  io_success := allDone && (settle > 40.U)
  when (io_success && !RegNext(io_success, false.B)) {
    printf(p"AT ${cyc} FINISHED cpuResp=${drv.io.nResp} amo=${outer.backend.module.io.dbg.nAmo} scOk=${outer.backend.module.io.dbg.nScOk} scFail=${outer.backend.module.io.dbg.nScFail} kills=${outer.backend.module.io.dbg.nKill} bridgeIllegal=${outer.bridge.module.io.dbg.illegal} tlErr=${outer.bridge.module.io.dbg.tlErrors}\n")
  }
}

// the simulation top: the subsystem with SimAXIMem on its memory port (the same memory model the M3/RD2 sims use)
class AtomicSocHarness(implicit val p: Parameters) extends Module {
  val io = IO(new Bundle { val success = Output(Bool()) })
  val dut = Module(LazyModule(new AtomicZynqTop).module)
  dut.connectSimAXIMem()
  dut.debug := DontCare
  dut.tieOffInterrupts()
  dut.reset := reset
  io.success := dut.io_success
}
class WithAtomicSoc(scen: Int, bridgeFault: Int = 0, respStall: Int = 0, respRandom: Boolean = false) extends Config((site, here, up) => {
  case AtomicSocKey => AtomicSocParams(scen, bridgeFault, respStall, respRandom)
})
// base: the teaching subsystem parameters (RocketTilesKey = Nil from WithTeachingCpu, the teaching ROM, the
// DefaultConfig memory map: ExtMem 0x8000_0000 + 256 MiB, one channel) plus the atomic hub
class AtomicSocBase extends Config(new WithAtomicHub() ++ new WithTeachingCpu() ++ new WithTeachingBootROM ++ new freechips.rocketchip.system.DefaultConfig)
class AtomicSocAmoRaceConfig  extends Config(new WithAtomicSoc(2) ++ new AtomicSocBase)
class AtomicSocLrscRaceConfig extends Config(new WithAtomicSoc(5, respRandom = true) ++ new AtomicSocBase)
class AtomicSocErrorsConfig   extends Config(new WithAtomicSoc(6, respStall = 3) ++ new AtomicSocBase)
class AtomicSocPartialConfig  extends Config(new WithAtomicSoc(3) ++ new AtomicSocBase)
class AtomicSocNegAmoMapConfig extends Config(new WithAtomicSoc(2, bridgeFault = 9) ++ new AtomicSocBase)   // ADD emitted as SWAP, real topology
class AtomicSocNegNoKillConfig extends Config(new WithAtomicSoc(5) ++ new WithAtomicHub(fNoKill = true) ++ new WithTeachingCpu() ++ new WithTeachingBootROM ++ new freechips.rocketchip.system.DefaultConfig)
