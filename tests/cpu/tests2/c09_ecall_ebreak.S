# c09: the environment calls. Both raise an exception rather than retiring, mtval is 0 for ecall and the
# instruction's own address for ebreak, and neither may appear in the commit trace -- that part is checked
# externally, by PC, because a program cannot observe its own non-retirement.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        .option push
        .option norvc
        .globl the_ecall
the_ecall:
        ecall
        .option pop
        la      t0, last_cause
        ld      t1, 0(t0)
        CHECK_EQ(t1, 11, 1)
        la      t0, last_tval
        ld      t1, 0(t0)
        CHECK_EQ(t1, 0, 2)
        la      t0, last_epc
        ld      t1, 0(t0)
        la      t2, the_ecall
        CHECK_EQ_R(t1, t2, 3)
        .option push
        .option norvc
        .globl the_ebreak
the_ebreak:
        ebreak
        .option pop
        la      t0, last_cause
        ld      t1, 0(t0)
        CHECK_EQ(t1, 3, 4)
        la      t0, last_tval
        ld      t1, 0(t0)
        la      t2, the_ebreak
        CHECK_EQ_R(t1, t2, 5)                  # mtval for a breakpoint is its own address
        la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 2, 6)
        PASS
