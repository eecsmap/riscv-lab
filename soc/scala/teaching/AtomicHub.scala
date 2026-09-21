// CPU-A stage 1 (R2): the real insertion point. The subsystem's coherence manager is the hook between the
// system bus and the memory bus: the default builds TLBroadcast -> TLWidthWidget. This configuration builds
// AtomicBackend -> TLBroadcast -> TLWidthWidget instead, so the backend sees the system bus's clients by
// name (the broadcast hub folds every client into one named "TLBroadcast" downstream of it) and every
// transaction bound for DRAM from every PL master passes through it before the hub. Isolated: only
// configurations that mix this in get the backend; the default board/RD2 configurations are unchanged.
package teaching

import chisel3._
import freechips.rocketchip.config._
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.subsystem._
import freechips.rocketchip.tilelink._

object AtomicHub {
  // the backend built inside the coherence-manager closure, so the SoC top can wire its side-band
  var last: Option[AtomicBackend] = None
}

class WithAtomicHub(fReadErr: Boolean = false, fNoKill: Boolean = false, fWrongSrc: Boolean = false,
                    trace: Boolean = true) extends Config((site, here, up) => {
  case BankedL2Key => up(BankedL2Key, site).copy(coherenceManager = { subsystem =>
    implicit val p = subsystem.p
    val BroadcastParams(nTrackers, bufferless) = p(BroadcastKey)
    val backend = LazyModule(new AtomicBackend(fReadErr, fNoKill, fWrongSrc,
                                               dramRegion = Seq(AddressSet(p(ExtMem).base, p(ExtMem).size - 1)),
                                               trace = trace))
    val bh = LazyModule(new TLBroadcast(subsystem.memBusBlockBytes, nTrackers, bufferless))
    val ww = LazyModule(new TLWidthWidget(subsystem.sbus.beatBytes))
    bh.node :*= backend.node
    ww.node :*= bh.node
    AtomicHub.last = Some(backend)
    (backend.node, ww.node, () => None)
  })
})
