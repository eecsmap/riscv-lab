# Forwarding: EX/MEM (distance 1), MEM/WB (distance 2), WB->ID bypass (distance 3), register file (distance 4+),
# x0 as a destination never forwarded, ALU/branch/store/jalr operands, 32-bit forms.
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        li      x5, 7
        add     x6, x5, x5          # x5 from EX/MEM
        CHECK_EQ(x6, 14, 1)
        li      x5, 3
        nop
        add     x6, x5, x5          # x5 from MEM/WB
        CHECK_EQ(x6, 6, 2)
        li      x5, 9
        nop
        nop
        add     x6, x5, x5          # x5 via the WB->ID bypass
        CHECK_EQ(x6, 18, 3)
        li      x5, 11
        nop
        nop
        nop
        add     x6, x5, x5          # x5 from the register file
        CHECK_EQ(x6, 22, 4)
        # both operands from different distances in one instruction
        li      x7, 100
        li      x8, 20
        sub     x9, x7, x8          # x7 dist 2, x8 dist 1
        CHECK_EQ(x9, 80, 5)
        # a chain: each value depends on the previous one
        li      x10, 1
        slli    x10, x10, 1
        addi    x10, x10, 3
        xori    x10, x10, 0x0f
        sub     x10, x0, x10
        CHECK_EQ(x10, -10, 6)
        # x0 as a destination: the write is discarded and must not be forwarded
        addi    x0, x0, 5
        add     x11, x0, x0
        CHECK_EQ(x11, 0, 7)
        li      x12, 4
        addi    x0, x12, 1
        addi    x13, x0, 1
        CHECK_EQ(x13, 1, 8)
        # a store's data and address from just-produced values
        la      x14, fwd_buf
        li      x15, 0x1234
        sd      x15, 0(x14)
        ld      x16, 0(x14)
        CHECK_EQ(x16, 0x1234, 9)
        addi    x14, x14, 8
        li      x15, -3
        sw      x15, 0(x14)
        lw      x16, 0(x14)
        CHECK_EQ(x16, -3, 10)
        # a branch on just-produced operands (taken and untaken)
        li      x17, 5
        li      x18, 5
        beq     x17, x18, 1f
        FAIL(11)
1:      addi    x18, x18, 1
        beq     x17, x18, 2f
        j       3f
2:      FAIL(12)
3:      # jalr through a just-computed address; the link is read immediately
        la      x19, 4f
        jalr    x20, 0(x19)
40:     FAIL(13)
4:      la      x21, 40b            # the link is the address right after the jalr
        CHECK_REG(x20, x21, 14)
        # 32-bit forms: sign extension across a forward
        li      x22, 0x7fffffff
        addiw   x23, x22, 1
        CHECK_EQ(x23, -2147483648, 15)
        sraiw   x24, x23, 4
        CHECK_EQ(x24, -134217728, 16)
        # lui / auipc feeding an add
        lui     x25, 0x12345
        addi    x25, x25, 0x678
        CHECK_EQ(x25, 0x12345678, 17)
        auipc   x26, 0
        auipc   x27, 0
        sub     x28, x27, x26
        CHECK_EQ(x28, 4, 18)
        # a forwarded value that is overwritten before use: the younger producer wins
        li      x29, 1
        li      x29, 2
        add     x30, x29, x0
        CHECK_EQ(x30, 2, 19)
        li      a0, 0
        ret
        .data
        .align 3
fwd_buf: .dword 0, 0
