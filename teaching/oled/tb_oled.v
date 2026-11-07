// OLED testbench: MCU-0 (mcu_top) with a Pmod OLEDrgb model on JB. Runs the firmware until it has drawn its screen
// and the heartbeat has started, then judges the run and writes the screen as an image.
//   +hex=<file> [+ms=<clocks per ms, as the firmware's TICKS_PER_MS>] [+frame_bytes=<n>] [+maxcycles=<n>] [+ppm=<file>]
//   [+vcd=<file>] [+sw=<SW1:0>] [+rects=<n>] [+script=<file>] [+until_led3=1] [+expect_led=<LED3..1>]
// +script: lines "<moves> <buttons>": when LED0 has toggled <moves> times, set BTN3..0 to <buttons> (hex).
// +until_led3=1: stop 400,000 cycles after LED3 lights (the snake's game over) instead of after two LED0 toggles.
// +expect_led: LED3..1 must read this at the end. +snap=<moves> +snap_ppm=<file>: also save the screen after that many
// LED0 toggles.
// PASS needs: no model ERROR (power order, SPI timing, command syntax -- see ssd1331_model.v), the display switched on,
// at least one data burst of frame_bytes (default 12,288: a full frame; the firmware's FRAME_SHIFT makes it smaller), at least `rects` rectangles (default 8) and 12 characters drawn, LED0 toggling
// (the heartbeat after the drawing), no bus error, no synchronous trap, and no SPI FIFO overflow.
`timescale 1ns/1ps
module tb_oled;
  reg clk = 1'b0, rst = 1'b1;
  always #5 clk = ~clk;
  reg [3:0] btn = 4'd0; reg [1:0] sw = 2'd0;
  wire [3:0] led; wire [7:0] jb; wire commit_valid, bus_error;
  reg [63:0] cycles = 64'd0;

  mcu_top top (.clk(clk), .rst(rst), .led(led), .jb(jb), .btn(btn), .sw(sw), .joy_sw(1'b0), .xadc_drdy(1'b0), .xadc_do(16'd0), .xadc_eos(1'b0), .a0_dig(1'b0), .uart_rx(1'b1), .uart_tx(), .commit_valid(commit_valid), .bus_error(bus_error));
  ssd1331_model oled (.clk(clk), .now(cycles), .cs(jb[0]), .mosi(jb[1]), .sck(jb[3]), .dc(jb[4]), .res(jb[5]),
                      .vccen(jb[6]), .pmoden(jb[7]));

  reg [1023:0] hexfile, vcdfile, ppmfile, scriptfile, snapfile;
  integer maxcycles = 20000000, frame_bytes = 12288, min_rects = 8, swset = 0, until_led3 = 0, expect_led = -1,
          snap = -1, script_fd = 0, next_at = -1, next_btn = 0, irqs = 0, led3_at = -1, rc, toggles = 0, errors = 0, traps = 0;
  reg led0_q = 1'b0, have_ppm = 1'b0;

  initial begin
    if (!$value$plusargs("hex=%s", hexfile)) begin $display("tb_oled: +hex=<file> is required"); $finish; end
    if ($value$plusargs("maxcycles=%d", maxcycles)) ;
    if ($value$plusargs("frame_bytes=%d", frame_bytes)) ;
    if ($value$plusargs("rects=%d", min_rects)) ;
    if ($value$plusargs("sw=%d", swset)) sw = swset;
    if ($value$plusargs("until_led3=%d", until_led3)) ;
    if ($value$plusargs("snap=%d", snap)) if (!$value$plusargs("snap_ppm=%s", snapfile)) snap = -1;
    if ($value$plusargs("expect_led=%d", expect_led)) ;
    if ($value$plusargs("script=%s", scriptfile)) begin
      script_fd = $fopen(scriptfile, "r");
      if (script_fd == 0) begin $display("tb_oled: cannot open the script"); $finish; end
      rc = $fscanf(script_fd, "%d %h\n", next_at, next_btn);
      if (rc != 2) next_at = -1;
    end
    if ($value$plusargs("ppm=%s", ppmfile)) have_ppm = 1'b1;
    $readmemh(hexfile, top.ram.mem);
    if ($value$plusargs("vcd=%s", vcdfile)) begin $dumpfile(vcdfile); $dumpvars(0, tb_oled); end
    repeat (3) @(posedge clk);
    #1 rst = 1'b0;
  end

  always @(posedge clk) if (!rst) begin
    cycles = cycles + 1;
    if (bus_error) begin errors = errors + 1; $display("BUS ERROR cyc=%0d", cycles); end
    if (top.cpu.trap_valid && top.cpu.trap_interrupt) irqs = irqs + 1;
    if (top.cpu.trap_valid && !top.cpu.trap_interrupt) begin
      traps = traps + 1;
      $display("TRAP cyc=%0d cause=%0d epc=%h", cycles, top.cpu.trap_cause, top.cpu.trap_epc[31:0]);
    end
    if (next_at >= 0 && toggles >= next_at) begin
      btn <= next_btn[3:0];
      $display("BTN  cyc=%0d after %0d moves: buttons %b", cycles, toggles, next_btn[3:0]);
      rc = $fscanf(script_fd, "%d %h\n", next_at, next_btn);
      if (rc != 2) next_at = -1;
    end
    if (snap >= 0 && toggles == snap) begin oled.dump_ppm(snapfile); snap = -1; end
    if (led[3] && led3_at < 0) begin led3_at = cycles; $display("LED3 cyc=%0d on (LEDs %b)", cycles, led); end
    if (led[0] != led0_q) begin toggles = toggles + 1; led0_q = led[0]; $display("LED0 cyc=%0d -> %0d", cycles, led[0]); end
    if ((until_led3 ? (led3_at >= 0 && cycles >= led3_at + 400000) : toggles >= 2) || cycles >= maxcycles || traps > 0) begin
      $display("SUMMARY cycles=%0d model_errors=%0d display_on=%0d commands=%0d rects=%0d clears=%0d glyphs=%0d data_bytes=%0d max_burst=%0d heartbeat=%0d irqs=%0d leds=%b bus_errors=%0d traps=%0d spi_overflow=%0d",
               cycles, oled.errors, oled.display_on, oled.cmds, oled.rects, oled.clears, oled.glyphs, oled.data_bytes,
               oled.max_burst, toggles, irqs, led, errors, traps, top.spi.ovf);
      if (have_ppm) oled.dump_ppm(ppmfile);
      if (oled.errors == 0 && oled.display_on && oled.max_burst >= frame_bytes && oled.rects >= min_rects && oled.glyphs >= 12
          && toggles >= 2 && errors == 0 && traps == 0 && !top.spi.ovf
          && (expect_led < 0 || led[3:1] == expect_led[2:0]) && (!until_led3 || led3_at >= 0)) $display("RESULT PASS");
      else $display("RESULT FAIL");
      $finish;
    end
  end
endmodule
