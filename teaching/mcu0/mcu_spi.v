// MCU-0 SPI master (OLED project 3, teaching/oled/README.md): the CPU hands over bytes, the hardware shifts them out.
// Write-only SPI mode 0 -- SCK rests low, MOSI changes while SCK is low, the device samples on the rising edge --
// which is all the Pmod OLEDrgb (SSD1331) needs. CS# and D/C# stay on GPIO: software sets them, after waiting for
// BUSY to clear (D/C# is sampled on each byte's 8th edge, so it must not change while a byte is on the wire).
//
// Registers, 64-bit words like the GPIO's (base 0x1002_0000):
//   +0x00 DATA8   W   one byte (lane 0) into the FIFO
//   +0x08 DATA16  W   two bytes from one halfword store (lanes 1:0): bits 15:8 go out first -- one RGB565 pixel
//   +0x10 STATUS  R   bit 0 BUSY (a byte on the wire or in the FIFO), bit 1 FULL (fewer than 2 free FIFO entries),
//                     bit 2 OVERFLOW (sticky: a write found no room and was dropped; cleared by writing CTRL)
//   +0x18 CTRL    RW  bit 0 EN (SCK and MOSI on Pmod JB come from here, not from GPIO), bits 15:8 DIV: each half of
//                     SCK lasts DIV clocks (0 counts as 1). Reset: EN = 0, DIV = 4 -> 8 clocks per bit, 5 MHz at 40 MHz.
//
// The FIFO holds 8 bytes. The slave interface has no way to stall a write, so a write that does not fit is dropped and
// OVERFLOW is set: software must look at FULL first.
`timescale 1ns/1ps
module mcu_spi (
  input             clk,
  input             rst,
  input             sel,
  input             we,
  input      [31:0] addr,
  input      [63:0] wdata,
  input      [7:0]  wmask,
  output reg [63:0] rdata,
  output reg        sck,
  output reg        mosi,
  output            en
);
  reg  [7:0] fifo [0:7];
  reg  [3:0] wp, rp;                    // one extra bit each, so that wp - rp counts 0..8
  wire [3:0] count = wp - rp;
  reg        ctrl_en, ovf;
  reg  [7:0] div;
  reg  [7:0] sh;                        // the byte on the wire; sh[7] is on MOSI
  reg  [2:0] bit_n;                     // bits of it still to send after the current one
  reg  [7:0] cnt;                       // clocks left in the current half of SCK
  reg        active;
  wire       busy = active || (count != 4'd0);
  wire       full = (count > 4'd6);
  wire [7:0] half = (div == 8'd0) ? 8'd1 : div;
  wire       is_data8 = (addr[11:3] == 9'd0), is_data16 = (addr[11:3] == 9'd1);
  wire       is_status = (addr[11:3] == 9'd2), is_ctrl = (addr[11:3] == 9'd3);
  wire       pop = (!active || (sck && cnt == 8'd1 && bit_n == 3'd0)) && (count != 4'd0);
  assign en = ctrl_en;

  always @(posedge clk) begin
    if (rst) begin
      wp <= 4'd0; rp <= 4'd0; ctrl_en <= 1'b0; ovf <= 1'b0; div <= 8'd4; rdata <= 64'd0;
      sh <= 8'd0; bit_n <= 3'd0; cnt <= 8'd0; active <= 1'b0; sck <= 1'b0; mosi <= 1'b0;
    end else begin
      // ---- the bus side
      if (sel) begin
        rdata <= is_status ? {61'd0, ovf, full, busy} : is_ctrl ? {48'd0, div, 7'd0, ctrl_en} : 64'd0;
        if (we && is_ctrl && wmask[0]) begin ctrl_en <= wdata[0]; ovf <= 1'b0; end
        if (we && is_ctrl && wmask[1]) div <= wdata[15:8];
        if (we && is_data8 && wmask[0]) begin
          if (count == 4'd8) ovf <= 1'b1;
          else begin fifo[wp[2:0]] <= wdata[7:0]; wp <= wp + 4'd1; end
        end
        if (we && is_data16 && wmask[1:0] == 2'b11) begin
          if (count > 4'd6) ovf <= 1'b1;
          else begin fifo[wp[2:0]] <= wdata[15:8]; fifo[wp[2:0] + 3'd1] <= wdata[7:0]; wp <= wp + 4'd2; end
        end
      end

      // ---- the wire side: each bit is DIV clocks with SCK low (MOSI settles), then DIV clocks with SCK high
      if (pop) begin                    // next byte: its bit 7 goes on MOSI while SCK is (or goes) low
        sh <= fifo[rp[2:0]]; mosi <= fifo[rp[2:0]][7]; rp <= rp + 4'd1;
        bit_n <= 3'd7; cnt <= half; sck <= 1'b0; active <= 1'b1;
      end else if (active) begin
        if (cnt != 8'd1) cnt <= cnt - 8'd1;
        else begin
          cnt <= half;
          if (!sck) sck <= 1'b1;        // rising edge: the device takes MOSI
          else begin                    // falling edge: next bit, or the byte is done
            sck <= 1'b0;
            if (bit_n == 3'd0) active <= 1'b0;
            else begin sh <= {sh[6:0], 1'b0}; mosi <= sh[6]; bit_n <= bit_n - 3'd1; end
          end
        end
      end
    end
  end
endmodule
