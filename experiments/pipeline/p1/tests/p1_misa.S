# PIPELINE ONLY (not differential: misa differs by design). misa reports exactly what P1 implements, RV64I
# (MXL = 2, extension bit I only), and a write is ignored.
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        csrr    t4, misa
        li      gp, 0x8000000000000100
        CHECK_REG(t4, gp, 1)
        csrw    misa, zero
        csrr    t5, misa
        CHECK_REG(t4, t5, 2)
        li      a0, 0
        ret
