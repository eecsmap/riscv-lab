# c04: the two counters this core really implements.
#   mcycle   advances every cycle, is writable, and a software write wins over that cycle's increment
#   minstret advances once per normal retirement, is writable, and a software write wins over this
#            instruction's own +1
# The expectations are architectural, not timing: a cycle count is compared with "greater than", while the
# retirement count is compared exactly against a statically known instruction sequence.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        # ---- mcycle really counts: two reads separated by work must differ, and increase
        csrr    s0, mcycle
        nop
        nop
        nop
        csrr    s1, mcycle
        bgeu    s0, s1, 1f                      # s1 must be strictly greater
        j       2f
1:      FAIL_CODE(1, s0)
2:      # ---- mcycle is writable, and the value written wins over the same cycle's increment
        li      t0, 0x1000
        csrw    mcycle, t0
        csrr    s2, mcycle
        # the read happens a few instructions later, so allow for the cycles in between but require that
        # the write landed: the value must be just above what was written, never the old free-running count
        li      t1, 0x1000
        bltu    s2, t1, 3f
        li      t2, 0x1100
        bgeu    s2, t2, 3f
        j       4f
3:      FAIL_CODE(2, s0)
4:      # ---- minstret: exact, because the instruction sequence between the two reads is static
        .option push
        .option norvc
        csrr    s3, minstret
        addi    t0, x0, 1
        addi    t0, x0, 2
        addi    t0, x0, 3
        csrr    s4, minstret
        .option pop
        sub     s5, s4, s3
        li      t1, 4                           # three addi plus the closing csrr
        CHECK_EQ_R(s5, t1, 3)
        # ---- writing minstret wins over this instruction's own increment, and it keeps counting after.
        # The whole sequence is kept static: no check macro may retire in the middle of the measurement.
        .option push
        .option norvc
        li      t0, 100
        csrw    minstret, t0                    # the write wins: this instruction's own +1 is suppressed
        csrr    s6, minstret                    # reads the value before its own +1, so exactly 100
        addi    t0, x0, 0
        csrr    s7, minstret                    # csrr(100) and the addi retired, so exactly 102
        .option pop
        li      t1, 100
        CHECK_EQ_R(s6, t1, 4)
        li      t1, 102
        CHECK_EQ_R(s7, t1, 5)
        la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 0, 6)
        PASS
