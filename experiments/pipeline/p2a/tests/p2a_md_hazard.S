# PIPE-P2a M: mul/div results through every forwarding path, load-use into M operands, M results as branch
# operands and load addresses, an M instruction behind a store in MEM, x0 as a destination. Explicit values.
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        li      s0, 12345
        li      s1, -7
        mul     s2, s0, s1              # -86415
        add     s3, s2, s2              # EX/MEM forward of an M result
        CHECK_EQ(s3, -172830, 1)
        la      t0, md_data
        ld      t1, 0(t0)               # 1000
        mul     s4, t1, s1              # load-use into an M operand: -7000
        CHECK_EQ(s4, -7000, 2)
        div     s5, s4, s1              # M -> M dependence: 1000
        rem     s6, s0, s5              # 12345 % 1000 = 345
        CHECK_EQ(s5, 1000, 3)
        CHECK_EQ(s6, 345, 4)
        sd      s5, 8(t0)               # a store in MEM while the next M instruction is in EX
        mulw    s7, s5, s5              # 1000000
        ld      t2, 8(t0)
        CHECK_EQ(t2, 1000, 5)
        CHECK_EQ(s7, 1000000, 6)
        divu    x0, s0, s1              # x0 destination: nothing is written
        add     t3, x0, x0
        CHECK_EQ(t3, 0, 7)
        li      t5, 2
        mul     t4, s0, t5              # 24690, used by a branch right away
        li      t6, 24690
        bne     t4, t6, 90f
        li      t5, 1
        mul     t6, t0, t5              # an M result used as a load address
        ld      a1, 0(t6)
        CHECK_EQ(a1, 1000, 8)
        mulh    a2, s0, s1              # -1 (high half of a small negative product)
        nop
        nop
        add     a3, a2, x0              # the WB->ID bypass / MEM/WB forward of an M result
        CHECK_EQ(a3, -1, 9)
        li      t5, 2
        divuw   a4, s1, t5              # (u32)-7 / 2 = 0x7ffffffc, sign-extended from 32 bits
        li      gp, 0x7ffffffc
        CHECK_REG(a4, gp, 10)
        remw    a5, s1, t5              # -7 % 2 = -1
        CHECK_EQ(a5, -1, 11)
        li      a0, 0
        ret
90:     FAIL(12)
        .data
        .align 3
md_data: .dword 1000, 0
