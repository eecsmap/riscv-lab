// RD2-D, first piece: a transparent watcher on a master's TileLink port.
//
// The SoC-level question "is this master finished?" has to be answerable for masters whose internals are not
// mine to change. The block-device controller is the case in point: RD2-C left it in the cold domain, which
// stops its trackers being wiped, but nothing reported whether it still had work outstanding, so its
// behaviour under a soft reset was untested rather than verified.
//
// This adapter passes every channel through untouched -- it is an identity node, and nothing in the path is
// gated, delayed or reordered -- and counts what crosses it: requests offered and not yet accepted, requests
// accepted whose response has not come back, and the totals. That is the per-master half of the ledger the
// quiesce condition needs; the AXI-boundary half is separate and still to come.
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config.Parameters
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.tilelink._
import freechips.rocketchip.util.PlusArg

class RD2WatchStatus extends Bundle {
  val pendingA    = Output(Bool())        // an A is offered and has not been accepted
  val outstanding = Output(Bool())        // at least one accepted request is unanswered
  val inflight    = Output(UInt(8.W))     // how many
  val nA          = Output(UInt(32.W))
  val nD          = Output(UInt(32.W))
  val maxInflight = Output(UInt(8.W))     // the high-water mark, so "it was never busy" is falsifiable
}

class RD2Watch(name: String, trace: Boolean = false)(implicit p: Parameters) extends LazyModule {
  val node = TLAdapterNode()
  private val masterName = name   // `name` is shadowed by LazyModuleImp.name inside the module body
  lazy val module = new LazyModuleImp(this) {
    val io = IO(new Bundle { val status = new RD2WatchStatus })

    // A master may present several ports -- the block-device controller has one per tracker -- so the
    // watcher covers all of them and reports the master as busy if any port is. Requiring a single port was
    // wrong and elaboration said so.
    val ports = node.in.size
    require(ports >= 1, s"RD2Watch($name) has no ports")
    val inflights = Seq.tabulate(ports) { i => RegInit(0.U(8.W)) }
    val nA = RegInit(0.U(32.W))
    val nD = RegInit(0.U(32.W))
    val maxInflight = RegInit(0.U(8.W))
    val pendA = Wire(Vec(ports, Bool()))

    (node.in zip node.out).zipWithIndex.foreach { case (((in, edgeIn), (out, edgeOut)), i) =>
      out <> in
      // a request that expects a response is counted when it is accepted; the *last* beat of its response
      // retires it, so a multi-beat D is one transaction
      val aFire = out.a.fire() && edgeOut.first(out.a)
      val dFire = in.d.fire() && edgeIn.last(in.d)
      when (aFire && !dFire) { inflights(i) := inflights(i) + 1.U }
      when (dFire && !aFire) { inflights(i) := inflights(i) - 1.U }
      when (aFire) { nA := nA + 1.U }
      when (dFire) { nD := nD + 1.U }
      pendA(i) := out.a.valid && !out.a.ready

      // Every request this master actually puts on the bus, with its payload. This is what lets a checker
      // attribute a write seen at the memory boundary to the master that originated it, instead of exempting
      // whatever it cannot explain.
      if (trace) {
        val cyc = RegInit(0.U(48.W)); cyc := cyc + 1.U
        // off unless a scenario asks for it: the accepted M3 gate parses these logs, and its console
        // reconstruction treats anything it does not recognise as program output. Adding a new line type to
        // every run broke that gate, which is a good reason for instrumentation to be opt-in.
        val traceOn = PlusArg("rd2_trace_masters", 0, "log every A beat each master puts on the bus") =/= 0.U
        when (traceOn && out.a.fire()) {
          printf(p"RD2M ${cyc} ${masterName} A port=${i.U} op=${out.a.bits.opcode} " +
                 p"addr=0x${Hexadecimal(out.a.bits.address)} size=${out.a.bits.size} " +
                 p"mask=0x${Hexadecimal(out.a.bits.mask)} data=0x${Hexadecimal(out.a.bits.data)}\n")
        }
      }
    }
    val inflight = inflights.reduce(_ +& _)(7, 0)
    when (inflight > maxInflight) { maxInflight := inflight }

    io.status.pendingA    := pendA.reduce(_ || _)
    io.status.outstanding := inflight =/= 0.U
    io.status.inflight    := inflight
    io.status.nA          := nA
    io.status.nD          := nD
    io.status.maxInflight := maxInflight
  }
}

// The block device, instantiated here rather than through testchipip's trait, so the watcher can sit in its
// master path. The controller, its address and its connections are exactly the trait's (BlockDevice.scala:
// 433-440); the only difference is the identity node in the middle.
trait HasRD2BlockDevice { this: freechips.rocketchip.subsystem.BaseSubsystem =>
  private val portName = "blkdev-controller"
  // the R-BOOT copy: testchipip's frontend/trackers/arbiter, with a router that can hold and flush
  val controller = LazyModule(new RD2BlockDeviceController(0x10015000, pbus.beatBytes))
  val bdevWatch = LazyModule(new RD2Watch("bdev", trace = p(RD2Key).busInstrumentation))
  pbus.toVariableWidthSlave(Some(portName)) { controller.mmio }
  sbus.fromPort(Some(portName))() :=* bdevWatch.node :=* controller.mem
  ibus.fromSync := controller.intnode
}

trait HasRD2BlockDeviceModuleImp extends LazyModuleImp {
  val outer: HasRD2BlockDevice
  val bdev = IO(new testchipip.BlockDeviceIO)
  bdev <> outer.controller.module.io.bdev

  def connectSimBlockDevice(clock: Clock, reset: Bool) {
    val sim = Module(new testchipip.SimBlockDevice)
    sim.io.clock := clock
    sim.io.reset := reset
    sim.io.bdev <> bdev
  }
}
