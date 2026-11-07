// MCU-0 UART (teaching/uart/README.md): 8 data bits, no parity, 1 stop bit (8N1), least significant bit first.
// A line idles high; a byte is a low start bit, the 8 data bits, and a high stop bit, each DIV clocks long.
// 40 MHz / 115200 baud = 347.2, so the reset DIV is 347 (0.06 % fast; both ends may be off by a few percent).
//
// The receiver: the pin goes through a 2-flop synchroniser first (it changes whenever the PC likes, not on our clock).
// A falling edge while idle starts a byte; half a bit later, in the middle of the start bit, the line must still be low
// (otherwise it was a glitch and is ignored). Then every DIV clocks one sample, in the middle of each data bit and of
// the stop bit. Sampling in the middle is what tolerates two clocks that disagree: the error grows by a little each
// bit, and there is half a bit of room for it.
// After a framing error (a stop bit that is low: noise, or a "break" -- the line held low on purpose) the receiver
// waits until the line is high again before it looks for a start bit. Otherwise a long break would be read as a run of
// bad frames, and the moment the line goes high in the middle of one of them, that frame could pass as a junk byte.
//
// Registers, 64-bit words like the GPIO's (base 0x1005_0000):
//   +0x00 TX      W   one byte (lane 0) to send. One byte waits here while the previous one is on the wire; a write
//                     that finds the wait slot full is dropped and sets TX_OVERFLOW, so software looks at TX_READY first.
//   +0x08 RX      R   bit 8 VALID, bits 7:0 the received byte. Reading takes the byte: VALID is clear until the next
//                     one arrives. One load both checks and takes, so there is no window between "is there one?" and
//                     "give it to me".
//   +0x10 STATUS  R   bit 0 TX_READY (the wait slot is free), bit 1 TX_IDLE (nothing waiting, nothing on the wire),
//                     bit 2 RX_VALID, and three sticky errors: bit 3 RX_OVERRUN (a byte arrived while the previous one
//                     had not been read; the new one is lost), bit 4 RX_FRAME (a stop bit was low), bit 5 TX_OVERFLOW.
//                 W   any write with lane 0 clears the three sticky bits.
//   +0x18 DIV     RW  bits 15:0, clocks per bit. Values below 4 count as 4.
`timescale 1ns/1ps
module mcu_uart (
  input             clk,
  input             rst,
  input             sel,
  input             we,
  input      [31:0] addr,
  input      [63:0] wdata,
  input      [7:0]  wmask,
  output reg [63:0] rdata,
  input             rx,             // from the PC (asynchronous)
  output reg        tx              // to the PC
);
  reg  [15:0] div;
  wire [15:0] bitlen = (div < 16'd4) ? 16'd4 : div;
  wire        is_tx = (addr[11:3] == 9'd0), is_rx = (addr[11:3] == 9'd1);
  wire        is_status = (addr[11:3] == 9'd2), is_div = (addr[11:3] == 9'd3);

  // ---- transmitter: one byte waiting (thr) plus the one on the wire (tsh)
  reg  [7:0]  thr;
  reg         thr_full, tact, txovf;
  reg  [8:0]  tsh;                  // what is still to go out after the current bit: data bits, then the stop bit
  reg  [3:0]  tbits;                // how many of them
  reg  [15:0] tcnt;                 // clocks left in the current bit

  // ---- receiver
  reg         rx1, rx2;             // the synchroniser: only rx2 is used
  reg         ract;
  reg  [3:0]  rbit;                 // 0 = in the start bit, 1..8 = data bits, 9 = the stop bit
  reg  [15:0] rcnt;                 // clocks to the next sample
  reg  [7:0]  rsh, rbr;
  reg         rvalid, ovr, ferr;
  reg         rwait;                // after a framing error: wait for the line to go high
  wire        take = sel && !we && is_rx && rvalid;   // this read takes the byte

  always @(posedge clk) begin
    if (rst) begin
      div <= 16'd347; rdata <= 64'd0;
      thr <= 8'd0; thr_full <= 1'b0; tact <= 1'b0; txovf <= 1'b0; tsh <= 9'h1FF; tbits <= 4'd0; tcnt <= 16'd0; tx <= 1'b1;
      rx1 <= 1'b1; rx2 <= 1'b1; ract <= 1'b0; rbit <= 4'd0; rcnt <= 16'd0; rsh <= 8'd0; rbr <= 8'd0;
      rvalid <= 1'b0; ovr <= 1'b0; ferr <= 1'b0; rwait <= 1'b0;
    end else begin
      // ---- the bus side
      if (sel) begin
        rdata <= is_rx     ? {55'd0, rvalid, rbr} :
                 is_status ? {58'd0, txovf, ferr, ovr, rvalid, !thr_full && !tact, !thr_full} :
                 is_div    ? {48'd0, div} : 64'd0;
        if (take) rvalid <= 1'b0;
        if (we && is_tx && wmask[0]) begin
          if (thr_full) txovf <= 1'b1;
          else begin thr <= wdata[7:0]; thr_full <= 1'b1; end
        end
        if (we && is_status && wmask[0]) begin ovr <= 1'b0; ferr <= 1'b0; txovf <= 1'b0; end
        if (we && is_div && wmask[0]) div[7:0]  <= wdata[7:0];
        if (we && is_div && wmask[1]) div[15:8] <= wdata[15:8];
      end

      // ---- the transmitter. A bus write only fills an empty slot and this only empties a full one, so they never
      // touch thr_full in the same cycle.
      if (!tact) begin
        tx <= 1'b1;
        if (thr_full) begin                       // start bit now
          tx <= 1'b0; tsh <= {1'b1, thr}; tbits <= 4'd9; tcnt <= bitlen; tact <= 1'b1; thr_full <= 1'b0;
        end
      end else if (tcnt != 16'd1) tcnt <= tcnt - 16'd1;
      else begin
        tcnt <= bitlen;
        if (tbits == 4'd0) begin tact <= 1'b0; tx <= 1'b1; end    // the stop bit has lasted a whole bit
        else begin tx <= tsh[0]; tsh <= {1'b1, tsh[8:1]}; tbits <= tbits - 4'd1; end
      end

      // ---- the receiver
      rx1 <= rx; rx2 <= rx1;
      if (rx2) rwait <= 1'b0;
      if (!ract) begin
        if (!rx2 && !rwait) begin ract <= 1'b1; rbit <= 4'd0; rcnt <= {1'b0, bitlen[15:1]}; end   // half a bit: the middle of the start bit
      end else if (rcnt != 16'd1) rcnt <= rcnt - 16'd1;
      else begin
        rcnt <= bitlen;
        if (rbit == 4'd0) begin
          if (rx2) ract <= 1'b0;                  // high again already: a glitch, not a start bit
          else rbit <= 4'd1;
        end else if (rbit != 4'd9) begin
          rsh <= {rx2, rsh[7:1]}; rbit <= rbit + 4'd1;                // least significant bit first
        end else begin                            // the middle of the stop bit
          ract <= 1'b0;
          if (!rx2) begin ferr <= 1'b1; rwait <= 1'b1; end
          else if (rvalid && !take) ovr <= 1'b1;
          else begin rbr <= rsh; rvalid <= 1'b1; end
        end
      end
    end
  end
endmodule
