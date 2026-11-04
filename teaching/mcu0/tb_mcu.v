// MCU-0 testbench: the board as the firmware sees it. Loads the image, runs, watches the LEDs, presses buttons.
//   +hex=<file> [+delay=<ticks>] [+maxcycles=<n>] [+vcd=<file>] [+need_irq=1]
// PASS needs: LED0 toggled at least 6 times with every interval between DELAY and 1.25*DELAY cycles, the button
// mirror was observed on LED1..3 after a press and cleared after the release, and no bus error ever occurred.
// +need_irq=1 (interrupt-driven firmware) also needs at least one interrupt per toggle and no synchronous trap, and
// checks intervals as DELAY +- 1/8 instead (see the comment at the check).
// Traps are counted from the core's trap port, which mcu_top leaves unconnected: a testbench-only view.
`timescale 1ns/1ps
module tb_mcu;
  reg clk = 1'b0, rst = 1'b1;
  always #5 clk = ~clk;
  reg [3:0] btn = 4'd0; reg [1:0] sw = 2'd0;
  wire [3:0] led; wire commit_valid, bus_error;
  mcu_top top (.clk(clk), .rst(rst), .led(led), .btn(btn), .sw(sw), .commit_valid(commit_valid), .bus_error(bus_error));

  reg [1023:0] hexfile, vcdfile;
  integer delay = 4000, maxcycles = 400000, cycles = 0, toggles = 0, last_toggle = 0, errors = 0, bad_interval = 0;
  integer mirror_seen = 0, clear_seen = 0, phase = 0, need_irq = 0, irqs = 0, syncs = 0;
  reg led0_q = 1'b0;

  initial begin
    if (!$value$plusargs("hex=%s", hexfile)) begin $display("tb_mcu: +hex=<file> is required"); $finish; end
    if ($value$plusargs("delay=%d", delay)) ;
    if ($value$plusargs("maxcycles=%d", maxcycles)) ;
    if ($value$plusargs("need_irq=%d", need_irq)) ;
    $readmemh(hexfile, top.ram.mem);
    if ($value$plusargs("vcd=%s", vcdfile)) begin $dumpfile(vcdfile); $dumpvars(0, tb_mcu); end
    repeat (3) @(posedge clk);
    #1 rst = 1'b0;
  end

  always @(posedge clk) if (!rst) begin
    cycles = cycles + 1;
    if (bus_error) begin errors = errors + 1; $display("BUS ERROR cyc=%0d", cycles); end
    if (top.cpu.trap_valid) begin
      if (top.cpu.trap_interrupt) irqs = irqs + 1;
      else begin syncs = syncs + 1; $display("TRAP cyc=%0d cause=%0d epc=%h (synchronous)", cycles, top.cpu.trap_cause, top.cpu.trap_epc[31:0]); end
    end
    if (led[0] != led0_q) begin
      toggles = toggles + 1;
      $display("LED0 cyc=%0d -> %0d (interval %0d)", cycles, led[0], cycles - last_toggle);
      // polled firmware waits DELAY from "now", so an interval is never shorter; interrupt firmware moves mtimecmp by
      // exactly DELAY, so the deadlines sit on a fixed grid and one interval is DELAY plus or minus the latency jitter
      if (toggles > 1 && (need_irq == 0 ? (cycles - last_toggle < delay || cycles - last_toggle > delay + delay / 4)
                                        : (cycles - last_toggle < delay - delay / 8 || cycles - last_toggle > delay + delay / 8)))
        bad_interval = bad_interval + 1;
      last_toggle = cycles; led0_q = led[0];
    end
    // the button script: press BTN0 and BTN2 after the second toggle, release after the fourth
    if (phase == 0 && toggles == 2) begin btn <= 4'b0101; phase = 1; $display("BTN  cyc=%0d press 0101", cycles); end
    if (phase == 1 && led[3:1] == 3'b101) begin mirror_seen = 1; phase = 2; $display("LED  cyc=%0d mirror seen %b", cycles, led); end
    if (phase == 2 && toggles == 4) begin btn <= 4'b0000; phase = 3; $display("BTN  cyc=%0d release", cycles); end
    if (phase == 3 && led[3:1] == 3'b000) begin clear_seen = 1; phase = 4; $display("LED  cyc=%0d mirror cleared %b", cycles, led); end
    if (toggles >= 6 || cycles >= maxcycles) begin
      $display("SUMMARY cycles=%0d toggles=%0d bad_intervals=%0d mirror=%0d cleared=%0d bus_errors=%0d irqs=%0d sync_traps=%0d",
               cycles, toggles, bad_interval, mirror_seen, clear_seen, errors, irqs, syncs);
      if (toggles >= 6 && bad_interval == 0 && mirror_seen && clear_seen && errors == 0
          && (need_irq == 0 || (irqs >= toggles && syncs == 0))) $display("RESULT PASS");
      else $display("RESULT FAIL");
      $finish;
    end
  end
endmodule
