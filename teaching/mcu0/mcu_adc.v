// MCU-0 ADC: the Zynq's XADC reading an analog joystick on the Arduino header (teaching/vga/README.md, project 5).
//
// The XADC is a hard block in the FPGA: a 12-bit, 1 MSPS converter with a sequencer that scans a list of channels by
// itself. mcu_board sets it up to scan, over and over: the chip temperature, VAUX1 (header pin A0) and VAUX9 (A1),
// each averaged over 16 conversions. The board scales 0..3.3 V on A0..A5 down to the XADC's 0..1 V, so the full
// 12-bit range 0..4095 is 0..3.3 V at the pin.
// Its results sit in status registers behind the XADC's DRP port (Dynamic Reconfiguration Port: an address, a read
// strobe DEN, and DRDY when the 16-bit word is there). This module does the DRP reads itself: whenever the XADC
// signals EOS (end of sequence), it reads the three results and keeps them, so the CPU reads plain registers with the
// router's one-cycle contract and never waits for the converter.
//
// Address map (base 0x1004_0000, a 4 KiB window), all read-only, 64-bit words:
//   +0x00 X      A0, 0..4095 (0 V .. 3.3 V)
//   +0x08 Y      A1, 0..4095
//   +0x10 TEMP   die temperature, 0..4095: degrees C = TEMP * 503.975 / 4096 - 273.15
//   +0x18 COUNT  sequences completed since reset: changes when X, Y and TEMP are fresh (about 10,000 a second)
// The DRP comes out of mcu_top: on the board it goes to the XADC primitive, in simulation to a model
// (teaching/vga/xadc_model.v). With nothing connected (DRDY and EOS low) the registers stay 0.
`timescale 1ns/1ps
module mcu_adc (
  input             clk,
  input             rst,
  input             sel,
  input             we,
  input      [31:0] addr,
  input      [63:0] wdata,
  input      [7:0]  wmask,
  output reg [63:0] rdata,
  // the XADC's DRP and its end-of-sequence pulse
  output reg        den,
  output reg [6:0]  daddr,
  input             drdy,
  input      [15:0] dout,
  input             eos
);
  localparam [6:0] A_TEMP = 7'h00, A_VAUX1 = 7'h11, A_VAUX9 = 7'h19;   // status registers: 0x10 + n is VAUXn
  reg [11:0] x, y, temp;
  reg [31:0] count;
  reg [1:0]  k;               // which result is being read: 0 X, 1 Y, 2 TEMP
  reg        busy, waiting;

  always @(posedge clk) begin
    den <= 1'b0;
    if (rst) begin
      x <= 12'd0; y <= 12'd0; temp <= 12'd0; count <= 32'd0; k <= 2'd0; busy <= 1'b0; waiting <= 1'b0;
      daddr <= 7'd0; rdata <= 64'd0;
    end else begin
      if (!busy && eos) begin busy <= 1'b1; k <= 2'd0; end
      if (busy && !waiting) begin                        // issue one read
        den <= 1'b1; waiting <= 1'b1;
        daddr <= (k == 2'd0) ? A_VAUX1 : (k == 2'd1) ? A_VAUX9 : A_TEMP;
      end
      if (busy && waiting && drdy) begin                 // the 12-bit result is MSB-aligned: bits 15:4
        waiting <= 1'b0;
        if (k == 2'd0) x <= dout[15:4];
        else if (k == 2'd1) y <= dout[15:4];
        else temp <= dout[15:4];
        if (k == 2'd2) begin busy <= 1'b0; count <= count + 32'd1; end
        else k <= k + 2'd1;
      end
      if (sel)
        rdata <= (addr[4:3] == 2'd0) ? {52'd0, x} : (addr[4:3] == 2'd1) ? {52'd0, y} :
                 (addr[4:3] == 2'd2) ? {52'd0, temp} : {32'd0, count};
    end
  end
endmodule
