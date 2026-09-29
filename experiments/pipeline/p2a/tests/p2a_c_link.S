# PIPE-P2a C: links, targets and pc-relative values at 2-byte alignment, with explicit expected values.
#   c.jalr links pc + 2; jal/jalr from a pc that is 2 mod 4 link pc + 4; a jump and a branch to a target that is
#   2 mod 4; auipc at a pc that is 2 mod 4; c.j / c.beqz / c.bnez forwards and backwards; c.jr as a return.
#include "p1mac.h"
        .option rvc
        .text
        .globl main
main:
        mv      s11, ra
        # 1. c.jalr: the link is its own pc + 2. The callee records ra and returns through a fixed label, so a wrong
        #    link is seen by this check rather than by wherever a wrong return would land.
        la      t0, sub_rec_ra
lk1:    c.jalr  t0                      # ra = lk1 + 2
back1:  mv      ra, a5
        la      t1, lk1
        addi    t1, t1, 2
        CHECK_REG(ra, t1, 1)
        # 2. jal at a pc that is 2 mod 4, to a target that is 2 mod 4; link = pc + 4
        .balign 4
        c.nop
lk2:    jal     ra, tgt2                # lk2 is 2 mod 4
        la      t1, lk2
        addi    t1, t1, 4
        CHECK_REG(ra, t1, 2)
        CHECK_EQ(a0, 0x22, 3)
        # 3. auipc at a pc that is 2 mod 4
        .balign 4
        c.nop
lk3:    auipc   t2, 0
        la      t1, lk3
        CHECK_REG(t2, t1, 4)
        # 4. a branch to a target 2 mod 4, taken; c.beqz / c.bnez forwards and backwards
        li      a1, 3
        li      a2, 0
b4:     c.addi  a2, 1
        c.addi  a1, -1
        c.bnez  a1, b4                  # backwards, taken twice
        CHECK_EQ(a2, 3, 5)
        li      a3, 0
        beq     a3, x0, tgt4
        li      a2, 99
        .balign 4
        c.nop
tgt4:   c.beqz  a3, fwd4                # tgt4 is 2 mod 4
        li      a2, 98
fwd4:   CHECK_EQ(a2, 3, 6)
        # 5. c.j over a 32-bit instruction; c.jr as a return from a compressed-call
        c.j     over5
        li      a2, 97
over5:  la      t0, sub_cjr
        jalr    ra, 0(t0)
        CHECK_EQ(a4, 0x55, 7)
        mv      ra, s11
        li      a0, 0
        ret
        .balign 4
        c.nop
tgt2:   li      a0, 0x22                # tgt2 is 2 mod 4
        c.jr    ra
sub_rec_ra:
        mv      a5, ra
        la      t0, back1
        jr      t0
sub_cjr:
        li      a4, 0x55
        c.jr    ra
