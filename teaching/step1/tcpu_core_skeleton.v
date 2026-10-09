// Step 1 starting point. Copy this file to teaching/work/cpu/tcpu_core.v and fill in the TODOs.
//
// The module name, every parameter and every port are the contract: the harness instantiates `tcpu_core`
// with all of them, so none may be removed or renamed. Parameters and ports you do not use yet stay as
// they are; outputs you do not drive yet are tied off below. Later steps add behaviour, never pins.
//
// What a step-1 core does, and nothing more:
//   S_IF_REQ   raise one 4-byte aligned fetch (req_size = 2) at pc; go to S_IF_WAIT
//   S_IF_WAIT  hold the request until req_ready; when resp_valid, latch the instruction; go to S_EXEC
//   S_EXEC     decode addi / auipc / sd / jal: compute the value, the next pc, and for sd the store request
//   S_WB       write rd, advance pc, report the retirement on the commit port; back to S_IF_REQ
//   (a store waits for its response in S_MEM_WAIT between S_EXEC and S_WB)
// PHYSICAL_PORT rules the harness enforces: a raised request keeps valid and its payload until req_ready;
// one request in flight; a read carries wdata = 0 and wmask = 0; resp_ready is constant 1.
`timescale 1ns/1ps
`include "tcpu_defs.vh"

module tcpu_core #(
  parameter [63:0] RESET_PC      = 64'h0000_0000_8000_0000,
  parameter        X0_WRITABLE   = 0,
  parameter        NO_LOAD_SEXT  = 0,
  parameter        REQ_WITHDRAW  = 0,   // step 1 mutant: withdraw one request before its handshake
  parameter        LOAD_WDATA_LEAK = 0,
  parameter        STOP_ON_TRAP  = 0,
  parameter        TRAP_BAD_MEPC = 0,
  parameter        TRAP_COUNTS_RET = 0,
  parameter        FAULT_W_SEXT    = 0,
  parameter        FAULT_MULH_SIGN = 0,
  parameter        FAULT_C_IMM     = 0,
  parameter        FAULT_C_REG     = 0,
  parameter        ALLOW_RO_WRITE = 0,
  parameter        EARLY_IRQ      = 0,
  parameter        IRQ_BAD_MEPC   = 0,
  parameter        STALE_MIE      = 0,
  parameter        FAULT_NO_DELEG = 0,
  parameter        FAULT_S_IRQ_IN_M = 0,
  parameter        FAULT_SRET_SPP = 0,
  parameter        FAULT_PTW_NO_PERM = 0,
  parameter        FAULT_IF2_NO_XLATE = 0,
  parameter        FAULT_PPN_TRUNC = 0,
  parameter        MISA_A = 0,
  parameter        FAULT_A_W_NOSEXT   = 0,
  parameter        FAULT_A_SC_RESULT  = 0,
  parameter        FAULT_A_AMO_AS_LOAD = 0,
  parameter        FAULT_A_EARLY_RETIRE = 0,
  parameter        FAULT_A_NO_RESV_CLEAR = 0
) (
  input             clk,
  input             rst,
  // --- PHYSICAL_PORT (V2 pins included; a step-1 core drives amo = 0 and lrsc = 0)
  output            req_valid,
  input             req_ready,
  output     [31:0] req_addr,
  output            req_write,
  output     [1:0]  req_size,
  output     [63:0] req_wdata,
  output     [7:0]  req_wmask,
  output     [3:0]  req_amo,
  output     [1:0]  req_lrsc,
  input             resp_valid,
  output            resp_ready,
  input      [63:0] resp_rdata,
  input             resp_error,
  input             resp_scfail,
  output            resv_clear,
  // --- observation: one retirement or one trap per cycle, never both
  output reg        commit_valid,
  output reg [63:0] commit_pc,
  output reg [31:0] commit_insn,
  output reg [2:0]  commit_len,
  output reg        commit_rd_valid,
  output reg [4:0]  commit_rd,
  output reg [63:0] commit_rd_data,
  output reg        trap_valid,
  output reg        trap_interrupt,
  output reg [63:0] trap_cause,
  output reg [63:0] trap_epc,
  output reg [63:0] trap_tval,
  output reg        halted,
  output            dbg_req_is_fetch,
  input      [4:0]  dbg_ra,
  output     [63:0] dbg_rd,
  input      [4:0]  dbg_ra2,
  output     [63:0] dbg_rd2,
  input      [4:0]  dbg_csr_sel,
  output     [63:0] dbg_csr_val,
  output     [1:0]  dbg_priv,
  input             irq_msip,
  input             irq_mtip,
  input             irq_meip,
  output     [3:0]  dbg_state,
  output            dbg_redirect,
  output     [63:0] dbg_pc,
  output            dbg_irq_enabled
);
  // State encodings are shared with the harness (it watches 0 and 1 to tell fetches apart), so keep them.
  localparam S_IF_REQ = 4'd0, S_IF_WAIT = 4'd1, S_EXEC = 4'd2, S_MEM_WAIT = 4'd4, S_WB = 4'd5;

  reg [3:0]  state;
  reg [63:0] pc, npc;
  reg [31:0] insn;

  // ---- the request registers: what the port shows is a register, so it cannot change while waiting
  reg         core_req_valid, core_req_write;
  reg  [31:0] core_req_addr;
  reg  [1:0]  core_req_size;
  reg  [63:0] core_req_wdata;
  reg  [7:0]  core_req_wmask;
  assign req_valid = core_req_valid;
  assign req_addr  = core_req_addr;
  assign req_write = core_req_write;
  assign req_size  = core_req_size;
  assign req_wdata = core_req_wdata;
  assign req_wmask = core_req_wmask;
  assign req_amo   = 4'd0;
  assign req_lrsc  = 2'd0;
  assign resp_ready = 1'b1;          // single outstanding: the response can always be taken
  assign resv_clear = 1'b0;

  // ---- decode (combinational, from the latched instruction)
  wire [6:0]  opcode = insn[6:0];
  wire [4:0]  rd     = insn[11:7];
  wire [2:0]  funct3 = insn[14:12];
  wire [4:0]  rs1    = insn[19:15];
  wire [4:0]  rs2    = insn[24:20];
  wire [63:0] imm_i  = {{52{insn[31]}}, insn[31:20]};
  wire [63:0] imm_s  = {{52{insn[31]}}, insn[31:25], insn[11:7]};
  wire [63:0] imm_u  = {{32{insn[31]}}, insn[31:12], 12'b0};
  wire [63:0] imm_j  = {{43{insn[31]}}, insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};
  // TODO: is_addi / is_auipc / is_sd / is_jal from opcode (tcpu_defs.vh has the major opcodes) and funct3

  // ---- register file: x0 reads 0 and ignores writes; dbg_* let the harness check your commit port
  wire [63:0] rs1_val, rs2_val;
  reg         rf_we;
  reg  [4:0]  rf_wa;
  reg  [63:0] rf_wd;
  tcpu_regfile #(.X0_WRITABLE(X0_WRITABLE)) rf (
    .clk(clk), .ra1(rs1), .ra2(rs2), .rd1(rs1_val), .rd2(rs2_val),
    .we(rf_we), .wa(rf_wa), .wd(rf_wd),
    .dbg_ra(dbg_ra), .dbg_rd(dbg_rd), .dbg_ra2(dbg_ra2), .dbg_rd2(dbg_rd2));

  // ---- observation tie-offs for what a step-1 core does not have yet
  assign dbg_req_is_fetch = (state == S_IF_REQ) || (state == S_IF_WAIT);
  assign dbg_state   = state;
  assign dbg_redirect = 1'b0;
  assign dbg_pc      = pc;
  assign dbg_irq_enabled = 1'b0;
  assign dbg_csr_val = 64'd0;
  assign dbg_priv    = 2'd3;

  // ---- writeback staging: decided in S_EXEC, performed in S_WB
  reg        wb_we;
  reg [4:0]  wb_rd;
  reg [63:0] wb_value;

  always @(posedge clk) begin
    // single-cycle pulses default to 0; a state that needs one sets it for that cycle only
    commit_valid <= 1'b0; trap_valid <= 1'b0; rf_we <= 1'b0;
    if (rst) begin
      state <= S_IF_REQ; pc <= RESET_PC; npc <= RESET_PC; insn <= 32'd0;
      core_req_valid <= 1'b0; core_req_write <= 1'b0; core_req_addr <= 32'd0; core_req_size <= 2'd0;
      core_req_wdata <= 64'd0; core_req_wmask <= 8'd0;
      wb_we <= 1'b0; wb_rd <= 5'd0; wb_value <= 64'd0;
      halted <= 1'b0; trap_interrupt <= 1'b0; trap_cause <= 64'd0; trap_epc <= 64'd0; trap_tval <= 64'd0;
      commit_pc <= 64'd0; commit_insn <= 32'd0; commit_len <= 3'd4;
      commit_rd_valid <= 1'b0; commit_rd <= 5'd0; commit_rd_data <= 64'd0;
    end else begin
      case (state)
        S_IF_REQ: begin
          // TODO: raise a 4-byte read of pc: valid, addr = pc[31:0], write = 0, size = 2, wdata = 0, wmask = 0
          // TODO: state <= S_IF_WAIT
        end
        S_IF_WAIT: begin
          // TODO: drop valid in the cycle you see req_ready (and not before)
          // TODO: when resp_valid: insn <= the 32-bit word at pc inside the 64-bit response (pc[2] picks the half)
          //       then state <= S_EXEC
          // REQ_WITHDRAW != 0 (mutant, see README): drop valid once while req_ready is still low, then re-raise it
        end
        S_EXEC: begin
          // TODO: addi  -> wb_we = 1, wb_rd = rd, wb_value = rs1_val + imm_i,   npc = pc + 4, state <= S_WB
          // TODO: auipc -> wb_value = pc + imm_u,                                 npc = pc + 4, state <= S_WB
          // TODO: jal   -> wb_value = pc + 4,                                     npc = pc + imm_j, state <= S_WB
          // TODO: sd    -> raise a write: addr = rs1_val + imm_s, size = 3, wdata = rs2_val, wmask = 8'hff;
          //                wb_we = 0, npc = pc + 4, state <= S_MEM_WAIT
        end
        S_MEM_WAIT: begin
          // TODO: drop valid on req_ready; when resp_valid, state <= S_WB
        end
        S_WB: begin
          // TODO: rf_we <= wb_we; rf_wa <= wb_rd; rf_wd <= wb_value;
          // TODO: commit_valid <= 1; commit_pc <= pc; commit_insn <= insn; commit_len <= 4;
          //       commit_rd_valid <= wb_we && (wb_rd != 0); commit_rd <= wb_rd; commit_rd_data <= wb_value;
          // TODO: pc <= npc; state <= S_IF_REQ
        end
        default: state <= S_IF_REQ;
      endcase
    end
  end
endmodule
