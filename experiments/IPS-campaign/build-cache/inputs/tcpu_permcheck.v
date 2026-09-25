// The Sv39 leaf permission check, in ONE place.
//
// tcpu_ptw.v computed this inline. A TLB hit must reach the same verdict, and a second copy of the
// expression is a second thing to keep in step -- so both instantiate this. The check is not a property
// of the PTE alone: acc_type, eff_priv, SUM and MXR all vary from one access to the next against the
// same page, which is precisely why a TLB may cache the PTE's bits and may never cache the verdict.
//
// Privileged Architecture v20240411 section 10.3.4. A/D are software-managed here, so A=0 (or D=0 for a
// store or AMO) is a fault, not something hardware repairs.
`timescale 1ns/1ps
module tcpu_permcheck (
  input  [1:0] acc_type,     // 0 fetch, 1 load, 2 store, 3 AMO (reads AND writes)
  input  [1:0] eff_priv,     // 0 U, 1 S
  input        sum,
  input        mxr,
  input        pte_r,
  input        pte_w,
  input        pte_x,
  input        pte_u,
  input        pte_a,
  input        pte_d,
  output       ok
);
  // MXR substitutes X for R on a LOAD only; an AMO needs R and W together and MXR does not apply to it.
  wire perm_rwx = (acc_type == 2'd0) ? pte_x :
                  (acc_type == 2'd1) ? (pte_r | (mxr & pte_x)) :
                  (acc_type == 2'd3) ? (pte_r & pte_w) : pte_w;
  // S never executes a U page, whatever SUM says.
  wire perm_u   = (eff_priv == 2'd0) ? pte_u :
                  (acc_type == 2'd0) ? !pte_u : (!pte_u | sum);
  wire perm_ad  = pte_a && ((acc_type != 2'd2 && acc_type != 2'd3) || pte_d);
  assign ok = perm_rwx & perm_u & perm_ad;
endmodule
