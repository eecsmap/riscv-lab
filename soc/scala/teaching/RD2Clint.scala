// RD2-C: the CLINT as an isolated copy, with one thing added: a reset that is *applied*, not implicit.
//
// Why a copy at all. Today the CLINT is reset by sys_reset along with everything else; under the RD2 split
// the whole subsystem is cold-domain, so without this the machine software interrupt would survive a CPU
// restart. That matters concretely: the boot ROM's wake loop polls msip, and a stale 1 would end it
// immediately, so the CPU would jump into a program that the host has not started yet.
//
// rocket-chip's CLINT is a diplomatic LazyModule, so it cannot be given a different implicit reset from a
// teaching class (rd2-0). Hence a copy, with an explicit `applyReset` input driven from the bridge's
// RESET_APPLY phase.
//
// What the applied reset clears, and what it deliberately does not:
//   * msip (`ipi`) is cleared. Its documented reset value is 0, and it is restart state.
//   * mtime keeps running. A timer that restarted with the CPU would be a different device; the real one
//     is free-running, and software reads it to schedule.
//   * mtimecmp is NOT reset -- exactly as in the real device, where those registers have no reset value at
//     all. Software that enables MTIE without first pushing mtimecmp out of reach sees mtip immediately;
//     that is true of the hardware today, and the M3 CLINT program already does the push explicitly.
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config.Parameters
import freechips.rocketchip.devices.tilelink.{CLINTConsts, CLINTParams}
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.interrupts._
import freechips.rocketchip.regmapper.{RegField, RegFieldDesc, RegFieldGroup}
import freechips.rocketchip.subsystem.BaseSubsystem
import freechips.rocketchip.tilelink.TLRegisterNode

class RD2Clint(params: CLINTParams, beatBytes: Int)(implicit p: Parameters) extends LazyModule {
  import CLINTConsts._

  val device = new SimpleDevice("clint", Seq("riscv,clint0")) { override val alwaysExtended = true }
  val node = TLRegisterNode(address = Seq(params.address), device = device, beatBytes = beatBytes)
  val intnode = IntNexusNode(
    sourceFn = { _ => IntSourcePortParameters(Seq(IntSourceParameters(ints, Seq(Resource(device, "int"))))) },
    sinkFn   = { _ => IntSinkPortParameters(Seq(IntSinkParameters())) },
    outputRequiresInput = false)

  lazy val module = new LazyModuleImp(this) {
    require(intnode.edges.in.size == 0, "RD2Clint only produces interrupts; it does not accept them")
    val io = IO(new Bundle {
      val rtcTick    = Input(Bool())
      val applyReset = Input(Bool())    // the RESET_APPLY phase: restart state is cleared here, once
      val msip       = Output(Bool())
      val nApplied   = Output(UInt(32.W))
    })

    val time = RegInit(0.U(timeWidth.W))
    when (io.rtcTick) { time := time + 1.U }

    val nTiles = intnode.out.size
    val timecmp = Seq.fill(nTiles) { Reg(UInt(timeWidth.W)) }
    val ipi = Seq.fill(nTiles) { RegInit(0.U(1.W)) }

    val nApplied = RegInit(0.U(32.W))
    when (io.applyReset && !RegNext(io.applyReset, false.B)) { nApplied := nApplied + 1.U }

    val (intnode_out, _) = intnode.out.unzip
    intnode_out.zipWithIndex.foreach { case (int, i) =>
      int(0) := ShiftRegister(ipi(i)(0), params.intStages)
      int(1) := ShiftRegister(time.asUInt >= timecmp(i).asUInt, params.intStages)
    }

    node.regmap(
      0 -> RegFieldGroup("msip", Some("MSIP Bits"), ipi.zipWithIndex.map { case (r, i) =>
        RegField(ipiWidth, r, RegFieldDesc(s"msip_$i", s"MSIP bit for Hart $i", reset = Some(0))) }),
      timecmpOffset(0) -> timecmp.zipWithIndex.flatMap { case (t, i) =>
        RegFieldGroup(s"mtimecmp_$i", Some(s"MTIMECMP for hart $i"),
          RegField.bytes(t, Some(RegFieldDesc(s"mtimecmp_$i", "", reset = None)))) },
      timeOffset -> RegFieldGroup("mtime", Some("Timer Register"),
        RegField.bytes(time, Some(RegFieldDesc("mtime", "", reset = Some(0), volatile = true)))))

    // The applied reset comes last, so it wins over a register write landing in the same cycle: a write from
    // the epoch that is being torn down must not survive the restart it is being reset for.
    when (io.applyReset) { ipi.foreach { r => r := 0.U } }

    io.msip := ipi.head(0)
    io.nApplied := nApplied
  }
}

trait HasRD2Clint { this: BaseSubsystem =>
  // at the architectural CLINT address; the subsystem's own CLINT is parked elsewhere by the RD2 config and
  // nothing is wired to it
  val rd2clint = LazyModule(new RD2Clint(CLINTParams(0x02000000L), pbus.beatBytes))
  pbus.toVariableWidthSlave(Some("rd2clint")) { rd2clint.node }
}
