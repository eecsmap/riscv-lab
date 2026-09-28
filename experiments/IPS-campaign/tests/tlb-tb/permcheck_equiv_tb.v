// tcpu_permcheck must be EXACTLY what tcpu_ptw.v computed inline, over every input.
//
// The refactor's whole point is that there is one expression rather than two that can drift. That is
// only true if the extraction changed nothing, and the input space is 4 * 4 * 2 * 2 * 64 = 4096
// combinations -- small enough that "equivalent" can be proved rather than argued.
//
// The reference below is transcribed from tcpu_ptw.v as it stood at 09449b24 (the accepted core), with
// FAULT_PTW_NO_PERM = 0. If it is ever edited to match the module, this test stops meaning anything.
`timescale 1ns/1ps
module permcheck_equiv_tb;
  reg [1:0] acc_type, eff_priv; reg sum, mxr;
  reg pte_r, pte_w, pte_x, pte_u, pte_a, pte_d;
  wire ok;
  tcpu_permcheck dut (.acc_type(acc_type), .eff_priv(eff_priv), .sum(sum), .mxr(mxr),
                      .pte_r(pte_r), .pte_w(pte_w), .pte_x(pte_x), .pte_u(pte_u),
                      .pte_a(pte_a), .pte_d(pte_d), .ok(ok));

  // ---- the reference, as tcpu_ptw.v wrote it
  wire ref_rwx = (acc_type == 2'd0) ? pte_x :
                 (acc_type == 2'd1) ? (pte_r | (mxr & pte_x)) :
                 (acc_type == 2'd3) ? (pte_r & pte_w) : pte_w;
  wire ref_u   = (eff_priv == 2'd0) ? pte_u :
                 (acc_type == 2'd0) ? !pte_u : (!pte_u | sum);
  wire ref_ad  = pte_a && ((acc_type != 2'd2 && acc_type != 2'd3) || pte_d);
  wire ref_ok  = (ref_rwx && ref_u && ref_ad);

  integer i, bad = 0, n = 0;
  initial begin
    for (i = 0; i < 4096; i = i + 1) begin
      {acc_type, eff_priv, sum, mxr, pte_r, pte_w, pte_x, pte_u, pte_a, pte_d} = i[11:0];
      #1;
      n = n + 1;
      if (ok !== ref_ok) begin
        bad = bad + 1;
        if (bad <= 5)
          $display("  DIFFER at %0d: type=%0d priv=%0d sum=%b mxr=%b rwxuad=%b%b%b%b%b%b module=%b ptw=%b",
                   i, acc_type, eff_priv, sum, mxr, pte_r, pte_w, pte_x, pte_u, pte_a, pte_d, ok, ref_ok);
      end
    end
    $display("PERMCHECK_EQUIV combinations=%0d differing=%0d", n, bad);
    if (bad != 0) $fatal(1, "the extraction CHANGED the permission check");
    $display("PERMCHECK_EQUIV_OK");
    $finish;
  end
endmodule
