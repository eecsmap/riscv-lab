// Canonicality for an AMO, at the tcpu_xlate boundary, with the real walker.
//
// The full-core route is blocked: ext03_a does not complete in this SoC configuration even on the
// baseline, so a core-level AMO probe would be testing the atomics gap. This drives tcpu_xlate
// directly instead, which is where the canonicality gate lives, and counts what the module asked
// memory for -- so "no physical request on an invalid hit" is measured, not argued.
`timescale 1ns/1ps
module xlate_amo_tb;
  reg clk = 0; always #5 clk = ~clk;
  reg rst = 1, flush = 0, start = 0;
  reg [63:0] va = 0;
  reg [1:0]  acc_type = 0, eff_priv = 1;
  reg sum = 0, mxr = 0;
  wire req_valid, busy, done, fault;
  wire [31:0] req_addr;
  wire [3:0]  cause;
  wire [55:0] pa;
  wire o_hit, o_miss;
  reg  req_ready = 1, resp_valid = 0, resp_error = 0;
  reg [63:0] resp_rdata = 0;

  integer fails = 0, checks = 0;
  // `reqs` is driven non-blocking from the memory model. Clearing it with a blocking assignment from
  // the stimulus races that, which is what made case 2 report requests it had not made. Snapshot and
  // subtract instead: one writer, one assignment style.
  integer reqs = 0, mark = 0;
  function integer since; input integer m; begin since = reqs - m; end endfunction
  task ok_(input [1023:0] w); begin checks=checks+1; $display("  ok   : %0s", w); end endtask
  task no_(input [1023:0] w); begin checks=checks+1; fails=fails+1; $display("  FAIL : %0s", w); end endtask
  task want(input c, input [1023:0] w); begin if (c) ok_(w); else no_(w); end endtask

  tcpu_xlate #(.TLB_ENTRIES(8)) dut (
    .clk(clk), .rst(rst), .flush(flush), .start(start), .va(va), .acc_type(acc_type),
    .eff_priv(eff_priv), .sum(sum), .mxr(mxr), .root_ppn(44'h80),
    .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr),
    .resp_valid(resp_valid), .resp_rdata(resp_rdata), .resp_error(resp_error),
    .busy(busy), .done(done), .fault(fault), .cause(cause), .pa(pa),
    .o_hit(o_hit), .o_miss(o_miss));

  // memory: every PTE read returns a valid 1 GiB leaf with R W X A D and U clear
  // A 1 GiB leaf must have ppn[17:0] == 0 or the walker rejects it as a misaligned superpage -- which
  // it did, correctly, when this bench first used ppn 0x20000. The bench was wrong, not the walker.
  localparam [63:0] LEAF = (64'h40000 << 10) | 64'h0CF;   // V R W X A D, ppn 0x40000, 1 GiB aligned
  always @(posedge clk) begin
    resp_valid <= 1'b0;
    if (req_valid && req_ready) begin reqs <= reqs + 1; resp_valid <= 1'b1; resp_rdata <= LEAF; end
  end

  reg saw_fault; reg [3:0] saw_cause; reg saw_done;
  task xlate(input [63:0] v, input [1:0] t);
  begin
    @(negedge clk); va = v; acc_type = t; start = 1; @(negedge clk); start = 0;
    saw_done = 0; saw_fault = 0; saw_cause = 0;
    begin : w
      integer n; n = 0;
      while (n < 80) begin
        if (done) begin saw_done = 1; saw_fault = fault; saw_cause = cause; disable w; end
        @(negedge clk); n = n + 1;
      end
    end
    // The TLB fill lands one cycle AFTER ptw_done, so a translation issued immediately would look up
    // an array that has not been written yet and miss. The core cannot do that -- it must finish the
    // memory access the translation was for -- so settling here models the caller rather than hiding
    // anything. Without it this bench reported a miss where the SoC regression measures 57.8% fewer
    // walks, which is how it was clear the bench was wrong and not the TLB.
    repeat (4) @(negedge clk);
  end endtask

  initial begin
    repeat (3) @(negedge clk); rst = 0; @(negedge clk);

    $display("== 1. a canonical AMO walks and succeeds, filling the TLB");
    mark = reqs; xlate(64'h0000_0000_4000_0000, 2'd3);
    want(saw_done && !saw_fault, "the canonical AMO translation succeeds");
    want(since(mark) > 0, "  and it really walked (it made memory requests)");
    $display("== 2. the same canonical AMO hits, with no memory request at all");
    mark = reqs; xlate(64'h0000_0000_4000_0000, 2'd3);
    want(saw_done && !saw_fault, "the second AMO succeeds");
    want(since(mark) == 0, "  from the TLB: NO memory request");

    $display("== 3. a NON-CANONICAL alias of that warm entry must fault, cause 15, with no request");
    mark = reqs; xlate(64'h0000_0080_4000_0000, 2'd3);   // bit 39 set: same va[38:12], not canonical
    want(saw_done && saw_fault, "the non-canonical AMO FAULTS");
    want(saw_cause == 4'd15, "  with cause 15, the store/AMO page-fault class");
    want(since(mark) == 0, "  and NO physical request was made");

    $display("== 4. the other sign-extension half");
    mark = reqs; xlate(64'hFFFF_FFC0_0000_0000, 2'd3);   // canonical high: warm it
    want(saw_done && !saw_fault, "a canonical high-half AMO succeeds");
    mark = reqs; xlate(64'h7FFF_FFC0_0000_0000, 2'd3);   // bit 63 cleared: not canonical
    want(saw_done && saw_fault && saw_cause == 4'd15, "its alias with bit 63 cleared faults, cause 15");
    want(since(mark) == 0, "  and makes no physical request");

    $display("== 5. the same alias for a LOAD is cause 13, and for a FETCH cause 12");
    mark = reqs; xlate(64'h0000_0080_4000_0000, 2'd1);
    want(saw_fault && saw_cause == 4'd13, "a non-canonical LOAD faults with cause 13");
    mark = reqs; xlate(64'h0000_0080_4000_0000, 2'd0);
    want(saw_fault && saw_cause == 4'd12, "a non-canonical FETCH faults with cause 12");
    want(since(mark) == 0, "  neither made a physical request");

    $display("XLATE_AMO_TB checks=%0d fails=%0d", checks, fails);
    if (fails != 0) $fatal(1, "XLATE_AMO_TB FAILED");
    $display("XLATE_AMO_TB_OK");
    $finish;
  end
  initial begin #200000; $display("XLATE_AMO_TB TIMEOUT"); $fatal(1, "timeout"); end
endmodule
