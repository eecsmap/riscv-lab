// CPU-A stage 1: PHYSICAL_PORT_V2 = V1 plus an AMO field, an LR/SC mark, an SC result and the reservation-clear
// pulse. A V1 request is a V2 request with amo = 0 and lrsc = 0. The V1 bundles and bridge are untouched.
// Contract: experiments/teaching-cpu/cpu-atomic-prep/CONTRACT.md as ruled in CODEX_DECISIONS.md.
package teaching

import chisel3._
import chisel3.util._

object AmoOp {
  val NONE = 0; val SWAP = 1; val ADD = 2; val XOR = 3; val AND = 4; val OR = 5
  val MIN = 6; val MAX = 7; val MINU = 8; val MAXU = 9
}
object LrSc { val NONE = 0; val LR = 1; val SC = 2 }

class PhysReqV2 extends Bundle {
  val addr  = UInt(32.W)
  val write = Bool()          // 1 for stores, AMOs and SC; 0 for loads and LR
  val size  = UInt(2.W)       // AMO / LR / SC: 2 (w) or 3 (d) only
  val wdata = UInt(64.W)      // store data, or the AMO operand, on the address's byte lanes
  val wmask = UInt(8.W)       // exactly the lanes for an AMO / SC
  val amo   = UInt(4.W)       // AmoOp, 0 = not an AMO
  val lrsc  = UInt(2.W)       // LrSc, 0 = ordinary
}
class PhysRespV2 extends Bundle {
  val rdata  = UInt(64.W)     // load data, or the AMO / LR old value, on the request's lanes
  val error  = Bool()
  val scFail = Bool()         // meaningful for an SC only: 1 = the store was not performed
}
class PhysPortV2IO extends Bundle {
  val req  = Decoupled(new PhysReqV2)
  val resp = Flipped(Decoupled(new PhysRespV2))
  val resvClear = Output(Bool())   // pulse from the core: a trap or a core reset clears the reservation
}

// The bridge <-> backend side-band. Transaction-bound: `mark` is pushed in the cycle the bridge *accepts the
// CPU's request* for an LR or SC (one outstanding: the next A the bridge offers is that transaction) and is
// consumed by the backend when it accepts that A; `scResult` is raised in the cycle the backend hands the SC's
// D to the inner side, and the bridge holds it until its own D arrives (they may be buffered apart).
class AtomicMark extends Bundle { val lr = Bool(); val sc = Bool() }
class AtomicSideband extends Bundle {
  val mark      = Valid(new AtomicMark)
  val resvClear = Output(Bool())
  val scResult  = Flipped(Valid(Bool()))   // bits = fail
}
