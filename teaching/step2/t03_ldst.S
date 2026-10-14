# t03: loads and stores of every width: sign and zero extension, byte lanes inside the 8-byte word,
# negative offsets, and that a narrow store touches only its lanes. Code 2 is the first signed load (lb of
# 0x88): NO_LOAD_SEXT=1 must fail there.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:
        la      s0, buf
        # ---- loads from a known pattern: byte i of buf is 0x11 * (i + 1) -------------------------------
        lb      t0, 0(s0)
        CHECK_EQ(t0, 0x11, 1)
        lb      t0, 7(s0)
        CHECK_EQ(t0, 0xffffffffffffff88, 2)
        lbu     t0, 7(s0)
        CHECK_EQ(t0, 0x88, 3)
        lh      t0, 2(s0)
        CHECK_EQ(t0, 0x4433, 4)
        lh      t0, 6(s0)
        CHECK_EQ(t0, 0xffffffffffff8877, 5)
        lhu     t0, 6(s0)
        CHECK_EQ(t0, 0x8877, 6)
        lw      t0, 0(s0)
        CHECK_EQ(t0, 0x44332211, 7)
        lw      t0, 4(s0)
        CHECK_EQ(t0, 0xffffffff88776655, 8)
        lwu     t0, 4(s0)
        CHECK_EQ(t0, 0x88776655, 9)
        ld      t0, 0(s0)
        CHECK_EQ(t0, 0x8877665544332211, 10)
        addi    s1, s0, 8
        lb      t0, -1(s1)                      # negative offset
        CHECK_EQ(t0, 0xffffffffffffff88, 11)
        # ---- stores: whole word, then narrower stores into its lanes --------------------------------------
        la      s2, dst
        li      t1, 0x11223344aabbccdd
        sd      t1, 0(s2)
        ld      t0, 0(s2)
        CHECK_EQ_R(t0, t1, 12)
        li      t2, 0xee
        sb      t2, 1(s2)
        ld      t0, 0(s2)
        CHECK_EQ(t0, 0x11223344aabbeedd, 13)
        li      t2, 0x1234
        sh      t2, 2(s2)
        ld      t0, 0(s2)
        CHECK_EQ(t0, 0x112233441234eedd, 14)
        li      t2, 0xdeadbeef                  # li sign-extends; sw stores the low 32 bits only
        sw      t2, 4(s2)
        ld      t0, 0(s2)
        CHECK_EQ(t0, 0xdeadbeef1234eedd, 15)
        lbu     t0, 1(s2)
        CHECK_EQ(t0, 0xee, 16)
        lhu     t0, 2(s2)
        CHECK_EQ(t0, 0x1234, 17)
        lw      t0, 4(s2)
        CHECK_EQ(t0, 0xffffffffdeadbeef, 18)
        # ---- the neighbouring word is untouched ---------------------------------------------------------
        ld      t0, 8(s2)
        CHECK_EQ(t0, 0, 19)
        li      t2, 0x5a
        sb      t2, 15(s2)                      # byte 7 of the next word
        ld      t0, 8(s2)
        CHECK_EQ(t0, 0x5a00000000000000, 20)
        ld      t0, 0(s2)
        CHECK_EQ(t0, 0xdeadbeef1234eedd, 21)
        # ---- a load's value is usable by the very next instruction --------------------------------------
        li      t3, 7
        sd      t3, 16(s2)
        ld      t4, 16(s2)
        addi    t4, t4, 1
        CHECK_EQ(t4, 8, 22)
        PASS

        .section .data, "aw", @progbits
        .align 3
buf:    .dword 0x8877665544332211
        .dword 0
dst:    .zero 64
