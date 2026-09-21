# c10: taking a trap is not a retirement. minstret is read immediately before a faulting instruction and
# again as the fourth instruction of the handler; exactly three handler instructions have retired in
# between (the mscratch swap and two stores), and the faulting word must contribute nothing. The delta is
# therefore exactly 4: the pre-trap csrr itself plus those three.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        .option push
        .option norvc
        csrr    s3, minstret
        .word   0x00000000                     # traps: must not be counted
        .option pop
        la      t0, handler_entry_instret
        ld      t1, 0(t0)
        sub     s4, t1, s3
        li      t2, 4
        CHECK_EQ_R(s4, t2, 1)
        la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 1, 2)
        PASS
