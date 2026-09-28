// Component tests for tcpu_tlb and tcpu_permcheck, before either is wired into the core.
//
// Every case states what it expects and why. The bench exits non-zero if any expectation is unmet, so
// a mutant of either module fails the run rather than merely changing a number nobody reads.
`timescale 1ns/1ps
module tlb_tb;
  reg clk = 0; always #5 clk = ~clk;
  reg rst = 1, flush = 0, fill = 0;
  reg [63:0] va = 0, fill_va = 0;
  reg [1:0] fill_level = 0;
  reg [43:0] fill_ppn = 0;
  reg fill_r=0, fill_w=0, fill_x=0, fill_u=0, fill_a=0, fill_d=0;
  wire hit, hit_r, hit_w, hit_x, hit_u, hit_a, hit_d;
  wire [43:0] hit_ppn; wire [1:0] hit_level;

  integer fails = 0, checks = 0;
  task ok_(input [1023:0] what); begin checks=checks+1; $display("  ok   : %0s", what); end endtask
  task no_(input [1023:0] what); begin checks=checks+1; fails=fails+1; $display("  FAIL : %0s", what); end endtask
  task want(input cond, input [1023:0] what); begin if (cond) ok_(what); else no_(what); end endtask

  tcpu_tlb #(.ENTRIES(8)) dut (
    .clk(clk), .rst(rst), .flush(flush), .va(va),
    .hit(hit), .hit_ppn(hit_ppn), .hit_level(hit_level),
    .hit_r(hit_r), .hit_w(hit_w), .hit_x(hit_x), .hit_u(hit_u), .hit_a(hit_a), .hit_d(hit_d),
    .fill(fill), .fill_va(fill_va), .fill_level(fill_level), .fill_ppn(fill_ppn),
    .fill_r(fill_r), .fill_w(fill_w), .fill_x(fill_x), .fill_u(fill_u), .fill_a(fill_a), .fill_d(fill_d));

  // a disabled instance: must never hit, whatever it is told
  reg [63:0] dva = 0;
  wire dhit;
  tcpu_tlb #(.ENTRIES(0)) dis (
    .clk(clk), .rst(rst), .flush(1'b0), .va(dva), .hit(dhit),
    .hit_ppn(), .hit_level(), .hit_r(), .hit_w(), .hit_x(), .hit_u(), .hit_a(), .hit_d(),
    .fill(fill), .fill_va(fill_va), .fill_level(fill_level), .fill_ppn(fill_ppn),
    .fill_r(fill_r), .fill_w(fill_w), .fill_x(fill_x), .fill_u(fill_u), .fill_a(fill_a), .fill_d(fill_d));

  // permission check, driven directly
  reg [1:0] p_type = 0, p_priv = 0; reg p_sum = 0, p_mxr = 0;
  reg p_r=0, p_w=0, p_x=0, p_u=0, p_a=0, p_d=0;
  wire p_ok;
  tcpu_permcheck pc (.acc_type(p_type), .eff_priv(p_priv), .sum(p_sum), .mxr(p_mxr),
                     .pte_r(p_r), .pte_w(p_w), .pte_x(p_x), .pte_u(p_u), .pte_a(p_a), .pte_d(p_d),
                     .ok(p_ok));

  task do_fill(input [63:0] v_, input [1:0] lv, input [43:0] pp,
               input r_, input w_, input x_, input u_, input a_, input d_);
  begin
    @(negedge clk);
    fill_va = v_; fill_level = lv; fill_ppn = pp;
    fill_r = r_; fill_w = w_; fill_x = x_; fill_u = u_; fill_a = a_; fill_d = d_;
    fill = 1; @(negedge clk); fill = 0;
  end endtask

  task do_flush; begin @(negedge clk); flush = 1; @(negedge clk); flush = 0; end endtask

  integer i;
  initial begin
    repeat (3) @(negedge clk); rst = 0; @(negedge clk);

    $display("== 1. an empty TLB hits nothing");
    va = 64'h0000_0000_0001_0000; #1;
    want(!hit, "a cold TLB misses");

    $display("== 2. a 4 KiB entry hits its own page and nothing else");
    do_fill(64'h0000_0000_0001_0000, 2'd0, 44'h00ABC, 1,1,0,0,1,1);
    va = 64'h0000_0000_0001_0000; #1; want(hit && hit_ppn == 44'h00ABC && hit_level == 2'd0,
      "the filled 4 KiB page hits with its own ppn and level");
    va = 64'h0000_0000_0001_0FFF; #1; want(hit, "  and anywhere inside the same 4 KiB page hits");
    va = 64'h0000_0000_0001_1000; #1; want(!hit, "  and the NEXT 4 KiB page misses");

    $display("== 3. the permission BITS come back, not a verdict");
    va = 64'h0000_0000_0001_0000; #1;
    want(hit_r && hit_w && !hit_x && !hit_u && hit_a && hit_d,
      "r,w,x,u,a,d are returned exactly as filled");

    $display("== 4. a 2 MiB superpage matches any 4 KiB page inside it, and nothing outside");
    do_flush;
    do_fill(64'h0000_0000_0040_0000, 2'd1, 44'h00200, 1,0,1,0,1,0);
    va = 64'h0000_0000_0040_0000; #1; want(hit && hit_level == 2'd1, "the superpage's own base hits");
    va = 64'h0000_0000_0055_5000; #1; want(hit, "  a 4 KiB page 1.3 MiB inside it hits the SAME entry");
    va = 64'h0000_0000_003F_F000; #1; want(!hit, "  the page just below it misses");
    va = 64'h0000_0000_0060_0000; #1; want(!hit, "  the page just above it misses");

    $display("== 5. a 1 GiB superpage");
    do_flush;
    do_fill(64'h0000_0000_4000_0000, 2'd2, 44'h40000, 1,1,0,0,1,1);
    va = 64'h0000_0000_7FFF_F000; #1; want(hit && hit_level == 2'd2, "an address 1 GiB-1 page in hits");
    va = 64'h0000_0000_8000_0000; #1; want(!hit, "  and the next gigabyte misses");

    $display("== 6. flush clears everything, in one cycle");
    do_flush;
    va = 64'h0000_0000_4000_0000; #1; want(!hit, "after flush, a previously hitting address misses");

    $display("== 7. round-robin: 8 entries live together, the 9th evicts the FIRST");
    do_flush;
    for (i = 0; i < 8; i = i + 1)
      do_fill(64'h0000_0000_0010_0000 + (i << 12), 2'd0, 44'h01000 + i[43:0], 1,1,0,0,1,1);
    for (i = 0; i < 8; i = i + 1) begin
      va = 64'h0000_0000_0010_0000 + (i << 12); #1;
      if (!hit || hit_ppn != 44'h01000 + i[43:0]) no_("all eight entries live together");
    end
    ok_("all eight entries live together");
    do_fill(64'h0000_0000_0020_0000, 2'd0, 44'h02000, 1,1,0,0,1,1);
    va = 64'h0000_0000_0010_0000; #1; want(!hit, "the ninth fill evicted the FIRST entry, not a random one");
    va = 64'h0000_0000_0010_1000; #1; want(hit, "  and the second entry is still there");
    va = 64'h0000_0000_0020_0000; #1; want(hit && hit_ppn == 44'h02000, "  and the ninth is resident");

    $display("== 8. ENTRIES=0 never hits, however it is filled");
    dva = 64'h0000_0000_0010_0000; #1;
    want(!dhit, "a disabled TLB misses an address that was just filled into it");

    $display("== 9. the permission check, which a hit must re-run every time");
    // fetch on an X page from S
    p_type=0; p_priv=1; p_sum=0; p_mxr=0; p_r=0;p_w=0;p_x=1;p_u=0;p_a=1;p_d=0; #1;
    want(p_ok, "S fetch on a supervisor X page: allowed");
    p_u=1; #1; want(!p_ok, "  the SAME page with U=1: refused, and SUM does not help a fetch");
    p_sum=1; #1; want(!p_ok, "  still refused with SUM=1: S never executes a U page");
    // load
    p_type=1; p_sum=0; p_r=1; p_x=0; p_u=0; #1; want(p_ok, "S load on an R page: allowed");
    p_u=1; #1; want(!p_ok, "  U page without SUM: refused");
    p_sum=1; #1; want(p_ok, "  U page WITH SUM: allowed");
    // MXR
    p_sum=0; p_u=0; p_r=0; p_x=1; #1; want(!p_ok, "load on an X-only page without MXR: refused");
    p_mxr=1; #1; want(p_ok, "  with MXR: allowed");
    // A/D
    p_mxr=0; p_r=1; p_x=0; p_type=2; p_w=1; p_a=1; p_d=1; #1; want(p_ok, "store with A and D: allowed");
    p_d=0; #1; want(!p_ok, "  store with D=0: REFUSED -- A/D are software-managed, not repaired");
    p_d=1; p_a=0; #1; want(!p_ok, "  store with A=0: refused");
    p_type=1; p_a=0; #1; want(!p_ok, "load with A=0: refused");
    // AMO needs R and W together, and MXR must not help it
    p_a=1; p_d=1; p_type=3; p_r=1; p_w=1; #1; want(p_ok, "AMO with R and W: allowed");
    p_r=0; p_x=1; p_mxr=1; #1; want(!p_ok, "  AMO on an X page with MXR: refused, MXR is for loads only");

    $display("TLB_TB checks=%0d fails=%0d", checks, fails);
    if (fails != 0) $fatal(1, "TLB_TB FAILED");
    $display("TLB_TB_OK");
    $finish;
  end

  initial begin #200000; $display("TLB_TB TIMEOUT"); $fatal(1, "timeout"); end
endmodule
