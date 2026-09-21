// M3: the teaching CPU on the real legacy SoC bus.
//
// Path under test: tcpu_core (BlackBox) -> PHYSICAL_PORT_V1 -> ReqRespToTL -> sbus -> mbus -> TL/AXI4 ->
// SimAXIMem, with the subsystem's own BootROM, CLINT, PLIC, error slave, TSI serial adapter and block device
// kept exactly as the Rocket configuration has them. No Rocket tile is instantiated, and the Rocket
// configurations themselves are untouched.
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config.{Config, Field, Parameters}
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.interrupts._
import freechips.rocketchip.subsystem._
import freechips.rocketchip.devices.tilelink._
import freechips.rocketchip.tilelink._
import freechips.rocketchip.tile.XLen
import freechips.rocketchip.util.{DontTouch, PlusArg}
import testchipip._
import testchipip.SerialAdapter._

case object TeachingCpuKey extends Field[TeachingCpuParams](TeachingCpuParams())
case class TeachingCpuParams(
  traceEvents: Boolean = true,     // print one line per bus handshake, commit and trap
  extraDelay: Boolean = false,     // a delayer in the teaching master's own path: controlled backpressure
  bridgeFault: Int = 0,            // a deliberate bridge defect, used as a negative control
  // The response intercept exists to attack the exit store in simulation. On the board it is removed at
  // elaboration rather than left switched off: with it false no PlusArg is instantiated and no comparison
  // logic is generated, so there is nothing to disable at run time and nothing to argue about -- which is
  // better than depending on how plusarg_reader behaves under whatever macros the synthesiser defines.
  tailIntercept: Boolean = true)

class TeachingCpuZynqTop(implicit p: Parameters) extends RocketSubsystem   // RocketTilesKey = Nil
    with HasMasterAXI4MemPort
    with HasSystemErrorSlave
    with HasPeripheryBootROM
    with HasSyncExtInterrupts
    with HasNoDebug
    with HasPeripherySerial
    with HasPeripheryBlockDevice {
  val cpuCfg = p(TeachingCpuKey)
  val bridge = LazyModule(new ReqRespToTL(cpuCfg.bridgeFault))
  // The delayer sits only in this master's path, so the backpressure is on the CPU's own requests and
  // nothing else in the subsystem is slowed down.
  if (cpuCfg.extraDelay) sbus.fromPort(Some("teaching-cpu"))() := TLDelayer(0.25) := bridge.node
  else                   sbus.fromPort(Some("teaching-cpu"))() := bridge.node

  // Real interrupt wiring for one hart. The CLINT sizes its msip/mtimecmp arrays from the number of outgoing
  // interrupt connections, so this sink is what makes msip[0] and mtimecmp[0] exist at all; the order of the
  // two bits is taken from the CLINT's own source (int(0) = msip, int(1) = mtip), not guessed.
  val clintSink = IntSinkNode(IntSinkPortSimple(1, 2))
  clintSink := clint.intnode
  // The PLIC's M-mode context for this hart. It is wired so that an external interrupt would arrive, but no
  // device drives it in this configuration; that is stated as untested rather than claimed.
  val plicSink = IntSinkNode(IntSinkPortSimple(1, 1))
  plicSink := plic.intnode
  // The debug module has no tile to talk to here; it is kept in the design and tied off, and is deliberately
  // NOT routed into any of the CPU's interrupt inputs.
  val dummyDebugSink = IntSinkNode(IntSinkPortSimple(1, 1))
  dummyDebugSink := IntSyncCrossingSink(3) := debug.intnode

  override lazy val module = new TeachingCpuZynqTopModule(this)
}

class TeachingCpuZynqTopModule(outer: TeachingCpuZynqTop) extends RocketSubsystemModuleImp(outer)
    with HasRTCModuleImp
    with HasMasterAXI4MemPortModuleImp
    with HasPeripheryBootROMModuleImp
    with HasExtInterruptsModuleImp
    with HasNoDebugModuleImp
    with HasPeripherySerialModuleImp
    with HasPeripheryBlockDeviceModuleImp
    with DontTouch {
  override def resetVectorBits: Int = 32
  val cfg = outer.p(TeachingCpuKey)

  // The reset vector comes from the subsystem's own BootROM parameters, not from a number typed here.
  val romParams = outer.p(BootROMParams)
  val cpu = Module(new TeachingCpu(romParams.hang))

  // ---- test-side interception of the CPU's own port -------------------------------
  // Selected at run time, so one build covers every program: +teach_tail_addr names a byte address and
  // +teach_tail_mode says what to do with the *response* to a write there -- 1 withholds it for ever,
  // 2 turns it into an error. Requests are never cancelled and req.valid is never withdrawn: only the
  // response side is touched, which is what "the host saw the value but the CPU has not finished" means.
  // Matching on the address alone is not enough: htif_putc writes the same word for every console
  // character, so an address-only match lands on the first character rather than on the exit. The exit
  // transaction is identified by four things together -- the store's own PC, the address, the direction,
  // and an HTIF *exit* payload (device 0, command 0, bit 0 set), which a console write never has.
  val phys = cpu.io.phys
  val br   = outer.bridge.module.io.phys
  val isExitStore = Wire(Bool())
  isExitStore := false.B
  if (cfg.tailIntercept) {
    val tailAddr  = PlusArg("teach_tail_addr", 0, "byte address whose write response is intercepted")
    val tailPc    = PlusArg("teach_tail_pc",   0, "PC of the store whose response is intercepted")
    val tailMode  = PlusArg("teach_tail_mode", 0, "0 none, 1 withhold, 2 force error, 3 delay")
    val tailDelay = PlusArg("teach_tail_delay", 0, "cycles to hold the response back in mode 3")
    // Matching on the address alone is not enough: htif_putc writes the same word for every console
    // character. The exit transaction is identified by the store's own PC, the address, the direction and
    // an HTIF *exit* payload (device 0, command 0, bit 0 set), which a console write never has.
    isExitStore := (tailAddr =/= 0.U) && phys.req.bits.write &&
                   (phys.req.bits.addr === tailAddr) &&
                   (tailPc === 0.U || cpu.io.obs.pc === tailPc) &&
                   phys.req.bits.wdata(0) && (phys.req.bits.wdata(63, 48) === 0.U)
    val armed = RegInit(false.B)
    val holdCnt = RegInit(0.U(32.W))
    when (phys.req.fire()) { armed := isExitStore; holdCnt := 0.U }
    when (armed && br.resp.valid) { holdCnt := holdCnt + 1.U }
    val withhold = armed && ((tailMode === 1.U) || ((tailMode === 3.U) && (holdCnt < tailDelay)))
    br.req.valid := phys.req.valid
    br.req.bits  := phys.req.bits
    phys.req.ready := br.req.ready
    phys.resp.valid      := br.resp.valid && !withhold
    phys.resp.bits.rdata := br.resp.bits.rdata
    phys.resp.bits.error := br.resp.bits.error || (armed && (tailMode === 2.U))
    br.resp.ready        := phys.resp.ready && !withhold
  } else {
    // nothing between the CPU and the bridge
    br <> phys
  }

  val clintInts = outer.clintSink.in.head._1
  cpu.io.irq.msip := clintInts(0)
  cpu.io.irq.mtip := clintInts(1)
  cpu.io.irq.meip := outer.plicSink.in.head._1(0)

  // Observation only. These are instrumentation, not part of the interface the board drives; the board
  // wrapper does not export them and leaves them out of its don't-touch set.
  val obs = IO(Output(new TeachingCpuObs))
  obs := cpu.io.obs
  val halted = IO(Output(Bool()))
  halted := cpu.io.obs.halted

  // ---- per-transaction event log -------------------------------------------------
  // One line per event, with a cycle and a sequence number. The port carries one outstanding transaction, so
  // a request and the next response belong together by construction; the sequence number is assigned on the
  // test side and is never added to the CPU's protocol.
  val cycle = RegInit(0.U(48.W)); cycle := cycle + 1.U
  val seq   = RegInit(0.U(32.W))
  val curSeq = RegInit(0.U(32.W))     // the sequence number of the transaction currently in flight
  // "busy" has to cover more than the handshake window: a request already offered but not yet accepted is
  // a commitment too, and a data response that has arrived is not finished until its instruction retires.
  val outstanding = RegInit(false.B)
  when (phys.req.fire())  { outstanding := true.B }
  when (phys.resp.fire()) { outstanding := false.B }
  val awaitingRetire = RegInit(false.B)
  when (phys.resp.fire() && !cpu.io.obs.isFetch) { awaitingRetire := true.B }
  when (cpu.io.obs.commitValid || cpu.io.obs.trapValid) { awaitingRetire := false.B }
  // Nothing is logged while reset is asserted: the registers hold randomised values then, and an event line
  // carrying them would be noise that an event-based gate has to special-case away.
  val logOn = !reset.toBool
  if (cfg.traceEvents) {
    when (logOn && phys.req.fire()) {
      seq := seq + 1.U
      curSeq := seq
      printf(p"EV ${cycle} REQ seq=${seq} pc=0x${Hexadecimal(cpu.io.obs.pc)} " +
             p"fetch=${cpu.io.obs.isFetch} addr=0x${Hexadecimal(phys.req.bits.addr)} " +
             p"write=${phys.req.bits.write} size=${phys.req.bits.size} " +
             p"wdata=0x${Hexadecimal(phys.req.bits.wdata)} wmask=0x${Hexadecimal(phys.req.bits.wmask)}\n")
    }
    when (logOn && phys.req.fire() && isExitStore) {
      printf(p"EV ${cycle} TAILHIT seq=${seq} pc=0x${Hexadecimal(cpu.io.obs.pc)} " +
             p"addr=0x${Hexadecimal(phys.req.bits.addr)} wdata=0x${Hexadecimal(phys.req.bits.wdata)}\n")
    }
    when (logOn && phys.resp.fire()) {
      printf(p"EV ${cycle} RESP seq=${curSeq} rdata=0x${Hexadecimal(phys.resp.bits.rdata)} " +
             p"error=${phys.resp.bits.error}\n")
    }
    when (logOn && cpu.io.obs.commitValid) {
      printf(p"EV ${cycle} COMMIT pc=0x${Hexadecimal(cpu.io.obs.commitPc)} " +
             p"insn=0x${Hexadecimal(cpu.io.obs.commitInsn)}\n")
    }
    when (logOn && cpu.io.obs.trapValid) {
      printf(p"EV ${cycle} TRAP interrupt=${cpu.io.obs.trapInterrupt} " +
             p"cause=0x${Hexadecimal(cpu.io.obs.trapCause)} epc=0x${Hexadecimal(cpu.io.obs.trapEpc)} " +
             p"tval=0x${Hexadecimal(cpu.io.obs.trapTval)}\n")
    }
    // every change of an interrupt level, so the log shows when a source came up and when it was quieted
    val irqNow  = Cat(cpu.io.irq.meip, cpu.io.irq.mtip, cpu.io.irq.msip)
    val irqPrev = RegNext(irqNow, 0.U)
    when (logOn && irqPrev =/= irqNow) {
      printf(p"EV ${cycle} IRQLEVEL msip=${cpu.io.irq.msip} mtip=${cpu.io.irq.mtip} meip=${cpu.io.irq.meip}\n")
    }
  }

  // AXI4 handshakes on the memory port, counted per channel. A burst makes several R or W beats for one AR
  // or AW, so these are not expected to match pairwise; LAST and B are what close a burst.
  val axi = mem_axi4.head
  val nAr = RegInit(0.U(32.W)); val nR = RegInit(0.U(32.W)); val nRlast = RegInit(0.U(32.W))
  val nAw = RegInit(0.U(32.W)); val nW = RegInit(0.U(32.W)); val nWlast = RegInit(0.U(32.W))
  val nB  = RegInit(0.U(32.W))
  if (cfg.traceEvents) {
    when (logOn && axi.ar.fire()) {
      printf(p"EVA ${cycle} AR id=${axi.ar.bits.id} addr=0x${Hexadecimal(axi.ar.bits.addr)} " +
             p"len=${axi.ar.bits.len} size=${axi.ar.bits.size}\n") }
    when (logOn && axi.r.fire()) {
      printf(p"EVA ${cycle} R id=${axi.r.bits.id} last=${axi.r.bits.last} resp=${axi.r.bits.resp}\n") }
    when (logOn && axi.aw.fire()) {
      printf(p"EVA ${cycle} AW id=${axi.aw.bits.id} addr=0x${Hexadecimal(axi.aw.bits.addr)} " +
             p"len=${axi.aw.bits.len} size=${axi.aw.bits.size}\n") }
    when (logOn && axi.w.fire()) {
      printf(p"EVA ${cycle} W last=${axi.w.bits.last}\n") }
    when (logOn && axi.b.fire()) {
      printf(p"EVA ${cycle} B id=${axi.b.bits.id} resp=${axi.b.bits.resp}\n") }
  }
  when (axi.ar.fire()) { nAr := nAr + 1.U }
  when (axi.r.fire())  { nR  := nR  + 1.U; when (axi.r.bits.last) { nRlast := nRlast + 1.U } }
  when (axi.aw.fire()) { nAw := nAw + 1.U }
  when (axi.w.fire())  { nW  := nW  + 1.U; when (axi.w.bits.last) { nWlast := nWlast + 1.U } }
  when (axi.b.fire())  { nB  := nB  + 1.U }
  val busy = IO(Output(Bool()))
  busy := phys.req.valid || outstanding || awaitingRetire
  val axiStats = IO(Output(new Bundle {
    val ar = UInt(32.W); val r = UInt(32.W); val rlast = UInt(32.W)
    val aw = UInt(32.W); val w = UInt(32.W); val wlast = UInt(32.W); val b = UInt(32.W) }))
  axiStats.ar := nAr; axiStats.r := nR; axiStats.rlast := nRlast
  axiStats.aw := nAw; axiStats.w := nW; axiStats.wlast := nWlast; axiStats.b := nB
}

// Harness for the real boot chain. It is the legacy zynq.TestHarness with one substitution: the Rocket top
// is replaced by the teaching top. Everything that makes the boot real -- the TSI serial link driven by
// fesvr, the reset the host releases, the block device, the ZynqAdapter that stands in for the PS -- is the
// same driver the Rocket configuration uses, so nothing about the host path is re-implemented here.
class TeachingCpuHarness(implicit val p: Parameters) extends Module {
  // This Chisel version requires a top-level Module to expose exactly io, clock and reset, so the
  // observation outputs live inside the single io bundle rather than beside it.
  val io = IO(new Bundle {
    val success = Output(Bool())
    val halted  = Output(Bool())
    val busy    = Output(Bool())      // a CPU transaction is in flight
    val dutReset = Output(Bool())     // the subsystem's own reset, which the host releases
    val axi = Output(new Bundle {
      val ar = UInt(32.W); val r = UInt(32.W); val rlast = UInt(32.W)
      val aw = UInt(32.W); val w = UInt(32.W); val wlast = UInt(32.W); val b = UInt(32.W) })
  })
  val driver = Module(LazyModule(new zynq.TestHarnessDriver).module)
  val dut = Module(LazyModule(new TeachingCpuZynqTop).module)

  // The subsystem is held in reset by the harness at power-on *and* by the host until it releases
  // sys_reset. Taking sys_reset alone is wrong: that register is not itself reset, so with randomised
  // initialisation it can start deasserted, leaving the subsystem running on random state before anything
  // has reset it -- which shows up as bus-monitor assertions firing at time zero.
  dut.reset := driver.io.sys_reset || reset.toBool
  dut.debug := DontCare
  dut.tieOffInterrupts()
  dut.dontTouchPorts()
  dut.connectSimAXIMem()
  driver.io.serial <> dut.serial
  driver.io.bdev <> dut.bdev
  io.success := driver.io.success

  // observation only; these take no part in the boot
  io.halted := dut.halted
  io.busy := dut.busy
  io.dutReset := driver.io.sys_reset
  io.axi := dut.axiStats
}

// The teaching boot ROM: one instruction differs from the original, and only this configuration uses it.
class WithTeachingBootROM extends Config((site, here, up) => {
  case BootROMParams => BootROMParams(
    contentFileName = "../common/src/main/resources/teaching/bootrom.teaching.rv64.img")   // relative to simulation/, like the original
})
class WithOriginalBootROM extends Config((site, here, up) => {
  case BootROMParams => BootROMParams(
    contentFileName = s"../testchipip/bootrom/bootrom.rv${site(XLen)}.img")
})
class WithTeachingCpu(p0: TeachingCpuParams = TeachingCpuParams()) extends Config((site, here, up) => {
  case TeachingCpuKey => p0
  case RocketTilesKey => Nil
})
class TeachingCpuBase extends Config(new zynq.WithZynqAdapter ++ new freechips.rocketchip.system.DefaultConfig)
// the configuration under test
class TeachingCpuBootConfig extends Config(
  new WithTeachingCpu() ++ new WithTeachingBootROM ++ new TeachingCpuBase)
// the compatibility negative: the same CPU with the unmodified ROM
class TeachingCpuOrigRomConfig extends Config(
  new WithTeachingCpu() ++ new WithOriginalBootROM ++ new TeachingCpuBase)
// controlled backpressure on the teaching master's own path
class TeachingCpuDelayConfig extends Config(
  new WithTeachingCpu(TeachingCpuParams(extraDelay = true)) ++ new WithTeachingBootROM ++ new TeachingCpuBase)
// a bridge that drops the first read response: no transaction may be left unanswered, and this proves the
// gate that says so is not vacuous
class TeachingCpuDropRespConfig extends Config(
  new WithTeachingCpu(TeachingCpuParams(bridgeFault = 2)) ++ new WithTeachingBootROM ++ new TeachingCpuBase)

// ---------------------------------------------------------------------------------------------------
// Board level. This is zynq.Top with one substitution: the Rocket subsystem becomes the teaching one.
// The two external AXI interfaces, the ZynqAdapter, the serial and block-device links and the reset
// sequencing are the ones the existing wrapper and block design already drive; nothing here adds a pin.
class TeachingBoardTop(implicit val p: Parameters) extends Module {
  val address = p(zynq.ZynqAdapterBase)
  val config  = p(ExtIn)
  val target  = Module(LazyModule(new TeachingCpuZynqTop).module)
  val adapter = Module(LazyModule(new zynq.ZynqAdapter(address, config)).module)

  require(target.mem_axi4.size == 1)

  val io = IO(new Bundle {
    val ps_axi_slave = Flipped(adapter.axi.cloneType)
    val mem_axi = target.mem_axi4.head.cloneType
  })

  io.mem_axi <> target.mem_axi4.head
  adapter.axi <> io.ps_axi_slave
  adapter.io.serial <> target.serial
  adapter.io.bdev <> target.bdev

  target.debug := DontCare
  target.tieOffInterrupts()
  // The observation outputs are simulation instrumentation. They are not exported here and they are left
  // out of the don't-touch set, so the logic behind them can be optimised away instead of being pinned
  // into the netlist. dontTouchPorts() would have retained all of it, because it marks every port.
  target.dontTouchPortsExcept { p =>
    val n = p.instanceName
    n.startsWith("obs") || n.startsWith("halted") || n.startsWith("busy") || n.startsWith("axiStats")
  }
  target.reset := adapter.io.sys_reset
}

// The board configuration: the teaching ROM, no injected delay, no bridge fault, and the response
// intercept removed at elaboration rather than switched off at run time.
// WithoutTLMonitors matches what the baseline board configuration does: the monitors are verification
// logic and the Rocket bitstream has none of them. Leaving them in would put 40 monitor modules and their
// plusarg readers into the netlist. The simulation configurations keep the monitors on purpose.
// traceEvents = false as well: the event log is teaching instrumentation, and while every printf lands
// inside `ifndef SYNTHESIS`, leaving it on would keep the observation nets alive as printf operands in a
// build that is going to be synthesised. Off, they feed nothing at all, which is a much easier thing to
// check. The simulation configurations keep it on, and that is where the events are read.
class TeachingBoardConfig extends Config(
  new WithTeachingCpu(TeachingCpuParams(traceEvents = false, extraDelay = false, bridgeFault = 0,
                                        tailIntercept = false)) ++
  new WithTeachingBootROM ++ new freechips.rocketchip.subsystem.WithoutTLMonitors ++
  new zynq.WithZynqAdapter ++ new freechips.rocketchip.system.DefaultConfig)
