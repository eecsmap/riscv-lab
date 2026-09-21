// M3: a thin BlackBox around the teaching CPU's Verilog. It adds no logic of its own -- the point is that
// the core that was accepted in M2-3 is the core that runs here, unmodified, with its PHYSICAL_PORT_V1
// signals adapted to the bridge's bundle and nothing else.
package teaching

import chisel3._
import chisel3.experimental.IntParam
import chisel3.util._

class TcpuCoreBlackBox(resetPc: BigInt, misaA: Int = 0) extends BlackBox(Map(
      // the integration uses the SoC's own reset vector; the standalone harness keeps its own default
      "RESET_PC" -> IntParam(resetPc),
      // CPU-A: 1 only in a configuration that has the atomic path. With 0 the A instructions are illegal
      // and misa.A reads 0, so a configuration never claims support it does not have.
      "MISA_A" -> IntParam(misaA))) {
  val io = IO(new Bundle {
    val clk = Input(Clock())
    val rst = Input(Bool())
    // PHYSICAL_PORT_V1
    val req_valid  = Output(Bool())
    val req_ready  = Input(Bool())
    val req_addr   = Output(UInt(32.W))
    val req_write  = Output(Bool())
    val req_size   = Output(UInt(2.W))
    val req_wdata  = Output(UInt(64.W))
    val req_wmask  = Output(UInt(8.W))
    // CPU-A (PHYSICAL_PORT_V2): the atomic/reservation pins. A V1 wrapper ties resp_scfail low and leaves
    // req_amo / req_lrsc / resv_clear unread -- the core drives amo = 0 and lrsc = 0 for every request a
    // V1 configuration can make, so its behaviour is the behaviour that was accepted.
    val req_amo    = Output(UInt(4.W))
    val req_lrsc   = Output(UInt(2.W))
    val resp_scfail = Input(Bool())
    val resv_clear = Output(Bool())
    val resp_valid = Input(Bool())
    val resp_ready = Output(Bool())
    val resp_rdata = Input(UInt(64.W))
    val resp_error = Input(Bool())
    // observation, not part of the contract
    val commit_valid    = Output(Bool())
    val commit_pc       = Output(UInt(64.W))
    val commit_insn     = Output(UInt(32.W))
    val commit_rd_valid = Output(Bool())
    val commit_rd       = Output(UInt(5.W))
    val commit_rd_data  = Output(UInt(64.W))
    val trap_valid      = Output(Bool())
    val trap_interrupt  = Output(Bool())
    val trap_cause      = Output(UInt(64.W))
    val trap_epc        = Output(UInt(64.W))
    val trap_tval       = Output(UInt(64.W))
    val halted          = Output(Bool())
    val dbg_req_is_fetch = Output(Bool())
    val dbg_ra   = Input(UInt(5.W))
    val dbg_rd   = Output(UInt(64.W))
    val dbg_ra2  = Input(UInt(5.W))
    val dbg_rd2  = Output(UInt(64.W))
    val dbg_csr_sel = Input(UInt(4.W))
    val dbg_csr_val = Output(UInt(64.W))
    // interrupt levels, in this clock domain
    val irq_msip = Input(Bool())
    val irq_mtip = Input(Bool())
    val irq_meip = Input(Bool())
    val dbg_state    = Output(UInt(4.W))
    val dbg_redirect = Output(Bool())
    val dbg_pc       = Output(UInt(64.W))
    val dbg_irq_enabled = Output(Bool())
  })
  // The Verilog itself is passed to the simulator build from teaching-cpu-work/cpu/rtl, which keeps one
  // copy of the accepted core and one hash for it.
  override def desiredName = "tcpu_core"
}

// The wrapper: BlackBox + the PhysPortIO the bridge expects. The CPU is always ready for a response, which
// is what "single outstanding" means on this port, so the handshake reduces to a valid.
class TeachingCpu(resetPc: BigInt) extends Module {
  val io = IO(new Bundle {
    val phys = new PhysPortIO
    val irq  = Input(new Bundle { val msip = Bool(); val mtip = Bool(); val meip = Bool() })
    val obs  = Output(new TeachingCpuObs)
    val physObs = Output(new PhysObs)     // the fields an observer needs, the same shape on V1 and V2
  })
  val core = Module(new TcpuCoreBlackBox(resetPc))
  core.io.clk := clock
  core.io.rst := reset.toBool

  io.phys.req.valid      := core.io.req_valid
  io.phys.req.bits.addr  := core.io.req_addr
  io.phys.req.bits.write := core.io.req_write
  io.phys.req.bits.size  := core.io.req_size
  io.phys.req.bits.wdata := core.io.req_wdata
  io.phys.req.bits.wmask := core.io.req_wmask
  core.io.req_ready      := io.phys.req.ready

  core.io.resp_valid     := io.phys.resp.valid
  core.io.resp_rdata     := io.phys.resp.bits.rdata
  core.io.resp_error     := io.phys.resp.bits.error
  core.io.resp_scfail    := false.B                 // no atomic can reach a V1 port
  io.phys.resp.ready     := core.io.resp_ready
  io.physObs.reqFire  := io.phys.req.fire()
  io.physObs.reqValid := io.phys.req.valid
  io.physObs.respFire := io.phys.resp.fire()
  io.physObs.addr     := io.phys.req.bits.addr
  io.physObs.write    := io.phys.req.bits.write
  io.physObs.size     := io.phys.req.bits.size
  io.physObs.wdata    := io.phys.req.bits.wdata
  io.physObs.wmask    := io.phys.req.bits.wmask
  io.physObs.rdata    := io.phys.resp.bits.rdata
  io.physObs.error    := io.phys.resp.bits.error

  core.io.irq_msip := io.irq.msip
  core.io.irq_mtip := io.irq.mtip
  core.io.irq_meip := io.irq.meip
  core.io.dbg_ra := 0.U; core.io.dbg_ra2 := 0.U; core.io.dbg_csr_sel := 0.U

  io.obs.commitValid := core.io.commit_valid
  io.obs.commitPc    := core.io.commit_pc
  io.obs.commitInsn  := core.io.commit_insn
  io.obs.trapValid   := core.io.trap_valid
  io.obs.trapInterrupt := core.io.trap_interrupt
  io.obs.trapCause   := core.io.trap_cause
  io.obs.trapEpc     := core.io.trap_epc
  io.obs.trapTval    := core.io.trap_tval
  io.obs.state       := core.io.dbg_state
  io.obs.pc          := core.io.dbg_pc
  io.obs.irqEnabled  := core.io.dbg_irq_enabled
  io.obs.isFetch     := core.io.dbg_req_is_fetch
  io.obs.halted      := core.io.halted
}

// The parts of the physical port an observer (the R-BOOT event trace, the status word) reads. Both
// wrappers publish it, so the SoC's observation code is the same whichever port the CPU has.
class PhysObs extends Bundle {
  val reqFire  = Bool()
  val reqValid = Bool()
  val respFire = Bool()
  val addr     = UInt(32.W)
  val write    = Bool()
  val size     = UInt(2.W)
  val wdata    = UInt(64.W)
  val wmask    = UInt(8.W)
  val rdata    = UInt(64.W)
  val error    = Bool()
}

// CPU-A: the same BlackBox with its V2 port exposed. No logic of its own either -- the core that passed
// the core-level gates is the core that runs here.
class TeachingCpuV2(resetPc: BigInt) extends Module {
  val io = IO(new Bundle {
    val phys = new PhysPortV2IO
    val irq  = Input(new Bundle { val msip = Bool(); val mtip = Bool(); val meip = Bool() })
    val obs  = Output(new TeachingCpuObs)
    val physObs = Output(new PhysObs)
  })
  val core = Module(new TcpuCoreBlackBox(resetPc, misaA = 1))   // this configuration has the atomic path
  core.io.clk := clock
  core.io.rst := reset.toBool

  io.phys.req.valid      := core.io.req_valid
  io.phys.req.bits.addr  := core.io.req_addr
  io.phys.req.bits.write := core.io.req_write
  io.phys.req.bits.size  := core.io.req_size
  io.phys.req.bits.wdata := core.io.req_wdata
  io.phys.req.bits.wmask := core.io.req_wmask
  io.phys.req.bits.amo   := core.io.req_amo
  io.phys.req.bits.lrsc  := core.io.req_lrsc
  core.io.req_ready      := io.phys.req.ready

  core.io.resp_valid     := io.phys.resp.valid
  core.io.resp_rdata     := io.phys.resp.bits.rdata
  core.io.resp_error     := io.phys.resp.bits.error
  core.io.resp_scfail    := io.phys.resp.bits.scFail
  io.phys.resp.ready     := core.io.resp_ready
  io.phys.resvClear      := core.io.resv_clear

  core.io.irq_msip := io.irq.msip
  core.io.irq_mtip := io.irq.mtip
  core.io.irq_meip := io.irq.meip
  core.io.dbg_ra := 0.U; core.io.dbg_ra2 := 0.U; core.io.dbg_csr_sel := 0.U

  io.obs.commitValid := core.io.commit_valid
  io.obs.commitPc    := core.io.commit_pc
  io.obs.commitInsn  := core.io.commit_insn
  io.obs.trapValid   := core.io.trap_valid
  io.obs.trapInterrupt := core.io.trap_interrupt
  io.obs.trapCause   := core.io.trap_cause
  io.obs.trapEpc     := core.io.trap_epc
  io.obs.trapTval    := core.io.trap_tval
  io.obs.state       := core.io.dbg_state
  io.obs.pc          := core.io.dbg_pc
  io.obs.irqEnabled  := core.io.dbg_irq_enabled
  io.obs.isFetch     := core.io.dbg_req_is_fetch
  io.obs.halted      := core.io.halted

  io.physObs.reqFire  := io.phys.req.fire()
  io.physObs.reqValid := io.phys.req.valid
  io.physObs.respFire := io.phys.resp.fire()
  io.physObs.addr     := io.phys.req.bits.addr
  io.physObs.write    := io.phys.req.bits.write
  io.physObs.size     := io.phys.req.bits.size
  io.physObs.wdata    := io.phys.req.bits.wdata
  io.physObs.wmask    := io.phys.req.bits.wmask
  io.physObs.rdata    := io.phys.resp.bits.rdata
  io.physObs.error    := io.phys.resp.bits.error
}

class TeachingCpuObs extends Bundle {
  val commitValid   = Bool()
  val commitPc      = UInt(64.W)
  val commitInsn    = UInt(32.W)
  val trapValid     = Bool()
  val trapInterrupt = Bool()
  val trapCause     = UInt(64.W)
  val trapEpc       = UInt(64.W)
  val trapTval      = UInt(64.W)
  val state         = UInt(4.W)
  val pc            = UInt(64.W)
  val irqEnabled    = Bool()
  val isFetch       = Bool()
  val halted        = Bool()
}
