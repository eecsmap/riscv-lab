// R-BOOT: the block-device controller with the two things a controlled restart needs -- a hold on new
// submissions, and a flush of the bookkeeping that would otherwise be handed to the next program.
//
// testchipip's BlockDeviceFrontend, BlockDeviceTracker and BlockDeviceArbiter are used as they are. What is
// copied is the router (it owns the allocation and completion queues, which are exactly the state that
// leaks across a restart) and the controller's wiring. The upstream file is untouched; Rocket's default
// configurations never instantiate any of this.
//
// Why a hold and not a reset: a tracker that has accepted a request is in the middle of a DMA, and the DMA
// must *finish* -- the fault this fixes is precisely old data still landing after the new program was
// loaded. So: refuse new work, let old work complete, and only then throw away the completions nobody will
// legitimately consume, counting each one.
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config.Parameters
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.tilelink._
import freechips.rocketchip.util.DecoupledHelper
import testchipip._

class RD2BlockDeviceRouter(implicit p: Parameters) extends BlockDeviceModule {
  val io = IO(new Bundle {
    val in = Flipped(new BlockDeviceBackendIO)
    val out = Vec(nTrackers, new BlockDeviceTrackerIO)
    val hold  = Input(Bool())     // accept no new request; nothing presented is withdrawn
    val flush = Input(Bool())     // empty the two queues; only meaningful once every tracker is idle
    val queuedCompletions = Output(UInt(backendQueueCountBits.W))
    val queuedAllocs      = Output(UInt(backendQueueCountBits.W))
    val nDiscarded        = Output(UInt(32.W))
  })

  val outReadyAll = io.out.map(_.req.ready)
  val outReadyOH = PriorityEncoderOH(outReadyAll)
  val outReady = outReadyAll.reduce(_ || _)

  val allocQueue = Module(new Queue(UInt(tagBits.W), backendQueueDepth))
  io.in.nallocate := PopCount(outReadyAll)

  // the hold is a fourth party to the handshake: with it asserted nothing fires, and the frontend's pending
  // allocation read simply keeps waiting -- its ready is low, its request is not lost
  val helper = DecoupledHelper(outReady, io.in.req.valid, allocQueue.io.enq.ready, !io.hold)
  io.in.req.ready := helper.fire(io.in.req.valid)
  allocQueue.io.enq.valid := helper.fire(allocQueue.io.enq.ready)
  allocQueue.io.enq.bits := OHToUInt(outReadyOH)
  io.out.zipWithIndex.foreach { case (out, i) =>
    out.req.valid := helper.fire(outReady, outReadyOH(i))
    out.req.bits := io.in.req.bits
  }

  val completeQueue = Module(new Queue(UInt(tagBits.W), backendQueueDepth))
  val completeArb = Module(new RRArbiter(Bool(), nTrackers))
  completeArb.io.in <> io.out.map(_.complete)
  completeQueue.io.enq.valid := completeArb.io.out.valid
  completeQueue.io.enq.bits := completeArb.io.chosen
  completeArb.io.out.ready := completeQueue.io.enq.ready

  // Flushing drains both queues internally and hides them from the frontend meanwhile. A stock Queue has no
  // clear, and none is needed: with depth 2 this takes at most two cycles, and every completion dropped this
  // way is counted -- it is a recorded discard, not a silent one.
  val nDisc = RegInit(0.U(32.W))
  io.in.complete.valid := completeQueue.io.deq.valid && !io.flush
  io.in.complete.bits  := completeQueue.io.deq.bits
  completeQueue.io.deq.ready := io.in.complete.ready || io.flush
  when (io.flush && completeQueue.io.deq.valid) { nDisc := nDisc + 1.U }
  io.in.allocate.valid := allocQueue.io.deq.valid && !io.flush
  io.in.allocate.bits  := allocQueue.io.deq.bits
  allocQueue.io.deq.ready := io.in.allocate.ready || io.flush
  io.in.ncomplete := completeQueue.io.count

  io.queuedCompletions := completeQueue.io.count
  io.queuedAllocs      := allocQueue.io.count
  io.nDiscarded        := nDisc
}

class RD2BootIO(implicit p: Parameters) extends BlockDeviceBundle {
  val hold  = Input(Bool())
  val flush = Input(Bool())
  // R-BOOT write-target fix: which *operation* the device is actually carrying, so a restart can be aimed
  // at a disk WRITE that has been accepted and is still in flight rather than at "the device is busy".
  // A read and a write both make the device busy; only these say which one it is.
  val opAccepted    = Output(Bool())              // pulse: a tracker accepted a request this cycle
  val opWrite       = Output(Bool())              // ... and its direction (1 = write to the disk)
  val opSector      = Output(UInt(32.W))          // ... and its first sector
  val opLen         = Output(UInt(32.W))
  val writeInflight = Output(Bool())              // a write has been accepted and has not completed
  val writeSector   = Output(UInt(32.W))          // the sector of that write
  val readInflight  = Output(Bool())              // the same for a read, so the negative can be stated
  val stallDevice = Input(Bool())     // test only: the device never answers (the stuck-device negative)
  val trackersIdle = Output(Bool())   // every tracker back in s_idle: old DMA can no longer touch memory
  val queuedCompletions = Output(UInt(backendQueueCountBits.W))
  val queuedAllocs = Output(UInt(backendQueueCountBits.W))
  val nDiscarded = Output(UInt(32.W))
}

class RD2BlockDeviceController(address: BigInt, beatBytes: Int)(implicit p: Parameters)
    extends LazyModule with HasBlockDeviceParameters {
  val mmio = TLIdentityNode()
  val mem = TLIdentityNode()
  val trackers = Seq.tabulate(nTrackers)(id => LazyModule(new BlockDeviceTracker(id)))
  val frontend = LazyModule(new BlockDeviceFrontend(BlockDeviceFrontendParams(address, beatBytes)))
  frontend.node := mmio
  val intnode = frontend.intnode
  trackers.foreach { tr => mem := TLWidthWidget(dataBitsPerBeat / 8) := tr.node }

  lazy val module = new LazyModuleImp(this) with HasBlockDeviceParameters {
    val io = IO(new Bundle {
      val bdev = new BlockDeviceIO
      val rboot = new RD2BootIO
    })
    val fe = frontend.module
    val router = Module(new RD2BlockDeviceRouter)
    val trs = trackers.map(_.module)
    val arbiter = Module(new BlockDeviceArbiter)

    fe.io.info := io.bdev.info
    router.io.in <> fe.io.back
    trs.zip(router.io.out).foreach { case (tracker, out) => tracker.io.front <> out }
    arbiter.io.in <> trs.map(_.io.bdev)
    io.bdev <> arbiter.io.out
    // the stuck device: responses from the host side never arrive (test only; a normal run never sets it)
    when (io.rboot.stallDevice) {
      arbiter.io.out.resp.valid := false.B
      io.bdev.resp.ready := false.B
    }

    router.io.hold  := io.rboot.hold
    router.io.flush := io.rboot.flush
    // a tracker is idle exactly when it would accept a new request: that is its s_idle, observed from outside
    io.rboot.trackersIdle := trs.map(_.io.front.req.ready).reduce(_ && _)
    // one flag per tracker: set at the request handshake with the request's own direction, cleared when
    // that tracker reports completion. The sector comes from the same handshake.
    val opFire   = router.io.out.map(_.req.fire())
    val anyFire  = opFire.reduce(_ || _)
    val fireIdxW = Mux1H(opFire, router.io.out.map(_.req.bits.write))
    val fireIdxS = Mux1H(opFire, router.io.out.map(_.req.bits.offset))
    val fireIdxL = Mux1H(opFire, router.io.out.map(_.req.bits.len))
    val inflW = router.io.out.zipWithIndex.map { case (out, i) =>
      val busy = RegInit(false.B); val isWr = RegInit(false.B); val sec = RegInit(0.U(32.W))
      when (out.req.fire())      { busy := true.B;  isWr := out.req.bits.write; sec := out.req.bits.offset }
      when (out.complete.fire()) { busy := false.B }
      (busy, isWr, sec)
    }
    io.rboot.opAccepted    := anyFire
    io.rboot.opWrite       := fireIdxW
    io.rboot.opSector      := fireIdxS
    io.rboot.opLen         := fireIdxL
    io.rboot.writeInflight := inflW.map { case (b, w, _) => b && w }.reduce(_ || _)
    io.rboot.readInflight  := inflW.map { case (b, w, _) => b && !w }.reduce(_ || _)
    io.rboot.writeSector   := Mux1H(inflW.map { case (b, w, _) => b && w }, inflW.map(_._3))
    io.rboot.queuedCompletions := router.io.queuedCompletions
    io.rboot.queuedAllocs := router.io.queuedAllocs
    io.rboot.nDiscarded := router.io.nDiscarded
  }
}
