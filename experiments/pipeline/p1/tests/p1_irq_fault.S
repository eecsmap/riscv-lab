# An interrupt and an older synchronous exception close together (the harness raises the line near the faulting
# load; the run is repeated at several positions). Both must be taken exactly once, in some order; each epc must
# be right; the counted work must be complete.
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        li      t0, 8
        csrw    mie, t0
        csrsi   mstatus, 8
        li      a1, 0
        .rept 12
        addi    a1, a1, 1
        .endr
        li      t1, 1
        slli    t1, t1, 40
the_load:
        ld      t2, 0(t1)           # load access fault (cause 5), detected in MEM
        .rept 12
        addi    a1, a1, 1
        .endr
        li      t3, 300
1:      addi    t3, t3, -1
        bnez    t3, 1b
        csrci   mstatus, 8
        CHECK_EQ(a1, 24, 1)
        la      t0, trap_n
        ld      t0, 0(t0)
        CHECK_EQ(t0, 2, 2)
        la      t0, irq_n
        ld      t0, 0(t0)
        CHECK_EQ(t0, 1, 3)
        # find the load fault in the log (entry 0 or 1) and check it
        LOG_ENTRY(0)
        bltz    t4, 2f
        j       3f
2:      LOG_ENTRY(1)
3:      CHECK_EQ(t4, 5, 4)
        la      t0, the_load
        CHECK_REG(t5, t0, 5)
        li      a0, 0
        ret
