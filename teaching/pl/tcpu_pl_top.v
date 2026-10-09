// Pure-PL top: the core, the BRAM memory, and a tohost snoop whose outputs can drive LEDs.
// No bridge, no TileLink, no host. The program is the BRAM's initial contents.
`timescale 1ns/1ps
module tcpu_pl_top #(
  parameter        MEM_BYTES   = 65536,
  parameter [31:0] MEM_BASE    = 32'h8000_0000,
  parameter        INIT_HEX    = "",
  parameter [63:0] RESET_PC    = 64'h0000_0000_8000_0000,
  parameter [31:0] TOHOST_ADDR = 32'h8000_0080   // where the linker put tohost (nm <elf> | grep tohost)
) (
  input             clk,
  input             rst,
  output reg        tohost_valid,   // a write to TOHOST_ADDR has happened; sticky until reset
  output reg [62:0] tohost_code,    // the written value >> 1
  output            tohost_pass,    // tohost_valid && code == 0: the PASS LED
  output            commit_valid    // one blink per retirement, for an activity LED or an ILA trigger
);
  wire        req_valid, req_ready, req_write, resp_valid, resp_ready, resp_error, resp_scfail;
  wire [31:0] req_addr;
  wire [1:0]  req_size, req_lrsc;
  wire [63:0] req_wdata, resp_rdata;
  wire [7:0]  req_wmask;
  wire [3:0]  req_amo;

  tcpu_core #(.RESET_PC(RESET_PC)) cpu (
    .clk(clk), .rst(rst),
    .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr), .req_write(req_write),
    .req_size(req_size), .req_wdata(req_wdata), .req_wmask(req_wmask), .req_amo(req_amo), .req_lrsc(req_lrsc),
    .resp_valid(resp_valid), .resp_ready(resp_ready), .resp_rdata(resp_rdata), .resp_error(resp_error),
    .resp_scfail(resp_scfail), .resv_clear(),
    .commit_valid(commit_valid), .commit_pc(), .commit_insn(), .commit_len(), .commit_rd_valid(), .commit_rd(),
    .commit_rd_data(), .trap_valid(), .trap_interrupt(), .trap_cause(), .trap_epc(), .trap_tval(), .halted(),
    .dbg_req_is_fetch(), .dbg_ra(5'd0), .dbg_rd(), .dbg_ra2(5'd0), .dbg_rd2(), .dbg_csr_sel(5'd0), .dbg_csr_val(),
    .dbg_priv(), .irq_msip(1'b0), .irq_mtip(1'b0), .irq_meip(1'b0), .dbg_state(), .dbg_redirect(), .dbg_pc(),
    .dbg_irq_enabled());

  tcpu_bram_mem #(.MEM_BYTES(MEM_BYTES), .MEM_BASE(MEM_BASE), .INIT_HEX(INIT_HEX)) mem (
    .clk(clk), .rst(rst),
    .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr), .req_write(req_write),
    .req_size(req_size), .req_wdata(req_wdata), .req_wmask(req_wmask), .req_amo(req_amo), .req_lrsc(req_lrsc),
    .resp_valid(resp_valid), .resp_ready(resp_ready), .resp_rdata(resp_rdata), .resp_error(resp_error),
    .resp_scfail(resp_scfail));

  // the snoop: the handshake of a write to the tohost word
  always @(posedge clk) begin
    if (rst) begin tohost_valid <= 1'b0; tohost_code <= 63'd0; end
    else if (req_valid && req_ready && req_write && (req_addr == TOHOST_ADDR) && req_wdata[0]) begin
      tohost_valid <= 1'b1; tohost_code <= req_wdata[63:1];
    end
  end
  assign tohost_pass = tohost_valid && (tohost_code == 63'd0);
endmodule
