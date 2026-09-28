# FENCE.I: a routine is executed (so its line is in the I-cache), rewritten by stores, FENCE.I, executed again:
# the new code must run. Then the same without FENCE.I is NOT checked (stale execution is allowed there).
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        mv      s5, ra
        la      s0, patch_fn
        jalr    ra, 0(s0)
        CHECK_EQ(a0, 1, 1)
        la      t0, new_code
        lw      t1, 0(t0)
        sw      t1, 0(s0)           # li a0, 2
        fence.i
        jalr    ra, 0(s0)
        CHECK_EQ(a0, 2, 2)
        mv      ra, s5
        li      a0, 0
        ret
        .align 4
patch_fn:
        li      a0, 1
        ret
new_code:
        li      a0, 2
