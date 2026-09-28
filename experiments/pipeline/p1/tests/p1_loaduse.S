# Load-use: a consumer at distance 0, 1, 2 from its load; the store datum from a load; a branch and a jalr on a
# loaded value; pointer chasing; sign/zero extension of each width.
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        la      s0, lu_data
        ld      t0, 0(s0)
        addi    t1, t0, 1           # distance 0: must wait for the load
        CHECK_EQ(t1, 0x1112131415161719, 1)
        ld      t0, 8(s0)
        nop
        addi    t1, t0, 1           # distance 1
        CHECK_EQ(t1, -1, 2)
        ld      t0, 16(s0)
        nop
        nop
        addi    t1, t0, 1           # distance 2
        CHECK_EQ(t1, 43, 3)
        # store the loaded value immediately
        ld      t2, 0(s0)
        sd      t2, 24(s0)
        ld      t3, 24(s0)
        CHECK_REG(t2, t3, 4)
        # a branch on a loaded value
        ld      t0, 16(s0)
        li      t1, 42
        bne     t0, t1, 1f
        j       2f
1:      FAIL(5)
2:      # jalr to an address loaded from memory
        la      t0, lu_target
        la      t1, 3f
        sd      t1, 0(t0)
        ld      t2, 0(t0)
        jalr    x0, 0(t2)
        FAIL(6)
3:      # pointer chasing: each load's address is the previous load's value
        la      t0, chase0
        ld      t0, 0(t0)           # chase0 -> &chase1
        ld      t0, 0(t0)           # -> &chase2
        ld      t0, 0(t0)           # -> &chase3
        ld      t0, 0(t0)           # -> 0x5a5a
        CHECK_EQ(t0, 0x5a5a, 7)
        # widths and extensions
        lb      t0, 32(s0)
        CHECK_EQ(t0, -128, 8)
        lbu     t0, 32(s0)
        CHECK_EQ(t0, 128, 9)
        lh      t0, 32(s0)
        CHECK_EQ(t0, -32640, 10)
        lhu     t0, 32(s0)
        CHECK_EQ(t0, 0x8080, 11)
        lw      t0, 32(s0)
        CHECK_EQ(t0, -2139062144, 12)
        lwu     t0, 32(s0)
        CHECK_EQ(t0, 0x80808080, 13)
        # load then two consumers in a row
        ld      t0, 16(s0)
        add     t1, t0, t0
        add     t2, t1, t0
        CHECK_EQ(t2, 126, 14)
        li      a0, 0
        ret
        .data
        .align 3
lu_data:   .dword 0x1112131415161718, -2, 42, 0, 0x8080808080808080
lu_target: .dword 0
chase0:    .dword chase1
chase1:    .dword chase2
chase2:    .dword chase3
chase3:    .dword 0x5a5a
