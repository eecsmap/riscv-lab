# t02: the six conditional branches (taken and not taken, signed and unsigned, 64-bit compare), a backward
# loop, and the two jumps: link values and the jalr target rule.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:
        li      t0, 5
        li      t1, 5
        li      t2, -1
        li      t3, 1
        # ---- taken ---------------------------------------------------------------------------------------
        beq     t0, t1, 1f
        FAIL_CODE(1, t4)
1:      bne     t0, t2, 2f
        FAIL_CODE(2, t4)
2:      blt     t2, t3, 3f                      # -1 < 1 signed
        FAIL_CODE(3, t4)
3:      bge     t3, t2, 4f                      # 1 >= -1 signed
        FAIL_CODE(4, t4)
4:      bltu    t3, t2, 5f                      # 1 < 0xffff...ffff unsigned
        FAIL_CODE(5, t4)
5:      bgeu    t2, t3, 6f
        FAIL_CODE(6, t4)
6:      bge     t0, t1, 7f                      # equal counts as >=
        FAIL_CODE(7, t4)
7:      bgeu    t0, t1, 8f
        FAIL_CODE(8, t4)
8:
        # ---- not taken: any of these jumping is code 9 -------------------------------------------------
        bne     t0, t1, 9f
        beq     t0, t2, 9f
        blt     t3, t2, 9f                      # 1 < -1 signed: no
        bge     t2, t3, 9f                      # -1 >= 1 signed: no
        bltu    t2, t3, 9f                      # huge < 1 unsigned: no
        bgeu    t3, t2, 9f                      # 1 >= huge unsigned: no
        blt     t0, t1, 9f                      # 5 < 5: no
        bltu    t0, t1, 9f
        j       10f
9:      FAIL_CODE(9, t4)
        # ---- a backward loop ----------------------------------------------------------------------------
10:     li      t0, 10
        li      t1, 0
11:     addi    t1, t1, 3
        addi    t0, t0, -1
        bnez    t0, 11b
        CHECK_EQ(t1, 30, 10)
        # ---- the compare is 64-bit: values that differ only above bit 31 are different -------------------
        li      t0, 0x100000000
        li      t1, 0
        beq     t0, t1, 12f
        j       13f
12:     FAIL_CODE(11, t4)
13:
        # ---- jal: the link is the address of the following instruction ---------------------------------
        jal     t4, 15f
14:     FAIL_CODE(12, t5)
15:     la      t5, 14b
        CHECK_EQ_R(t4, t5, 13)
        # ---- jalr: target = rs1 + imm, link = pc + 4 -----------------------------------------------------
        la      t4, 17f
        addi    t4, t4, -8
        jalr    t5, 8(t4)
16:     FAIL_CODE(14, t6)
17:     la      t6, 16b
        CHECK_EQ_R(t5, t6, 15)
        # ---- jalr clears bit 0 of the target ------------------------------------------------------------
        la      t4, 18f
        ori     t4, t4, 1
        jalr    x0, 0(t4)
        FAIL_CODE(16, t6)
18:     la      t4, 19f                         # negative offset
        addi    t4, t4, 16
        jalr    x0, -16(t4)
        FAIL_CODE(17, t6)
19:     PASS
