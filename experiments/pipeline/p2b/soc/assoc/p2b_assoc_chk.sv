// PIPE-P2b: SoC-level request -> retirement association checker (task codex-pipe-p2b-retirement-association).
//
// Simulation only. Bound into the GENERATED RD2ZynqTop (the SoC module that holds the hart and RD2Soc's
// `awaitingRetire` register), it watches the real integration: the hart wrapper's published classification
// (obs.isFetch), the physical port's request / response handshakes, the commit and trap ports, and the SoC's own
// awaitingRetire register. Nothing it observes is re-implemented or re-printed.
//
// Ground truth, independent of the wrapper's classification: the OWNER of each port transaction is taken from the
// core's own request-time metadata in the cycle of the request handshake --
//   the walker's request is on the port (core.wr_req_valid): a PTE read; IF-PTE or D-PTE from the walk's owner
//     (core.wk_own = WK_F / WK_D), recorded at the handshake -- not from the address, not from the wrapper;
//   otherwise the core's own request with owner fetch (core.preq_owner_f): an instruction fetch / refill;
//   otherwise a data request of the instruction in MEM: its pc and sequence number (core.mem_pc / mem_seq) and its
//     kind (load, store, AMO, LR, SC) are recorded as the requester's identity.
// The core has one port transaction outstanding at a time (checked), so the response belongs to the recorded owner.
// Killed transactions (a fetch the front end abandoned, a PTE read of an aborted walk draining) keep their owner.
//
// Checks (each failure prints `ASSOC FAIL <check>: ...`):
//   classify     at every response: the wrapper's isFetch must be 1 for FETCH / IF-PTE / D-PTE and 0 for DATA
//   association  after a DATA response, the next retirement (commit, or synchronous trap) must be that
//                requester's -- same pc AND same sequence number; an interrupt taken or a different instruction
//                retiring first is a failure (an unrelated older commit clearing the requester's wait), and so is
//                a second DATA response before the first one's requester retired (a requester that never retires)
//   soc-register the SoC's awaitingRetire register must equal the truth model every cycle: set by a DATA response
//                (unless a retirement lands in the same cycle -- RD2Soc's last connect wins, reported as a
//                priority case), cleared by the next retirement, NOT reset by a CPU reset (it is SoC state)
//   same-cycle   a DATA response in the same cycle as a retirement (it would leave awaitingRetire clear while the
//                requester has not retired)
//   protocol     a second request while one is outstanding; a response with nothing outstanding; a walker
//                request with no walk owner
//   stale        after a CPU reset, no response may reach the core for a transaction it issued before the reset
//                (the bridge's drain completes such a transaction on the bus and discards its response; the bus
//                side -- every Get matched by its Put -- is check-drain.py's, run on the same logs). This is the
//                physical reset-drain guarantee on the core's port; it is not inferred from the busy flag.
//                A core-port transaction outstanding when the reset asserts is expected and counted.
// A DATA response whose requester is removed by a CPU reset before retiring is not a failure of the association
// (the instruction never retires); it is counted as reset_abandoned, and the soc-register check keeps modelling
// the register (it stays set until the first retirement after the reset).
//
// At the end: `ASSOC COVER ...` (per-owner responses, killed ones, overlaps, priority cases, resets) and
// `ASSOC END fails=N`.
`timescale 1ns/1ps
module p2b_assoc_chk (
  input        clock,
  input        reset,             // SoC reset
  input        aw_soc,            // RD2Soc awaitingRetire (the generated register)
  input        isFetch,           // the hart wrapper's obs.isFetch
  input        reqFire,
  input        respFire,
  input        commitValid,
  input        trapValid,
  input        trapInterrupt,
  input [63:0] commitPc,
  input [63:0] trapEpc
);
  // ---- ground truth from the core (hierarchical: RD2ZynqTop.harts.cpu.core)
  wire        c_rst   = harts.cpu.core.rst;
  wire        c_wr    = harts.cpu.core.wr_req_valid;
  wire [1:0]  c_wk    = harts.cpu.core.wk_own;
  wire        c_ownf  = harts.cpu.core.preq_owner_f;
  wire        c_pkill = harts.cpu.core.preq_killed;
  wire        c_wkill = harts.cpu.core.wr_killed_pending;
  wire [63:0] c_mpc   = harts.cpu.core.mem_pc;
  wire [31:0] c_mseq  = harts.cpu.core.mem_seq;
  wire        c_isst  = harts.cpu.core.mem_isst;
  wire        c_isa   = harts.cpu.core.mem_isa;
  wire        c_lr    = harts.cpu.core.mem_a_lr;
  wire        c_sc    = harts.cpu.core.mem_issc;
  wire [31:0] c_wbseq = harts.cpu.core.wb_seq;
  wire        c_wbv   = harts.cpu.core.wb_v;

  localparam O_FETCH = 0, O_IFPTE = 1, O_DPTE = 2, O_DATA = 3;
  localparam K_LOAD = 0, K_STORE = 1, K_AMO = 2, K_LR = 3, K_SC = 4;
  reg        out_v;  reg [1:0] out_own; reg [2:0] out_kind; reg [63:0] out_pc; reg [31:0] out_seq;
  reg        out_retired_between;             // a retirement happened while this transaction was outstanding
  reg        pend;   reg [63:0] pend_pc; reg [31:0] pend_seq; reg [2:0] pend_kind;
  reg        aw_model;
  reg        rst_q;
  integer    fails, cyc;
  integer    n_resp [0:3]; integer n_kill [0:3]; integer n_kind [0:4];
  integer    n_if_overlap, n_d_overlap, n_pte_samecyc, n_data_samecyc, n_data_trap, n_rst, n_rst_pend, n_rst_out, n_irq_between;
  integer    lat, lat_max;
  function [79:0] oname(input [1:0] o);
    oname = (o == O_FETCH) ? "FETCH" : (o == O_IFPTE) ? "IF-PTE" : (o == O_DPTE) ? "D-PTE" : "DATA";
  endfunction
  function [47:0] kname(input [2:0] k);
    kname = (k == K_LOAD) ? "load" : (k == K_STORE) ? "store" : (k == K_AMO) ? "AMO" : (k == K_LR) ? "LR" : "SC";
  endfunction
  integer i;
  reg trace_on;
  initial trace_on = $test$plusargs("assoc_trace");   // +assoc_trace: one line per request, response, retirement
  initial begin
    fails = 0; cyc = 0; out_v = 0; pend = 0; aw_model = 0; rst_q = 1; lat = 0; lat_max = 0;
    for (i = 0; i < 4; i = i + 1) begin n_resp[i] = 0; n_kill[i] = 0; end
    for (i = 0; i < 5; i = i + 1) n_kind[i] = 0;
    n_if_overlap = 0; n_d_overlap = 0; n_pte_samecyc = 0; n_data_samecyc = 0; n_data_trap = 0; n_rst = 0; n_rst_pend = 0; n_rst_out = 0;
    n_irq_between = 0;
  end
  wire retire = commitValid || trapValid;
  reg  resp_data;                            // this cycle's response is a DATA response (truth)

  always @(posedge clock) begin
    cyc = cyc + 1; resp_data = 0;
    if (reset) begin
      out_v = 0; pend = 0; aw_model = 0; rst_q = 1;
    end else begin
      // ---- soc-register: the register's value in this cycle is what the previous edges made it
      if (aw_soc !== aw_model) begin
        fails = fails + 1;
        $display("ASSOC FAIL soc-register cyc=%0d: RD2Soc awaitingRetire=%0d, the truth model says %0d (pending %s pc=%h seq=%0d)",
                 cyc, aw_soc, aw_model, pend ? kname(pend_kind) : "-", pend_pc, pend_seq);
      end
      // ---- CPU reset (the drain's hold, or any core reset while the SoC runs)
      if (c_rst && !rst_q) begin
        n_rst = n_rst + 1;
        if (out_v) n_rst_out = n_rst_out + 1;     // completed on the bus by the bridge, its response discarded
        if (pend) n_rst_pend = n_rst_pend + 1;
      end
      rst_q = c_rst;
      if (c_rst) begin
        out_v = 0;
        pend = 0;              // the requester is gone; the SoC register is SoC state and is not cleared (aw_model kept)
      end else begin
        // ---- retirement: association with a pending DATA response
        if (trace_on && retire) $display("ASSOC TRACE cyc=%0d retire %s pc=%h seq=%0d%s pend=%0d", cyc, commitValid ? "commit" : "trap",
                                          commitValid ? commitPc : trapEpc, c_wbseq, (trapValid && trapInterrupt) ? " irq" : "", pend);
        if (retire && pend) begin
          if (commitValid && commitPc == pend_pc && c_wbseq == pend_seq) ;
          else if (trapValid && !trapInterrupt && trapEpc == pend_pc && c_wbseq == pend_seq) n_data_trap = n_data_trap + 1;
          else begin
            fails = fails + 1;
            $display("ASSOC FAIL association cyc=%0d: the %s of pc %h seq %0d had its response; the next retirement is %s pc %h seq %0d%s",
                     cyc, kname(pend_kind), pend_pc, pend_seq, commitValid ? "a commit of" : "a trap at",
                     commitValid ? commitPc : trapEpc, c_wbseq, (trapValid && trapInterrupt) ? " (an interrupt)" : "");
          end
          if (lat + 1 > lat_max) lat_max = lat + 1;
          pend = 0;
        end
        if (pend) lat = lat + 1;
        if (out_v && retire) out_retired_between = 1;
        // ---- response
        if (respFire) begin
          if (!out_v) begin
            fails = fails + 1;
            $display("ASSOC FAIL %s cyc=%0d: a response with no transaction outstanding%s", (n_rst > 0) ? "stale" : "protocol", cyc,
                     (n_rst > 0) ? " (after a CPU reset: a pre-reset transaction's response reached the core?)" : "");
          end else begin
            n_resp[out_own] = n_resp[out_own] + 1;
            if (trace_on) $display("ASSOC TRACE cyc=%0d resp %s pc=%h seq=%0d isFetch=%0d", cyc, oname(out_own), out_pc, out_seq, isFetch);
            if ((out_own == O_FETCH && c_pkill) || ((out_own == O_IFPTE || out_own == O_DPTE) && c_wkill)) n_kill[out_own] = n_kill[out_own] + 1;
            if (isFetch !== (out_own != O_DATA)) begin
              fails = fails + 1;
              $display("ASSOC FAIL classify cyc=%0d: the response of a %s transaction (owner recorded at its request) is published with isFetch=%0d%s",
                       cyc, oname(out_own), isFetch, (out_own == O_DATA) ? "" : " -- the SoC would wait for a retirement that is not this transaction's");
            end
            if (out_own == O_IFPTE || out_own == O_DPTE) begin
              if (retire) n_pte_samecyc = n_pte_samecyc + 1;
              if (retire || out_retired_between) begin
                if (out_own == O_IFPTE) n_if_overlap = n_if_overlap + 1; else n_d_overlap = n_d_overlap + 1;
              end
            end
            if (out_own == O_DATA) begin
              resp_data = 1;
              n_kind[out_kind] = n_kind[out_kind] + 1;
              if (retire) begin
                n_data_samecyc = n_data_samecyc + 1; fails = fails + 1;
                $display("ASSOC FAIL same-cycle cyc=%0d: a retirement (pc %h) in the cycle of the %s response of pc %h: awaitingRetire stays clear",
                         cyc, commitValid ? commitPc : trapEpc, kname(out_kind), out_pc);
              end
              if (pend) begin
                fails = fails + 1;
                $display("ASSOC FAIL association cyc=%0d: the %s of pc %h seq %0d had its response and never retired before the next data response (pc %h seq %0d)",
                         cyc, kname(pend_kind), pend_pc, pend_seq, out_pc, out_seq);
              end
              pend = 1; pend_pc = out_pc; pend_seq = out_seq; pend_kind = out_kind; lat = 0;
            end
            out_v = 0;
          end
        end
        // ---- request (the owner is recorded here, from the core's own metadata)
        if (reqFire) begin
          if (out_v) begin
            fails = fails + 1; $display("ASSOC FAIL protocol cyc=%0d: a second request while a %s transaction is outstanding", cyc, oname(out_own));
          end
          out_v = 1; out_retired_between = 0;
          if (c_wr) begin
            if (c_wk == 2'd1) out_own = O_IFPTE;
            else if (c_wk == 2'd2) out_own = O_DPTE;
            else begin
              out_own = O_DPTE; fails = fails + 1;
              $display("ASSOC FAIL protocol cyc=%0d: a walker request with no walk owner (wk_own=%0d)", cyc, c_wk);
            end
          end else if (c_ownf) out_own = O_FETCH;
          else begin
            out_own = O_DATA; out_pc = c_mpc; out_seq = c_mseq;
            out_kind = !c_isa ? (c_isst ? K_STORE : K_LOAD) : c_lr ? K_LR : c_sc ? K_SC : K_AMO;
          end
          if (trace_on) $display("ASSOC TRACE cyc=%0d req %s pc=%h seq=%0d", cyc, oname(out_own), out_pc, out_seq);
        end
      end
      // ---- the truth model of RD2Soc's awaitingRetire (same connect order: set on a DATA response, then a retirement
      // in the same cycle clears it; SoC state, so a CPU reset does not touch it)
      if (resp_data) aw_model = 1'b1;
      if (retire) aw_model = 1'b0;
    end
  end

  final begin
    $display("ASSOC COVER responses fetch=%0d if_pte=%0d d_pte=%0d data=%0d load=%0d store=%0d amo=%0d lr=%0d sc=%0d killed_fetch=%0d killed_if_pte=%0d killed_d_pte=%0d",
             n_resp[0], n_resp[1], n_resp[2], n_resp[3], n_kind[0], n_kind[1], n_kind[2], n_kind[3], n_kind[4], n_kill[0], n_kill[1], n_kill[2]);
    $display("ASSOC COVER if_pte_overlapping_a_retirement=%0d d_pte_overlapping_a_retirement=%0d pte_same_cycle_as_a_retirement=%0d data_responses_then_trap=%0d same_cycle_data_priority=%0d max_cycles_resp_to_retire=%0d cpu_resets=%0d resets_abandoning_a_data_response=%0d resets_with_core_transaction_outstanding=%0d",
             n_if_overlap, n_d_overlap, n_pte_samecyc, n_data_trap, n_data_samecyc, lat_max, n_rst, n_rst_pend, n_rst_out);
    $display("ASSOC COVER data_response_pending_at_end=%0d", pend);
    $display("ASSOC END cycles=%0d fails=%0d", cyc, fails);
  end
endmodule
