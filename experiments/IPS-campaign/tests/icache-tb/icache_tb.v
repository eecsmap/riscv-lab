// Component tests for tcpu_icache and tcpu_cacheable, before either is wired into the core.
`timescale 1ns/1ps
module icache_tb;
  reg clk = 0; always #5 clk = ~clk;
  reg rst = 1, invalidate = 0, fill = 0;
  reg [31:0] pa = 0, fill_pa = 0;
  reg [127:0] fill_data = 0;
  wire hit; wire [127:0] line_data;

  integer fails = 0, checks = 0;
  task ok_(input [1023:0] w); begin checks=checks+1; $display("  ok   : %0s", w); end endtask
  task no_(input [1023:0] w); begin checks=checks+1; fails=fails+1; $display("  FAIL : %0s", w); end endtask
  task want(input c, input [1023:0] w); begin if (c) ok_(w); else no_(w); end endtask

  tcpu_icache #(.BYTES(1024), .LINE_BYTES(16)) dut (
    .clk(clk), .rst(rst), .invalidate(invalidate), .pa(pa), .hit(hit), .line_data(line_data),
    .fill(fill), .fill_pa(fill_pa), .fill_data(fill_data));

  reg [31:0] dpa = 0; wire dhit;
  tcpu_icache #(.BYTES(0), .LINE_BYTES(16)) dis (
    .clk(clk), .rst(rst), .invalidate(1'b0), .pa(dpa), .hit(dhit), .line_data(),
    .fill(fill), .fill_pa(fill_pa), .fill_data(fill_data));

  reg [31:0] cpa = 0; wire cacheable;
  tcpu_cacheable cc (.pa(cpa), .cacheable(cacheable));

  task do_fill(input [31:0] p, input [127:0] d);
  begin @(negedge clk); fill_pa = p; fill_data = d; fill = 1; @(negedge clk); fill = 0; end endtask
  task do_inv; begin @(negedge clk); invalidate = 1; @(negedge clk); invalidate = 0; end endtask

  initial begin
    repeat (3) @(negedge clk); rst = 0; @(negedge clk);

    $display("== 1. a cold cache hits nothing");
    pa = 32'h8000_0000; #1; want(!hit, "a cold cache misses");

    $display("== 2. a filled line hits anywhere inside itself, and nowhere else");
    do_fill(32'h8000_0000, 128'hDEAD_BEEF_0000_1111_2222_3333_4444_5555);
    pa = 32'h8000_0000; #1; want(hit && line_data == 128'hDEAD_BEEF_0000_1111_2222_3333_4444_5555,
      "the filled line hits with its own data");
    pa = 32'h8000_000F; #1; want(hit, "  the last byte of the same 16-byte line hits");
    pa = 32'h8000_0010; #1; want(!hit, "  the next line misses");

    $display("== 3. direct mapped: 1 KiB apart is the SAME index and evicts");
    do_fill(32'h8000_0400, 128'h1);            // index 0 again, different tag
    pa = 32'h8000_0000; #1; want(!hit, "the line 1 KiB below was evicted by the conflict");
    pa = 32'h8000_0400; #1; want(hit && line_data == 128'h1, "  and the new line is resident");

    $display("== 4. 64 distinct lines live together");
    do_inv;
    begin : fill64
      integer i;
      for (i = 0; i < 64; i = i + 1) do_fill(32'h8000_0000 + (i << 4), {124'd0, i[3:0]});
      for (i = 0; i < 64; i = i + 1) begin
        pa = 32'h8000_0000 + (i << 4); #1;
        if (!hit) begin no_("all 64 lines live together"); disable fill64; end
      end
      ok_("all 64 lines live together (1 KiB / 16 B)");
    end

    $display("== 5. invalidate clears everything in one cycle");
    do_inv;
    pa = 32'h8000_0000; #1; want(!hit, "after invalidate, a previously hitting line misses");
    pa = 32'h8000_01F0; #1; want(!hit, "  and so does another");

    $display("== 6. there is NO WAY to fill half a line");
    // The interface takes the whole 128-bit line in one cycle, so a refill that errored on its second
    // beat simply never asserts fill. This checks the consequence: not filling leaves nothing valid.
    pa = 32'h8000_0800; #1; want(!hit, "a line that was never filled is not valid");
    do_fill(32'h8000_0800, 128'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111);
    pa = 32'h8000_0800; #1; want(hit && line_data[127:64] == 64'hAAAA_BBBB_CCCC_DDDD
                                     && line_data[63:0] == 64'hEEEE_FFFF_0000_1111,
      "and a filled line carries BOTH beats, or it is not filled at all");

    $display("== 7. reset invalidates, so a reloaded image cannot run from stale lines");
    @(negedge clk); rst = 1; @(negedge clk); rst = 0; @(negedge clk);
    pa = 32'h8000_0800; #1; want(!hit, "after reset, nothing is valid");

    $display("== 8. BYTES=0 never hits");
    dpa = 32'h8000_0000; #1; want(!dhit, "a disabled cache misses a line just filled into it");

    $display("== 9. cacheability defaults to NO");
    cpa = 32'h8000_0000; #1; want(cacheable,  "harness RAM at 0x80000000 is cacheable");
    cpa = 32'h1000_0000; #1; want(cacheable,  "the target DRAM window at 0x10000000 is cacheable");
    cpa = 32'h0200_0000; #1; want(!cacheable, "the CLINT msip is NOT cacheable");
    cpa = 32'h0200_BFF8; #1; want(!cacheable, "  nor is mtime -- a cached clock is a stale clock");
    cpa = 32'h0200_FFFF; #1; want(!cacheable, "  nor the last byte of the CLINT window");
    cpa = 32'h6000_0000; #1; want(!cacheable, "an address nobody thought about is NOT cacheable");
    cpa = 32'h0000_0000; #1; want(!cacheable, "  and neither is zero");
    cpa = 32'hFFFF_FFFF; #1; want(!cacheable, "  nor the top of the space");

    $display("ICACHE_TB checks=%0d fails=%0d", checks, fails);
    if (fails != 0) $fatal(1, "ICACHE_TB FAILED");
    $display("ICACHE_TB_OK");
    $finish;
  end
  initial begin #200000; $display("ICACHE_TB TIMEOUT"); $fatal(1, "timeout"); end
endmodule
