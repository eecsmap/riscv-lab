// RD2-A: the experimental SoC with two reset domains.
//
// The measured starting point (rd2-0): every one of the subsystem's 147 reset-carrying instances -- the
// bridge, TLToAXI4, the user yanker, the serial adapter, the block-device trackers, CLINT and PLIC -- hangs
// off one net, `adapter_io_sys_reset`. A soft reset therefore erases, in one cycle, the record of work the
// rest of the SoC is still going to finish.
//
// Here the subsystem takes the *cold* reset, so that record survives, and the soft reset arrives as data on
// a port. The CPU is the only thing this stage puts in the soft domain, through the RD1 bridge's
// `cpuResetHold`; what stays cold and what that costs is stated below and in REPORT-A.md rather than
// quietly assumed.
//
// Nothing here edits a production class. TeachingCpuZynqTop, ReqRespToTL, TeachingCpu, the board
// configuration and the adapter are untouched; this is a parallel top used only by RD2 configurations.
package teaching

import chisel3._
import chisel3.util._
import chisel3.experimental.withReset
import freechips.rocketchip.config.{Config, Field, Parameters}
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.interrupts._
import freechips.rocketchip.subsystem._
import freechips.rocketchip.devices.tilelink._
import freechips.rocketchip.tilelink._
import freechips.rocketchip.util.{DontTouch, PlusArg}
import testchipip._

case class RD2Params(
  bridgeFault:  Int = 0,        // RD1's fault injection, for the negative scenarios only
  applyCycles:  Int = 2,        // how long RESET_APPLY is held
  drainTimeout: Int = 50000,    // status only: a drain that takes longer reports it, and clears nothing
  rbootTimeout: Int = 200000,   // R-BOOT: a block device that has not drained by then is reported stuck
  traceEvents:  Boolean = true,
  // CPU-A: opt in to the atomic path -- the V2 bridge and the V2 CPU wrapper instead of the RD1 bridge and
  // the V1 wrapper. Off by default, so every configuration that existed before elaborates exactly as it
  // did; only the configurations that set it (and mix in WithAtomicHub) get the atomic path.
  atomic:       Boolean = false,
  // the atomic path's per-transaction trace: on for the scored configurations, off for an OS-length run
  atomicTrace:  Boolean = true,
  // The per-disk-transfer BDEV_OP/BDEV_DONE trace. It is deliberately *not* under traceEvents: the xv6
  // configurations run with traceEvents = false and still need it, because a few lines per transfer is
  // affordable in an OS-length run and it is the only way to tell "the device never took the request" from
  // "it took it and never finished". It defaults to on, so every configuration that existed before
  // elaborates exactly as it did; the board configuration is the one that turns it off, because a printf
  // has no place in a netlist that is going to be synthesised.
  bdevTrace:    Boolean = true,
  // The bus-level test instrumentation: the per-master A/D watchers' trace and the request throttle.
  // Both are opt-in at run time -- the watchers print nothing unless +rd2_trace_masters is set and the
  // throttle delays nothing unless its plusargs are -- but "does nothing at run time" is not the same as
  // "is not in the netlist". Each PlusArg elaborates a plusarg_reader, and the board-proven build had
  // none at all. Defaults to on, so every existing configuration elaborates exactly as it did.
  busInstrumentation: Boolean = true)
case object RD2Key extends Field[RD2Params](RD2Params())

// What the PS can ask about the design. RD2-A fills in the CPU-side answers; the quiesce/AXI-ledger answers
// arrive in RD2-D and are deliberately left as explicit "not established yet" rather than optimistic ones.
class RD2Status extends Bundle {
  val cpuRestartSafe = Output(Bool())   // the drain finished and the CPU reset has been applied
  val plReconfigSafe = Output(Bool())   // RD2-D; 0 until the whole quiesce condition is real
  val draining       = Output(Bool())
  val timeout        = Output(Bool())   // sticky status; never clears anything
  val epoch          = Output(UInt(16.W))
  val nDrained       = Output(UInt(32.W))
  val pendingWork    = Output(Bool())   // the CPU bridge's
  val serialIdle     = Output(Bool())   // the TSI adapter has no frame and no TL transaction in flight
  val serialFrame    = Output(Bool())   // the host is mid-frame
  val serialTlOutstanding = Output(Bool())
  val serialRefusedCycles = Output(UInt(32.W))
  val bdevOutstanding = Output(Bool())   // the block device owes a response on its own master port
  val bdevBusy           = Output(Bool())  // a tracker is not idle, or the master port owes work
  val bootRestartReady   = Output(Bool())  // R-BOOT: old DMA done, old completions flushed, CPU applied
  val bootRestartTimeout = Output(Bool())  // R-BOOT: sticky, the device never drained
  val bdevQueued         = Output(UInt(8.W))   // completions waiting in the router, unconsumed
  val bdevDiscarded      = Output(UInt(32.W))
  val bdevInflight    = Output(UInt(8.W))
  // R-BOOT write-target fix: the device's *operation*, not just "busy"
  val bdevWriteInflight = Output(Bool())
  val bdevReadInflight  = Output(Bool())
  val bdevWriteSector   = Output(UInt(32.W))
  val writeInFlight   = Output(Bool())   // the transaction the bridge is carrying is a write
  val dramWriteInFlight = Output(Bool()) // ... and it is to DRAM, which the checker models
  val aWaits          = Output(UInt(32.W))
  val aFires          = Output(UInt(32.W))
  val dFires          = Output(UInt(32.W))
  val quiesceReq     = Output(Bool())   // the lock, as the design sees it
  val msip           = Output(Bool())   // cleared by the applied reset; the ROM's wake loop polls it
  val pendingA       = Output(Bool())   // the CPU's A is offered and not accepted
  val outstanding    = Output(Bool())   // the CPU's A was accepted and its D has not come back
}

class RD2ZynqTop(implicit p: Parameters) extends RocketSubsystem   // RocketTilesKey = Nil
    with HasMasterAXI4MemPort
    with HasSystemErrorSlave
    with HasPeripheryBootROM
    with HasSyncExtInterrupts
    with HasNoDebug
    with HasRD2Serial
    with HasRD2Clint
    with HasRD2BlockDevice {
  val cpuCfg = p(TeachingCpuKey)
  val rd2Cfg = p(RD2Key)
  // the RD1 bridge, unmodified: the drain contract it was accepted with is the contract here
  // faultMode is RD1's own injection knob, carried through so that a *real* wrong delivery can be produced
  // on the actual hardware path -- 3 duplicates a response, 7 mutates a payload that is waiting to be taken.
  // Mutating a log is not the same evidence, and these scenarios are declared as negatives.
  val bridge = if (rd2Cfg.atomic) None else
    Some(LazyModule(new RD1Bridge(rd2Cfg.bridgeFault, false, rd2Cfg.applyCycles, rd2Cfg.drainTimeout,
                                  legacyDrain = false)))
  // CPU-A: the accepted V2 bridge, with the same drain contract (BridgeDrainIO / BridgeDebug are shared)
  val bridgeV2 = if (rd2Cfg.atomic)
    Some(LazyModule(new RD2BridgeV2(rd2Cfg.bridgeFault, rd2Cfg.applyCycles, rd2Cfg.drainTimeout,
                                    atomicRegion = Seq(AddressSet(p(ExtMem).base, p(ExtMem).size - 1)),
                                    trace = rd2Cfg.atomicTrace))) else None
  val bridgeNode = if (rd2Cfg.atomic) bridgeV2.get.node else bridge.get.node
  // the accepted backend, built by WithAtomicHub at the coherence-manager hook (before TLBroadcast)
  val atomicBackend = if (rd2Cfg.atomic) AtomicHub.last else None
  // a watcher and a test-only delay point in the CPU master's path. The watcher is an identity node; the
  // throttle does nothing at all unless its plusargs are set, and a normal run sets none of them.
  val cpuWatch = LazyModule(new RD2Watch("cpu", trace = rd2Cfg.busInstrumentation))
  // The throttle is a test device end to end: with no plusargs set it is a wire, and on the board it is
  // three plusarg_readers and a delay path that nothing can ever ask for. It is left out entirely rather
  // than disabled, so there is nothing to argue about in the netlist.
  val throttle = if (rd2Cfg.busInstrumentation) Some(LazyModule(new RD2Throttle)) else None
  if (rd2Cfg.busInstrumentation)
    sbus.fromPort(Some("teaching-cpu"))() := cpuWatch.node := throttle.get.node := bridgeNode
  else
    sbus.fromPort(Some("teaching-cpu"))() := cpuWatch.node := bridgeNode


  // the interrupts come from the RD2 copy, which sits at the architectural address; the subsystem's own
  // CLINT is parked at an unused address by the RD2 configurations and drives nothing
  val clintSink = IntSinkNode(IntSinkPortSimple(1, 2))
  clintSink := rd2clint.intnode
  val plicSink = IntSinkNode(IntSinkPortSimple(1, 1))
  plicSink := plic.intnode
  val dummyDebugSink = IntSinkNode(IntSinkPortSimple(1, 1))
  dummyDebugSink := IntSyncCrossingSink(3) := debug.intnode

  override lazy val module = new RD2ZynqTopModule(this)
}

class RD2ZynqTopModule(outer: RD2ZynqTop) extends RocketSubsystemModuleImp(outer)
    with HasRTCModuleImp
    with HasMasterAXI4MemPortModuleImp
    with HasPeripheryBootROMModuleImp
    with HasExtInterruptsModuleImp
    with HasNoDebugModuleImp
    with HasRD2SerialModuleImp
    with HasRD2BlockDeviceModuleImp
    with DontTouch {
  override def resetVectorBits: Int = 32
  val cfg = outer.p(TeachingCpuKey)
  val romParams = outer.p(BootROMParams)

  // ---- the soft reset arrives as data, not as this module's reset ------------------------------------
  // This is the whole structural change. The module's own `reset` is the cold one; `softReset` is a level
  // the PS drives through the adapter register, and the only thing it resets directly is the CPU.
  val softReset  = IO(Input(Bool()))
  val quiesceReq = IO(Input(Bool()))
  val bdevStall  = IO(Input(Bool()))
  val status     = IO(new RD2Status)
  val statusWord = IO(Output(UInt(32.W)))
  // CPU-A: whichever bridge this configuration built -- the drain contract and the debug bundle are the
  // same types, so everything below is written once
  val bmodDrain = if (outer.rd2Cfg.atomic) outer.bridgeV2.get.module.io.drain else outer.bridge.get.module.io.drain
  val bmodDbg   = if (outer.rd2Cfg.atomic) outer.bridgeV2.get.module.io.dbg   else outer.bridge.get.module.io.dbg
  val drain = bmodDrain
  drain.softReset := softReset
  val bdevw = outer.bdevWatch.module
  val ser = outer.rd2serial.module
  ser.io.quiesceReq := quiesceReq
  // the applied reset: restart state is cleared in RESET_APPLY, once, after the drain -- never while a
  // transaction is still owed
  val rd2clint = outer.rd2clint.module
  // A one-shot at the entry to RESET_APPLY, not the level of the phase. The phase lasts as long as the reset
  // request is held, and a level would keep clearing msip for the whole hold -- so a host that writes msip
  // while it still holds the reset (which is exactly what fesvr does: it loads, then wakes) would lose the
  // wake silently and the CPU would sit in the ROM loop for ever. Measured: with the level, a 600-cycle hold
  // during the load left the program never starting. "Applied once, after the drain" is also what the
  // contract says.
  rd2clint.io.applyReset := drain.applying && !RegNext(drain.applying, false.B)
  rd2clint.io.rtcTick := outer.clint.module.io.rtcTick   // the same tick the subsystem generates

  // ---- the CPU is the soft domain --------------------------------------------------------------------
  // withReset works here because TeachingCpu is a plain Chisel Module instantiated by this code. It does
  // *not* work for a diplomatic child (LazyModuleImp builds its children in its own constructor, before any
  // of this runs), which is why every other soft-domain instance in later stages needs an explicit port.
  val cpuV1 = if (outer.rd2Cfg.atomic) None else
    Some(withReset(reset.toBool || drain.cpuResetHold) { Module(new TeachingCpu(romParams.hang)) })
  val cpuV2 = if (outer.rd2Cfg.atomic)
    Some(withReset(reset.toBool || drain.cpuResetHold) { Module(new TeachingCpuV2(romParams.hang)) }) else None
  if (outer.rd2Cfg.atomic) {
    outer.bridgeV2.get.module.io.phys <> cpuV2.get.io.phys
    // the side-band to the accepted backend at the coherence-manager hook
    outer.atomicBackend.getOrElse(throw new Exception("an atomic RD2 configuration needs WithAtomicHub"))
         .module.io.sb <> outer.bridgeV2.get.module.io.sb
  } else {
    outer.bridge.get.module.io.phys <> cpuV1.get.io.phys
  }
  // the observation view both wrappers publish, so the trace and the status word below are written once
  val physObs = if (outer.rd2Cfg.atomic) cpuV2.get.io.physObs else cpuV1.get.io.physObs
  val cpuIrq  = if (outer.rd2Cfg.atomic) cpuV2.get.io.irq     else cpuV1.get.io.irq
  val cpuObs  = if (outer.rd2Cfg.atomic) cpuV2.get.io.obs     else cpuV1.get.io.obs

  val clintInts = outer.clintSink.in.head._1
  cpuIrq.msip := clintInts(0)
  cpuIrq.mtip := clintInts(1)
  cpuIrq.meip := outer.plicSink.in.head._1(0)

  // ---- status ----------------------------------------------------------------------------------------
  // CPU_RESTART_SAFE means: the drain finished and the CPU reset has been applied for at least one whole
  // cycle, so deasserting the request now restarts a CPU that owes nothing. It is built from the bridge's
  // conditions, not from a debug counter, and the apply cycle is counted here rather than by changing the
  // accepted RD1 bridge.
  // Saturating, deliberately. The apply phase lasts as long as the reset request is held, so a wrapping
  // counter makes the SAFE bit drop for one cycle every 256 clocks even though nothing has changed -- which
  // is exactly what a polling PS would eventually sample. (Measured on the previous build: SAFE rose again
  // at cycles 204, 460 and 716 of a single held reset.) It is cleared only when the phase ends, which is the
  // round boundary.
  val applyCnt = RegInit(0.U(8.W))
  when (drain.applying) { when (applyCnt =/= 255.U) { applyCnt := applyCnt + 1.U } }
  .otherwise { applyCnt := 0.U }
  val pendingWork = drain.pendingA || drain.outstanding
  status.cpuRestartSafe := drain.applying && (applyCnt >= 1.U) && !pendingWork
  // RD2-D owns this one. Until the AXI ledger and the block device's own refusal exist, the honest value is
  // 0: a bit named SAFE does not get to mean "probably". The serial adapter's half of the condition is
  // already real (it refuses new commands under the lock and reports when it is finished), and it is
  // reported separately so the gap is visible rather than hidden inside a 0.
  status.plReconfigSafe := false.B
  status.msip        := rd2clint.io.msip
  status.serialIdle  := !ser.io.status.pendingWork
  status.serialFrame := ser.io.status.frameActive
  status.serialTlOutstanding := ser.io.status.tlOutstanding
  status.serialRefusedCycles := ser.io.status.nRefusedCycles
  status.bdevOutstanding := bdevw.io.status.outstanding || bdevw.io.status.pendingA
  status.bdevInflight := bdevw.io.status.inflight

  // ---- R-BOOT: the controlled restart -------------------------------------------------------------
  // See restart-boot/DESIGN.md. Hold new block-device submissions from the cycle the reset is sampled, let
  // every tracker finish its DMA, then flush the completions nobody will legitimately consume, then -- and
  // only then -- say the program may be put back. A device that never finishes trips a sticky timeout and
  // the ready bit is never asserted; nothing is cleared to make it look idle.
  val ctl = outer.controller.module
  // the device's current operation (direction and sector), not merely "busy" -- see RD2BlockDevice.scala
  status.bdevWriteInflight := ctl.io.rboot.writeInflight
  status.bdevReadInflight  := ctl.io.rboot.readInflight
  status.bdevWriteSector   := ctl.io.rboot.writeSector
  // rbFailed is terminal: only a cold reset leaves it. Once the deadline has passed, a device that finally
  // answers may finish its own handshakes (the hold stays on, nothing is flushed or cleared), but READY is
  // never asserted -- readiness after a reported failure is not something the design gets to manufacture.
  val rbIdle :: rbDrain :: rbFlush :: rbReady :: rbFailed :: Nil = Enum(5)
  val rb = RegInit(rbIdle)
  val rbCnt = RegInit(0.U(32.W))
  val rbTimeout = RegInit(false.B)
  val bdevIdle = ctl.io.rboot.trackersIdle && !bdevw.io.status.outstanding && !bdevw.io.status.pendingA
  val cpuDone = drain.applying && !pendingWork              // the bridge drained and the CPU reset applied
  ctl.io.rboot.hold  := softReset || (rb =/= rbIdle)
  ctl.io.rboot.flush := rb === rbFlush
  ctl.io.rboot.stallDevice := bdevStall
  switch (rb) {
    is (rbIdle)  { when (softReset) { rb := rbDrain; rbCnt := 0.U } }
    is (rbDrain) {
      rbCnt := rbCnt + 1.U
      // precedence: completion observed at or before the deadline cycle wins; after it, failure is latched
      when (bdevIdle && cpuDone) { rb := rbFlush; rbCnt := 0.U }
      .elsewhen (rbCnt >= outer.rd2Cfg.rbootTimeout.U) { rbTimeout := true.B; rb := rbFailed }
    }
    is (rbFailed) { /* terminal: a late completion changes nothing here */ }
    is (rbFlush) {
      rbCnt := rbCnt + 1.U
      when (rbCnt >= 2.U && ctl.io.rboot.queuedCompletions === 0.U && ctl.io.rboot.queuedAllocs === 0.U) {
        rb := rbReady
      }
    }
    is (rbReady) { when (!softReset) { rb := rbIdle } }
  }
  status.bdevBusy := !ctl.io.rboot.trackersIdle || bdevw.io.status.outstanding || bdevw.io.status.pendingA
  status.bootRestartReady   := (rb === rbReady) && softReset
  status.bootRestartTimeout := rbTimeout
  status.bdevQueued    := ctl.io.rboot.queuedCompletions
  status.bdevDiscarded := ctl.io.rboot.nDiscarded
  // most of this CPU's traffic is instruction fetch, so "reset while something is in flight" lands on a read
  // unless the condition says otherwise. This is what lets the three write-boundary scenarios be aimed.
  val inflightWrite = RegEnable(physObs.write, false.B, physObs.reqFire)
  // and to DRAM specifically: the first write in flight is often an MMIO one (the CLINT), which is not
  // memory the checker models, so a scenario aimed at "a modelled write in flight" has to say so
  val inflightDram = RegEnable(physObs.addr(31, 28) === 0x8.U, false.B, physObs.reqFire)
  status.writeInFlight := inflightWrite
  status.dramWriteInFlight := inflightWrite && inflightDram
  status.aWaits := bmodDbg.aWaits
  status.aFires := bmodDbg.aFires
  status.dFires := bmodDbg.dFires
  status.quiesceReq  := quiesceReq
  status.draining    := drain.draining
  status.timeout     := drain.timeout
  status.epoch       := drain.epoch
  status.nDrained    := drain.nDrained
  status.pendingWork := pendingWork
  status.pendingA    := drain.pendingA
  status.outstanding := drain.outstanding

  // ---- the 32-bit status word the PS reads at 0x14 -----------------------------------------------------
  // All bits are from the cycle the read is answered. Bits 0-2 are levels, bit 3 is sticky to cold reset.
  // Bit 1 is the one that is allowed to be pessimistic and never optimistic.
  statusWord := Cat(drain.nDrained(15, 0), drain.epoch(7, 0), 0.U(2.W),
                    status.bootRestartTimeout, status.bootRestartReady,
                    drain.timeout, drain.draining, status.plReconfigSafe, status.cpuRestartSafe)

  // ---- instrumentation (simulation configurations only) ----------------------------------------------
  val cycle = RegInit(0.U(48.W)); cycle := cycle + 1.U
  val logOn = !reset.toBool

  // One line per accepted block-device operation, and one when it completes -- deliberately *outside* the
  // event-trace block, because it is a handful of lines per disk transfer rather than per cycle, and it is
  // the only way to tell "the device never took the request" from "it took it and never finished" in a run
  // long enough that a per-cycle trace is impossible.
  if (outer.rd2Cfg.bdevTrace) {
    when (ctl.io.rboot.opAccepted) {
      printf(p"RBOOT ${cycle} BDEV_OP dir=${Mux(ctl.io.rboot.opWrite, 1.U, 0.U)} " +
             p"sector=${ctl.io.rboot.opSector} len=${ctl.io.rboot.opLen}\n")
    }
    val bdevWrPrev = RegNext(ctl.io.rboot.writeInflight, false.B)
    val bdevRdPrev = RegNext(ctl.io.rboot.readInflight, false.B)
    when (bdevWrPrev && !ctl.io.rboot.writeInflight) { printf(p"RBOOT ${cycle} BDEV_DONE dir=1\n") }
    when (bdevRdPrev && !ctl.io.rboot.readInflight) { printf(p"RBOOT ${cycle} BDEV_DONE dir=0\n") }
  }

  // The event format is the accepted one, field for field, so the M3 checker applies to these logs
  // unchanged; `epoch` is appended rather than replacing anything. The sequence number is assigned on the
  // test side exactly as before -- one outstanding transaction, so a request and the next response belong
  // together by construction.
  val seq    = RegInit(0.U(32.W))
  val curSeq = RegInit(0.U(32.W))
  val outstandingEv = RegInit(false.B)
  when (physObs.reqFire)  { outstandingEv := true.B }
  when (physObs.respFire) { outstandingEv := false.B }
  val awaitingRetire = RegInit(false.B)
  when (physObs.respFire && !cpuObs.isFetch) { awaitingRetire := true.B }
  when (cpuObs.commitValid || cpuObs.trapValid) { awaitingRetire := false.B }
  when (physObs.reqFire) { seq := seq + 1.U; curSeq := seq }
  if (cfg.traceEvents) {
    when (logOn && physObs.reqFire) {
      printf(p"EV ${cycle} REQ seq=${seq} pc=0x${Hexadecimal(cpuObs.pc)} " +
             p"fetch=${cpuObs.isFetch} addr=0x${Hexadecimal(physObs.addr)} " +
             p"write=${physObs.write} size=${physObs.size} " +
             p"wdata=0x${Hexadecimal(physObs.wdata)} wmask=0x${Hexadecimal(physObs.wmask)} " +
             p"epoch=${drain.epoch}\n")
    }
    when (logOn && physObs.respFire) {
      printf(p"EV ${cycle} RESP seq=${curSeq} rdata=0x${Hexadecimal(physObs.rdata)} " +
             p"error=${physObs.error} epoch=${drain.epoch}\n")
    }
    when (logOn && cpuObs.commitValid) {
      printf(p"EV ${cycle} COMMIT pc=0x${Hexadecimal(cpuObs.commitPc)} " +
             p"insn=0x${Hexadecimal(cpuObs.commitInsn)}\n")
    }
    when (logOn && cpuObs.trapValid) {
      printf(p"EV ${cycle} TRAP interrupt=${cpuObs.trapInterrupt} " +
             p"cause=0x${Hexadecimal(cpuObs.trapCause)} epc=0x${Hexadecimal(cpuObs.trapEpc)} " +
             p"tval=0x${Hexadecimal(cpuObs.trapTval)}\n")
    }
    val irqNow  = Cat(cpuIrq.meip, cpuIrq.mtip, cpuIrq.msip)
    val irqPrev = RegNext(irqNow, 0.U)
    when (logOn && irqPrev =/= irqNow) {
      printf(p"EV ${cycle} IRQLEVEL msip=${cpuIrq.msip} mtip=${cpuIrq.mtip} meip=${cpuIrq.meip}\n")
    }
    // the reset sequence itself, as events, so a checker can bind them to transactions
    when (logOn && drain.cpuResetHold && !RegNext(drain.cpuResetHold, false.B)) {
      printf(p"RD2 ${cycle} HOLD_ASSERT epoch=${drain.epoch} pendingA=${drain.pendingA} " +
             p"outstanding=${drain.outstanding}\n")
    }
    when (logOn && !drain.cpuResetHold && RegNext(drain.cpuResetHold, false.B)) {
      printf(p"RD2 ${cycle} HOLD_RELEASE epoch=${drain.epoch} nDrained=${drain.nDrained} " +
             p"nLocal=${drain.nLocalDisc} nBuf=${drain.nBufDisc} serialCmds=${ser.io.status.nCmds} " +
             p"serialRefusedCycles=${ser.io.status.nRefusedCycles} " +
             p"serialOrphan=${ser.io.status.nOrphan} " +
             p"serialSameCyc=${ser.io.status.nSameCyc} serialMinLat=${ser.io.status.minLat} " +
             p"cpuAWaits=${bmodDbg.aWaits} " +
             p"cpuSameCyc=${bmodDbg.sameCyc} " +
             p"clintApplies=${rd2clint.io.nApplied} bdevInflight=${bdevw.io.status.inflight} " +
             p"bdevA=${bdevw.io.status.nA} bdevD=${bdevw.io.status.nD} " +
             p"bdevMax=${bdevw.io.status.maxInflight}\n")
    }
    when (logOn && drain.drainDone) {
      printf(p"RD2 ${cycle} DRAIN_DONE epoch=${drain.epoch} nDrained=${drain.nDrained} " +
             p"nLocal=${drain.nLocalDisc} nBuf=${drain.nBufDisc}\n")
    }
    when (logOn && drain.applying && !RegNext(drain.applying, false.B)) {
      printf(p"RD2 ${cycle} RESET_APPLY epoch=${drain.epoch}\n")
    }
    when (logOn && drain.applying && !RegNext(drain.applying, false.B)) {
      printf(p"RD2 ${cycle} CLINT_APPLIED epoch=${drain.epoch} msip_before=${rd2clint.io.msip} " +
             p"serialFrame=${ser.io.status.frameActive} serialTL=${ser.io.status.tlOutstanding} " +
             p"serialCmds=${ser.io.status.nCmds} serialOrphan=${ser.io.status.nOrphan}\n")
    }
    // the safety bit must not blink while the request is still held: if it ever falls with the reset still
    // asserted and no new work, that is the counter-wrap fault, and it is an event rather than a silence
    when (logOn && !status.cpuRestartSafe && RegNext(status.cpuRestartSafe, false.B) && softReset) {
      printf(p"RD2 ${cycle} SAFE_DROP epoch=${drain.epoch} pendingWork=${pendingWork} " +
             p"applying=${drain.applying}\n")
    }
    when (logOn && rb === rbDrain && RegNext(rb, rbIdle) === rbIdle) {
      printf(p"RBOOT ${cycle} DRAIN_START trackersIdle=${ctl.io.rboot.trackersIdle} " +
             p"bdevInflight=${bdevw.io.status.inflight} queued=${ctl.io.rboot.queuedCompletions}\n")
    }
    when (logOn && rb === rbFlush && RegNext(rb, rbIdle) === rbDrain) {
      printf(p"RBOOT ${cycle} BDEV_DRAINED queued=${ctl.io.rboot.queuedCompletions} " +
             p"allocs=${ctl.io.rboot.queuedAllocs} waited=${rbCnt}\n")
    }
    when (logOn && rb === rbReady && RegNext(rb, rbIdle) === rbFlush) {
      printf(p"RBOOT ${cycle} READY discarded=${ctl.io.rboot.nDiscarded}\n")
    }
    // the device answering *after* the deadline: recorded so the scenario can show it happened, and that it
    // changed nothing
    val lateSeen = RegInit(false.B)
    when (rb === rbFailed && bdevIdle && !lateSeen) {
      lateSeen := true.B
      printf(p"RBOOT ${cycle} LATE_DRAIN trackersIdle=${ctl.io.rboot.trackersIdle} ready=${rb === rbReady} " +
             p"queued=${ctl.io.rboot.queuedCompletions} discarded=${ctl.io.rboot.nDiscarded}\n")
    }
    when (logOn && rbTimeout && !RegNext(rbTimeout, false.B)) {
      printf(p"RBOOT ${cycle} TIMEOUT trackersIdle=${ctl.io.rboot.trackersIdle} " +
             p"bdevInflight=${bdevw.io.status.inflight}\n")
    }
    when (logOn && status.cpuRestartSafe && !RegNext(status.cpuRestartSafe, false.B)) {
      printf(p"RD2 ${cycle} CPU_RESTART_SAFE epoch=${drain.epoch}\n")
    }
  }

  // ---- AXI observation, unchanged in shape from the accepted configuration ----------------------------
  val axi = mem_axi4.head
  val nAr = RegInit(0.U(32.W)); val nR = RegInit(0.U(32.W)); val nRlast = RegInit(0.U(32.W))
  val nAw = RegInit(0.U(32.W)); val nW = RegInit(0.U(32.W)); val nWlast = RegInit(0.U(32.W))
  val nB  = RegInit(0.U(32.W))
  if (cfg.traceEvents) {
    when (logOn && axi.ar.fire()) {
      printf(p"EVA ${cycle} AR id=${axi.ar.bits.id} addr=0x${Hexadecimal(axi.ar.bits.addr)} " +
             p"len=${axi.ar.bits.len} size=${axi.ar.bits.size}\n") }
    when (logOn && axi.r.fire()) {
      printf(p"EVA ${cycle} R id=${axi.r.bits.id} last=${axi.r.bits.last} resp=${axi.r.bits.resp} " +
             p"data=0x${Hexadecimal(axi.r.bits.data)}\n") }
    when (logOn && axi.aw.fire()) {
      printf(p"EVA ${cycle} AW id=${axi.aw.bits.id} addr=0x${Hexadecimal(axi.aw.bits.addr)} " +
             p"len=${axi.aw.bits.len} size=${axi.aw.bits.size}\n") }
    // the write payload, so a checker can see what actually reached memory without taking the CPU-side
    // event log's word for it: that log is the thing being judged
    when (logOn && axi.w.fire()) {
      printf(p"EVA ${cycle} W last=${axi.w.bits.last} strb=0x${Hexadecimal(axi.w.bits.strb)} " +
             p"data=0x${Hexadecimal(axi.w.bits.data)}\n") }
    when (logOn && axi.b.fire()) {
      printf(p"EVA ${cycle} B id=${axi.b.bits.id} resp=${axi.b.bits.resp}\n") }
  }
  when (axi.ar.fire()) { nAr := nAr + 1.U }
  when (axi.r.fire())  { nR  := nR  + 1.U; when (axi.r.bits.last) { nRlast := nRlast + 1.U } }
  when (axi.aw.fire()) { nAw := nAw + 1.U }
  when (axi.w.fire())  { nW  := nW  + 1.U; when (axi.w.bits.last) { nWlast := nWlast + 1.U } }
  when (axi.b.fire())  { nB  := nB  + 1.U }

  val obs = IO(Output(new TeachingCpuObs)); obs := cpuObs
  val halted = IO(Output(Bool())); halted := cpuObs.halted
  // the same definition as the accepted configuration: a request offered but not accepted is a commitment,
  // and a data response is not finished until its instruction retires
  val busy = IO(Output(Bool()))
  busy := physObs.reqValid || outstandingEv || awaitingRetire
  val axiStats = IO(Output(new Bundle {
    val ar = UInt(32.W); val r = UInt(32.W); val rlast = UInt(32.W)
    val aw = UInt(32.W); val w = UInt(32.W); val wlast = UInt(32.W); val b = UInt(32.W) }))
  axiStats.ar := nAr; axiStats.r := nR; axiStats.rlast := nRlast
  axiStats.aw := nAw; axiStats.w := nW; axiStats.wlast := nWlast; axiStats.b := nB
}

// ---- the board top: the split, in one place ----------------------------------------------------------
// `target.reset` is the cold reset, and `sys_reset` -- the same adapter register bit the PS writes today --
// goes in as data. The adapter itself is untouched and keeps its own (cold) domain, as it already has.
class RD2BoardTop(implicit val p: Parameters) extends Module {
  val address = p(zynq.ZynqAdapterBase)
  val config  = p(ExtIn)
  val target  = Module(LazyModule(new RD2ZynqTop).module)
  val adapter = Module(LazyModule(new zynq.ZynqAdapterRD2(address, config)).module)

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
  target.dontTouchPortsExcept { p =>
    val n = p.instanceName
    n.startsWith("obs") || n.startsWith("halted") || n.startsWith("busy") ||
    n.startsWith("axiStats") || n.startsWith("status")
  }
  target.reset     := reset.toBool          // D0: cold only
  target.softReset := adapter.io.sys_reset  // D1 request: data, not reset
  // the RD2 register pair lives in the isolated adapter copy, so the shared one is untouched
  adapter.io.rd2.status := target.statusWord
  target.quiesceReq := adapter.io.rd2.quiesceReq
  target.bdevStall := false.B   // simulation-only knob; the board top never drives it
}

// ---- the real boot chain, with the split domains ----------------------------------------------------
// The one difference from the accepted harness is the same one: the subsystem is not held by sys_reset, so
// TSI loading proceeds while the CPU is held. That is the property the whole quiesce design depends on.
// legacyReset models today's wiring inside this harness: the soft reset is the subsystem's reset, exactly
// as `target.reset := adapter.io.sys_reset` does on the accepted board. Everything else -- the injector, the
// programs, the gates -- is identical, so the comparison is between reset structures and nothing else.
class RD2Harness(implicit val p: Parameters) extends Module {
  // a def, not a constructor parameter: the generator instantiates the top by reflection with exactly one
  // Parameters argument, and a def is already overridden by the time the constructor body below runs
  protected def legacyReset: Boolean = false
  val io = IO(new Bundle {
    val success = Output(Bool())
    val halted  = Output(Bool())
    val busy    = Output(Bool())
    val dutReset = Output(Bool())
    val restartSafe = Output(Bool())
    val softResetEff = Output(Bool())    // sys_reset from the driver, or an injected pulse
    val injections = Output(UInt(8.W))
    val restartSafeLevel = Output(Bool())
    // the PS's own control, driven by the simulation loop exactly as a write to 0x10 drives it on the board
    val hostSoftReset = Input(Bool())
    val pendingWork = Output(Bool())
    val bdevOutstanding = Output(Bool())   // the block device still owes work on its own master port
    val bdevBusy = Output(Bool())
    val bootRestartReady = Output(Bool())
    val bootRestartTimeout = Output(Bool())
    val bdevQueued = Output(UInt(8.W))
    val bdevWriteInflight = Output(Bool())
    val bdevReadInflight  = Output(Bool())
    val bdevWriteSector   = Output(UInt(32.W))
    // for an OS-length run: the host samples these periodically instead of logging every cycle
    val obsPc      = Output(UInt(64.W))
    val obsRetired = Output(UInt(64.W))
    // the last trap and how many have been taken: an OS that traps in a loop is diagnosable from these
    // alone, without a per-cycle trace
    val obsTraps     = Output(UInt(64.W))
    val obsTrapCause = Output(UInt(64.W))
    val obsTrapEpc   = Output(UInt(64.W))
    val obsTrapTval  = Output(UInt(64.W))
    val aWaits  = Output(UInt(32.W))       // cycles this master's A was offered and not accepted
    val aFires  = Output(UInt(32.W))
    val dFires  = Output(UInt(32.W))
    val epoch = Output(UInt(16.W))
    val axi = Output(new Bundle {
      val ar = UInt(32.W); val r = UInt(32.W); val rlast = UInt(32.W)
      val aw = UInt(32.W); val w = UInt(32.W); val wlast = UInt(32.W); val b = UInt(32.W) })
  })
  val driver = Module(LazyModule(new zynq.TestHarnessDriver).module)
  val dut = Module(LazyModule(new RD2ZynqTop).module)

  // ---- the soft-reset injector -------------------------------------------------------------------------
  // A soft reset is a thing the PS does at a moment of its choosing, so the interesting cases are the ones
  // where it lands *during* something: a TSI frame the host is half-way through sending, or a CPU
  // transaction the fabric has not answered yet. The injector waits for the named condition rather than a
  // cycle number, which is what makes the scenario reproducible.
  //
  //   +rd2_reset_at=<cycle>    arm at this cycle (0 = never inject)
  //   +rd2_reset_when=0|1|2    0: immediately; 1: when the CPU has work in flight; 2: mid TSI frame
  //   +rd2_reset_len=<n>       hold for n cycles; 0 means "hold until the design says CPU_RESTART_SAFE",
  //                            which is the handshake that replaces the board's fixed 50 ms wait
  //   +rd2_reset_n=<k>         do it k times (default 1)
  // the PS's two controls, as the harness's own inputs: `hostSoftReset` is what the C++ side drives to do
  // exactly what a write to 0x10 does on the board, and the quiesce plusargs exercise 0x18
  val icyc = RegInit(0.U(48.W)); icyc := icyc + 1.U
  val qAt  = PlusArg("rd2_quiesce_at",  0, "cycle at which QUIESCE_REQ is asserted (0 = never)")
  val qLen = PlusArg("rd2_quiesce_len", 0, "cycles to hold QUIESCE_REQ")
  val qOn  = (qAt =/= 0.U) && (icyc >= qAt) && (icyc < (qAt + qLen))
  dut.quiesceReq := qOn
  when (qOn && !RegNext(qOn, false.B)) {
    printf(p"RD2H ${icyc} QUIESCE_ASSERT serialFrame=${dut.status.serialFrame} " +
           p"serialTL=${dut.status.serialTlOutstanding}\n")
  }
  when (!qOn && RegNext(qOn, false.B)) {
    printf(p"RD2H ${icyc} QUIESCE_RELEASE serialIdle=${dut.status.serialIdle} " +
           p"refusedCycles=${dut.status.serialRefusedCycles}\n")
  }
  val iAt   = PlusArg("rd2_reset_at",   0, "cycle at which the soft-reset injector arms (0 = never)")
  val iWhen = PlusArg("rd2_reset_when", 0, "0 immediately, 1 CPU work in flight, 2 mid TSI frame")
  val iLen  = PlusArg("rd2_reset_len",  4, "cycles to hold the soft reset (0 = until CPU_RESTART_SAFE)")
  val iN    = PlusArg("rd2_reset_n",    1, "how many times to inject")

  val iFired = RegInit(0.U(8.W))
  val iHold  = RegInit(false.B)
  val iCnt   = RegInit(0.U(32.W))
  val iArmed = RegInit(true.B)
  val cond = MuxLookup(iWhen, true.B, Seq(
    0.U -> true.B,
    1.U -> (dut.status.pendingA || dut.status.outstanding),
    2.U -> dut.status.serialFrame,
    3.U -> dut.status.bdevOutstanding,
    4.U -> dut.status.pendingA,                              // the write is offered and not yet accepted
    5.U -> (dut.status.outstanding && !dut.status.pendingA),  // accepted, its response not back yet
    6.U -> (dut.status.pendingA && dut.status.writeInFlight),
    7.U -> (dut.status.outstanding && !dut.status.pendingA && dut.status.writeInFlight),
    8.U -> (dut.status.pendingA && dut.status.dramWriteInFlight),
    9.U -> (dut.status.outstanding && !dut.status.pendingA && dut.status.dramWriteInFlight)))
  val iHit = iArmed && !iHold && (iAt =/= 0.U) && (icyc >= iAt) && (iFired < iN) && cond
  when (iHit) {
    iHold := true.B; iCnt := 0.U; iFired := iFired + 1.U; iArmed := false.B
    printf(p"RD2H ${icyc} INJECT n=${iFired + 1.U} when=${iWhen} pendingA=${dut.status.pendingA} " +
           p"outstanding=${dut.status.outstanding} serialFrame=${dut.status.serialFrame} " +
           p"serialTL=${dut.status.serialTlOutstanding} msip=${dut.status.msip}\n")
  }
  when (iHold) {
    iCnt := iCnt + 1.U
    val longEnough = Mux(iLen === 0.U, dut.status.cpuRestartSafe, iCnt >= (iLen - 1.U))
    when (longEnough) {
      iHold := false.B
      printf(p"RD2H ${icyc} RELEASE held=${iCnt + 1.U} restartSafe=${dut.status.cpuRestartSafe} " +
             p"pendingWork=${dut.status.pendingWork} msip=${dut.status.msip} epoch=${dut.status.epoch}\n")
    }
  }
  // re-arm only once the CPU is running again, so repeated injections are separate rounds
  when (!iHold && !dut.status.cpuRestartSafe && !iArmed && (iFired < iN)) { iArmed := true.B }

  val softEff = driver.io.sys_reset || iHold || io.hostSoftReset
  if (legacyReset) {
    // today: one domain. The soft reset wipes the fabric, both masters' records and the CLINT with it.
    dut.reset     := reset.toBool || softEff
    dut.softReset := false.B
  } else {
    dut.reset     := reset.toBool
    dut.softReset := softEff
  }
  dut.debug := DontCare
  dut.tieOffInterrupts()
  dut.dontTouchPorts()
  dut.connectSimAXIMem()
  driver.io.serial <> dut.serial
  driver.io.bdev <> dut.bdev
  io.success := driver.io.success
  io.halted := dut.halted
  io.busy := dut.busy
  io.dutReset := driver.io.sys_reset
  io.restartSafe := dut.status.cpuRestartSafe
  io.softResetEff := softEff
  io.injections := iFired
  io.restartSafeLevel := dut.status.cpuRestartSafe
  io.pendingWork := dut.status.pendingWork
  io.bdevOutstanding := dut.status.bdevOutstanding
  io.bdevBusy := dut.status.bdevBusy
  io.bootRestartReady := dut.status.bootRestartReady
  io.bootRestartTimeout := dut.status.bootRestartTimeout
  io.bdevQueued := dut.status.bdevQueued
  io.bdevWriteInflight := dut.status.bdevWriteInflight
  io.bdevReadInflight  := dut.status.bdevReadInflight
  io.bdevWriteSector   := dut.status.bdevWriteSector
  io.obsPc := dut.obs.pc
  val retired = RegInit(0.U(64.W))
  when (dut.obs.commitValid) { retired := retired + 1.U }
  io.obsRetired := retired
  val nTraps = RegInit(0.U(64.W))
  val lastCause = RegInit(0.U(64.W)); val lastEpc = RegInit(0.U(64.W)); val lastTval = RegInit(0.U(64.W))
  when (dut.obs.trapValid) {
    nTraps := nTraps + 1.U; lastCause := dut.obs.trapCause; lastEpc := dut.obs.trapEpc; lastTval := dut.obs.trapTval
  }
  io.obsTraps := nTraps; io.obsTrapCause := lastCause; io.obsTrapEpc := lastEpc; io.obsTrapTval := lastTval
  // the stuck-device negative: the device never answers from this cycle on
  val stallAt = PlusArg("rd2_bdev_stall_at", 0, "cycle from which the block device stops answering (0 = never)")
  val stallUntil = PlusArg("rd2_bdev_stall_until", 0, "cycle at which it answers again (0 = never)")
  dut.bdevStall := (stallAt =/= 0.U) && (icyc >= stallAt) && ((stallUntil === 0.U) || (icyc < stallUntil))
  io.aWaits := dut.status.aWaits
  io.aFires := dut.status.aFires
  io.dFires := dut.status.dFires
  io.epoch := dut.status.epoch
  io.axi := dut.axiStats
}

class WithRD2(rd2: RD2Params = RD2Params()) extends Config((site, here, up) => {
  case RD2Key => rd2
  // the subsystem's own CLINT is parked at an address nothing uses and nothing is wired to it; the RD2 copy
  // holds the architectural address. Moving it rather than deleting it keeps the subsystem's traits intact.
  case freechips.rocketchip.devices.tilelink.CLINTKey =>
    freechips.rocketchip.devices.tilelink.CLINTParams(baseAddress = 0x03000000L)
})

class RD2LegacyHarness(implicit p: Parameters) extends RD2Harness {
  override protected def legacyReset = true
}

// the negative configurations: a real fault on the real path, not a mutated log
class RD2FaultDupConfig extends Config(
  new WithRD2(RD2Params(bridgeFault = 3)) ++
  new WithTeachingCpu(TeachingCpuParams(traceEvents = true, extraDelay = false, bridgeFault = 0,
                                        tailIntercept = false)) ++
  new WithTeachingBootROM ++ new zynq.WithZynqAdapter ++ new freechips.rocketchip.system.DefaultConfig)
// fault 1 corrupts the *write payload* after an A stall, so the bytes that reach memory are not the bytes
// the CPU asked for: the case the AXI-side ledger exists to catch.
class RD2FaultWriteConfig extends Config(
  new WithRD2(RD2Params(bridgeFault = 1)) ++
  new WithTeachingCpu(TeachingCpuParams(traceEvents = true, extraDelay = false, bridgeFault = 0,
                                        tailIntercept = false)) ++
  new WithTeachingBootROM ++ new zynq.WithZynqAdapter ++ new freechips.rocketchip.system.DefaultConfig)
class RD2FaultMutateConfig extends Config(
  new WithRD2(RD2Params(bridgeFault = 7)) ++
  new WithTeachingCpu(TeachingCpuParams(traceEvents = true, extraDelay = false, bridgeFault = 0,
                                        tailIntercept = false)) ++
  new WithTeachingBootROM ++ new zynq.WithZynqAdapter ++ new freechips.rocketchip.system.DefaultConfig)

// simulation: the teaching ROM, events on, no intercept, monitors on
class RD2BootConfig extends Config(
  new WithRD2() ++
  new WithTeachingCpu(TeachingCpuParams(traceEvents = true, extraDelay = false, bridgeFault = 0,
                                        tailIntercept = false)) ++
  new WithTeachingBootROM ++ new zynq.WithZynqAdapter ++ new freechips.rocketchip.system.DefaultConfig)

// the board shape of the same thing: no monitors, no events, for the generated-RTL comparison only.
// It is *not* a replacement for the accepted board configuration and nothing is synthesised from it here.
class RD2BoardConfig extends Config(
  new WithRD2(RD2Params(traceEvents = false)) ++
  new WithTeachingCpu(TeachingCpuParams(traceEvents = false, extraDelay = false, bridgeFault = 0,
                                        tailIntercept = false)) ++
  new WithTeachingBootROM ++ new freechips.rocketchip.subsystem.WithoutTLMonitors ++
  new zynq.WithZynqAdapter ++ new freechips.rocketchip.system.DefaultConfig)

// ---- CPU-A: the isolated atomic R-BOOT configuration -------------------------------------------------
// The same R-BOOT topology (TSI, the block device, DDR through TLToAXI4, the teaching ROM, the real CLINT
// and PLIC, the drain contract) with the V2 bridge, the V2 CPU wrapper and the accepted AtomicBackend at
// the coherence-manager hook. Nothing above is edited: RD2Params.atomic is false everywhere else, so every
// configuration that existed before elaborates exactly as it did.
class RD2AtomicBootConfig extends Config(
  new WithAtomicHub() ++
  new WithRD2(RD2Params(atomic = true)) ++
  new WithTeachingCpu(TeachingCpuParams(traceEvents = true, extraDelay = false, bridgeFault = 0,
                                        tailIntercept = false)) ++
  new WithTeachingBootROM ++ new zynq.WithZynqAdapter ++ new freechips.rocketchip.system.DefaultConfig)

// CPU-A / xv6: the atomic R-BOOT configuration with the per-event trace off. Booting an operating system
// runs for tens of millions of cycles; the event trace is invaluable for a ten-thousand-cycle bring-up
// program and unusable here (it costs ~80 bytes of log per cycle). Everything else -- the CPU, the atomic
// backend, the devices, the drain contract -- is identical to RD2AtomicBootConfig, so a stage that fails
// can be re-run on that configuration to get the full trace.
class RD2AtomicXv6Config extends Config(
  new WithAtomicHub(trace = false) ++
  new WithRD2(RD2Params(atomic = true, traceEvents = false, atomicTrace = false)) ++
  new WithTeachingCpu(TeachingCpuParams(traceEvents = false, extraDelay = false, bridgeFault = 0,
                                        tailIntercept = false)) ++
  new WithTeachingBootROM ++ new zynq.WithZynqAdapter ++ new freechips.rocketchip.system.DefaultConfig)

// xv6: the same machine as RD2AtomicXv6Config with the TileLink monitors left out. The monitors are pure
// verification logic -- they check protocol compliance and never drive anything -- and they are a large
// fraction of the emitted RTL, so they dominate an OS-length simulation. Protocol compliance is checked by
// the accepted gates, which run on the monitored configurations; this one exists so that a boot that takes
// tens of millions of cycles finishes in a reasonable wall time.
class RD2AtomicXv6FastConfig extends Config(
  new freechips.rocketchip.subsystem.WithoutTLMonitors ++
  new WithAtomicHub(trace = false) ++
  new WithRD2(RD2Params(atomic = true, traceEvents = false, atomicTrace = false)) ++
  new WithTeachingCpu(TeachingCpuParams(traceEvents = false, extraDelay = false, bridgeFault = 0,
                                        tailIntercept = false)) ++
  new WithTeachingBootROM ++ new zynq.WithZynqAdapter ++ new freechips.rocketchip.system.DefaultConfig)

// ---- CPU-A / xv6, board shape ------------------------------------------------------------------------
// The same machine as RD2AtomicXv6FastConfig, generated as RD2BoardTop instead of the harness: no TileLink
// monitors, no event trace, no atomic trace, and -- the one thing the simulation configurations keep --
// no BDEV trace either, because every printf here would be elaborated into a netlist that is going to be
// synthesised. Nothing above is edited: bdevTrace defaults to true, so every existing configuration
// elaborates exactly as it did.
class RD2AtomicBoardConfig extends Config(
  new freechips.rocketchip.subsystem.WithoutTLMonitors ++
  new WithAtomicHub(trace = false) ++
  new WithRD2(RD2Params(atomic = true, traceEvents = false, atomicTrace = false, bdevTrace = false,
                        busInstrumentation = false)) ++
  new WithTeachingCpu(TeachingCpuParams(traceEvents = false, extraDelay = false, bridgeFault = 0,
                                        tailIntercept = false)) ++
  new WithTeachingBootROM ++ new zynq.WithZynqAdapter ++ new freechips.rocketchip.system.DefaultConfig)
