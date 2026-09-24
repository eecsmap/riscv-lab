// tcpu_ifill against a memory model: what goes OUT matters as much as what comes back.
//
// The model records every request it is given, so the bench can assert that a hit produced NO external
// transaction at all, that a non-cacheable access produced exactly ONE and not a line read, and that a
// refill is exactly two beats inside one line.
`timescale 1ns/1ps
module ifill_tb;
  reg clk = 0; always #5 clk = ~clk;
  reg rst = 1, invalidate = 0;
  reg        c_req_valid = 0, c_req_write = 0, c_is_fetch = 1;
  reg [31:0] c_req_addr = 0;
  wire c_req_ready, c_resp_valid, c_resp_error;
  wire [63:0] c_resp_rdata;
  wire m_req_valid, o_hit, o_miss;
  wire [31:0] m_req_addr;
  reg  m_req_ready = 1, m_resp_valid = 0, m_resp_error = 0;
  reg  [63:0] m_resp_rdata = 0;

  integer fails = 0, checks = 0;
  task ok_(input [1023:0] w); begin checks=checks+1; $display("  ok   : %0s", w); end endtask
  task no_(input [1023:0] w); begin checks=checks+1; fails=fails+1; $display("  FAIL : %0s", w); end endtask
  task want(input c, input [1023:0] w); begin if (c) ok_(w); else no_(w); end endtask

  tcpu_ifill #(.BYTES(1024), .LINE_BYTES(16)) dut (
    .clk(clk), .rst(rst), .invalidate(invalidate),
    .c_req_valid(c_req_valid), .c_req_ready(c_req_ready), .c_req_addr(c_req_addr),
    .c_req_write(c_req_write), .c_is_fetch(c_is_fetch),
    .c_resp_valid(c_resp_valid), .c_resp_rdata(c_resp_rdata), .c_resp_error(c_resp_error),
    .m_req_valid(m_req_valid), .m_req_ready(m_req_ready), .m_req_addr(m_req_addr),
    .m_resp_valid(m_resp_valid), .m_resp_rdata(m_resp_rdata), .m_resp_error(m_resp_error),
    .o_hit(o_hit), .o_miss(o_miss));

  // ---- the memory model: it REMEMBERS what it was asked for
  integer ext_count = 0;
  reg [31:0] ext_addr [0:63];
  integer err_at = -1;                        // beat index at which to report an error, -1 = never
  integer beat = 0;
  always @(posedge clk) begin
    m_resp_valid <= 1'b0; m_resp_error <= 1'b0;
    if (m_req_valid && m_req_ready) begin
      ext_addr[ext_count] <= m_req_addr;
      ext_count <= ext_count + 1;
      m_resp_valid <= 1'b1;
      m_resp_rdata <= {32'hA5A50000, m_req_addr};      // data that identifies its own address
      if (err_at >= 0 && beat == err_at) m_resp_error <= 1'b1;
      beat <= beat + 1;
    end
  end

  reg [63:0] got; reg goterr;
  task do_fetch(input [31:0] a, input isfetch, input iswrite);
  begin
    @(negedge clk); c_req_addr = a; c_is_fetch = isfetch; c_req_write = iswrite; c_req_valid = 1;
    while (!c_req_ready) @(negedge clk);
    @(negedge clk); c_req_valid = 0;
    got = 64'hX; goterr = 0;
    begin : w
      integer n; n = 0;
      while (n < 60) begin
        if (c_resp_valid) begin got = c_resp_rdata; goterr = c_resp_error; disable w; end
        @(negedge clk); n = n + 1;
      end
    end
  end endtask

  task reset_ext; begin ext_count = 0; beat = 0; end endtask

  initial begin
    repeat (3) @(negedge clk); rst = 0; @(negedge clk);

    $display("== 1. a cold fetch misses and refills exactly one line, two beats");
    reset_ext; do_fetch(32'h8000_0004, 1, 0);
    want(ext_count == 2, "a miss makes exactly TWO external requests");
    want(ext_addr[0] == 32'h8000_0000 && ext_addr[1] == 32'h8000_0008,
      "  at the line base and base+8, in order");
    want(got == {32'hA5A50000, 32'h8000_0000}, "  and the core gets the 64-bit word containing its address");

    $display("== 2. a second fetch in the same line makes NO external request");
    reset_ext; do_fetch(32'h8000_000C, 1, 0);
    want(ext_count == 0, "a hit produces no external transaction AT ALL");
    want(got == {32'hA5A50000, 32'h8000_0008}, "  and returns the right half of the line");
    reset_ext; do_fetch(32'h8000_0000, 1, 0);
    want(ext_count == 0, "  and so does the other half");

    $display("== 3. a conflicting line evicts, 1 KiB apart");
    reset_ext; do_fetch(32'h8000_0400, 1, 0);
    want(ext_count == 2, "the conflicting line is fetched");
    reset_ext; do_fetch(32'h8000_0000, 1, 0);
    want(ext_count == 2, "  and the evicted line must be fetched again");

    $display("== 4. fence.i invalidates");
    reset_ext; do_fetch(32'h8000_0000, 1, 0);
    want(ext_count == 0, "the line is resident again");
    @(negedge clk); invalidate = 1; @(negedge clk); invalidate = 0;
    reset_ext; do_fetch(32'h8000_0000, 1, 0);
    want(ext_count == 2, "after fence.i it must be fetched again");

    $display("== 5. a failed refill leaves NO line, and the error reaches the core");
    err_at = 1;                               // the SECOND beat errors
    reset_ext; do_fetch(32'h8000_0800, 1, 0);
    want(goterr, "the requesting access sees the error");
    err_at = -1;
    reset_ext; do_fetch(32'h8000_0800, 1, 0);
    want(ext_count == 2, "  and the line was NOT left valid: it is fetched again");
    want(!goterr, "  the retry, with no error, succeeds");

    $display("== 6. non-cacheable bypasses with ONE access and no line read");
    reset_ext; do_fetch(32'h0200_BFF8, 1, 0);
    want(ext_count == 1, "a CLINT fetch makes exactly one external request");
    want(ext_addr[0] == 32'h0200_BFF8, "  at the address asked for, not a line base");
    reset_ext; do_fetch(32'h0200_BFF8, 1, 0);
    want(ext_count == 1, "  and it is never cached: the second one goes out too");

    $display("== 7. a DATA access is passed straight through, never cached");
    reset_ext; do_fetch(32'h8000_2000, 0, 0);
    want(ext_count == 1, "a data read makes exactly one external request");
    want(ext_addr[0] == 32'h8000_2000, "  at its own address");
    reset_ext; do_fetch(32'h8000_2000, 0, 0);
    want(ext_count == 1, "  and a second one goes out: data is not cached");
    reset_ext; do_fetch(32'h8000_2000, 1, 0);
    want(ext_count == 2, "  and a FETCH of the same address still misses, so the data never filled it");

    $display("== 8. a WRITE is passed through even when it looks cacheable");
    reset_ext; do_fetch(32'h8000_3000, 1, 1);
    want(ext_count == 1, "a write makes exactly one external request and reads no line");

    $display("IFILL_TB checks=%0d fails=%0d", checks, fails);
    if (fails != 0) $fatal(1, "IFILL_TB FAILED");
    $display("IFILL_TB_OK");
    $finish;
  end
  initial begin #500000; $display("IFILL_TB TIMEOUT"); $fatal(1, "timeout"); end
endmodule
