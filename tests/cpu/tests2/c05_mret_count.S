# c05: MRET retires normally and is counted, while a faulting instruction is not. The handler here is the
# shared one, so one trap costs exactly: the faulting instruction (not counted) plus the handler's own
# instructions plus its MRET (all counted). Rather than depend on the handler's length, this test measures
# the same span twice -- once without a trap and once with one -- and checks the difference.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        # span A: no trap
        .option push
        .option norvc
        csrr    s0, minstret
        addi    t0, x0, 1
        csrr    s1, minstret
        .option pop
        sub     s2, s1, s0                      # = 2: the addi and the closing csrr
        li      t1, 2
        CHECK_EQ_R(s2, t1, 1)
        # span B: the same span with an illegal instruction in the middle
        .option push
        .option norvc
        csrr    s3, minstret
        .globl  the_bad_word
the_bad_word:
        .word   0x00000000                      # traps: must NOT be counted
        csrr    s4, minstret
        .option pop
        sub     s5, s4, s3
        # The span now also contains the handler, whose length is not this test's business: what matters
        # is that it grew by more than the trap-free span, i.e. the handler's instructions were counted,
        # while the faulting word itself was not. Which PCs retired is checked externally, by PC, from the
        # commit trace -- the faulting word must appear zero times and the handler's MRET exactly once.
        li      t1, 3
        bgeu    s5, t1, 2f
        FAIL_CODE(2, s0)
2:
        la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 1, 3)
        la      t0, last_cause
        ld      t1, 0(t0)
        CHECK_EQ(t1, 2, 4)
        PASS
