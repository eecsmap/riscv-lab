// MC-M1: the replaceable hart wrapper.
//
// What RD2ZynqTop used to instantiate piecemeal on the atomic path -- the V2 CPU wrapper, the V2 bridge, the
// CPU-side watcher and the test-only throttle -- now lives here, behind one boundary. Outside it the SoC sees
// exactly the external contract CONTRACT.md C1-C2 names: ONE TileLink client node (the bridge's, still named
// "teaching-phys", still IdRange(0, 1)), the bridge's drain and debug bundles unchanged, the atomic side-band
// to the backend, the three interrupt levels, and the stable observation bundle. The multicycle core's FSM
// state and redirect flag come out only as `impl`, which nothing outside the wrapper may read
// (TESTPLAN T1.3).
//
// Deliberately NOT changed this round, by the MC-M1 terms: the client name, the single side-band, the bridge,
// the watcher and throttle, the response latency, the TLB and I-cache sizes. This is a boundary, not a
// behaviour change, and T1.7 checks that by comparing retirement, traps and memory effects against the SoC
// as it was before the wrapper existed.
package teaching

import chisel3._
import chisel3.experimental.withReset
import freechips.rocketchip.config.Parameters
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.tilelink._

class TeachingHartIrq extends Bundle { val msip = Bool(); val mtip = Bool(); val meip = Bool() }

// MC-M2b: the ONE place a hart's TileLink client name comes from. The hart wrapper names its bridge's client
// with it, and the backend (WithAtomicHub) binds its side-band slots with the same function over the same
// NUM_CORES -- so hart -> source range -> side-band slot is one explicit binding by exact name (CONTRACT
// C3.1, ruling D4), never a sort over sources and never a prefix match.
object TeachingHart {
  def clientName(hartId: Int): String = s"teaching-phys-$hartId"
  def clientNames(numCores: Int): Seq[String] = Seq.tabulate(numCores)(clientName)
}

class TeachingHart(val hartId: Int, resetPc: BigInt,
                   bridgeFault: Int, applyCycles: Int, drainTimeout: Int,
                   atomicRegion: Seq[AddressSet], atomicTrace: Boolean, busInstrumentation: Boolean)
                  (implicit p: Parameters) extends LazyModule {
  // MC-M2b: any non-negative hart id. Its identity -- the exact client name, the side-band slot the backend
  // binds by that name, its own reservation, its HART_ID parameter -- all come from this one number.
  require(hartId >= 0, s"unsupported hart $hartId: hart ids are 0..NUM_CORES-1")

  val bridge   = LazyModule(new RD2BridgeV2(bridgeFault, applyCycles, drainTimeout, atomicRegion, atomicTrace,
                                            clientName = TeachingHart.clientName(hartId), hartId = hartId))
  // the watcher is an identity node; the throttle does nothing unless its plusargs are set, and is left out
  // of the netlist entirely when the instrumentation is off (see RD2Soc for why)
  val watch    = LazyModule(new RD2Watch(s"cpu$hartId", trace = busInstrumentation))
  val throttle = if (busInstrumentation) Some(LazyModule(new RD2Throttle)) else None
  // the same chain RD2ZynqTop built before: watch := [throttle :=] bridge
  if (busInstrumentation) watch.node := throttle.get.node := bridge.node
  else                    watch.node := bridge.node
  val node = watch.node

  lazy val module = new LazyModuleImp(this) {
    val io = IO(new Bundle {
      val irq     = Input(new TeachingHartIrq)
      val drain   = new BridgeDrainIO          // softReset in, the phases out: the bridge's, passed through
      val dbg     = new BridgeDebug
      val sb      = new AtomicSideband         // to the backend at the coherence-manager hook
      val obs     = Output(new TeachingCpuObs)
      val physObs = Output(new PhysObs)
      val impl    = Output(new TeachingCpuImplObs)   // implementation detail; see TeachingCpuImplObs
      // MC-M2b: the longest run of cycles this hart's A stayed offered before the fabric took it (1 = taken
      // in the cycle it was offered). Fairness evidence per hart, read at the end of a long run.
      val maxAWait = Output(UInt(32.W))
    })
    val b = bridge.module
    val waitRun = RegInit(0.U(32.W)); val maxAWait = RegInit(0.U(32.W))
    when (b.io.drain.pendingA) { waitRun := waitRun + 1.U; when (waitRun + 1.U > maxAWait) { maxAWait := waitRun + 1.U } }
    .otherwise { waitRun := 0.U }
    io.maxAWait := maxAWait
    b.io.drain <> io.drain
    io.dbg     <> b.io.dbg
    io.sb      <> b.io.sb

    // The CPU is the soft domain: its reset is this module's reset OR the bridge's hold, exactly as the SoC
    // composed it before. withReset works here because TeachingCpuV2 is a plain Chisel Module instantiated
    // by this code, not a diplomatic child.
    val cpu = withReset(reset.toBool || b.io.drain.cpuResetHold) { Module(new TeachingCpuV2(resetPc, hartId)) }
    b.io.phys <> cpu.io.phys
    cpu.io.irq.msip := io.irq.msip
    cpu.io.irq.mtip := io.irq.mtip
    cpu.io.irq.meip := io.irq.meip
    io.obs     := cpu.io.obs
    io.physObs := cpu.io.physObs
    io.impl    := cpu.io.impl
  }
}
