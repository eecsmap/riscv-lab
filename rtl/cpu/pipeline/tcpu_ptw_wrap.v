// PIPE-P2a: cancellation and preemption around the UNCHANGED shared page-table walker (tcpu_ptw.v).
//
// The pipeline needs to abandon a walk at any moment (a front-end flush kills a fetch-side walk; a data-side walk
// preempts a fetch-side one) and must never withdraw a request the port has seen. tcpu_ptw has neither a kill nor a
// preempt input, but it has two properties this wrapper relies on (tcpu_ptw.v):
//   * its request is its OWN registered output, raised in its WAIT state and held until req_ready -- so a request
//     the wrapper has not forwarded yet is invisible outside;
//   * a synchronous reset returns it to IDLE with busy/done/req_valid low and nothing else remembered.
// So: the walker's request is FORWARDED into this wrapper's own port holding register only when the port is free;
// from then on the holding register owns the transaction until its response is consumed. An abort resets the walker
// at once (whatever state it is in) and marks an outstanding forwarded transaction killed: the transaction stays
// on the port unchanged until its handshake, and its response is consumed here and never reaches a walker. A killed
// walk never reports done, so nothing can fill from it. A speculative walk (a fetch walk that is not the oldest
// work) forwards only PTE addresses in cacheable RAM; an uncached PTE address waits, unforwarded, until the walk
// becomes non-speculative or is aborted (e.g. preempted by a data-side walk, which then proceeds).
//
// Negative controls (WRAP_FAULT): 1 WITHDRAW       an abort also drops a forwarded request that is not yet accepted
//                                 2 DONE_AFTER_KILL a walker done pulse in the abort cycle still reports done
//                                 3 SPEC_UNCACHED  a speculative walk forwards an uncached PTE address
//                                 4 KEEP_RESPONSE  a killed transaction's response is delivered to the walker
`timescale 1ns/1ps
module tcpu_ptw_wrap #(
  parameter WRAP_FAULT = 0,
  parameter FAULT_PTW_NO_PERM = 0   // passed to the walker (its own CPU-SV39 fault injection)
) (
  input             clk,
  input             rst,
  // ---- the walk request (accepted only while start_ok)
  input             start,
  input      [63:0] va,
  input      [1:0]  acc_type,
  input      [1:0]  eff_priv,
  input             sum,
  input             mxr,
  input      [43:0] root_ppn,
  input             spec,            // the walk is speculative (may change at any time; 0 lets an uncached PTE go)
  input             abort,           // abandon the current walk now (a flush, or a preemption)
  input             grant,           // the core's port arbiter lets the walker take the port this cycle
  output            start_ok,        // the walker is idle and no abort is being applied
  output            busy,            // a walk is in progress (not counting a killed transaction draining)
  // ---- the result (never for a killed walk)
  output            done,
  output            fault,
  output     [3:0]  cause,
  output     [55:0] pa,
  output     [43:0] leaf_ppn,
  output     [1:0]  leaf_level,
  output     [5:0]  leaf_perm,       // P2b: the leaf's {r, w, x, u, a, d}, for the TLB fill
  output            taking_port,     // P2b: the walker's request is forwarded onto the port this cycle
  output            port_busy,       // P2b: the holding register holds a transaction (live or killed)
  // ---- the physical port (one request in flight; the holding register below)
  output            req_valid,
  input             req_ready,
  output     [31:0] req_addr,
  input             resp_valid,
  input      [63:0] resp_rdata,
  input             resp_error,
  // ---- observation (simulation checks)
  output            dbg_killed_pending,
  output            dbg_unforwarded
);
  generate if (WRAP_FAULT < 0 || WRAP_FAULT > 4) begin : refuse_WRAP_FAULT pipe_p2a_unsupported_WRAP_FAULT u (); end endgenerate
  // ---- the holding register: {valid, waiting, killed, addr}
  reg         h_valid, h_wait, h_killed;
  reg  [31:0] h_addr;
  wire        h_fire = h_valid && req_ready;
  wire        h_resp = resp_valid && h_wait;
  wire        h_free = !h_valid && !h_wait;
  assign req_valid = h_valid;
  assign req_addr  = h_addr;

  // ---- the walker, unchanged; reset locally on an abort
  wire        w_req_valid, w_busy, w_done, w_fault;
  wire [31:0] w_req_addr;
  wire [3:0]  w_cause;
  wire [55:0] w_pa;
  wire [43:0] w_leaf_ppn;
  wire [1:0]  w_leaf_level;
  wire        w_lr, w_lw, w_lx, w_lu, w_la, w_ld;
  wire        cacheable;
  tcpu_cacheable cb (.pa(w_req_addr), .cacheable(cacheable));
  // the walker's own req_valid IS "not yet forwarded": it drops it the cycle after its handshake (tcpu_ptw.v WAIT)
  wire        may_forward = w_req_valid && h_free && grant && !abort &&
                            (!spec || cacheable || WRAP_FAULT == 3);
  // the walker's response: only the live transaction's (WRAP_FAULT 4: a killed one too)
  wire        deliver = h_resp && (!h_killed || WRAP_FAULT == 4) && !abort;
  tcpu_ptw #(.FAULT_PTW_NO_PERM(FAULT_PTW_NO_PERM)) walker (
    .clk(clk), .rst(rst || abort), .start(start && start_ok), .va(va), .acc_type(acc_type), .eff_priv(eff_priv),
    .sum(sum), .mxr(mxr), .root_ppn(root_ppn),
    .req_valid(w_req_valid), .req_ready(may_forward), .req_addr(w_req_addr),
    .resp_valid(deliver), .resp_rdata(resp_rdata), .resp_error(resp_error),
    .busy(w_busy), .done(w_done), .fault(w_fault), .cause(w_cause), .pa(w_pa),
    .leaf_ppn(w_leaf_ppn), .leaf_level(w_leaf_level), .leaf_r(w_lr), .leaf_w(w_lw), .leaf_x(w_lx), .leaf_u(w_lu),
    .leaf_a(w_la), .leaf_d(w_ld));
  assign start_ok = !w_busy && !abort && !rst;
  assign busy     = w_busy;
  // a done pulse in the abort cycle belongs to the abandoned walk
  wire   live_done = w_done && (!abort || WRAP_FAULT == 2);
  assign done = live_done;
  assign fault = w_fault;
  assign cause = w_cause;
  assign pa = w_pa;
  assign leaf_ppn = w_leaf_ppn;
  assign leaf_level = w_leaf_level;
  assign leaf_perm = {w_lr, w_lw, w_lx, w_lu, w_la, w_ld};
  assign taking_port = may_forward;
  assign port_busy = h_valid || h_wait;
  assign dbg_killed_pending = h_killed && (h_valid || h_wait);
  assign dbg_unforwarded = w_req_valid;

  always @(posedge clk) begin
    if (rst) begin
      h_valid <= 1'b0; h_wait <= 1'b0; h_killed <= 1'b0; h_addr <= 32'd0;
    end else begin
      if (h_fire) begin h_valid <= 1'b0; h_wait <= 1'b1; end
      if (h_resp) begin h_wait <= 1'b0; h_killed <= 1'b0; end
      if (may_forward) begin h_valid <= 1'b1; h_addr <= w_req_addr; h_killed <= 1'b0; end
      if (abort) begin
        // what the port has seen stays on the port; it is only marked (WRAP_FAULT 1: an unaccepted one is dropped)
        if (h_valid && !h_fire && WRAP_FAULT == 1) h_valid <= 1'b0;
        else if ((h_valid || (h_wait && !h_resp)) && !may_forward) h_killed <= 1'b1;
      end
    end
  end
endmodule
