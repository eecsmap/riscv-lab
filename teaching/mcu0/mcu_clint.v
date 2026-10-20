// MCU-0 CLINT: the harness model made synthesizable. 64 KiB window: msip at +0 (bit 0 of a 32-bit word),
// mtimecmp at +0x4000 (64-bit), mtime at +0xBFF8 (64-bit, one tick per TICK_DIV cycles). mtip is the level
// mtime >= mtimecmp. Other offsets read 0 and ignore writes. Writes honour the byte lanes.
`timescale 1ns/1ps
module mcu_clint #(parameter TICK_DIV = 1) (
  input             clk,
  input             rst,
  input             sel,
  input             we,
  input      [31:0] addr,
  input      [63:0] wdata,
  input      [7:0]  wmask,
  output reg [63:0] rdata,
  output            mtip,
  output            msip
);
  reg        msip_r;
  reg [63:0] mtimecmp, mtime;
  reg [31:0] tick;
  wire [15:0] off = addr[15:0];
  wire is_msip = (off[15:3] == 13'd0), is_cmp = (off == 16'h4000), is_time = (off == 16'hBFF8);
  assign mtip = (mtime >= mtimecmp);
  assign msip = msip_r;
  integer i;
  always @(posedge clk) begin
    if (rst) begin
      msip_r <= 1'b0; mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF; mtime <= 64'd0; tick <= 32'd0; rdata <= 64'd0;
    end else begin
      if (tick + 1 >= TICK_DIV) begin tick <= 32'd0; mtime <= mtime + 64'd1; end else tick <= tick + 32'd1;
      if (sel) begin
        rdata <= is_msip ? {63'd0, msip_r} : is_cmp ? mtimecmp : is_time ? mtime : 64'd0;
        if (we) begin
          if (is_msip && wmask[0]) msip_r <= wdata[0];
          if (is_cmp)  for (i = 0; i < 8; i = i + 1) if (wmask[i]) mtimecmp[i*8 +: 8] <= wdata[i*8 +: 8];
          if (is_time) for (i = 0; i < 8; i = i + 1) if (wmask[i]) mtime[i*8 +: 8]    <= wdata[i*8 +: 8];
        end
      end
    end
  end
endmodule
