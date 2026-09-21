# c06: jump-target alignment. A taken jump to a misaligned target raises cause 0 with mtval = the target;
# a branch that is not taken must not look at its target at all.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        # ---- not taken, misaligned target: must not trap (`bne x0, x0, .+2`)
        .option push
        .option norvc
        .word   0x00001163
        .option pop
        la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 0, 1)
        # ---- taken jalr to a misaligned target: cause 0, mtval = the target
        la      s0, 1f
        addi    s0, s0, 2                       # a 2-byte misaligned target, and this core has no C
        .option push
        .option norvc
        jalr    x1, 0(s0)
        .option pop
1:      la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 1, 2)
        la      t0, last_cause
        ld      t1, 0(t0)
        CHECK_EQ(t1, 0, 3)
        la      t0, last_tval
        ld      t1, 0(t0)
        CHECK_EQ_R(t1, s0, 4)                   # mtval is the offending target address
        PASS
