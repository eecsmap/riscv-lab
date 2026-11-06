// A stand-in for the XADC in simulation (the real primitive is Xilinx's and does not run in iverilog). It has the
// part of the XADC that mcu_adc uses: an EOS pulse every PERIOD clocks, and DRP reads answered 3 clocks after DEN,
// with the 12-bit value in bits 15:4. The testbench sets x, y and temp (all 0 by default: an empty header, which
// the board's divider holds at 0 V). Each reading of X and Y gets -2..+2 LSB of noise, as a real converter shows;
// bits 3:0 are noise too, and mcu_adc must ignore them.
`timescale 1ns/1ps
module xadc_model #(
  parameter PERIOD = 4000     // ~ 10,000 sequences a second at 40 MHz, as on the board
) (
  input             clk,
  input             den,
  input      [6:0]  daddr,
  output reg        drdy,
  output reg [15:0] dout,
  output reg        eos
);
  reg [11:0] x = 12'd0, y = 12'd0, temp = 12'd0;
  integer    t = 0, seed = 7, n;
  reg [2:0]  pend = 3'd0;
  reg [6:0]  a;
  reg [11:0] v;
  reg [3:0]  low;

  initial begin drdy = 1'b0; dout = 16'd0; eos = 1'b0; end

  always @(posedge clk) begin
    eos <= 1'b0; drdy <= 1'b0;
    t = t + 1;
    if (t % PERIOD == 0) eos <= 1'b1;
    if (den) begin pend <= 3'd1; a = daddr; end
    else if (pend != 3'd0) pend <= pend + 3'd1;
    if (pend == 3'd3) begin
      n = $random(seed) % 3;                                   // -2..2
      v = (a == 7'h11) ? x : (a == 7'h19) ? y : (a == 7'h00) ? temp : 12'd0;
      if (a != 7'h00 && !(v < 2 && n < 0) && !(v > 4093 && n > 0)) v = v + n;
      low = $random(seed);
      dout <= {v, low};
      drdy <= 1'b1; pend <= 3'd0;
    end
  end
endmodule
