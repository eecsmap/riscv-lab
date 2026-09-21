// M1: physical memory port per experiments/teaching-cpu/PHYSICAL_PORT_V1.md (frozen 2026-09-14).
package teaching

import chisel3._
import chisel3.util._

class PhysReq extends Bundle {
  val addr  = UInt(32.W)   // byte physical address, naturally aligned to 1<<size, never crossing the 8-byte beat
  val write = Bool()
  val size  = UInt(2.W)    // log2(bytes): 0/1/2/3 -> 1/2/4/8; used directly as the TileLink lgSize
  val wdata = UInt(64.W)   // byte lanes selected by addr(2,0); 0 for reads
  val wmask = UInt(8.W)    // non-zero subset of ((1 << (1 << size)) - 1) << addr(2,0) for writes; 0 for reads
}

class PhysResp extends Bundle {
  val rdata = UInt(64.W)   // same byte lanes as the request; 0 for writes and for error responses
  val error = Bool()       // illegal request (rejected locally, no TL transaction) or TLBundleD.error from downstream
}

// Master side: the CPU / tester drives req, consumes resp. One outstanding transaction.
class PhysPortIO extends Bundle {
  val req  = Decoupled(new PhysReq)
  val resp = Flipped(Decoupled(new PhysResp))
}

object PhysPort {
  // allowed byte-lane mask for (size, addr(2,0))
  def laneMask(size: UInt, addrLo: UInt): UInt = {
    val base = MuxLookup(size, 0xff.U(8.W), Seq(0.U -> 0x01.U(8.W), 1.U -> 0x03.U(8.W), 2.U -> 0x0f.U(8.W), 3.U -> 0xff.U(8.W)))
    (base << addrLo)(7, 0)
  }
  def aligned(size: UInt, addrLo: UInt): Bool =
    MuxLookup(size, false.B, Seq(0.U -> true.B, 1.U -> (addrLo(0) === 0.U), 2.U -> (addrLo(1, 0) === 0.U), 3.U -> (addrLo === 0.U)))
}
