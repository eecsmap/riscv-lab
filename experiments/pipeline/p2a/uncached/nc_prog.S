# PIPE-P2a uncached-fetch footprint program (codex-pipe-p2a-uncached-fetch). main (RAM) calls code that lives in an
# uncached "device" window at 0x4000_0000 and checks results and the trap log. The bench fails device reads of the
# three addresses it is given (dev4, dev5 + 2, dev6 + 2) and records every device read.
#include "p1mac.h"
        .option rvc
        .text
        .globl main
main:
        mv      s11, ra
        li      a0, 0
        la      t0, dev0
        jalr    ra, 0(t0)               # +1 +2 +4          -> 7
        la      t0, dev1
        jalr    ra, 0(t0)               # +8 (straddles)    -> 15
        la      t0, dev2
        jalr    ra, 0(t0)               # +16 +5            -> 36
        la      t0, dev3
        jalr    ra, 0(t0)               # taken jumps only  -> 36
        CHECK_EQ(a0, 36, 1)
        # fetch errors: first parcel, second parcel inside the word, second parcel in the next word
        la      t1, r4
        la      t2, fetch_recover
        sd      t1, 0(t2)
        la      t0, dev4
        jalr    ra, 0(t0)
r4:     la      t1, r5
        sd      t1, 0(t2)
        la      t0, dev5
        jalr    ra, 0(t0)
r5:     la      t1, r6
        sd      t1, 0(t2)
        la      t0, dev6
        jalr    ra, 0(t0)
r6:     CHECK_EQ(a0, 36, 2)             # nothing of a faulting instruction executed
        la      t0, trap_n
        ld      t0, 0(t0)
        CHECK_EQ(t0, 3, 3)
        LOG_ENTRY(0)
        CHECK_EQ(t4, 1, 4)
        la      gp, dev4
        CHECK_REG(t5, gp, 5)
        CHECK_REG(t6, gp, 6)            # mtval = the first parcel
        LOG_ENTRY(1)
        CHECK_EQ(t4, 1, 7)
        la      gp, dev5
        CHECK_REG(t5, gp, 8)
        addi    gp, gp, 2
        CHECK_REG(t6, gp, 9)            # mtval = the second parcel
        LOG_ENTRY(2)
        CHECK_EQ(t4, 1, 10)
        la      gp, dev6
        CHECK_REG(t5, gp, 11)
        addi    gp, gp, 2
        CHECK_REG(t6, gp, 12)           # mtval = the second parcel, in the next word
        mv      ra, s11
        li      a0, 0
        ret

        .section .devtext, "ax", @progbits
        .globl dev0, dev1, dev2, dev3, dev4, dev5, dev6
# every instruction that must be 32 bits is written as one: the assembler compresses what it can under .option rvc
#define W32(...) .option push; .option norvc; __VA_ARGS__; .option pop
dev0:   c.addi  a0, 1                   # +0
        c.addi  a0, 2                   # +2
        W32(addi a0, a0, 4)             # +4..+7: 32 bits inside the word
        c.jr    ra                      # +8
        .balign 0x40
        .2byte  0x0001, 0x0001, 0x0001  # never executed: must never be read
dev1:   W32(addi a0, a0, 8)             # +6..+9: 32 bits across the word boundary
        c.jr    ra
        .balign 0x40
        .2byte  0x0001                  # never executed
dev2:   W32(addi a0, a0, 16)            # +2..+5
        c.addi  a0, 5                   # +6
        c.jr    ra                      # +8
        .balign 0x40
dev3:   c.j     3f                      # +0
        .2byte  0x0001, 0x0001, 0x0001  # +2..+7: skipped by a taken jump, must never be read
3:      W32(beq x0, x0, 4f)             # +8..+11
        .2byte  0x0001, 0x0001          # +12..+15: skipped by a taken branch, must never be read
4:      c.jr    ra                      # +16
        .balign 0x40
dev4:   c.addi  a0, 1                   # its read fails: first-parcel instruction access fault
        c.jr    ra
        .balign 0x40
dev5:   W32(addi a0, a0, 1)             # its SECOND parcel's read fails (inside the word)
        c.jr    ra
        .balign 0x40
        .2byte  0x0001, 0x0001, 0x0001
dev6:   W32(addi a0, a0, 1)             # +6: its second parcel (+8, the next word) fails
        c.jr    ra
