// RD1: directed soft-reset / drain scenarios for the bridge, with an event log an independent scoreboard
// reads. Nothing here is instantiated by any board or SoC configuration.
//
// The harness is deliberately *not* self-judging. It prints one line per real event -- CPU request accepted,
// TL A fired, TL D fired, response delivered to the CPU, local discard, buffered discard, drained discard,
// reset asserted, drain done, reset applied, hold released, epoch advanced, write applied in the manager,
// injector hit -- each tagged with (epoch, txid), and scripts/rd1-score.py decides. That keeps the judging
// out of the thing being judged.
package teaching

import chisel3._
import chisel3.util._
import freechips.rocketchip.config.{Config, Parameters}
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.tilelink._
import freechips.rocketchip.unittest._

// A manager whose latency, A back-pressure, error behaviour and "never answers" case are all controllable,
// and whose read data is unique per response, so an old D can never be mistaken for a new one by accident.
class RD1Manager(address: AddressSet, latency: Int, aStall: Int, neverAfter: Int, errorMask: BigInt,
                 depth: Int = 1, zeroLat: Boolean = false, aNeverReady: Boolean = false, beatBytes: Int = 8)(implicit p: Parameters) extends LazyModule {
  val device = new MemoryDevice
  val node = TLManagerNode(Seq(TLManagerPortParameters(Seq(TLManagerParameters(
    address = Seq(address), resources = device.reg, regionType = RegionType.UNCACHED,
    supportsGet = TransferSizes(1, beatBytes), supportsPutFull = TransferSizes(1, beatBytes),
    supportsPutPartial = TransferSizes(1, beatBytes), fifoId = Some(0))),
    beatBytes = beatBytes, minLatency = if (zeroLat) 0 else 1)))

  lazy val module = new LazyModuleImp(this) {
    val (tl, edge) = node.in(0)
    val cyc = RegInit(0.U(32.W)); cyc := cyc + 1.U

    class Entry extends Bundle {
      val src   = UInt(tl.d.bits.source.getWidth.W)
      val sz    = UInt(tl.d.bits.size.getWidth.W)
      val isGet = Bool()
      val addr  = UInt(32.W)
      val due   = UInt(32.W)
    }
    val q = Module(new Queue(new Entry, depth))
    val zeroLatWire = zeroLat.B
    val nA   = RegInit(0.U(32.W))
    val dSeq = RegInit(0.U(24.W))
    val stallN = RegInit(0.U(32.W))

    val neverReady = if (aNeverReady) (nA >= 1.U) else false.B
    val stalling = (if (aStall == 0) false.B else (tl.a.valid && (stallN < aStall.U))) || neverReady
    when (tl.a.valid && (stallN < aStall.U)) { stallN := stallN + 1.U }
    when (tl.a.fire()) { stallN := 0.U }

    q.io.enq.valid := tl.a.valid && !stalling && !zeroLatWire
    q.io.enq.bits.src   := tl.a.bits.source
    q.io.enq.bits.sz    := tl.a.bits.size
    q.io.enq.bits.isGet := tl.a.bits.opcode === TLMessages.Get
    q.io.enq.bits.addr  := tl.a.bits.address
    q.io.enq.bits.due   := cyc + latency.U
    if (!zeroLat) { tl.a.ready := q.io.enq.ready && !stalling }

    when (tl.a.fire()) {
      nA := nA + 1.U
      printf(p"RD1 ${cyc} M_A addr=0x${Hexadecimal(tl.a.bits.address)} get=${tl.a.bits.opcode === TLMessages.Get} n=${nA + 1.U}\n")
      when (tl.a.bits.opcode =/= TLMessages.Get) {
        printf(p"RD1 ${cyc} WRITE_APPLY addr=0x${Hexadecimal(tl.a.bits.address)} data=0x${Hexadecimal(tl.a.bits.data)} mask=0x${Hexadecimal(tl.a.bits.mask)}\n")
      }
    }

    // the "never answers" case: after `neverAfter` transactions the manager simply stops responding
    val never = if (neverAfter == 0) false.B else (nA > neverAfter.U)
    val head  = q.io.deq.bits
    val isErr = if (errorMask == 0) false.B else ((head.addr & errorMask.U) === errorMask.U)
    // data unique per response: nothing that arrives late can look like something asked for later
    val data = Cat("hD1".U(8.W), dSeq, head.addr)(63, 0)
    if (zeroLat) {
      q.io.deq.ready := false.B              // the queue is unused in this mode, but must be fully driven
      // combinational manager: the D for this A is produced in the very cycle the A is accepted
      val aIsGet = tl.a.bits.opcode === TLMessages.Get
      val aErr   = if (errorMask == 0) false.B else ((tl.a.bits.address.pad(32) & errorMask.U) === errorMask.U)
      val aData  = Cat("hD1".U(8.W), dSeq, tl.a.bits.address.pad(32))(63, 0)
      q.io.enq.valid := false.B
      tl.a.ready := tl.d.ready && !never && !stalling
      tl.d.valid := tl.a.valid && !never && !stalling
      tl.d.bits  := Mux(aIsGet, edge.AccessAck(tl.a.bits.source, tl.a.bits.size, aData, aErr),
                                edge.AccessAck(tl.a.bits.source, tl.a.bits.size, aErr))
      when (tl.d.fire()) {
        dSeq := dSeq + 1.U
        printf(p"RD1 ${cyc} M_D data=0x${Hexadecimal(aData)} err=${aErr} get=${aIsGet}\n")
      }
    } else {
      tl.d.valid := q.io.deq.valid && (cyc >= head.due) && !never
      tl.d.bits  := Mux(head.isGet, edge.AccessAck(head.src, head.sz, data, isErr),
                                    edge.AccessAck(head.src, head.sz, isErr))
      q.io.deq.ready := tl.d.ready && (cyc >= head.due) && !never
      when (tl.d.fire()) {
        dSeq := dSeq + 1.U
        printf(p"RD1 ${cyc} M_D data=0x${Hexadecimal(data)} err=${isErr} get=${head.isGet}\n")
      }
    }
    tl.b.valid := false.B; tl.c.ready := true.B; tl.e.ready := true.B
  }
}

// trigger codes
object RD1Trig {
  val idle = 0; val reqOffer = 1; val afterReqBeforeA = 2; val aFire = 3; val dFire = 4
  val adSame = 5; val waitingD = 6; val respBp = 7; val illegal = 8; val none = 9
  val respReady = 10   // a response is buffered and the CPU would take it in this very cycle
}

class RD1Harness(trig: Int, resetLen: Int, pulses: Int, latency: Int, aStall: Int, neverAfter: Int,
                 respBp: Int, useDrainBridge: Boolean, nPre: Int, nPost: Int, writes: Boolean,
                 errorMask: BigInt, applyCycles: Int, depth: Int, zeroLat: Boolean,
                 drainTimeout: Int, armAfter: Int, fixedData: Boolean, aNeverReady: Boolean,
                 separateRounds: Boolean)(implicit p: Parameters) extends LazyModule {
  val ramBase = 0x0L; val ramSize = 0x400L
  val illegalAddr = 0x40000L              // mapped by nobody: the bridge must reject it locally

  val mgr    = LazyModule(new RD1Manager(AddressSet(ramBase, ramSize - 1), latency, aStall, neverAfter, errorMask, depth, zeroLat, aNeverReady))
  // one bridge, two behaviours: the drain contract, or a model of today's behaviour (legacyDrain)
  val bridge = LazyModule(new RD1Bridge(0, false, applyCycles, drainTimeout, legacyDrain = !useDrainBridge))
  val xbar   = LazyModule(new TLXbar)
  val tap    = TLIdentityNode()          // the tapped bundles belong to *this* module, so reading them is legal
  mgr.node := xbar.node
  xbar.node := tap := bridge.node

  lazy val module = new LazyModuleImp(this) with UnitTestModule {
    val cyc = RegInit(0.U(32.W)); cyc := cyc + 1.U

    val phys = Wire(new PhysPortIO)
    val softReset = WireInit(false.B)
    bridge.module.io.phys <> phys
    bridge.module.io.drain.softReset := softReset
    val cpuResetHold = bridge.module.io.drain.cpuResetHold
    val epoch = bridge.module.io.drain.epoch
    val (tlb, _) = tap.in(0)

    // ---- CPU endpoint ---------------------------------------------------------------------------------
    val txid   = RegInit(0.U(32.W))
    val issued = RegInit(0.U(16.W))
    val series = RegInit(0.U(8.W))                 // 0 = before the reset, 1 = after it
    val inFlight = RegInit(false.B)
    val holdD  = RegNext(cpuResetHold, false.B)
    val releasing = !cpuResetHold && holdD
    when (cpuResetHold && !holdD) { printf(p"RD1 ${cyc} HOLD_ASSERT epoch=${epoch}\n") }
    when (releasing) { printf(p"RD1 ${cyc} HOLD_RELEASE epoch=${epoch}\n") }

    val nThis = Mux(series === 0.U, nPre.U, nPost.U)
    val wantIllegal = (trig == RD1Trig.illegal).B && (issued === (nPre - 1).U) && (series === 0.U)
    val addr = Mux(wantIllegal, illegalAddr.U,
                   if (fixedData) (ramBase.U + 0x40.U) else (ramBase.U + Cat(issued(5, 0), 0.U(3.W))))
    val wdata = if (fixedData) "hFEEDFACE00000001".U(64.W)
                else Cat("hC".U(4.W), series(3, 0), issued(7, 0), cyc(15, 0), "hBEEF".U(16.W), 0.U(16.W))(63, 0)

    val holdDelayed = RegNext(cpuResetHold, false.B)   // a real CPU also takes a cycle to stop
    phys.req.valid      := !holdDelayed && (issued < nThis) && !inFlight
    phys.req.bits.addr  := addr
    phys.req.bits.write := writes.B && issued(0)
    phys.req.bits.size  := 3.U
    phys.req.bits.wdata := wdata
    phys.req.bits.wmask := Mux(writes.B && issued(0), "hff".U, 0.U)

    val bpCount = RegInit(0.U(8.W))
    val bpReady = (respBp == 0).B || (bpCount >= respBp.U)
    phys.resp.ready := bpReady && !cpuResetHold
    when (phys.resp.valid && !phys.resp.ready) { bpCount := bpCount + 1.U }
    when (phys.resp.fire()) { bpCount := 0.U }

    when (phys.req.fire()) {
      txid := txid + 1.U; issued := issued + 1.U; inFlight := true.B
      printf(p"RD1 ${cyc} REQ_ACCEPT epoch=${epoch} txid=${txid + 1.U} addr=0x${Hexadecimal(phys.req.bits.addr)} " +
             p"write=${phys.req.bits.write} data=0x${Hexadecimal(phys.req.bits.wdata)}\n")
    }
    // the release wins over the issue in the same cycle: a request accepted exactly at the drain boundary is
    // the first of the new series, not the last of the old one
    when (releasing) {
      series   := series + 1.U
      issued   := Mux(phys.req.fire(), 1.U, 0.U)
      inFlight := phys.req.fire()
    }
    when (phys.resp.fire()) {
      inFlight := false.B
      printf(p"RD1 ${cyc} CPU_DELIVER epoch=${epoch} txid=${txid} data=0x${Hexadecimal(phys.resp.bits.rdata)} err=${phys.resp.bits.error}\n")
    }

    // ---- bridge-side events ---------------------------------------------------------------------------
    locally {
      val d = bridge.module.io.drain
      val nDr = RegNext(d.nDrained, 0.U); val nLo = RegNext(d.nLocalDisc, 0.U); val nBu = RegNext(d.nBufDisc, 0.U)
      when (d.nDrained =/= nDr)   { printf(p"RD1 ${cyc} DRAIN_DISCARD epoch=${epoch} txid=${txid} n=${d.nDrained}\n") }
      when (d.nLocalDisc =/= nLo) { printf(p"RD1 ${cyc} LOCAL_DISCARD epoch=${epoch} txid=${txid} n=${d.nLocalDisc}\n") }
      when (d.nBufDisc =/= nBu)   { printf(p"RD1 ${cyc} BUFFERED_DISCARD epoch=${epoch} txid=${txid} n=${d.nBufDisc}\n") }
      when (d.drainDone)          { printf(p"RD1 ${cyc} DRAIN_DONE epoch=${epoch} pendingA=${d.pendingANext} outstanding=${d.outstandingNext} regPendingA=${d.pendingA} regOutstanding=${d.outstanding}\n") }
      val applyD = RegNext(d.applying, false.B)
      when (d.applying && !applyD) { printf(p"RD1 ${cyc} RESET_APPLY epoch=${epoch}\n") }
      val epD = RegNext(d.epoch, 0.U)
      when (d.epoch =/= epD)      { printf(p"RD1 ${cyc} EPOCH new=${d.epoch}\n") }
      when (d.timeout && !RegNext(d.timeout, false.B)) { printf(p"RD1 ${cyc} TIMEOUT epoch=${epoch}\n") }
    }

    // ---- injector -------------------------------------------------------------------------------------
    val aValid = tlb.a.valid; val aReady = tlb.a.ready; val dValid = tlb.d.valid; val dReady = tlb.d.ready
    val pendA = aValid && !aReady
    val outst = RegInit(false.B)
    when (aValid && aReady) { outst := true.B }
    when (dValid && dReady) { outst := false.B }
    val illegalPending = RegNext(phys.req.fire() && (phys.req.bits.addr === illegalAddr.U), false.B)
    val respBuffered = bridge.module.io.drain.respBuffered   // independent of softReset: no loop

    val cond = MuxLookup(trig.U, false.B, Seq(
      RD1Trig.idle.U            -> (!aValid && !outst && !phys.req.valid && !respBuffered &&
                                    !inFlight && (issued > 0.U)),
      RD1Trig.reqOffer.U        -> (phys.req.valid && !holdDelayed && (issued === (nPre - 1).U)),
      RD1Trig.afterReqBeforeA.U -> pendA,
      RD1Trig.aFire.U           -> (aValid && aReady),
      RD1Trig.dFire.U           -> (dValid && dReady && outst),
      RD1Trig.adSame.U          -> (aValid && aReady && dValid),
      RD1Trig.waitingD.U        -> (outst && !dValid),
      RD1Trig.respBp.U          -> (respBuffered && !bpReady),
      RD1Trig.illegal.U         -> illegalPending,   // registered: the cycle after acceptance, still sIllegal
      RD1Trig.respReady.U       -> (respBuffered && bpReady),
      RD1Trig.none.U            -> false.B))

    val fired   = RegInit(0.U(8.W))
    val pulseCt = RegInit(0.U(16.W))
    val arming  = RegInit(true.B)
    val warm    = RegInit(0.U(16.W)); warm := warm + 1.U
    // armAfter counts *episodes* of the condition, so a scenario can aim at the second or third occurrence
    // (the transaction the manager will never answer, say) rather than always the first.
    val seen = RegInit(0.U(16.W))
    val condEdge = cond && !RegNext(cond, false.B)
    when (condEdge) { seen := seen + 1.U }
    val firstFire = fired === 0.U
    val hitNow = arming && (warm > 3.U) && (fired < pulses.U) &&
                 Mux(firstFire, condEdge && (seen >= armAfter.U), cond)
    when (hitNow) {
      printf(p"RD1 ${cyc} HIT trig=${trig.U} fired=${fired + 1.U} pendA=${pendA} outst=${outst} " +
             p"aValid=${aValid} aReady=${aReady} dValid=${dValid} dReady=${dReady} reqValid=${phys.req.valid} " +
             p"respValid=${phys.resp.valid} illegal=${illegalPending}\n")
      fired := fired + 1.U; pulseCt := (resetLen - 1).U; arming := false.B
    }
    when (!hitNow && pulseCt > 0.U) { pulseCt := pulseCt - 1.U }
    // asserted in the very cycle the condition holds, so a "same cycle" scenario really is same-cycle
    softReset := hitNow || (pulseCt > 0.U)
    when (softReset && !RegNext(softReset, false.B)) { printf(p"RD1 ${cyc} RESET_ASSERT epoch=${epoch}\n") }
    // a second pulse, deliberately during the drain, when more than one was asked for
    // two different shapes of "more than one reset": another pulse *inside* the drain that is already
    // running, or a fresh round once the CPU has been let go and is working again. separateRounds picks the
    // second, so each pulse gets its own drain, its own apply and its own release.
    val rearmWhen = if (separateRounds) (!cpuResetHold && !holdDelayed && inFlight) else cpuResetHold
    when (!arming && (fired < pulses.U) && (pulseCt === 0.U) && rearmWhen) { arming := true.B }

    // ---- finish ----------------------------------------------------------------------------------------
    // completion protocol: with no reset the run ends when the single series is delivered; with a reset it
    // ends when the post-reset series is delivered. The guard is a failure indicator, never a pass.
    val nSeries = if (separateRounds) pulses else 1   // one completed reset series per round
    val done = Mux((pulses == 0).B, (issued >= nPre.U) && !inFlight,
                                    (series >= nSeries.U) && (issued >= nPost.U) && !inFlight)
    val guard = RegInit(0.U(32.W)); guard := guard + 1.U
    val finish = done || (guard > 40000.U)
    val fin = RegInit(false.B)
    when (finish && !fin) {
      fin := true.B
      val d = bridge.module.io.drain
      printf(p"RD1 ${cyc} FINISH done=${done} series=${series} issued=${issued} epoch=${epoch} " +
             p"txid=${txid} hits=${fired} hold=${cpuResetHold} pendingA=${d.pendingA} " +
             p"outstanding=${d.outstanding} resetPending=${d.resetPending} timeout=${d.timeout} " +
             p"nDrained=${d.nDrained} nLocal=${d.nLocalDisc} nBuf=${d.nBufDisc}\n")
    }
    io.finished := fin
  }
}

class RD1Test(trig: Int, resetLen: Int = 3, pulses: Int = 1, latency: Int = 4, aStall: Int = 0,
              neverAfter: Int = 0, respBp: Int = 0, useDrainBridge: Boolean = true, nPre: Int = 4,
              nPost: Int = 4, writes: Boolean = true, errorMask: BigInt = 0, applyCycles: Int = 2,
              depth: Int = 1, zeroLat: Boolean = false, drainTimeout: Int = 50000, armAfter: Int = 0,
              fixedData: Boolean = false, aNeverReady: Boolean = false, separateRounds: Boolean = false,
              timeout: Int = 200000)(implicit p: Parameters) extends UnitTest(timeout) {
  val dut = Module(LazyModule(new RD1Harness(trig, resetLen, pulses, latency, aStall, neverAfter, respBp,
                                             useDrainBridge, nPre, nPost, writes, errorMask, applyCycles, depth, zeroLat, drainTimeout, armAfter, fixedData, aNeverReady, separateRounds)).module)
  dut.io.start := io.start
  io.finished := dut.io.finished
}

class WithRD1(trig: Int, resetLen: Int = 3, pulses: Int = 1, latency: Int = 4, aStall: Int = 0,
              neverAfter: Int = 0, respBp: Int = 0, useDrainBridge: Boolean = true, nPre: Int = 4,
              nPost: Int = 4, writes: Boolean = true, errorMask: BigInt = 0, applyCycles: Int = 2,
              depth: Int = 1, zeroLat: Boolean = false, drainTimeout: Int = 50000, armAfter: Int = 0,
              fixedData: Boolean = false, aNeverReady: Boolean = false, separateRounds: Boolean = false,
              timeout: Int = 200000)
  extends Config((site, here, up) => {
    case UnitTests => (q: Parameters) => {
      implicit val p = q
      Seq(Module(new RD1Test(trig, resetLen, pulses, latency, aStall, neverAfter, respBp, useDrainBridge,
                             nPre, nPost, writes, errorMask, applyCycles, depth, zeroLat, drainTimeout, armAfter, fixedData, aNeverReady, separateRounds, timeout)))
    }
  })

// --- scenarios, new bridge -----------------------------------------------------------------------------
class RD1IdleConfig        extends Config(new WithRD1(RD1Trig.idle) ++ new Base)
class RD1ReqOfferConfig    extends Config(new WithRD1(RD1Trig.reqOffer) ++ new Base)
class RD1BeforeAConfig     extends Config(new WithRD1(RD1Trig.afterReqBeforeA, aStall = 6) ++ new Base)
class RD1AStallConfig      extends Config(new WithRD1(RD1Trig.afterReqBeforeA, aStall = 40, resetLen = 2) ++ new Base)
class RD1AFireConfig       extends Config(new WithRD1(RD1Trig.aFire, resetLen = 1) ++ new Base)
class RD1DFireConfig       extends Config(new WithRD1(RD1Trig.dFire, resetLen = 1) ++ new Base)
class RD1ADSameConfig      extends Config(new WithRD1(RD1Trig.adSame, latency = 0, resetLen = 1, zeroLat = true) ++ new Base)
class RD1WaitingDConfig    extends Config(new WithRD1(RD1Trig.waitingD, latency = 30) ++ new Base)
class RD1RespBpConfig      extends Config(new WithRD1(RD1Trig.respBp, respBp = 6) ++ new Base)
class RD1IllegalConfig     extends Config(new WithRD1(RD1Trig.illegal) ++ new Base)
class RD1SinglePulseConfig extends Config(new WithRD1(RD1Trig.waitingD, latency = 30, resetLen = 1) ++ new Base)
class RD1MultiPulseConfig  extends Config(new WithRD1(RD1Trig.waitingD, latency = 30, resetLen = 2, pulses = 4) ++ new Base)
class RD1ReadOnlyConfig    extends Config(new WithRD1(RD1Trig.waitingD, latency = 8, writes = false) ++ new Base)
class RD1DErrorConfig      extends Config(new WithRD1(RD1Trig.waitingD, latency = 8, errorMask = 0x200) ++ new Base)
class RD1LongRespConfig    extends Config(new WithRD1(RD1Trig.waitingD, latency = 400) ++ new Base)
class RD1NeverRespConfig   extends Config(new WithRD1(RD1Trig.waitingD, latency = 4, neverAfter = 1, drainTimeout = 3000, armAfter = 1, timeout = 120000) ++ new Base)
class RD1NoResetConfig     extends Config(new WithRD1(RD1Trig.none, pulses = 0, nPre = 8, nPost = 0) ++ new Base)
class RD1ZeroLatConfig     extends Config(new WithRD1(RD1Trig.aFire, latency = 0, resetLen = 1, zeroLat = true) ++ new Base)

// the pipelined-manager scenario: a new A can be accepted while an older D is still in flight, which is the
// only arrangement in which "an old D is mis-paired with a new request" can happen at all
class RD1MispairConfig     extends Config(new WithRD1(RD1Trig.waitingD, latency = 25, resetLen = 1, depth = 2) ++ new Base)
// the same-cycle boundary: a response is buffered and the CPU is ready, and the reset lands in that cycle
class RD1RespSameCycConfig extends Config(new WithRD1(RD1Trig.respReady, latency = 3, resetLen = 1) ++ new Base)
// the manager never grants a.ready again: pendingA forever, so the hold must be forever too
// the manager grants a.ready once and never again, so the *second* request is the one stuck offering A.
// That is the first pendA episode of the run (the first request was granted immediately), hence armAfter 0.
class RD1ANeverReadyConfig extends Config(new WithRD1(RD1Trig.afterReqBeforeA, aNeverReady = true, drainTimeout = 3000, armAfter = 0, timeout = 120000) ++ new Base)
// two legal writes with the same address and the same data: a checker keyed on (addr,data) would reject them
class RD1FixedDataConfig   extends Config(new WithRD1(RD1Trig.waitingD, latency = 6, fixedData = true) ++ new Base)
// four separate reset rounds, each with its own drain / apply / release
class RD1MultiRoundConfig  extends Config(new WithRD1(RD1Trig.waitingD, latency = 12, pulses = 4, resetLen = 2,
                                                      nPre = 3, nPost = 3, separateRounds = true, timeout = 400000) ++ new Base)

// --- the same scenarios against a model of today's behaviour, as the honest comparison -----------------
class RD1OldIdleConfig     extends Config(new WithRD1(RD1Trig.idle, useDrainBridge = false) ++ new Base)
class RD1OldBeforeAConfig  extends Config(new WithRD1(RD1Trig.afterReqBeforeA, aStall = 6, useDrainBridge = false) ++ new Base)
class RD1OldAStallConfig   extends Config(new WithRD1(RD1Trig.afterReqBeforeA, aStall = 40, resetLen = 2, useDrainBridge = false) ++ new Base)
class RD1OldAFireConfig    extends Config(new WithRD1(RD1Trig.aFire, resetLen = 1, useDrainBridge = false) ++ new Base)
class RD1OldDFireConfig    extends Config(new WithRD1(RD1Trig.dFire, resetLen = 1, useDrainBridge = false) ++ new Base)
class RD1OldWaitingDConfig extends Config(new WithRD1(RD1Trig.waitingD, latency = 30, useDrainBridge = false) ++ new Base)
class RD1OldRespBpConfig   extends Config(new WithRD1(RD1Trig.respBp, respBp = 6, useDrainBridge = false) ++ new Base)
class RD1OldSinglePulseConfig extends Config(new WithRD1(RD1Trig.waitingD, latency = 30, resetLen = 1, useDrainBridge = false) ++ new Base)
class RD1OldMispairConfig  extends Config(new WithRD1(RD1Trig.waitingD, latency = 25, resetLen = 1, depth = 2, useDrainBridge = false) ++ new Base)
