// M2-1: 31x64 register file. x0 is not stored: it reads as zero and writes to it are discarded,
// which is the property t01's CHECK_X0_ZERO checks (and the x0-writable fault injection breaks).
`timescale 1ns/1ps
module tcpu_regfile #(parameter X0_WRITABLE = 0) (
  input             clk,
  input      [4:0]  ra1, ra2,
  output     [63:0] rd1, rd2,
  input             we,
  input      [4:0]  wa,
  input      [63:0] wd,
  // debug read port: lets the harness check the observation port against the real architectural state
  input      [4:0]  dbg_ra,
  output     [63:0] dbg_rd,
  input      [4:0]  dbg_ra2,
  output     [63:0] dbg_rd2
);
  reg [63:0] regs [0:31];
  integer i;
  initial for (i = 0; i < 32; i = i + 1) regs[i] = 64'd0;
  // fault injection (X0_WRITABLE=1) makes x0 an ordinary register -- see the M2-1 fault controls
  wire write_ok = we && (X0_WRITABLE ? 1'b1 : (wa != 5'd0));
  always @(posedge clk) if (write_ok) regs[wa] <= wd;
  assign rd1 = (X0_WRITABLE == 0 && ra1 == 5'd0) ? 64'd0 : regs[ra1];
  assign rd2 = (X0_WRITABLE == 0 && ra2 == 5'd0) ? 64'd0 : regs[ra2];
  assign dbg_rd  = (X0_WRITABLE == 0 && dbg_ra  == 5'd0) ? 64'd0 : regs[dbg_ra];
  assign dbg_rd2 = (X0_WRITABLE == 0 && dbg_ra2 == 5'd0) ? 64'd0 : regs[dbg_ra2];
endmodule
