// PIPE-P2a walker-wrapper unit bench (codex-pipe-p2a-extensions-walker, item 3).
//
// Proves that the UNCHANGED tcpu_ptw, inside tcpu_ptw_wrap, can be cancelled and preempted at every moment:
// for each walk scenario, port timing (+ready-delay, +resp-delay) and abort cycle t (0 .. the walk's length + 2),
// walk A starts at cycle 0 and is aborted at cycle t; then data-side walk B (scenario 1) starts as soon as the
// wrapper accepts it and must produce exactly the reference result. Checked every cycle, from outside the wrapper:
//   withdraw / payload    a request on the port stays valid, with the same address, until its handshake
//   one-outstanding       never a second handshake before the previous response
//   killed-delivered      a killed transaction's response never reaches the walker
//   resp-to-unforwarded   the walker never receives a response while its own request is still unforwarded
//   spec-uncached         a speculative walk never puts an uncached PTE address on the port
//   done-after-kill       from the abort cycle until B starts, no done is reported
//   wrong-result          A (if it completed before the abort) and B equal the reference walks
//   drain                 at the end every handshake has had its response
// The abort moment is classified from the state at the abort cycle (walker state and level, holding register).
`timescale 1ns/1ps
module wb_tb;
  parameter WF = 0;            // WRAP_FAULT of the wrapper under test
  reg clk = 1'b0; always #5 clk = ~clk;
  reg rst = 1'b1;
  // ---- memory: 64 KiB of cacheable RAM at 0x8000_0000, 4 KiB of uncached memory at 0x3000_0000; anything else errors
  reg [63:0] ram [0:8191];
  reg [63:0] unc [0:511];
  // ---- wrapper
  reg         start = 0, spec = 0, abort = 0;
  // +grant-mode=1: the core's arbiter gives the walker the port only every third cycle (other users hold it), so
  // the walker's request waits UNFORWARDED -- the state in which an abort is invisible to the port
  integer     grant_mode, gcyc;
  wire        grant = (grant_mode == 0) || (gcyc % 3 == 0);
  always @(posedge clk) gcyc <= rst ? 0 : gcyc + 1;
  reg  [63:0] va = 0;
  reg  [1:0]  acc = 0;
  wire        start_ok, busy, done, fault, req_valid, dbg_killed_pending, dbg_unforwarded;
  wire [3:0]  cause;
  wire [55:0] pa;
  wire [43:0] leaf_ppn;
  wire [1:0]  leaf_level;
  wire [31:0] req_addr;
  reg         req_ready = 0, resp_valid = 0, resp_error = 0;
  reg  [63:0] resp_rdata = 0;
  tcpu_ptw_wrap #(.WRAP_FAULT(WF)) dut (
    .clk(clk), .rst(rst), .start(start), .va(va), .acc_type(acc), .eff_priv(2'd1), .sum(1'b0), .mxr(1'b0),
    .root_ppn(44'h80001), .spec(spec), .abort(abort), .grant(grant), .start_ok(start_ok), .busy(busy),
    .done(done), .fault(fault), .cause(cause), .pa(pa), .leaf_ppn(leaf_ppn), .leaf_level(leaf_level),
    .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr),
    .resp_valid(resp_valid), .resp_rdata(resp_rdata), .resp_error(resp_error),
    .dbg_killed_pending(dbg_killed_pending), .dbg_unforwarded(dbg_unforwarded));

  // ---- port model: fixed delays, one request in flight
  integer rd, rs, wcnt, rcnt, n_hs, n_resp;
  reg busy_m; reg [31:0] a_addr;
  always @(posedge clk) begin
    if (rst) begin req_ready <= 0; resp_valid <= 0; resp_error <= 0; busy_m <= 0; wcnt <= 0; rcnt <= 0; end
    else begin
      resp_valid <= 0; resp_error <= 0;
      if (busy_m) begin
        if (rcnt <= 1) begin
          busy_m <= 0; resp_valid <= 1; n_resp = n_resp + 1;
          if (a_addr[31:16] == 16'h8000) begin resp_rdata <= ram[a_addr[15:3]]; resp_error <= 0; end
          else if (a_addr[31:12] == 20'h30000) begin resp_rdata <= unc[a_addr[11:3]]; resp_error <= 0; end
          else begin resp_rdata <= 64'hdeadbeefdeadbeef; resp_error <= 1; end
        end else rcnt <= rcnt - 1;
      end
      if (req_valid && req_ready) begin busy_m <= 1; rcnt <= rs; req_ready <= 0; wcnt <= 0; a_addr <= req_addr; n_hs = n_hs + 1; end
      else if (req_valid && !busy_m && !req_ready) begin if (wcnt >= rd) req_ready <= 1; else wcnt <= wcnt + 1; end
    end
  end

  // ---- page tables (Sv39): root 0x8000_1000
  function [63:0] ptr;  input [43:0] ppn; ptr  = {10'd0, ppn, 10'b0000000001}; endfunction        // V only
  function [63:0] leaf; input [43:0] ppn; leaf = {10'd0, ppn, 10'b0011001111}; endfunction        // V R W X A D
  task put(input [31:0] addr, input [63:0] v);
    begin if (addr[31:16] == 16'h8000) ram[addr[15:3]] = v; else unc[addr[11:3]] = v; end
  endtask
  integer i;
  task tables;
    begin
      for (i = 0; i < 8192; i = i + 1) ram[i] = 64'd0;
      for (i = 0; i < 512; i = i + 1) unc[i] = 64'd0;
      put(32'h8000_1000 + 8*1, ptr(44'h80002));       // va[38:30]=1 -> L1 at 0x8000_2000
      put(32'h8000_2000 + 8*1, ptr(44'h80003));       //   va[29:21]=1 -> L0 at 0x8000_3000
      put(32'h8000_3000 + 8*3, leaf(44'h80010));      //     va[20:12]=3 -> 4 KiB page 0x8001_0000   (scenario 1)
      put(32'h8000_2000 + 8*2, leaf(44'h80200));      //   va[29:21]=2 -> 2 MiB megapage 0x8020_0000 (scenario 2)
                                                      //     va[20:12]=4 under L0: invalid PTE        (scenario 3)
      put(32'h8000_1000 + 8*2, ptr(44'h90000));       // va[38:30]=2 -> L1 at 0x9000_0000: no memory   (scenario 4)
      put(32'h8000_1000 + 8*3, ptr(44'h30000));       // va[38:30]=3 -> L1 at 0x3000_0000: UNCACHED    (scenario 5)
      put(32'h3000_0000 + 8*0, ptr(44'h80004));       //   va[29:21]=0 -> L0 at 0x8000_4000
      put(32'h8000_4000 + 8*5, leaf(44'h80020));      //     va[20:12]=5 -> 4 KiB page 0x8002_0000
    end
  endtask
  function [63:0] sva; input integer s; case (s)
    1: sva = 64'h0000_0000_4020_3abc; 2: sva = 64'h0000_0000_4040_0123; 3: sva = 64'h0000_0000_4020_4000;
    4: sva = 64'h0000_0000_8000_0000; 5: sva = 64'h0000_0000_c000_5010; default: sva = 0; endcase endfunction

  // ---- checks
  string run_seen [string]; int tot [string]; int runs_failed [string];
  integer run_err, t_abort, cyc, pt_s;
  reg in_kill;                  // from the abort cycle until B starts: no done may appear
  reg p_pend; reg [31:0] p_addr;
  task err(input string name, input string detail);
    begin
      run_err = run_err + 1;
      if (tot.exists(name)) tot[name] = tot[name] + 1; else tot[name] = 1;
      if (!run_seen.exists(name)) begin
        run_seen[name] = "1";
        if (runs_failed.exists(name)) runs_failed[name] = runs_failed[name] + 1; else runs_failed[name] = 1;
        $display("WB ERROR s=%0d rd=%0d rs=%0d t=%0d cyc=%0d %0s: %0s", pt_s, rd, rs, t_abort, cyc, name, detail);
      end
    end
  endtask
  function uncached(input [31:0] a); uncached = !(a[31:28] == 4'h1 || a[31:28] == 4'h8); endfunction
  always @(posedge clk) if (!rst) begin
    if (p_pend) begin
      if (!req_valid) err("withdraw", "a request left the port before its handshake");
      else if (req_addr != p_addr) err("payload", "the request address changed before its handshake");
    end
    p_pend = req_valid && !req_ready; p_addr = req_addr;
    if (req_valid && req_ready && dut.h_wait && !resp_valid) err("one-outstanding", "a second handshake with a response outstanding");
    if (dut.deliver && dut.h_killed) err("killed-delivered", "a killed transaction's response reached the walker");
    if (dut.deliver && dut.w_req_valid) err("resp-to-unforwarded", "the walker got a response while its request was unforwarded");
    if (req_valid && spec && uncached(req_addr)) err("spec-uncached", $sformatf("speculative walk put uncached 0x%08x on the port", req_addr));
    if (in_kill && done) err("done-after-kill", "a done was reported for an aborted walk");
  end

  // ---- coverage of the abort moment
  localparam NC = 11;
  int cov [0:NC-1];
  // 0 idle  1 walker REQ state  2 unforwarded (waiting for the port or blocked as speculative)  3 would forward now
  // 4 offered, not ready  5 handshaking  6 outstanding, no response yet  7 response at level 2  8 at level 1
  // 9 at level 0  10 error response
  task classify;
    begin
      if (!dut.walker.busy && !dut.h_valid && !dut.h_wait) cov[0] = cov[0] + 1;
      if (dut.walker.state == 2'd1) cov[1] = cov[1] + 1;
      if (dut.w_req_valid && !dut.may_forward) cov[2] = cov[2] + 1;
      if (dut.w_req_valid && dut.h_free && (!spec || dut.cacheable)) cov[3] = cov[3] + 1;
      if (req_valid && !req_ready) cov[4] = cov[4] + 1;
      if (req_valid && req_ready) cov[5] = cov[5] + 1;
      if (dut.h_wait && !resp_valid) cov[6] = cov[6] + 1;
      if (dut.h_wait && resp_valid && !resp_error) cov[9 - dut.walker.level] = cov[9 - dut.walker.level] + 1;
      if (dut.h_wait && resp_valid && resp_error) cov[10] = cov[10] + 1;
    end
  endtask

  // ---- one run: walk A (scenario s, fetch side, speculative?) aborted at t (t < 0: never), then walk B
  reg        ref_done [1:5]; reg ref_fault [1:5]; reg [3:0] ref_cause [1:5]; reg [55:0] ref_pa [1:5];
  reg        got_done, got_fault; reg [3:0] got_cause; reg [55:0] got_pa; integer got_at;
  task wait_result(input integer limit);
    integer k;
    begin
      got_done = 0; k = 0;
      while (!got_done && k < limit) begin
        @(posedge clk); k = k + 1; cyc = cyc + 1;
        if (done) begin got_done = 1; got_fault = fault; got_cause = cause; got_pa = pa; got_at = cyc; end
      end
    end
  endtask
  task reset_all;
    begin
      rst = 1; start = 0; abort = 0; spec = 0; in_kill = 0; p_pend = 0; run_seen.delete();
      repeat (3) @(posedge clk); #1 rst = 0; cyc = 0; n_hs = 0; n_resp = 0; run_err = 0;
    end
  endtask
  task reference(input integer s);
    begin
      reset_all; pt_s = s; t_abort = -1;
      #1 va = sva(s); acc = 2'd0; start = 1; @(posedge clk); #1 start = 0; cyc = 1;
      wait_result(400);
      ref_done[s] = got_done; ref_fault[s] = got_fault; ref_cause[s] = got_cause; ref_pa[s] = got_pa;
      if (!got_done) err("reference", "the reference walk did not finish");
    end
  endtask
  integer len_s;
  task one(input integer s, input integer t, input reg sp);
    integer k; reg a_done;
    begin
      reset_all; pt_s = s; t_abort = t;
      #1 va = sva(s); acc = 2'd0; spec = sp; start = 1; a_done = 0;
      for (k = 0; k <= t; k = k + 1) begin
        if (k == t) begin abort = 1; in_kill = 1; classify; end
        @(posedge clk); cyc = cyc + 1; #1 start = 0;
        if (done && !in_kill) begin
          a_done = 1;
          if (done != ref_done[s] || fault != ref_fault[s] || cause != ref_cause[s] || (!fault && pa != ref_pa[s]))
            err("wrong-result", "walk A (before the abort) differs from its reference");
        end
        if (k == t) abort = 0;
      end
      // walk B: data side (a load), not speculative, scenario 1
      k = 0; while (!start_ok && k < 400) begin @(posedge clk); cyc = cyc + 1; k = k + 1; end
      #1 in_kill = 0; va = sva(1); acc = 2'd1; spec = 0; start = 1; @(posedge clk); cyc = cyc + 1; #1 start = 0;
      wait_result(400);
      if (!got_done) err("b-timeout", "walk B never finished");
      else if (got_fault != 0 || got_pa != ref_pa[1]) err("wrong-result", $sformatf("walk B: fault=%0d pa=%h, reference pa=%h", got_fault, got_pa, ref_pa[1]));
      k = 0; while ((dut.h_valid || dut.h_wait || busy_m) && k < 100) begin @(posedge clk); k = k + 1; end
      repeat (2) @(posedge clk);
      if (n_hs != n_resp) err("drain", $sformatf("%0d handshakes, %0d responses", n_hs, n_resp));
    end
  endtask
  // speculative uncached: A (scenario 5) stays speculative for 60 cycles, must put nothing uncached on the port;
  // then either it becomes non-speculative and completes, or it is preempted by B
  task spec_case(input integer mode);   // 0 = becomes non-speculative, 1 = preempted
    integer k;
    begin
      reset_all; pt_s = 50 + mode; t_abort = 60;
      #1 va = sva(5); acc = 2'd0; spec = 1; start = 1; @(posedge clk); cyc = cyc + 1; #1 start = 0;
      for (k = 0; k < 60; k = k + 1) begin @(posedge clk); cyc = cyc + 1; if (done) err("wrong-result", "a speculative walk finished through an uncached table"); end
      if (!dut.w_req_valid || dut.w_req_addr[31:12] != 20'h30000) err("spec-stall", "the speculative walk is not waiting at its uncached PTE");
      if (mode == 0) begin
        #1 spec = 0; wait_result(400);
        if (!got_done || got_fault || got_pa != ref_pa[5]) err("wrong-result", "the walk made non-speculative did not complete correctly");
      end else begin
        #1 abort = 1; in_kill = 1; classify; @(posedge clk); cyc = cyc + 1; #1 abort = 0;
        k = 0; while (!start_ok && k < 400) begin @(posedge clk); k = k + 1; end
        #1 in_kill = 0; spec = 0; va = sva(1); acc = 2'd1; start = 1; @(posedge clk); #1 start = 0;
        wait_result(400);
        if (!got_done || got_fault || got_pa != ref_pa[1]) err("wrong-result", "the data walk after preempting did not complete correctly");
      end
      repeat (rs + rd + 4) @(posedge clk);
      if (n_hs != n_resp) err("drain", "handshakes and responses differ");
    end
  endtask

  integer s, t, total_runs, total_err;
  string nm;
  initial begin
    if (!$value$plusargs("ready-delay=%d", rd)) rd = 0;
    if (!$value$plusargs("resp-delay=%d", rs)) rs = 1;
    if (!$value$plusargs("grant-mode=%d", grant_mode)) grant_mode = 0;
    if (rs < 1) rs = 1;
    for (i = 0; i < NC; i = i + 1) cov[i] = 0;
    total_runs = 0; total_err = 0;
    tables;
    for (s = 1; s <= 5; s = s + 1) reference(s);
    $display("WB REF rd=%0d rs=%0d s1 pa=%h | s2 pa=%h | s3 fault cause=%0d | s4 fault cause=%0d | s5 pa=%h",
             rd, rs, ref_pa[1], ref_pa[2], ref_cause[3], ref_cause[4], ref_pa[5]);
    for (s = 1; s <= 5; s = s + 1) begin
      reference(s); len_s = got_at;
      for (t = 0; t <= len_s + 2; t = t + 1) begin
        one(s, t, 1'b0); total_runs = total_runs + 1; total_err = total_err + run_err;
      end
    end
    spec_case(0); total_runs = total_runs + 1; total_err = total_err + run_err;
    spec_case(1); total_runs = total_runs + 1; total_err = total_err + run_err;
    $display("WB COVER wf=%0d gm=%0d rd=%0d rs=%0d idle=%0d req=%0d unforwarded=%0d forwardable=%0d offered=%0d handshake=%0d outstanding=%0d resp_l2=%0d resp_l1=%0d resp_l0=%0d error=%0d",
             WF, grant_mode, rd, rs, cov[0], cov[1], cov[2], cov[3], cov[4], cov[5], cov[6], cov[7], cov[8], cov[9], cov[10]);
    if (tot.first(nm)) do $display("WB ERRCOUNT %0s runs=%0d cycles=%0d", nm, runs_failed[nm], tot[nm]); while (tot.next(nm));
    $display("WB TOTAL runs=%0d errors=%0d", total_runs, total_err);
    $finish;
  end
endmodule
