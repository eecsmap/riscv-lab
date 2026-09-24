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
  output reg        done,
  output reg        fault,
  output reg [3:0]  cause,
  output reg [55:0] pa,

  // observation only: not architectural, and not relied on by the core
  output reg        o_hit,
  output reg        o_miss
);
  // ---- the request being translated, latched at `start` so a hit can be answered next cycle
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
  reg         ptw_start;

  // The walker reports the leaf it used; those bits are what gets cached.
  wire [43:0] ptw_leaf_ppn;
  wire [1:0]  ptw_leaf_level;
  wire        ptw_leaf_r, ptw_leaf_w, ptw_leaf_x, ptw_leaf_u, ptw_leaf_a, ptw_leaf_d;

  tcpu_tlb #(.ENTRIES(TLB_ENTRIES)) tlb (
    .clk(clk), .rst(rst), .flush(flush),
    .va(va_r), .hit(tlb_hit), .hit_ppn(tlb_ppn), .hit_level(tlb_level),
    .hit_r(tlb_r), .hit_w(tlb_w), .hit_x(tlb_x), .hit_u(tlb_u), .hit_a(tlb_a), .hit_d(tlb_d),
    .fill(tlb_fill), .fill_va(va_r), .fill_level(ptw_leaf_level), .fill_ppn(ptw_leaf_ppn),
    .fill_r(ptw_leaf_r), .fill_w(ptw_leaf_w), .fill_x(ptw_leaf_x),
    .fill_u(ptw_leaf_u), .fill_a(ptw_leaf_a), .fill_d(ptw_leaf_d));

  wire hit_perm_ok;
  tcpu_permcheck hit_perm (
    .acc_type(type_r), .eff_priv(priv_r), .sum(sum_r), .mxr(mxr_r),
    .pte_r(tlb_r), .pte_w(tlb_w), .pte_x(tlb_x), .pte_u(tlb_u), .pte_a(tlb_a), .pte_d(tlb_d),
    .ok(hit_perm_ok));

  // the PA a hit yields, rebuilt exactly as tcpu_ptw's leaf_pa does
  wire [55:0] hit_pa = (tlb_level == 2'd2) ? {tlb_ppn[43:18], va_r[29:0]} :
                       (tlb_level == 2'd1) ? {tlb_ppn[43:9],  va_r[20:0]} : {tlb_ppn, va_r[11:0]};
  wire [3:0]  hit_pf_cause = (type_r == 2'd0) ? 4'd12 : (type_r == 2'd1) ? 4'd13 : 4'd15;
  // a non-canonical VA is the walker's business; it is never cached, so a hit cannot be non-canonical

  tcpu_ptw #(.FAULT_PTW_NO_PERM(FAULT_PTW_NO_PERM)) ptw (
    .clk(clk), .rst(rst), .start(ptw_start), .va(va_r), .acc_type(type_r), .eff_priv(priv_r),
    .sum(sum_r), .mxr(mxr_r), .root_ppn(root_ppn),
    .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr),
    .resp_valid(resp_valid), .resp_rdata(resp_rdata), .resp_error(resp_error),
    .busy(ptw_busy), .done(ptw_done), .fault(ptw_fault), .cause(ptw_cause), .pa(ptw_pa),
    .leaf_ppn(ptw_leaf_ppn), .leaf_level(ptw_leaf_level),
    .leaf_r(ptw_leaf_r), .leaf_w(ptw_leaf_w), .leaf_x(ptw_leaf_x),
    .leaf_u(ptw_leaf_u), .leaf_a(ptw_leaf_a), .leaf_d(ptw_leaf_d));

  reg lookup;                 // one cycle: the TLB is being consulted for the latched request
  assign busy = ptw_busy | lookup | start;
  always @(posedge clk) begin
    done <= 1'b0; fault <= 1'b0; ptw_start <= 1'b0; tlb_fill <= 1'b0;
    o_hit <= 1'b0; o_miss <= 1'b0;
    if (rst) begin
      lookup <= 1'b0; va_r <= 64'd0; type_r <= 2'd0; priv_r <= 2'd0; sum_r <= 1'b0; mxr_r <= 1'b0;
      cause <= 4'd0; pa <= 56'd0;
    end else begin
      if (start) begin
        va_r <= va; type_r <= acc_type; priv_r <= eff_priv; sum_r <= sum; mxr_r <= mxr;
        lookup <= 1'b1;
      end else if (lookup) begin
        lookup <= 1'b0;
        if (tlb_hit) begin
          o_hit <= 1'b1;
          done  <= 1'b1;
          if (hit_perm_ok) begin
            pa <= hit_pa;
          end else begin
            fault <= 1'b1; cause <= hit_pf_cause;
          end
        end else begin
          o_miss <= 1'b1;
          ptw_start <= 1'b1;
        end
      end
      if (ptw_done) begin
        done  <= 1'b1;
        fault <= ptw_fault;
        cause <= ptw_cause;
        pa    <= ptw_pa;
        // ONLY a walk that produced a PA fills
        if (!ptw_fault) tlb_fill <= 1'b1;
      end
    end
  end
endmodule
