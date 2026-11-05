// VGA testbench: MCU-0 (mcu_top) watched by a "monitor" on its VGA outputs.
//   +hex=<file> +font=<font_rom.hex> [+frames=<n>] [+vblank_only=0] [+maxcycles=<n>] [+ppm=<file>] [+sw=<SW1:0>] [+expect_led=<LED2..1>]
//   [+vcd=<file>]
// The monitor locks onto the first VSYNC and from then on knows where the beam must be. Every clock it checks:
//   - HSYNC high exactly in columns 840..967 of each 1056-clock line, VSYNC high exactly for 4 lines of each 628
//   - black outside the 800 x 600 visible area
//   - inside it, the colour this testbench works out by itself from the text RAM, the scroll register, the font
//     (font_rom.hex, from the same font8x8.h) and its own copy of the palette -- so a pipeline stage too few or too
//     many, a swapped colour or a wrong row/column calculation shows up as a mismatch at an exact pixel
// It starts judging pixels at the first frame after LED1 lights (the firmware has drawn its screen) and checks
// `frames` whole frames (default 2). From then on the firmware promises to change the screen only in the vertical
// blank: every store into the text RAM or the scroll register while the beam is on lines 0..599 is a "late store"
// (+vblank_only=0 turns that rule off, for an app that does not make the promise).
// PASS needs: no sync error, no pixel mismatch, no late store, the frames checked, LED0 toggling (the per-frame loop
// runs), no bus error, no synchronous trap, and LED2..1 = expect_led (default 1: drawn, not scrolling).
`timescale 1ns/1ps
module tb_vga;
  localparam LINE = 1056, LINES = 628, H_SYNC0 = 840, H_SYNC1 = 968, V_FIRST = 601;   // VSYNC rises at the start of line 601
  reg clk = 1'b0, rst = 1'b1;
  always #5 clk = ~clk;
  reg [3:0] btn = 4'd0; reg [1:0] sw = 2'd0;
  wire [3:0] led, vr, vg, vb; wire [7:0] jb; wire hs, vs, commit_valid, bus_error;
  reg [63:0] cycles = 64'd0;

  mcu_top top (.clk(clk), .rst(rst), .led(led), .jb(jb), .vga_r(vr), .vga_g(vg), .vga_b(vb), .vga_hs(hs), .vga_vs(vs),
               .btn(btn), .sw(sw), .commit_valid(commit_valid), .bus_error(bus_error));

  reg [7:0]  font [0:2047];
  reg [11:0] shot [0:479999];             // the first frame checked, for the picture
  reg [1023:0] hexfile, fontfile, ppmfile, vcdfile;
  integer frames = 2, vblank_only = 1, late = 0, maxcycles = 8000000, swset = 0, expect_led = 1;
  integer locked_at = -1, last_vs = -1, judging = 0, checked = 0, sync_err = 0, pix_err = 0, errors = 0, traps = 0,
          toggles = 0, t, ln, col, vline, srow, cell_i, fd, i;
  reg vs_q = 1'b0, led0_q = 1'b0, have_ppm = 1'b0, shooting = 1'b0;
  reg [63:0] word; reg [15:0] c; reg [7:0] glyph; reg [3:0] idx; reg [11:0] want, got;

  function [11:0] palette(input [3:0] k);   // the colours as the README lists them, written out independently
    case (k)
      0: palette = 12'h000;  1: palette = 12'h00A;  2: palette = 12'h0A0;  3: palette = 12'h0AA;
      4: palette = 12'hA00;  5: palette = 12'hA0A;  6: palette = 12'hA50;  7: palette = 12'hAAA;
      8: palette = 12'h555;  9: palette = 12'h55F; 10: palette = 12'h5F5; 11: palette = 12'h5FF;
      12: palette = 12'hF55; 13: palette = 12'hF5F; 14: palette = 12'hFF5; default: palette = 12'hFFF;
    endcase
  endfunction

  initial begin
    if (!$value$plusargs("hex=%s", hexfile) || !$value$plusargs("font=%s", fontfile)) begin
      $display("tb_vga: +hex=<file> and +font=<file> are required"); $finish;
    end
    if ($value$plusargs("frames=%d", frames)) ;
    if ($value$plusargs("vblank_only=%d", vblank_only)) ;
    if ($value$plusargs("maxcycles=%d", maxcycles)) ;
    if ($value$plusargs("sw=%d", swset)) sw = swset;
    if ($value$plusargs("expect_led=%d", expect_led)) ;
    if ($value$plusargs("ppm=%s", ppmfile)) have_ppm = 1'b1;
    $readmemh(fontfile, font);
    $readmemh(hexfile, top.ram.mem);
    if ($value$plusargs("vcd=%s", vcdfile)) begin $dumpfile(vcdfile); $dumpvars(0, tb_vga); end
    repeat (3) @(posedge clk);
    #1 rst = 1'b0;
  end

  always @(posedge clk) if (!rst) begin
    cycles = cycles + 1;
    if (bus_error) begin errors = errors + 1; $display("BUS ERROR cyc=%0d", cycles); end
    if (top.cpu.trap_valid && !top.cpu.trap_interrupt) begin
      traps = traps + 1;
      $display("TRAP cyc=%0d cause=%0d epc=%h", cycles, top.cpu.trap_cause, top.cpu.trap_epc[31:0]);
    end
    if (led[0] != led0_q) begin toggles = toggles + 1; led0_q = led[0]; end
    if (judging && vblank_only && top.vga.sel && top.vga.we && top.vga.vc < 600) begin
      late = late + 1;
      if (late <= 5) $display("LATE STORE cyc=%0d: the CPU wrote %h while the beam was on line %0d", cycles, top.vga.addr, top.vga.vc);
    end

    // ---- VSYNC: lock on, check the frame length, count the frames judged
    if (vs && !vs_q) begin
      if (last_vs >= 0 && cycles - last_vs != LINE * LINES) begin
        sync_err = sync_err + 1; $display("SYNC ERROR cyc=%0d: frame of %0d clocks, not %0d", cycles, cycles - last_vs, LINE * LINES);
      end
      if (locked_at < 0) $display("VGA  cyc=%0d locked on VSYNC", cycles);
      last_vs = cycles; locked_at = cycles;
      if (judging) begin checked = checked + 1; shooting = 1'b0; end
      if (!judging && led[1]) begin judging = 1; shooting = have_ppm; $display("VGA  cyc=%0d judging from this frame (LEDs %b)", cycles, led); end
    end
    vs_q = vs;

    // ---- where the beam must be, and what it must show
    if (locked_at >= 0) begin
      t = cycles - locked_at; ln = t / LINE; col = t - ln * LINE;
      vline = (ln + V_FIRST) % LINES;
      if (ln >= LINES) begin
        sync_err = sync_err + 1; locked_at = -1;
        $display("SYNC ERROR cyc=%0d: no VSYNC for a whole frame", cycles);
      end else begin
        if (hs != (col >= H_SYNC0 && col < H_SYNC1) || vs != (ln < 4)) begin
          sync_err = sync_err + 1;
          if (sync_err <= 5) $display("SYNC ERROR cyc=%0d line %0d column %0d: hs=%b vs=%b", cycles, vline, col, hs, vs);
        end
        got = {vr, vg, vb};
        if (vline < 600 && col < 800) begin
          srow = (vline >> 3) + top.vga.top; if (srow >= 75) srow = srow - 75;
          cell_i = srow * 100 + (col >> 3);
          word = top.vga.tmem[cell_i >> 2];
          c = word >> ((cell_i & 3) * 16);
          glyph = font[{c[7:0], vline[2:0]}];
          idx = glyph[7 - (col & 7)] ? c[11:8] : c[15:12];
          want = palette(idx);
          if (shooting) shot[vline * 800 + col] = got;
        end else want = 12'h000;
        if (judging && got !== want) begin
          pix_err = pix_err + 1;
          if (pix_err <= 5) $display("PIXEL ERROR cyc=%0d at x=%0d y=%0d: got %h, want %h", cycles, col, vline, got, want);
        end
      end
    end

    if (checked >= frames || cycles >= maxcycles || traps > 0) begin
      $display("SUMMARY cycles=%0d frames_checked=%0d sync_errors=%0d pixel_errors=%0d late_stores=%0d heartbeat=%0d leds=%b scroll=%0d bus_errors=%0d traps=%0d",
               cycles, checked, sync_err, pix_err, late, toggles, led, top.vga.top, errors, traps);
      if (have_ppm && checked > 0) begin
        fd = $fopen(ppmfile, "w");
        $fwrite(fd, "P3\n800 600\n15\n");
        for (i = 0; i < 480000; i = i + 1) $fwrite(fd, "%0d %0d %0d\n", shot[i][11:8], shot[i][7:4], shot[i][3:0]);
        $fclose(fd);
      end
      if (checked >= frames && sync_err == 0 && pix_err == 0 && late == 0 && toggles >= 2 && errors == 0 && traps == 0
          && led[2:1] == expect_led[1:0]) $display("RESULT PASS");
      else $display("RESULT FAIL");
      $finish;
    end
  end
endmodule
