// MCU-0 on the PYNQ-Z1: 125 MHz on H16 -> MMCM x8/25 -> 40 MHz, the same clocking the accepted SoC uses.
// BTN3 is the reset; BTN0..2 and the two switches are GPIO inputs (with RESET_SW1 = 1, SW1 is the reset and all four
// buttons are inputs); the four LEDs are GPIO OUT[3:0] and the Pmod JB
// header is GPIO OUT[15:8] (all low after reset: a Pmod OLEDrgb there stays powered off until firmware enables it).
// With PMOD_VGA = 1 a Pmod VGA on JA + JB shows the VGA text mode instead (teaching/vga): JA = red (pins 1-4) and
// blue (7-10), JB = green (1-4), HSYNC (7), VSYNC (8). Then nothing else drives JB; with PMOD_VGA = 0, JA stays low.
// The XADC scans the joystick on the Arduino header -- A0 (VAUX1), A1 (VAUX9) -- and the die temperature for mcu_adc;
// the joystick's switch is on D4 (active low, the pin's pull-up is on in the XDC). Power the joystick from 3.3 V.
// Not simulated here (MMCME2_BASE is a Xilinx primitive): mcu_top is what tb_mcu exercises.
`timescale 1ns/1ps
module mcu_board #(
  parameter MEM_BYTES = 65536,
  parameter INIT_HEX  = "blink.hex",
  parameter RESET_SW1 = 0,         // 1: SW1 up holds the reset and BTN3 becomes an input (OLED snake: four directions)
  parameter PMOD_VGA  = 0          // 1: JA + JB carry the VGA picture (a Pmod VGA across both headers)
) (
  input        clk,          // 125 MHz board clock
  output [3:0] led,
  output [7:0] ja,           // Pmod JA: ja[0..3] = pins 1-4, ja[4..7] = pins 7-10
  output [7:0] jb,           // Pmod JB: jb[0..3] = pins 1-4, jb[4..7] = pins 7-10
  input  [3:0] btn,
  input  [1:0] sw,
  input        vaux1_p,      // Arduino A0 (through the board's 3.3 V -> 1 V divider)
  input        vaux1_n,
  input        vaux9_p,      // Arduino A1
  input        vaux9_n,
  input        joy_sw_n      // Arduino D4: the joystick's switch, low = pressed
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
    else         rst_sync <= {rst_sync[1:0], RESET_SW1 ? sw[1] : btn[3]};
  wire rst = rst_sync[2];

  wire [7:0] jb_mcu;
  wire [3:0] vga_r, vga_g, vga_b;
  wire       vga_hs, vga_vs;
  assign ja = PMOD_VGA ? {vga_b, vga_r} : 8'd0;
  assign jb = PMOD_VGA ? {2'b00, vga_vs, vga_hs, vga_g} : jb_mcu;

  // the XADC: continuous sequence of temperature, VAUX1, VAUX9, each averaged over 16 conversions, unipolar 0..1 V.
  // ADCCLK = 40 MHz / 2 = 20 MHz (at most 26); a sequence takes about 0.1 ms.
  wire        xadc_den, xadc_drdy, xadc_eos;
  wire [6:0]  xadc_daddr;
  wire [15:0] xadc_do;
  wire [15:0] vauxp = {6'd0, vaux9_p, 7'd0, vaux1_p, 1'b0};
  wire [15:0] vauxn = {6'd0, vaux9_n, 7'd0, vaux1_n, 1'b0};
  XADC #(
    .INIT_40(16'h1000),   // config 0: average 16 samples, unipolar
    .INIT_41(16'h2FFF),   // config 1: continuous sequence mode, alarms off, all calibrations applied
    .INIT_42(16'h0200),   // config 2: ADCCLK = DCLK / 2
    .INIT_48(16'h0101),   // sequence: calibration, temperature
    .INIT_49(16'h0202),   // sequence: VAUX1, VAUX9
    .INIT_4A(16'h0100),   // average: temperature
    .INIT_4B(16'h0202),   // average: VAUX1, VAUX9
    .INIT_4C(16'h0000), .INIT_4D(16'h0000),   // all unipolar
    .INIT_4E(16'h0000),
    .INIT_4F(16'h0202)    // VAUX1, VAUX9: longer acquisition (the board's divider is not a low-impedance source)
  ) xadc (
    .DCLK(clk40), .DEN(xadc_den), .DADDR(xadc_daddr), .DWE(1'b0), .DI(16'd0), .DO(xadc_do), .DRDY(xadc_drdy),
    .RESET(1'b0), .CONVST(1'b0), .CONVSTCLK(1'b0), .VP(1'b0), .VN(1'b0), .VAUXP(vauxp), .VAUXN(vauxn),
    .ALM(), .OT(), .BUSY(), .CHANNEL(), .EOC(), .EOS(xadc_eos), .JTAGBUSY(), .JTAGLOCKED(), .JTAGMODIFIED(),
    .MUXADDR());

  mcu_top #(.MEM_BYTES(MEM_BYTES), .INIT_HEX(INIT_HEX), .TICK_DIV(1)) mcu (
    .clk(clk40), .rst(rst), .led(led), .jb(jb_mcu),
    .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b), .vga_hs(vga_hs), .vga_vs(vga_vs), .btn(RESET_SW1 ? btn : {1'b0, btn[2:0]}), .sw(sw),
    .joy_sw(!joy_sw_n), .xadc_den(xadc_den), .xadc_daddr(xadc_daddr), .xadc_drdy(xadc_drdy), .xadc_do(xadc_do),
    .xadc_eos(xadc_eos), .commit_valid(), .bus_error());
endmodule
