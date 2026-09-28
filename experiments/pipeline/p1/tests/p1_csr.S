# CSR serialisation: a CSR written from a just-produced value and read back and used at once; the three
# read-modify-write forms and their immediates; minstret deltas (architectural, compared exactly); an MRET to a
# label; FENCE, FENCE.I and WFI as serialising no-ops.
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        li      t0, 0x1234
        addi    t0, t0, 1
        csrw    mscratch, t0
        csrr    t1, mscratch
        addi    t1, t1, 1
        CHECK_EQ(t1, 0x1236, 1)
        li      t3, 0xf0
        csrrs   t2, mscratch, t3
        CHECK_EQ(t2, 0x1235, 2)
        csrr    t2, mscratch
        CHECK_EQ(t2, 0x12f5, 3)
        csrrc   t2, mscratch, t3
        csrr    t2, mscratch
        CHECK_EQ(t2, 0x1205, 4)
        csrrwi  t2, mscratch, 9
        CHECK_EQ(t2, 0x1205, 5)
        csrrsi  t2, mscratch, 6
        csrrci  t2, mscratch, 1
        csrr    t2, mscratch
        CHECK_EQ(t2, 0xe, 6)
        # minstret: two reads 5 instructions apart differ by 5 (retirements, not cycles)
        csrr    s3, minstret
        nop
        nop
        nop
        nop
        csrr    s4, minstret
        sub     s5, s4, s3
        CHECK_EQ(s5, 5, 8)
        # MRET to a label, staying in M
        la      t0, 1f
        csrw    mepc, t0
        li      t1, 0x1800
        csrs    mstatus, t1          # MPP = M
        mret
        FAIL(9)
1:      fence
        fence.i
        wfi
        li      t0, 3
        addi    t0, t0, 4
        CHECK_EQ(t0, 7, 10)
        li      a0, 0
        ret
