// PIPE-P2b: the pipeline's TLB -- the policy of the shared tcpu_tlb.v, with TWO combinational lookup ports.
//
// F1 looks up the instruction fetch and MEM looks up the data access in the same cycle, so one lookup port is not
// enough; tcpu_tlb.v (unchanged, still used by the multicycle core) has one. Everything else is its policy, kept:
//   * it caches the leaf PTE's BITS, never a verdict (the permission check runs on every hit, per access);
//   * round-robin replacement, so the same program fills the same entries in the same order;
//   * a conservative full flush on every sfence.vma and every satp write (no ASID, no G bit stored);
//   * only a walk that produced a PA fills, and a flush in the same cycle wins over a fill;
//   * a superpage entry matches on the bits above its own boundary only.
`timescale 1ns/1ps
module tcpu_tlb2 #(
  parameter ENTRIES = 8,
  parameter NO_FLUSH = 0           // negative control (PIPE_FAULT 21): the flush is ignored
) (
  input             clk,
  input             rst,
  input             flush,
  // lookup port A (fetch) and port B (data), combinational
  input      [63:0] va_a,
  output            hit_a,
  output     [43:0] ppn_a,
  output     [1:0]  lvl_a,
  output     [5:0]  perm_a,        // {r, w, x, u, a, d}
  input      [63:0] va_b,
  output            hit_b,
  output     [43:0] ppn_b,
  output     [1:0]  lvl_b,
  output     [5:0]  perm_b,
  // fill, one cycle
  input             fill,
  input      [63:0] fill_va,
  input      [1:0]  fill_level,
  input      [43:0] fill_ppn,
  input      [5:0]  fill_perm
);
  reg              v    [0:ENTRIES-1];
  reg  [26:0]      vpn  [0:ENTRIES-1];
  reg  [1:0]       lvl  [0:ENTRIES-1];
  reg  [43:0]      ppn  [0:ENTRIES-1];
  reg  [5:0]       perm [0:ENTRIES-1];
  reg  [31:0]      rr;
  function match;
    input [26:0] tag; input [1:0] level; input [26:0] probe;
    begin
      case (level)
        2'd2:    match = (tag[26:18] == probe[26:18]);
        2'd1:    match = (tag[26:9]  == probe[26:9]);
        default: match = (tag        == probe);
      endcase
    end
  endfunction
  integer i;
  reg ha, hb; reg [43:0] pa_, pb_; reg [1:0] la_, lb_; reg [5:0] qa_, qb_;
  always @(*) begin
    ha = 1'b0; pa_ = 44'd0; la_ = 2'd0; qa_ = 6'd0;
    hb = 1'b0; pb_ = 44'd0; lb_ = 2'd0; qb_ = 6'd0;
    for (i = 0; i < ENTRIES; i = i + 1) begin
      if (!ha && v[i] && match(vpn[i], lvl[i], va_a[38:12])) begin ha = 1'b1; pa_ = ppn[i]; la_ = lvl[i]; qa_ = perm[i]; end
      if (!hb && v[i] && match(vpn[i], lvl[i], va_b[38:12])) begin hb = 1'b1; pb_ = ppn[i]; lb_ = lvl[i]; qb_ = perm[i]; end
    end
  end
  assign hit_a = ha; assign ppn_a = pa_; assign lvl_a = la_; assign perm_a = qa_;
  assign hit_b = hb; assign ppn_b = pb_; assign lvl_b = lb_; assign perm_b = qb_;
  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < ENTRIES; i = i + 1) v[i] <= 1'b0;
      rr <= 32'd0;
    end else if (flush && NO_FLUSH == 0) begin
      for (i = 0; i < ENTRIES; i = i + 1) v[i] <= 1'b0;
    end else if (fill) begin
      v   [rr % ENTRIES] <= 1'b1;
      vpn [rr % ENTRIES] <= fill_va[38:12];
      lvl [rr % ENTRIES] <= fill_level;
      ppn [rr % ENTRIES] <= fill_ppn;
      perm[rr % ENTRIES] <= fill_perm;
      rr <= rr + 32'd1;
    end
  end
endmodule
