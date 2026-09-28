# Two flushes while one fetch transaction is outstanding (CONTRACT §3.1): a younger taken branch redirects in EX
# (flush 1) while the older load in MEM faults beyond the physical space and traps in WB (flush 2). All code here
# is cold, so wrong-path refills are in flight, and the handler's own code is cold too, so the front end is
# waiting for the fetch engine when the stale refill returns. Correct: the stale response is discarded.
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        la      t0, tf_handler
        csrw    mtvec, t0
        li      a1, 0
        li      t1, 1
        slli    t1, t1, 40
        .align 4
        ld      t2, 0(t1)           # faults in MEM
        beq     x0, x0, tf_target   # taken: redirect while the load is in MEM
        .rept 16
        addi    a1, a1, 100         # wrong path: never executed
        .endr
        .space 256
tf_target:
        addi    a1, a1, 1
        CHECK_EQ(a1, 2, 1)          # the handler added 1, the target added 1
        la      t0, tf_count
        ld      t0, 0(t0)
        CHECK_EQ(t0, 1, 2)
        li      a0, 0
        ret
        .space 512
        .align 4
tf_handler:
        addi    a1, a1, 1
        la      t4, tf_count
        ld      t5, 0(t4)
        addi    t5, t5, 1
        sd      t5, 0(t4)
        csrr    t4, mepc
        addi    t4, t4, 4
        csrw    mepc, t4
        mret
        .data
        .align 3
tf_count: .dword 0
