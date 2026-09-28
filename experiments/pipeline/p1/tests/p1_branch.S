# Branches and jumps: every condition taken and untaken, back-to-back branches, a counted loop, a JAL chain,
# a branch right after a load, and a taken branch whose fall-through would store (the store must not happen).
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        mv      s11, ra             # the JAL chain below uses ra
        li      s1, 0               # a counter of taken paths
        li      t0, -1
        li      t1, 1
        beq     t0, t1, 91f
        bne     t0, t1, 1f
        j       91f
1:      addi    s1, s1, 1
        blt     t0, t1, 2f          # signed: -1 < 1
        j       91f
2:      addi    s1, s1, 1
        bltu    t0, t1, 91f         # unsigned: 0xff..f > 1
        bgeu    t0, t1, 3f
        j       91f
3:      addi    s1, s1, 1
        bge     t0, t1, 91f
        bge     t1, t0, 4f
        j       91f
4:      addi    s1, s1, 1
        CHECK_EQ(s1, 4, 1)
        # back-to-back: the second branch is in ID/fetch when the first redirects
        li      t2, 0
        beq     x0, x0, 5f
        beq     x0, x0, 91f
5:      bne     x0, x0, 91f
        beq     x0, x0, 6f
        addi    t2, t2, 1
6:      CHECK_EQ(t2, 0, 2)
        # a counted loop: 50 taken back-branches, one fall-through
        li      t3, 50
        li      t4, 0
7:      addi    t4, t4, 2
        addi    t3, t3, -1
        bnez    t3, 7b
        CHECK_EQ(t4, 100, 3)
        # a JAL chain
        jal     ra, 10f
        CHECK_EQ(a1, 3, 4)
        j       11f
10:     li      a1, 1
        jal     t0, 12f
12:     addi    a1, a1, 2
        ret
11:     # branch right after a load
        la      s2, br_data
        ld      t0, 0(s2)
        beqz    t0, 91f
        ld      t0, 8(s2)
        beqz    t0, 13f
        j       91f
13:     # a taken branch with a store on its fall-through path: the store must not happen
        li      t5, 0x77
        beq     x0, x0, 14f
        sd      t5, 16(s2)
        sd      t5, 16(s2)
14:     ld      t6, 16(s2)
        CHECK_EQ(t6, 0, 5)
        mv      ra, s11
        li      a0, 0
        ret
91:     FAIL(9)
        .data
        .align 3
br_data: .dword 1, 0, 0
