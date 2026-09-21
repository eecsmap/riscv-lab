// CPU-SV39: the page-table walker. Serial, no TLB, no cache: one 8-byte PTE read per level over the
// core's single physical port (which the core hands to this module while `busy`). The steps are those of
// the Privileged Architecture v20240411 §10.3.4; the choices (software-managed A/D, 32-bit physical
// space, no Svnapot/Svpbmt) are stated in experiments/teaching-cpu/cpu-sv39/DESIGN.md.
//
// Contract with the core: `start` is a one-cycle pulse with va/type/priv/sum/mxr/root valid; the walker
// raises `busy` the next cycle and drives the request signals until `done` (one cycle) with either
// `fault` + `cause`, or `pa`. Requests are never withdrawn; a response is consumed the cycle it arrives.
`timescale 1ns/1ps
module tcpu_ptw #(
  parameter FAULT_PTW_NO_PERM = 0   // fault injection: the leaf permission checks (R/W/X/U/SUM/MXR) are skipped
) (
  input             clk,
  input             rst,
  input             start,
  input      [63:0] va,
  input      [1:0]  acc_type,        // 0 fetch, 1 load, 2 store, 3 AMO (CPU-A: reads and writes)
  input      [1:0]  eff_priv,        // the privilege the permission check uses (U = 0, S = 1)
  input             sum,
  input             mxr,
  input      [43:0] root_ppn,
  // the physical port while busy
  output reg        req_valid,
  input             req_ready,
  output reg [31:0] req_addr,
  input             resp_valid,
  input      [63:0] resp_rdata,
  input             resp_error,
  output reg        busy,
  output reg        done,
  output reg        fault,
  output reg [3:0]  cause,           // 12/13/15 page fault or 1/5/7 access fault, by acc_type
  output reg [55:0] pa
);
  localparam IDLE = 2'd0, REQ = 2'd1, WAIT = 2'd2;
  reg [1:0]  state;
  reg [1:0]  level;
  reg [55:0] a;                      // the current table's physical base
  reg [63:0] va_r;
  reg [1:0]  type_r, priv_r;
  reg        sum_r, mxr_r;

  wire [8:0] vpn = (level == 2'd2) ? va_r[38:30] : (level == 2'd1) ? va_r[29:21] : va_r[20:12];
  wire [55:0] pte_addr = a + {44'd0, vpn, 3'b000};
  wire [3:0] pf_cause = (type_r == 2'd0) ? 4'd12 : (type_r == 2'd1) ? 4'd13 : 4'd15;   // 3 (AMO) is store-class
  wire [3:0] af_cause = (type_r == 2'd0) ? 4'd1  : (type_r == 2'd1) ? 4'd5  : 4'd7;
  wire canonical = (va[63:39] == {25{va[38]}});

  // the PTE just read
  wire        pte_v = resp_rdata[0], pte_r = resp_rdata[1], pte_w = resp_rdata[2], pte_x = resp_rdata[3],
              pte_u = resp_rdata[4], pte_a = resp_rdata[6], pte_d = resp_rdata[7];
  wire [43:0] pte_ppn = resp_rdata[53:10];
  wire        pte_reserved = |resp_rdata[63:54];
  wire        pte_leaf = pte_r | pte_x;
  wire        misaligned_super = (level == 2'd2 && pte_ppn[17:0] != 18'd0) || (level == 2'd1 && pte_ppn[8:0] != 9'd0);
  // CPU-A: an AMO both reads and writes, so it needs R and W together; MXR does not apply to it (it
  // substitutes for a *load*'s read permission only). An SC only writes. This is Rocket's rule.
  wire        perm_rwx = (type_r == 2'd0) ? pte_x :
                         (type_r == 2'd1) ? (pte_r | (mxr_r & pte_x)) :
                         (type_r == 2'd3) ? (pte_r & pte_w) : pte_w;
  wire        perm_u   = (priv_r == 2'd0) ? pte_u :
                         (type_r == 2'd0) ? !pte_u : (!pte_u | sum_r);   // S never executes a U page
  wire        perm_ad  = pte_a && ((type_r != 2'd2 && type_r != 2'd3) || pte_d);
  wire        perm_ok  = (FAULT_PTW_NO_PERM != 0) ? perm_ad : (perm_rwx && perm_u && perm_ad);
  wire [55:0] leaf_pa  = (level == 2'd2) ? {pte_ppn[43:18], va_r[29:0]} :
                         (level == 2'd1) ? {pte_ppn[43:9],  va_r[20:0]} : {pte_ppn, va_r[11:0]};

  always @(posedge clk) begin
    done <= 1'b0; fault <= 1'b0;
    if (rst) begin
      state <= IDLE; busy <= 1'b0; req_valid <= 1'b0; req_addr <= 32'd0; level <= 2'd2; a <= 56'd0;
      va_r <= 64'd0; type_r <= 2'd0; priv_r <= 2'd0; sum_r <= 1'b0; mxr_r <= 1'b0; cause <= 4'd0; pa <= 56'd0;
    end else case (state)
      IDLE: if (start) begin
        va_r <= va; type_r <= acc_type; priv_r <= eff_priv; sum_r <= sum; mxr_r <= mxr;
        a <= {root_ppn, 12'd0}; level <= 2'd2; busy <= 1'b1;
        if (!canonical) begin
          // a non-canonical virtual address is a page fault of the access's class (§10.3.4 step 1 note)
          done <= 1'b1; fault <= 1'b1; busy <= 1'b0;
          cause <= (acc_type == 2'd0) ? 4'd12 : (acc_type == 2'd1) ? 4'd13 : 4'd15;
        end else state <= REQ;
      end
      REQ: begin
        // the PTE's physical address must exist: the SoC has a 32-bit physical space
        if (pte_addr[55:32] != 24'd0) begin
          done <= 1'b1; fault <= 1'b1; cause <= af_cause; busy <= 1'b0; state <= IDLE;
        end else begin
          req_valid <= 1'b1; req_addr <= pte_addr[31:0]; state <= WAIT;
        end
      end
      WAIT: begin
        if (req_valid && req_ready) req_valid <= 1'b0;          // payload held until the handshake
        if (resp_valid) begin
          if (resp_error) begin
            done <= 1'b1; fault <= 1'b1; cause <= af_cause; busy <= 1'b0; state <= IDLE;
          end else if (!pte_v || (!pte_r && pte_w) || pte_reserved) begin
            done <= 1'b1; fault <= 1'b1; cause <= pf_cause; busy <= 1'b0; state <= IDLE;
          end else if (!pte_leaf) begin
            // A non-leaf PTE: D, A and U are reserved (v20240411 §10.3.1) and any of them set is a page
            // fault of the access's class (§10.3.4 step 3); G and RSW are not (Codex review, nonleaf-fix).
            if (level == 2'd0 || pte_u || pte_a || pte_d) begin   // a pointer where a leaf must be, or a reserved bit set
              done <= 1'b1; fault <= 1'b1; cause <= pf_cause; busy <= 1'b0; state <= IDLE;
            end else begin
              a <= {pte_ppn, 12'd0}; level <= level - 2'd1; state <= REQ;
            end
          end else if (misaligned_super || !perm_ok) begin
            done <= 1'b1; fault <= 1'b1; cause <= pf_cause; busy <= 1'b0; state <= IDLE;
          end else begin
            done <= 1'b1; pa <= leaf_pa; busy <= 1'b0; state <= IDLE;
          end
        end
      end
      default: state <= IDLE;
    endcase
  end
endmodule
