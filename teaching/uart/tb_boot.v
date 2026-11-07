// Bootloader testbench: mcu_top running uart_boot, a model of the PC on the two wires, and mcu_break between the RX
// wire and the reset, as on the board.
//   +hex=<bootloader> +pay=<program, one byte per line> +pay_len=<n> +pay_crc=<crc32, hex>
//   [+div=<ours>] [+pc_div=<the PC's>] [+maxcycles=<n>] [+vcd=<file>]
// The script, each step started by what came back:
//   1. at the first "boot> ": a header for 0x8000_0000 (over the bootloader itself) -- the answer must be 'R'
//   2. at the second: the program for 0x8000_1000, its bytes, its CRC -- the answers must be 'A', then 'K'
//   3. at the third: 'G' -- the answer must be 'G', then the program (uart_echo) must start: at its prompt the PC types
//      "hi" + CR and must get "HI (2 chars)" back
//   4. a break: RX low for 3 x LIMIT clocks -- mcu_break must reset the MCU once, and the bootloader's prompt must come
//      back exactly once more (4 in all, counted after a quiet wait)
// The PC sends back to back and 3 percent slow, as in tb_uart. PASS needs every answer right, the program's echo,
// exactly 4 prompts, exactly one reset pulse from mcu_break, no framing error, no bus error, no synchronous trap.
`timescale 1ns/1ps
module tb_boot;
  localparam LIMIT = 20000;                     // break length for this simulation (the board: 2^20 clocks)
  reg clk = 1'b0, rst0 = 1'b1;
  always #5 clk = ~clk;
  wire [3:0] led; wire commit_valid, bus_error, utx, brk;
  reg urx = 1'b1;
  wire rst = rst0 | brk;
  mcu_break #(.LIMIT(LIMIT)) brkdet (.clk(clk), .rx(urx), .brk(brk));
  mcu_top top (.clk(clk), .rst(rst), .led(led), .btn(4'd0), .sw(2'd0), .joy_sw(1'b0), .xadc_drdy(1'b0), .xadc_do(16'd0),
               .xadc_eos(1'b0), .a0_dig(1'b0), .uart_rx(urx), .uart_tx(utx), .commit_valid(commit_valid), .bus_error(bus_error));

  reg [1023:0] hexfile, payfile, vcdfile;
  integer maxcycles = 6000000, div = 120, pc_div = 124, cycles = 0, errors = 0, syncs = 0, fails = 0;
  integer pay_len = 0, pay_crc = 0, i;
  reg [7:0] pay [0:65535];

  initial begin
    if (!$value$plusargs("hex=%s", hexfile) || !$value$plusargs("pay=%s", payfile) ||
        !$value$plusargs("pay_len=%d", pay_len) || !$value$plusargs("pay_crc=%h", pay_crc)) begin
      $display("tb_boot: +hex, +pay, +pay_len and +pay_crc are required"); $finish;
    end
    if ($value$plusargs("maxcycles=%d", maxcycles)) ;
    if ($value$plusargs("div=%d", div)) ;
    if ($value$plusargs("pc_div=%d", pc_div)) ;
    $readmemh(hexfile, top.ram.mem);
    $readmemh(payfile, pay, 0, pay_len - 1);
    if ($value$plusargs("vcd=%s", vcdfile)) begin $dumpfile(vcdfile); $dumpvars(0, tb_boot); end
    repeat (3) @(posedge clk);
    #1 rst0 = 1'b0;
  end

  // ---- the PC receives (as in tb_uart): every byte goes into `win`, the last 24 bytes
  reg tx_q = 1'b1, rbusy = 1'b0;
  integer rcnt = 0, rbitn = 0, ngot = 0, ferrs = 0, prompts = 0, echo_banners = 0, echo_ok = 0;
  integer expect_at = -1, answers = 0;          // answers: how many expected answers have arrived
  reg [7:0] rbyte = 8'd0, expect_code = 8'd0;
  reg [8*24-1:0] win = 0;
  always @(posedge clk) begin
    if (!rbusy) begin
      if (tx_q && !utx) begin rbusy = 1'b1; rcnt = div / 2; rbitn = 0; end
    end else begin
      rcnt = rcnt - 1;
      if (rcnt == 0) begin
        rcnt = div;
        if (rbitn == 0) begin
          if (utx) rbusy = 1'b0; else rbitn = 1;
        end else if (rbitn <= 8) begin
          rbyte = {utx, rbyte[7:1]}; rbitn = rbitn + 1;
        end else begin
          rbusy = 1'b0;
          if (!utx) begin ferrs = ferrs + 1; $display("FRAME ERROR cyc=%0d", cycles); end
          else begin
            if (ngot == expect_at) begin
              if (rbyte != expect_code) begin
                fails = fails + 1; $display("\nWRONG ANSWER cyc=%0d: got '%c' (%h), expected '%c'", cycles, rbyte, rbyte, expect_code);
              end else begin answers = answers + 1; $display("\nANSWER cyc=%0d '%c' as expected", cycles, rbyte); end
              expect_at = -1;
            end
            ngot = ngot + 1;
            win = {win[8*23-1:0], rbyte};
            if (rbyte == 8'h0A) $write("\n"); else if (rbyte != 8'h0D) $write("%c", rbyte);
            if (win[8*6-1:0] == "boot> ") prompts = prompts + 1;
            if (win[8*9-1:0] == "line.\015\012> ") echo_banners = echo_banners + 1;
            if (win[8*16-1:0] == "HI (2 chars)\015\012> ") echo_ok = echo_ok + 1;
          end
        end
      end
    end
    tx_q = utx;
  end

  // ---- the PC sends: a queue of bytes, back to back; or a break
  reg [7:0] q [0:70000];
  integer qh = 0, qt = 0, scnt = 0, sbit = 0, brk_left = 0;
  reg sbusy = 1'b0;
  reg [9:0] sframe;
  task push; input [7:0] b; begin q[qt] = b; qt = qt + 1; end endtask
  task push32; input [31:0] w; begin push(w[7:0]); push(w[15:8]); push(w[23:16]); push(w[31:24]); end endtask
  always @(posedge clk) if (!rst0) begin
    if (brk_left > 0) begin
      urx <= 1'b0; brk_left = brk_left - 1;
      if (brk_left == 0) urx <= 1'b1;
    end else if (sbusy) begin
      scnt = scnt - 1;
      if (scnt == 0) begin
        sbit = sbit + 1; scnt = pc_div;
        if (sbit == 10) sbusy = 1'b0; else urx <= sframe[sbit];
      end
    end
    if (!sbusy && brk_left == 0 && qh != qt) begin     // the next start bit straight away
      sframe = {1'b1, q[qh], 1'b0}; qh = qh + 1;
      sbusy = 1'b1; sbit = 0; scnt = pc_div; urx <= 1'b0;
    end
  end

  // ---- the script
  integer stage = 0, quiet_until = 0;
  always @(posedge clk) if (!rst0) begin
    if (stage == 0 && prompts == 1) begin
      $display("\nPC   cyc=%0d header for 80000000 (over the bootloader): must be refused", cycles);
      push("L"); push32(32'h8000_0000); push32(16); expect_at = ngot; expect_code = "R"; stage = 1;
    end
    if (stage == 1 && prompts == 2) begin
      $display("\nPC   cyc=%0d loads %0d bytes at 80001000, crc %h", cycles, pay_len, pay_crc);
      push("L"); push32(32'h8000_1000); push32(pay_len); expect_at = ngot; expect_code = "A"; stage = 2;
    end
    if (stage == 2 && answers == 2) begin               // the 'A' is in: send the bytes and the CRC
      for (i = 0; i < pay_len; i = i + 1) push(pay[i]);
      push32(pay_crc); expect_at = ngot; expect_code = "K"; stage = 3;
    end
    if (stage == 3 && prompts == 3) begin
      $display("\nPC   cyc=%0d go", cycles);
      push("G"); expect_at = ngot; expect_code = "G"; stage = 4;
    end
    if (stage == 4 && echo_banners == 1) begin
      $display("\nPC   cyc=%0d the program runs: types hi", cycles);
      push("h"); push("i"); push(8'h0D); stage = 5;
    end
    if (stage == 5 && echo_ok == 1) begin
      $display("\nPC   cyc=%0d break: RX low for %0d clocks", cycles, 3 * LIMIT);
      brk_left = 3 * LIMIT; stage = 6;
    end
    if (stage == 6 && prompts == 4) begin quiet_until = cycles + 6 * LIMIT; stage = 7; end
  end

  integer resets = 0;
  reg brk_q = 1'b0;
  always @(posedge clk) begin
    if (brk && !brk_q) begin resets = resets + 1; $display("\nRESET cyc=%0d from the break detector", cycles); end
    brk_q = brk;
  end
  always @(posedge clk) if (!rst) begin
    if (bus_error) begin errors = errors + 1; $display("BUS ERROR cyc=%0d", cycles); end
    if (top.cpu.trap_valid && !top.cpu.trap_interrupt) begin
      syncs = syncs + 1; $display("TRAP cyc=%0d cause=%0d epc=%h (synchronous)", cycles, top.cpu.trap_cause, top.cpu.trap_epc[31:0]);
    end
  end
  always @(posedge clk) if (!rst0) begin
    cycles = cycles + 1;
    if ((stage == 7 && cycles >= quiet_until) || cycles >= maxcycles) begin
      $display("\nSUMMARY cycles=%0d stage=%0d prompts=%0d wrong_answers=%0d echo_banners=%0d echo_ok=%0d resets=%0d frame_errors=%0d bus_errors=%0d sync_traps=%0d",
               cycles, stage, prompts, fails, echo_banners, echo_ok, resets, ferrs, errors, syncs);
      if (stage == 7 && prompts == 4 && fails == 0 && echo_banners == 1 && echo_ok == 1 && resets == 1 && ferrs == 0 && errors == 0 && syncs == 0)
        $display("RESULT PASS");
      else $display("RESULT FAIL");
      $finish;
    end
  end
endmodule
