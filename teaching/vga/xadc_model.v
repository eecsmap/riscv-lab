// A stand-in for the XADC in simulation (the real primitive is Xilinx's and does not run in iverilog). It has the
// part of the XADC that mcu_adc uses: an EOS pulse every PERIOD clocks, and DRP reads answered 3 clocks after DEN,
// with the 12-bit value in bits 15:4. The testbench sets x, y and temp (all 0 by default: an empty header, which
// the board's divider holds at 0 V). Each reading of X and Y gets -2..+2 LSB of noise, as a real converter shows;
// bits 3:0 are noise too, and mcu_adc must ignore them.
// dig is the same A0 pin read by a digital input buffer (VGA project 6): every clock it is 1 when x plus -4..+4 steps of
// noise is at or above THR. So far below THR it is always 0, far above always 1, and within a few steps of THR it
// flickers -- like a real input with no hysteresis, whose threshold sits somewhere between 0.8 V and 2.0 V.
`timescale 1ns/1ps
module xadc_model #(
  parameter PERIOD = 4000,    // ~ 10,000 sequences a second at 40 MHz (the board measures about 6,400)
  parameter THR    = 1700      // the digital input's threshold, in ADC steps: 1.37 V
) (
  input             clk,
  input             den,
  input      [6:0]  daddr,
  output reg        drdy,
  output reg [15:0] dout,
  output reg        eos,
  output reg        dig
);
  reg [11:0] x = 12'd0, y = 12'd0, temp = 12'd0;
  integer    t = 0, seed = 7, n;
  reg [2:0]  pend = 3'd0;
  reg [6:0]  a;
  reg [11:0] v;
  reg [3:0]  low;
  integer    nd, seed2 = 11;

  initial begin drdy = 1'b0; dout = 16'd0; eos = 1'b0; dig = 1'b0; end

  always @(posedge clk) begin
    eos <= 1'b0; drdy <= 1'b0;
    nd = $random(seed2) % 5;                                   // -4..4
    dig <= ($signed({20'd0, x}) + nd) >= THR;
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
