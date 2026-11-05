// A behavioural model of the Pmod OLEDrgb (SSD1331), for simulation only. It watches the eight Pmod pins once per
// clock and does what the controller would do with them: shifts SPI bytes in, runs the commands, keeps the 96 x 64
// frame buffer (dump_ppm writes it as an image). Everything a real display would silently get wrong is an ERROR:
//
//   power order (datasheet 7.9)   SPI before the Pmod is powered or out of reset; VCC on before RES# was pulsed;
//                                 display-on (AFh) with VCC off; RES# low shorter than 3 us
//   Digilent's waits              RES# sooner than 20 ms after PMODEN; AFh sooner than 25 ms after VCCEN
//   SPI (7.1.3, timing table)     SCK period under 150 ns; MOSI or D/C# changing on the rising SCK edge itself (no
//                                 setup time); CS# raised in the middle of a byte
//   commands                      an unknown command byte; display data while a command still waits for parameters;
//                                 an address outside 96 x 64
//
// Time: `now` counts core clocks, and the SPI rules use them as 25 ns each (40 MHz, the board's clock). The waits
// (ms, us) use MS_CYCLES clocks per millisecond, so a simulation can scale them down: firmware built with
// -DTICKS_PER_MS=40 waits 40 clocks for "1 ms", and the model is given +ms=40 to match.
`timescale 1ns/1ps
module ssd1331_model (
  input        clk,
  input [63:0] now,
  input        cs,      // pin 1, active low
  input        mosi,    // pin 2
  input        sck,     // pin 4
  input        dc,      // pin 7: 0 command, 1 data
  input        res,     // pin 8, active low
  input        vccen,   // pin 9
  input        pmoden   // pin 10
);
  localparam W = 96, H = 64, SCK_MIN = 6;       // 150 ns at 25 ns per clock
  integer ms = 40000;                           // clocks per millisecond for the waits (+ms=)

  reg [15:0] fb [0:6143];
  reg [7:0]  p  [0:31];                         // parameters of the current command

  integer errors = 0, cmds = 0, rects = 0, clears = 0, data_bytes = 0, glyphs = 0, max_burst = 0, unknown_note = 0;
  reg     display_on = 1'b0, reset_done = 1'b0, fill_en = 1'b0, hi_phase = 1'b0;
  reg [63:0] t_pmoden, t_res_fall, t_vcc, t_on, t_last_rise, t_burst;
  reg     have_rise = 1'b0, res_fell = 1'b0;   // res_fell: RES# went low while powered
  reg     cs_q = 1'b1, sck_q = 1'b0, mosi_q = 1'b0, dc_q = 1'b0, res_q = 1'b0, vccen_q = 1'b0, pmoden_q = 1'b0;
  reg [7:0]  shift = 8'd0, cmd = 8'd0, hi = 8'd0, remap = 8'd0;
  integer nbits = 0, need = 0, idx = 0, burst = 0;
  integer c1 = 0, c2 = W - 1, r1 = 0, r2 = H - 1, col = 0, row = 0;
  integer i, x, y;

  initial begin
    if ($value$plusargs("ms=%d", ms)) ;
    for (i = 0; i < W * H; i = i + 1) fb[i] = 16'h0000;
  end

  task err;
    input [8*96-1:0] msg;
    begin
      errors = errors + 1;
      if (errors <= 12) $display("OLED ERROR cyc=%0d %0s", now, msg);
    end
  endtask

  function integer nparams;                     // parameter bytes after each command, -1 = not an SSD1331 command
    input [7:0] c;
    begin
      case (c)
        8'hAE, 8'hAF, 8'hA4, 8'hA5, 8'hA6, 8'hA7, 8'h2E, 8'h2F, 8'hB9, 8'hAC, 8'hE3: nparams = 0;
        8'hFD, 8'hA0, 8'hA1, 8'hA2, 8'hA8, 8'hAD, 8'hB0, 8'hB1, 8'hB3, 8'hBB, 8'hBE, 8'h87,
        8'h81, 8'h82, 8'h83, 8'h8A, 8'h8B, 8'h8C, 8'h26: nparams = 1;
        8'h15, 8'h75: nparams = 2;
        8'h24, 8'h25: nparams = 4;
        8'h27, 8'hAB: nparams = 5;
        8'h23: nparams = 6;
        8'h21: nparams = 7;
        8'h22: nparams = 10;
        8'hB8: nparams = 32;
        default: nparams = -1;
      endcase
    end
  endfunction

  task check_box;                               // p[0..3] = column 1, row 1, column 2, row 2
    begin
      if (p[0] >= W || p[2] >= W || p[1] >= H || p[3] >= H || p[0] > p[2] || p[1] > p[3]) begin
        err("box outside 96 x 64, or start after end");
        p[0] = 0; p[1] = 0; p[2] = 0; p[3] = 0;
      end
    end
  endtask

  task execute;
    reg [15:0] line, fill;
    begin
      cmds = cmds + 1;
      case (cmd)
        8'hAF: begin
          if (!vccen) err("display on (AFh) while VCC is off: turn VCCEN on first (datasheet 7.9)");
          else if (now - t_vcc < 25 * ms) err("display on (AFh) less than 25 ms after VCCEN: VCC not stable yet");
          display_on = 1'b1; t_on = now;
          $display("OLED cyc=%0d display on", now);
        end
        8'hAE: display_on = 1'b0;
        8'hA0: begin
          remap = p[0];
          if (p[0][7:6] != 2'b01) err("remap A0h: this model only knows 65k colour format 1 (A[7:6] = 01)");
        end
        8'h15: begin
          if (p[0] >= W || p[1] >= W || p[0] > p[1]) err("column window (15h) outside 0..95 or start after end");
          else begin c1 = p[0]; c2 = p[1]; col = c1; end
          hi_phase = 1'b0;
        end
        8'h75: begin
          if (p[0] >= H || p[1] >= H || p[0] > p[1]) err("row window (75h) outside 0..63 or start after end");
          else begin r1 = p[0]; r2 = p[1]; row = r1; end
          hi_phase = 1'b0;
        end
        8'h26: fill_en = p[0][0];
        8'h25: begin
          check_box;
          for (y = p[1]; y <= p[3]; y = y + 1) for (x = p[0]; x <= p[2]; x = x + 1) fb[y * W + x] = 16'h0000;
          clears = clears + 1;
        end
        8'h22: begin
          check_box;
          line = {p[4][5:1], p[5][5:0], p[6][5:1]};   // datasheet 9.1: colour C, B, A; C and A in bits 5:1
          fill = {p[7][5:1], p[8][5:0], p[9][5:1]};
          for (y = p[1]; y <= p[3]; y = y + 1)
            for (x = p[0]; x <= p[2]; x = x + 1)
              if (x == p[0] || x == p[2] || y == p[1] || y == p[3]) fb[y * W + x] = line;
              else if (fill_en) fb[y * W + x] = fill;
          rects = rects + 1;
        end
        8'h21, 8'h23, 8'h24, 8'h27, 8'h2F: begin
          if (!unknown_note) $display("OLED NOTE cyc=%0d command %h is accepted but not drawn by this model", now, cmd);
          unknown_note = 1;
        end
        default: ;                              // configuration only: nothing to show
      endcase
    end
  endtask

  task got_byte;
    input [7:0] b;
    input       is_data;
    begin
      if (!is_data) begin
        if (need > 0) begin
          p[idx] = b; idx = idx + 1; need = need - 1;
          if (need == 0) execute;
        end else begin
          cmd = b; idx = 0; need = nparams(b);
          if (need < 0) begin
            err("not an SSD1331 command byte (is D/C# low for a data byte?)");
            $display("OLED        the byte was %h", b);
            need = 0;
          end else if (need == 0) execute;
        end
      end else begin
        data_bytes = data_bytes + 1; burst = burst + 1;
        if (need > 0) begin
          err("display data while a command still waits for parameters (D/C# high too early?)");
          need = 0;
        end
        if (!hi_phase) begin hi = b; hi_phase = 1'b1; end
        else begin
          fb[row * W + col] = {hi, b}; hi_phase = 1'b0;
          if (col == c2) begin col = c1; row = (row == r2) ? r1 : row + 1; end
          else col = col + 1;
        end
      end
    end
  endtask

  always @(posedge clk) begin
    // ---- supplies and reset
    if (pmoden && !pmoden_q) t_pmoden = now;
    if (!pmoden && pmoden_q) begin reset_done = 1'b0; res_fell = 1'b0; display_on = 1'b0; end
    if (!res && res_q) begin
      if (!pmoden) err("RES# pulsed while the Pmod is unpowered (PMODEN low)");
      else if (now - t_pmoden < 20 * ms) err("RES# low less than 20 ms after PMODEN: VDD has not settled");
      t_res_fall = now; reset_done = 1'b0; res_fell = pmoden;
    end
    if (res && !res_q && res_fell) begin
      if ((now - t_res_fall) * 1000 < 3 * ms) err("RES# low for less than 3 us (datasheet 7.9, t1)");
      reset_done = 1'b1; res_fell = 1'b0;
      need = 0; hi_phase = 1'b0; fill_en = 1'b0; c1 = 0; c2 = W - 1; r1 = 0; r2 = H - 1; col = 0; row = 0;
    end
    if (vccen && !vccen_q) begin
      if (!reset_done) err("VCC on (VCCEN) before the controller was reset: datasheet 7.9 wants RES# first");
      t_vcc = now;
    end

    // ---- SPI
    if (!cs && cs_q) begin nbits = 0; burst = 0; t_burst = now; end
    if (cs && !cs_q) begin
      if (nbits != 0) err("CS# raised in the middle of a byte");
      if (burst > max_burst) max_burst = burst;
      if (burst == 128) glyphs = glyphs + 1;
      if (burst >= 1024)
        $display("OLED BURST cyc=%0d data_bytes=%0d cycles=%0d (%0d per byte; at 40 MHz %0d us)",
                 now, burst, now - t_burst, (now - t_burst) / burst, (now - t_burst) / 40);
      nbits = 0;
    end
    if (sck && !sck_q && !cs) begin
      if (!pmoden || !res || !reset_done) err("SPI clock while the display is unpowered or held in reset");
      if (have_rise && now - t_last_rise < SCK_MIN) err("SCK period under 150 ns (6 clocks at 40 MHz)");
      if (mosi != mosi_q) err("MOSI changed on the rising SCK edge itself: set it while SCK is low");
      if (nbits == 7 && dc != dc_q) err("D/C# changed on the 8th rising SCK edge, where it is sampled");
      t_last_rise = now; have_rise = 1'b1;
      shift = {shift[6:0], mosi};
      nbits = nbits + 1;
      if (nbits == 8) begin got_byte(shift, dc); nbits = 0; end
    end
    cs_q <= cs; sck_q <= sck; mosi_q <= mosi; dc_q <= dc; res_q <= res; vccen_q <= vccen; pmoden_q <= pmoden;
  end

  // the frame buffer as a text PPM (P3), each 5- or 6-bit component widened to 8 bits
  task dump_ppm;
    input [8*256-1:0] file;
    integer fd, k;
    reg [15:0] px;
    begin
      fd = $fopen(file, "w");
      $fwrite(fd, "P3\n%0d %0d\n255\n", W, H);
      for (k = 0; k < W * H; k = k + 1) begin
        px = fb[k];
        $fwrite(fd, "%0d %0d %0d\n", {px[15:11], px[15:13]}, {px[10:5], px[10:9]}, {px[4:0], px[4:2]});
      end
      $fclose(fd);
    end
  endtask
endmodule
