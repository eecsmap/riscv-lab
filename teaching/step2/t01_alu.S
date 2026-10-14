# t01: the RV64I integer instructions. Each check has its own code; the first failing one ends the run.
# Codes 1 and 2 are the x0 property (a write to x0 is discarded, a read of x0 is 0): X0_WRITABLE=1 must
# fail here and nowhere earlier.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:
        # ---- x0 --------------------------------------------------------------------------------------
        # Every constant is built from x0 (`li gp, 0` is `addi gp, x0, 0`), so once x0 holds garbage the
        # checks themselves are poisoned. The test therefore captures its expected value BEFORE writing x0
        # and clears x0 again (sub x0, x0, x0 writes 0 on a writable x0, is discarded on a real one) before
        # any check runs. X0_WRITABLE=1 fails at code 1.
        li      t1, 0
        addi    x0, x0, 5
        addi    t0, x0, 0
        sub     x0, x0, x0
        CHECK_EQ_R(t0, t1, 1)
        lui     x0, 0x12345
        add     t0, x0, x0
        sub     x0, x0, x0
        CHECK_EQ(t0, 0, 2)
        # ---- register-immediate -------------------------------------------------------------------------
        li      t0, 100
        addi    t1, t0, -150
        CHECK_EQ(t1, -50, 3)
        slti    t1, t0, 101
        CHECK_EQ(t1, 1, 4)
        slti    t1, t0, 100
        CHECK_EQ(t1, 0, 5)
        li      t2, -1
        sltiu   t1, t2, 1                       # 0xffff...ffff < 1 unsigned: no
        CHECK_EQ(t1, 0, 6)
        sltiu   t1, x0, 1                       # seqz
        CHECK_EQ(t1, 1, 7)
        andi    t1, t2, 0x0f0
        CHECK_EQ(t1, 0xf0, 8)
        ori     t1, t0, 0x3
        CHECK_EQ(t1, 103, 9)
        xori    t1, t2, 0x7ff
        CHECK_EQ(t1, -2048, 10)
        # ---- 64-bit immediate shifts: the shift amount is 6 bits -------------------------------------
        li      t3, 0x8000000000000001
        slli    t1, t3, 1
        CHECK_EQ(t1, 2, 11)
        srli    t1, t3, 63
        CHECK_EQ(t1, 1, 12)
        srai    t1, t3, 63
        CHECK_EQ(t1, -1, 13)
        srai    t1, t3, 4
        CHECK_EQ(t1, 0xf800000000000000, 14)
        srli    t1, t3, 4
        CHECK_EQ(t1, 0x0800000000000000, 15)
        # ---- W immediates: operate on the low 32 bits, sign-extend the 32-bit result -------------------
        li      t4, 0x7fffffff
        addiw   t1, t4, 1
        CHECK_EQ(t1, 0xffffffff80000000, 16)
        li      t4, 0x0000000100000001          # upper half must be ignored
        addiw   t1, t4, 1
        CHECK_EQ(t1, 2, 17)
        li      t4, 0x40000000
        slliw   t1, t4, 1
        CHECK_EQ(t1, 0xffffffff80000000, 18)
        li      t4, 0xffffffff80000000
        srliw   t1, t4, 4                       # logical on the 32-bit value 0x80000000
        CHECK_EQ(t1, 0x08000000, 19)
        sraiw   t1, t4, 4
        CHECK_EQ(t1, 0xfffffffff8000000, 20)
        # ---- register-register ------------------------------------------------------------------------
        li      t0, 7
        li      t1, -3
        add     t2, t0, t1
        CHECK_EQ(t2, 4, 21)
        sub     t2, t0, t1
        CHECK_EQ(t2, 10, 22)
        sub     t2, t1, t0
        CHECK_EQ(t2, -10, 23)
        li      t3, 65                          # only rs2[5:0] = 1 is the shift amount
        sll     t2, t0, t3
        CHECK_EQ(t2, 14, 24)
        slt     t2, t1, t0
        CHECK_EQ(t2, 1, 25)
        sltu    t2, t1, t0                      # 0xffff...fffd < 7 unsigned: no
        CHECK_EQ(t2, 0, 26)
        sltu    t2, t0, t1
        CHECK_EQ(t2, 1, 27)
        xor     t2, t0, t1
        CHECK_EQ(t2, -6, 28)
        srl     t2, t1, t3
        CHECK_EQ(t2, 0x7ffffffffffffffe, 29)
        sra     t2, t1, t3
        CHECK_EQ(t2, -2, 30)
        or      t2, t0, t1
        CHECK_EQ(t2, -1, 31)
        and     t2, t0, t1
        CHECK_EQ(t2, 5, 32)
        # ---- W register ops ------------------------------------------------------------------------------
        li      t0, 0x7fffffff
        li      t1, 1
        addw    t2, t0, t1
        CHECK_EQ(t2, 0xffffffff80000000, 33)
        li      t0, 0xffffffff80000000
        subw    t2, t0, t1
        CHECK_EQ(t2, 0x7fffffff, 34)
        li      t0, 1
        li      t3, 33                          # W shifts use rs2[4:0] = 1
        sllw    t2, t0, t3
        CHECK_EQ(t2, 2, 35)
        li      t0, 0xffffffff80000000
        li      t3, 31
        srlw    t2, t0, t3
        CHECK_EQ(t2, 1, 36)
        sraw    t2, t0, t3
        CHECK_EQ(t2, -1, 37)
        li      t0, 0x123456789abcdef0          # the upper half must not leak into a W result
        addw    t2, t0, x0
        CHECK_EQ(t2, 0xffffffff9abcdef0, 38)
        # ---- lui / auipc ----------------------------------------------------------------------------------
        lui     t2, 0xfffff
        CHECK_EQ(t2, 0xfffffffffffff000, 39)
        lui     t2, 0x12345
        CHECK_EQ(t2, 0x12345000, 40)
1:      auipc   t2, 0
        la      t3, 1b
        CHECK_EQ_R(t2, t3, 41)
2:      auipc   t2, 1
        la      t3, 2b
        li      t4, 0x1000
        add     t3, t3, t4
        CHECK_EQ_R(t2, t3, 42)
        # ---- fences are legal and retire; they have no other effect in this core ------------------------
        fence
        fence.i
        fence   rw, rw
        li      t0, 3
        CHECK_EQ(t0, 3, 43)
        PASS
