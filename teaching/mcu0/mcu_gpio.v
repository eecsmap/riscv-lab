// MCU-0 GPIO: +0 OUT (16 bits, read/write), +8 IN (8 bits, read-only). Both are 64-bit words so lw/sw and ld/sd
// both work. OUT has two byte lanes that are written independently: lane 0 (OUT[7:0], the LEDs) and lane 1
// (OUT[15:8], the Pmod JB header). A byte store to +1 changes only the JB pins, so code driving a Pmod never has to
// read-modify-write the LED bits. The inputs are synchronised with two flops.
`timescale 1ns/1ps
module mcu_gpio (
  input             clk,
  input             rst,
  input             sel,
  input             we,
  input      [31:0] addr,
  input      [63:0] wdata,
  input      [7:0]  wmask,
  output reg [63:0] rdata,
  output reg [15:0] gpio_out,
  input      [7:0]  gpio_in
);
  reg [7:0] in_s1, in_s2;
  wire is_out = (addr[11:3] == 9'd0), is_in = (addr[11:3] == 9'd1);
  always @(posedge clk) begin
    in_s1 <= gpio_in; in_s2 <= in_s1;
    if (rst) begin gpio_out <= 16'd0; rdata <= 64'd0; end
    else if (sel) begin
      rdata <= is_out ? {48'd0, gpio_out} : is_in ? {56'd0, in_s2} : 64'd0;
      if (we && is_out && wmask[0]) gpio_out[7:0]  <= wdata[7:0];
      if (we && is_out && wmask[1]) gpio_out[15:8] <= wdata[15:8];
    end
  end
endmodule
