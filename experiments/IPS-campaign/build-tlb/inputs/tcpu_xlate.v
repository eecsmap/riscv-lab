// Address translation: a TLB in front of the walker, presenting the WALKER'S OWN INTERFACE.
//
// The core's S_XLATE state is unchanged by this stage. It still pulses `start`, waits for `done`, and
// reads `fault`/`cause`/`pa`. What changes is that a hit answers in one cycle without touching the
// memory port, and a miss walks exactly as before and then fills.
//
// The permission check is NOT cached. tcpu_permcheck is instantiated here and evaluated on every hit
// with that access's own type, privilege, SUM and MXR -- the same module tcpu_ptw.v uses, proved
// exhaustively equivalent to the expression it replaced. A hit that fails the check raises the same
// page fault, with the same cause, that the walker would have raised.
//
// Only a walk that produced a PA fills. A faulting walk leaves the TLB alone, so a faulting access
// repeated faults again for its own reason rather than hitting something it should never have cached.
`timescale 1ns/1ps
module tcpu_xlate #(
  parameter TLB_ENTRIES = 8,
  parameter FAULT_PTW_NO_PERM = 0
) (
  input             clk,
  input             rst,
  input             flush,           // sfence.vma (any form) or a change of satp

  input             start,
  input      [63:0] va,
  input      [1:0]  acc_type,
  input      [1:0]  eff_priv,
  input             sum,
  input             mxr,
  input      [43:0] root_ppn,

  // the physical port, driven only while a WALK is in progress
  output            req_valid,
  input             req_ready,
  output     [31:0] req_addr,
  input             resp_valid,
  input      [63:0] resp_rdata,
  input             resp_error,

  output            busy,
  output            done,
  output            fault,
  output     [3:0]  cause,
  output     [55:0] pa,

  // observation only: not architectural, and not relied on by the core
  output reg        o_hit,
  output reg        o_miss
);
  // ---- The lookup is COMBINATIONAL, on the incoming request, in the cycle `start` arrives.
  //
  // The first version latched the request and spent a cycle looking it up before starting the walk.
  // That cost one cycle on EVERY translation, and it showed: with the TLB disabled, perf02's 4 KiB ALU
  // ROI read 40.05 CPI against fetch32's 37.04. The disabled configuration is supposed to be
  // architecturally equivalent to fetch32 AND cycle-identical to it, and "close" is not identical.
  //
  // So the walker is started from the same signal, in the same cycle, as the core used to start it
  // directly: `start & ~hit`. The core holds va/acc_type/priv stable for the whole translation, which
  // is what made the extra latch unnecessary in the first place.
  reg [63:0] va_r;
  reg [1:0]  type_r, priv_r;
  reg        sum_r, mxr_r;

  wire        tlb_hit;
  wire [43:0] tlb_ppn;
  wire [1:0]  tlb_level;
  wire        tlb_r, tlb_w, tlb_x, tlb_u, tlb_a, tlb_d;
  reg         tlb_fill;

  wire        ptw_done, ptw_fault, ptw_busy;
  wire [3:0]  ptw_cause;
  wire [55:0] ptw_pa;

  // The walker reports the leaf it used; those bits are what gets cached.
  wire [43:0] ptw_leaf_ppn;
  wire [1:0]  ptw_leaf_level;
  wire        ptw_leaf_r, ptw_leaf_w, ptw_leaf_x, ptw_leaf_u, ptw_leaf_a, ptw_leaf_d;

  // looked up on the INCOMING va during `start`, and on the latched one afterwards so the fill can
  // still address the right entry
  wire [63:0] look_va = start ? va : va_r;
  tcpu_tlb #(.ENTRIES(TLB_ENTRIES)) tlb (
    .clk(clk), .rst(rst), .flush(flush),
    .va(look_va), .hit(tlb_hit), .hit_ppn(tlb_ppn), .hit_level(tlb_level),
    .hit_r(tlb_r), .hit_w(tlb_w), .hit_x(tlb_x), .hit_u(tlb_u), .hit_a(tlb_a), .hit_d(tlb_d),
    .fill(tlb_fill), .fill_va(va_r), .fill_level(ptw_leaf_level), .fill_ppn(ptw_leaf_ppn),
    .fill_r(ptw_leaf_r), .fill_w(ptw_leaf_w), .fill_x(ptw_leaf_x),
    .fill_u(ptw_leaf_u), .fill_a(ptw_leaf_a), .fill_d(ptw_leaf_d));

  wire [1:0] look_type = start ? acc_type : type_r;
  wire [1:0] look_priv = start ? eff_priv : priv_r;
  wire       look_sum  = start ? sum      : sum_r;
  wire       look_mxr  = start ? mxr      : mxr_r;
  wire hit_perm_ok;
  tcpu_permcheck hit_perm (
    .acc_type(look_type), .eff_priv(look_priv), .sum(look_sum), .mxr(look_mxr),
    .pte_r(tlb_r), .pte_w(tlb_w), .pte_x(tlb_x), .pte_u(tlb_u), .pte_a(tlb_a), .pte_d(tlb_d),
    .ok(hit_perm_ok));

  // the PA a hit yields, rebuilt exactly as tcpu_ptw's leaf_pa does
  wire [55:0] hit_pa = (tlb_level == 2'd2) ? {tlb_ppn[43:18], look_va[29:0]} :
                       (tlb_level == 2'd1) ? {tlb_ppn[43:9],  look_va[20:0]} : {tlb_ppn, look_va[11:0]};
  wire [3:0]  hit_pf_cause = (look_type == 2'd0) ? 4'd12 : (look_type == 2'd1) ? 4'd13 : 4'd15;

  // CANONICALITY. The comment that used to sit here said a hit cannot be non-canonical because a
  // non-canonical VA is never cached. That was false and Codex reproduced it: tcpu_tlb compares only
  // va[38:12], so an entry filled by a CANONICAL address is hit by a later NON-CANONICAL alias with
  // the same low VPN and different upper bits, and the hit path skipped the walker's
  // `va[63:39] == {25{va[38]}}` check entirely. Observed fault=0 cause=0 hit=1 where a load page fault
  // was required.
  //
  // The repair does not duplicate the check or the fault. A non-canonical VA simply may not USE a
  // cached entry, so it goes to the walker -- which rejects it in its IDLE state, before issuing any
  // request, with the cause the architecture requires and the tval the core already reports. No
  // physical access happens on an invalid hit because the walker never makes one for a
  // non-canonical address.
  //
  // With TLB_ENTRIES = 0, tlb_hit is constant 0, so `tlb_hit & canonical` is constant 0 too and the
  // disabled-TLB timing control is untouched.
  wire        canonical  = (look_va[63:39] == {25{look_va[38]}});
  wire        hit_usable = tlb_hit & canonical;

  wire ptw_start_w = start & ~hit_usable;
  tcpu_ptw #(.FAULT_PTW_NO_PERM(FAULT_PTW_NO_PERM)) ptw (
    .clk(clk), .rst(rst), .start(ptw_start_w), .va(va), .acc_type(acc_type), .eff_priv(eff_priv),
    .sum(sum), .mxr(mxr), .root_ppn(root_ppn),
    .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr),
    .resp_valid(resp_valid), .resp_rdata(resp_rdata), .resp_error(resp_error),
    .busy(ptw_busy), .done(ptw_done), .fault(ptw_fault), .cause(ptw_cause), .pa(ptw_pa),
    .leaf_ppn(ptw_leaf_ppn), .leaf_level(ptw_leaf_level),
    .leaf_r(ptw_leaf_r), .leaf_w(ptw_leaf_w), .leaf_x(ptw_leaf_x),
    .leaf_u(ptw_leaf_u), .leaf_a(ptw_leaf_a), .leaf_d(ptw_leaf_d));

  // A WALK's result passes STRAIGHT THROUGH, exactly as it did when the core instantiated the walker
  // directly. Registering it added a cycle to every miss -- which showed as perf02's megapage ALU ROI
  // reading 660,047 cycles with the TLB disabled against fetch32's 631,753. Only the HIT path is
  // registered, because a hit has to be answered one cycle after the lookup and there is nothing else
  // to answer it with.
  reg        hit_done, hit_fault;
  reg [3:0]  hit_cause;
  reg [55:0] hit_pa_r;
  assign done  = ptw_done | hit_done;
  assign fault = ptw_done ? ptw_fault : hit_fault;
  assign cause = ptw_done ? ptw_cause : hit_cause;
  assign pa    = ptw_done ? ptw_pa    : hit_pa_r;
  assign busy  = ptw_busy | start | hit_done;
  always @(posedge clk) begin
    tlb_fill <= 1'b0; o_hit <= 1'b0; o_miss <= 1'b0;
    hit_done <= 1'b0; hit_fault <= 1'b0;
    if (rst) begin
      va_r <= 64'd0; type_r <= 2'd0; priv_r <= 2'd0; sum_r <= 1'b0; mxr_r <= 1'b0;
      hit_cause <= 4'd0; hit_pa_r <= 56'd0;
    end else begin
      if (start) begin
        va_r <= va; type_r <= acc_type; priv_r <= eff_priv; sum_r <= sum; mxr_r <= mxr;
        if (hit_usable) begin
          o_hit    <= 1'b1;
          hit_done <= 1'b1;
          if (hit_perm_ok) hit_pa_r <= hit_pa;
          else begin hit_fault <= 1'b1; hit_cause <= hit_pf_cause; end
        end else begin
          o_miss <= 1'b1;            // the walker was started combinationally, in THIS cycle
        end
      end
      // ONLY a walk that produced a PA fills. The result itself is not registered here.
      if (ptw_done && !ptw_fault) tlb_fill <= 1'b1;
    end
  end
endmodule
