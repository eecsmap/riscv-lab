# c01: the six Zicsr forms and their write-intent rules. Write intent follows the *encoding*: CSRRS/CSRRC
# with rs1 = x0 must not write, but rs1 = x5 holding zero must. mscratch is the scratch CSR throughout,
# so nothing here depends on a counter that is moving underneath the test.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        # ---- CSRRW: writes always, reads only when rd != x0
        li      t0, 0x0F0F0F0F
        csrw    mscratch, t0                    # csrrw x0, mscratch, t0 -- writes, no read
        csrr    t1, mscratch
        CHECK_EQ_R(t0, t1, 1)
        li      t2, 0x12345678
        csrrw   t3, mscratch, t2                # returns the old value, installs the new one
        CHECK_EQ_R(t3, t0, 2)
        csrr    t1, mscratch
        CHECK_EQ_R(t1, t2, 3)
        # ---- CSRRS with rs1 = x0: reads, must NOT write
        li      t0, 0
        csrrs   t1, mscratch, x0
        CHECK_EQ_R(t1, t2, 4)
        csrr    t1, mscratch
        CHECK_EQ_R(t1, t2, 5)                   # unchanged
        # ---- CSRRS with a non-zero register holding zero: this DOES write (intent is by encoding)
        li      s0, 0                           # s0 is x8, a non-zero register number holding zero
        csrrs   t1, mscratch, s0                # set no bits, but it is still a write
        csrr    t1, mscratch
        CHECK_EQ_R(t1, t2, 6)                   # value is the same, which is what "set zero bits" means
        # ---- CSRRS sets bits. The mask is chosen to be disjoint from the bits already set (0x12345678
        # has bit 7 clear), so that clearing the same mask afterwards really does restore the old value --
        # with an overlapping mask it would not, and that is checked separately below.
        li      s1, 0x80
        csrrs   t1, mscratch, s1
        csrr    t1, mscratch
        li      t4, 0x123456F8
        CHECK_EQ_R(t1, t4, 7)
        # ---- CSRRC clears bits
        csrrc   t1, mscratch, s1               # returns the old value ...
        CHECK_EQ_R(t1, t4, 8)                   # ... which is the value with the bit still set
        csrr    t1, mscratch                    # and the register now has it cleared again
        CHECK_EQ_R(t1, t2, 14)
        # ---- clearing an overlapping mask clears every bit in it, not just the ones CSRRS added
        li      s1, 0x000F0000
        csrrs   t1, mscratch, s1                # 0x12345678 -> 0x123F5678
        csrrc   t1, mscratch, s1                # -> 0x12305678: the original bit 18 goes too
        csrr    t1, mscratch
        li      t4, 0x12305678
        CHECK_EQ_R(t1, t4, 15)
        csrw    mscratch, t2                    # restore, so the rest of the test starts from a known value
        # ---- immediate forms: CSRRWI / CSRRSI / CSRRCI, uimm = 0 must not write for S/C
        csrrwi  t1, mscratch, 5
        csrr    t1, mscratch
        li      t4, 5
        CHECK_EQ_R(t1, t4, 9)
        csrrsi  t1, mscratch, 2
        csrr    t1, mscratch
        li      t4, 7
        CHECK_EQ_R(t1, t4, 10)
        csrrci  t1, mscratch, 1
        csrr    t1, mscratch
        li      t4, 6
        CHECK_EQ_R(t1, t4, 11)
        csrrsi  t1, mscratch, 0                 # uimm = 0: reads, must not write
        csrr    t1, mscratch
        CHECK_EQ_R(t1, t4, 12)
        # no trap may have happened anywhere above
        la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 0, 13)
        PASS
