// A small fully-associative TLB, shared between instruction and data accesses.
//
// Design fixed before implementation in experiments/IPS-campaign/STAGE2-DESIGN.md. The short version:
//
//   * it caches the leaf PTE's BITS, never the walker's verdict, because the verdict depends on the
//     access and the bits do not;
//   * replacement is round-robin, so the same program produces the same fills in the same order and a
//     cycle count is reproducible;
//   * invalidation is a conservative full flush on every sfence.vma and every satp write, so no ASID
//     and no G bit are stored -- an entry cannot outlive the address space it was filled in;
//   * a walk that FAULTED fills nothing.
//
// ENTRIES = 0 disables it entirely: `hit` is constant 0 and every access walks, which must be
// architecturally identical to the predecessor stage. That is a test, not a feature.
`timescale 1ns/1ps
module tcpu_tlb #(
  parameter ENTRIES = 8
) (
  input             clk,
  input             rst,
  input             flush,            // sfence.vma (any form) or a satp write

  // combinational lookup
  input      [63:0] va,
  output            hit,
  output     [43:0] hit_ppn,
  output     [1:0]  hit_level,
  output            hit_r,
  output            hit_w,
  output            hit_x,
  output            hit_u,
  output            hit_a,
  output            hit_d,

  // fill, one cycle, only from a walk that produced a PA
  input             fill,
  input      [63:0] fill_va,
  input      [1:0]  fill_level,
  input      [43:0] fill_ppn,
  input             fill_r,
  input             fill_w,
  input             fill_x,
  input             fill_u,
  input             fill_a,
  input             fill_d
);
  generate
  if (ENTRIES == 0) begin : g_disabled
    assign hit = 1'b0; assign hit_ppn = 44'd0; assign hit_level = 2'd0;
    assign hit_r = 1'b0; assign hit_w = 1'b0; assign hit_x = 1'b0;
    assign hit_u = 1'b0; assign hit_a = 1'b0; assign hit_d = 1'b0;
    // fill and flush are accepted and ignored; nothing is stored, so nothing can go stale.
    wire _unused = &{1'b0, clk, rst, flush, va, fill, fill_va, fill_level, fill_ppn,
                     fill_r, fill_w, fill_x, fill_u, fill_a, fill_d};
  end else begin : g_tlb
    reg              v      [0:ENTRIES-1];
    reg  [26:0]      vpn    [0:ENTRIES-1];
    reg  [1:0]       lvl    [0:ENTRIES-1];
    reg  [43:0]      ppn    [0:ENTRIES-1];
    reg  [5:0]       perm   [0:ENTRIES-1];      // {r,w,x,u,a,d}
    reg  [31:0]      rr;                        // round-robin pointer, wider than needed and masked

    wire [26:0] look_vpn = va[38:12];
    wire [26:0] fillvpn  = fill_va[38:12];

    // A superpage matches on the bits above its own boundary only. The mask is the entry's own level,
    // so two 4 KiB pages inside one 2 MiB superpage cannot be confused for each other and a 2 MiB entry
    // is found by any address inside it.
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
    reg              h;
    reg [43:0]       h_ppn;
    reg [1:0]        h_lvl;
    reg [5:0]        h_perm;
    always @(*) begin
      h = 1'b0; h_ppn = 44'd0; h_lvl = 2'd0; h_perm = 6'd0;
      for (i = 0; i < ENTRIES; i = i + 1) begin
        if (!h && v[i] && match(vpn[i], lvl[i], look_vpn)) begin
          h = 1'b1; h_ppn = ppn[i]; h_lvl = lvl[i]; h_perm = perm[i];
        end
      end
    end
    assign hit = h; assign hit_ppn = h_ppn; assign hit_level = h_lvl;
    assign {hit_r, hit_w, hit_x, hit_u, hit_a, hit_d} = h_perm;

    always @(posedge clk) begin
      if (rst) begin
        for (i = 0; i < ENTRIES; i = i + 1) v[i] <= 1'b0;
        rr <= 32'd0;
      end else if (flush) begin
        // every entry, in one cycle: more conservative than the architecture requires, deliberately
        for (i = 0; i < ENTRIES; i = i + 1) v[i] <= 1'b0;
      end else if (fill) begin
        v   [rr[31:0] % ENTRIES] <= 1'b1;
        vpn [rr[31:0] % ENTRIES] <= fillvpn;
        lvl [rr[31:0] % ENTRIES] <= fill_level;
        ppn [rr[31:0] % ENTRIES] <= fill_ppn;
        perm[rr[31:0] % ENTRIES] <= {fill_r, fill_w, fill_x, fill_u, fill_a, fill_d};
        rr <= rr + 32'd1;
      end
    end
  end
  endgenerate
endmodule
