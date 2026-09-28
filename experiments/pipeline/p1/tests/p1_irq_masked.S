# The line is raised while MIE = 0: nothing may be taken. The instruction that sets MIE is serialising, so the
# interrupt is taken at the very next boundary: mepc must be exactly the instruction after the CSR write.
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        li      t0, 8
        csrw    mie, t0
        li      a1, 0
        .rept 40
        addi    a1, a1, 1           # the harness raises the line during these, with MIE still 0
        .endr
        li      t1, 100
1:      addi    t1, t1, -1
        bnez    t1, 1b
        la      t0, irq_n
        ld      t0, 0(t0)
        CHECK_EQ(t0, 0, 1)          # masked: not taken
        csrsi   mstatus, 8          # enable
after_enable:
        addi    a1, a1, 1
        csrci   mstatus, 8
        la      t0, irq_n
        ld      t0, 0(t0)
        CHECK_EQ(t0, 1, 2)
        LOG_ENTRY(0)
        la      t1, after_enable
        CHECK_REG(t5, t1, 3)        # taken at the boundary right after the enabling instruction
        CHECK_EQ(a1, 41, 4)
        li      a0, 0
        ret
