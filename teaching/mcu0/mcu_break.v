// MCU-0 break detector (teaching/uart): a serial line held low for LIMIT clocks gives ONE reset pulse of PULSE clocks.
// A normal byte is low for at most 9 bits (start bit + eight 0 data bits), 78 us at 115200 baud; the default LIMIT is
// 2^20 clocks, 26 ms at 40 MHz. The PC sends such a "break" (pyserial: send_break) to put the board back into the
// bootloader without anyone pressing BTN3 -- the same idea as an Arduino resetting when the serial port opens.
// After the pulse it waits for the line to go high again before it can fire once more: a line that stays low (an
// adapter without power pulls its TX pin low) resets the board once, not forever.
`timescale 1ns/1ps
module mcu_break #(
  parameter integer LIMIT = 1048576,
  parameter integer PULSE = 16
) (
  input      clk,
  input      rx,          // the raw pin (asynchronous)
  output reg brk = 1'b0
);
  reg        r1 = 1'b1, r2 = 1'b1;   // synchroniser
  reg [31:0] n = 32'd0;              // clocks low so far
  reg        armed = 1'b1;
  reg [7:0]  p = 8'd0;               // pulse clocks left
  always @(posedge clk) begin
    r1 <= rx; r2 <= r1;
    if (r2) begin n <= 32'd0; armed <= 1'b1; end
    else if (armed) begin
      if (n == LIMIT - 1) begin armed <= 1'b0; p <= PULSE; end
      else n <= n + 32'd1;
    end
    if (p != 8'd0) p <= p - 8'd1;
    brk <= (p != 8'd0);
  end
endmodule
