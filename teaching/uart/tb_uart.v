// UART testbench: mcu_top running a uart_* app, with a model of the PC on the other end of the two wires.
//   +hex=<file> [+maxcycles=<n>] [+div=<clocks per bit, ours>] [+pc_div=<clocks per bit, the PC's>] [+vcd=<file>]
// The PC model decodes everything on uart_tx (sampling in the middle of each bit, checking every stop bit) and, after
// the first prompt "> ", types MSG1 into uart_rx; after the second prompt, MSG2. Its bytes are back to back (the next
// start bit right after a stop bit) and, by default, 3 percent slower than ours (358 clocks a bit against 347): a
// receiver that samples at the edges of the bits instead of the middle gets them wrong.
// It waits 4 byte-times after the last prompt, so that anything extra after it (a second line end) is caught too.
// PASS needs: exactly the expected text came back, no framing error on the wire, no bus error, no synchronous trap,
// and the firmware's LEDs at the end: LED3 (a line was received) on, LED2 (a receive error) off.
`timescale 1ns/1ps
module tb_uart;
  reg clk = 1'b0, rst = 1'b1;
  always #5 clk = ~clk;
  wire [3:0] led; wire commit_valid, bus_error, utx;
  reg urx = 1'b1;
  mcu_top top (.clk(clk), .rst(rst), .led(led), .btn(4'd0), .sw(2'd0), .joy_sw(1'b0), .xadc_drdy(1'b0), .xadc_do(16'd0),
               .xadc_eos(1'b0), .a0_dig(1'b0), .uart_rx(urx), .uart_tx(utx), .commit_valid(commit_valid), .bus_error(bus_error));

  // what uart_echo must send back, in order (\015 = CR, \012 = LF), and what the PC types
  localparam EXP_N = 118;
  localparam [8*EXP_N-1:0] EXP =
    "\015\012MCU-0 UART ready. Type; it comes back in upper case. Enter ends a line.\015\012> HELLO, MCU (10 chars)\015\012> AB (2 chars)\015\012> ";
  localparam M1_N = 11, M2_N = 4;
  localparam [8*M1_N-1:0] MSG1 = "hello, mcu\015";   // Enter as CR, like most terminals
  localparam [8*M2_N-1:0] MSG2 = "ab\015\012";       // Enter as CR LF: must count as one line end, not two

  reg [1023:0] hexfile, vcdfile;
  integer maxcycles = 2000000, div = 347, pc_div = 358, cycles = 0, errors = 0, syncs = 0;
  reg [7:0] got [0:4095];
  integer ngot = 0, prompts = 0, ferrs = 0, glitches = 0, i, bad = 0, done_at = 0;

  initial begin
    if (!$value$plusargs("hex=%s", hexfile)) begin $display("tb_uart: +hex=<file> is required"); $finish; end
    if ($value$plusargs("maxcycles=%d", maxcycles)) ;
    if ($value$plusargs("div=%d", div)) ;
    if ($value$plusargs("pc_div=%d", pc_div)) ;
    $readmemh(hexfile, top.ram.mem);
    if ($value$plusargs("vcd=%s", vcdfile)) begin $dumpfile(vcdfile); $dumpvars(0, tb_uart); end
    repeat (3) @(posedge clk);
    #1 rst = 1'b0;
  end

  // ---- the PC receives: decode uart_tx, sampling in the middle of each bit
  reg tx_q = 1'b1, rbusy = 1'b0;
  integer rcnt = 0, rbitn = 0;
  reg [7:0] rbyte = 8'd0;
  always @(posedge clk) if (!rst) begin
    if (!rbusy) begin
      if (tx_q && !utx) begin rbusy = 1'b1; rcnt = div / 2; rbitn = 0; end
    end else begin
      rcnt = rcnt - 1;
      if (rcnt == 0) begin
        rcnt = div;
        if (rbitn == 0) begin
          if (utx) begin rbusy = 1'b0; glitches = glitches + 1; end else rbitn = 1;
        end else if (rbitn <= 8) begin
          rbyte = {utx, rbyte[7:1]}; rbitn = rbitn + 1;
        end else begin
          rbusy = 1'b0;
          if (!utx) begin ferrs = ferrs + 1; $display("FRAME ERROR cyc=%0d (stop bit low)", cycles); end
          else begin
            if (ngot < 4096) got[ngot] = rbyte;
            ngot = ngot + 1;
            if (rbyte == 8'h0A) $write("\n"); else if (rbyte != 8'h0D) $write("%c", rbyte);
            if (rbyte == ">") prompts = prompts + 1;
          end
        end
      end
    end
    tx_q = utx;
  end

  // ---- the PC sends: MSG1 after the first prompt, MSG2 after the second, back to back
  integer sidx = 0, scnt = 0, sbit = 0, stage = 0;   // 1: sending MSG1, 2: waiting, 3: sending MSG2, 4: done
  reg sbusy = 1'b0;
  reg [9:0] sframe;                                   // stop bit, 8 data bits, start bit: sent from bit 0 up
  always @(posedge clk) if (!rst) begin
    if (stage == 0 && prompts == 1) begin stage = 1; sidx = 0; $display("\nPC   cyc=%0d sends MSG1 (pc_div=%0d)", cycles, pc_div); end
    if (stage == 2 && prompts == 2) begin stage = 3; sidx = 0; $display("\nPC   cyc=%0d sends MSG2", cycles); end
    if (!sbusy && (stage == 1 || stage == 3)) begin
      sframe = {1'b1, (stage == 1) ? MSG1[8*(M1_N-1-sidx) +: 8] : MSG2[8*(M2_N-1-sidx) +: 8], 1'b0};
      sbusy = 1'b1; sbit = 0; scnt = pc_div; urx <= sframe[0];
    end else if (sbusy) begin
      scnt = scnt - 1;
      if (scnt == 0) begin
        sbit = sbit + 1; scnt = pc_div;
        if (sbit == 10) begin
          sbusy = 1'b0; sidx = sidx + 1;
          if (stage == 1 && sidx == M1_N) stage = 2;
          if (stage == 3 && sidx == M2_N) stage = 4;
          if (stage == 1 || stage == 3) begin   // the next start bit straight away
            sframe = {1'b1, (stage == 1) ? MSG1[8*(M1_N-1-sidx) +: 8] : MSG2[8*(M2_N-1-sidx) +: 8], 1'b0};
            sbusy = 1'b1; sbit = 0; urx <= sframe[0];
          end
        end else urx <= sframe[sbit];
      end
    end
  end

  always @(posedge clk) if (!rst) begin
    cycles = cycles + 1;
    if (bus_error) begin errors = errors + 1; $display("BUS ERROR cyc=%0d", cycles); end
    if (top.cpu.trap_valid && !top.cpu.trap_interrupt) begin
      syncs = syncs + 1; $display("TRAP cyc=%0d cause=%0d epc=%h (synchronous)", cycles, top.cpu.trap_cause, top.cpu.trap_epc[31:0]);
    end
    if (stage == 4 && prompts == 3 && done_at == 0) done_at = cycles;
    if ((done_at != 0 && cycles >= done_at + 40 * div) || cycles >= maxcycles) begin
      bad = 0;
      for (i = 0; i < EXP_N && i < ngot; i = i + 1)
        if (got[i] != EXP[8*(EXP_N-1-i) +: 8]) begin
          if (!bad) $display("\nMISMATCH at byte %0d: got %h, expected %h", i, got[i], EXP[8*(EXP_N-1-i) +: 8]);
          bad = 1;
        end
      if (ngot != EXP_N) begin $display("\nLENGTH received %0d bytes, expected %0d", ngot, EXP_N); bad = 1; end
      $display("\nSUMMARY cycles=%0d received=%0d expected=%0d mismatch=%0d frame_errors=%0d glitches=%0d bus_errors=%0d sync_traps=%0d leds=%b",
               cycles, ngot, EXP_N, bad, ferrs, glitches, errors, syncs, led);
      if (!bad && ferrs == 0 && glitches == 0 && errors == 0 && syncs == 0 && led[3] && !led[2]) $display("RESULT PASS");
      else $display("RESULT FAIL");
      $finish;
    end
  end
endmodule
