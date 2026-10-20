// MCU-0 on the PYNQ-Z1: 125 MHz on H16 -> MMCM x8/25 -> 40 MHz, the same clocking the accepted SoC uses.
// BTN3 is the reset; BTN0..2 and the two switches are GPIO inputs; the four LEDs are GPIO OUT[3:0].
// Not simulated here (MMCME2_BASE is a Xilinx primitive): mcu_top is what tb_mcu exercises.
`timescale 1ns/1ps
module mcu_board #(
  parameter MEM_BYTES = 65536,
  parameter INIT_HEX  = "blink.hex"
) (
  input        clk,          // 125 MHz board clock
  output [3:0] led,
  input  [3:0] btn,
  input  [1:0] sw
);
  wire gclk_i, clk40_i, clk40, fb, locked;
  IBUFG ibufg (.I(clk), .O(gclk_i));
  MMCME2_BASE #(
    .BANDWIDTH("OPTIMIZED"), .CLKFBOUT_MULT_F(8.0), .CLKFBOUT_PHASE(0.0), .CLKIN1_PERIOD(8.0),
    .CLKOUT0_DIVIDE_F(25.0), .CLKOUT0_DUTY_CYCLE(0.5), .CLKOUT0_PHASE(0.0),
    .CLKOUT1_DIVIDE(1), .CLKOUT2_DIVIDE(1), .CLKOUT3_DIVIDE(1), .CLKOUT4_DIVIDE(1), .CLKOUT5_DIVIDE(1), .CLKOUT6_DIVIDE(1),
    .DIVCLK_DIVIDE(1), .REF_JITTER1(0.0), .STARTUP_WAIT("FALSE")
  ) mmcm (
    .CLKOUT0(clk40_i), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(),
    .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUT(fb), .CLKFBOUTB(), .LOCKED(locked),
    .CLKIN1(gclk_i), .PWRDWN(1'b0), .RST(1'b0), .CLKFBIN(fb));
  BUFG bufg (.I(clk40_i), .O(clk40));

  // reset: held while the MMCM is not locked or BTN3 is pressed, released synchronously
  reg [2:0] rst_sync = 3'b111;
  always @(posedge clk40 or negedge locked)
    if (!locked) rst_sync <= 3'b111;
    else         rst_sync <= {rst_sync[1:0], btn[3]};
  wire rst = rst_sync[2];

  mcu_top #(.MEM_BYTES(MEM_BYTES), .INIT_HEX(INIT_HEX), .TICK_DIV(1)) mcu (
    .clk(clk40), .rst(rst), .led(led), .btn({1'b0, btn[2:0]}), .sw(sw), .commit_valid(), .bus_error());
endmodule
