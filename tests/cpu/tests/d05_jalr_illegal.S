# d05: JALR is defined only for funct3 = 000. Every other funct3 must raise an illegal-instruction trap,
# must not retire, and must not write its link register. Built once per funct3 with -DJALR_F3=n.
# x9 (s1) carries a sentinel so the harness can prove the link register was left alone.
#include "testmac.h"
#ifndef JALR_F3
#error "build with -DJALR_F3=<1..7>"
#endif
        .section .text, "ax", @progbits
        .globl main
main:   li      s1, 0x5A5A5A5A          # sentinel in the link register the bad JALR would write
        la      t0, landed
        .option push
        .option norvc
        .insn   i 0x67, JALR_F3, x9, t0, 0
        .option pop
        FAIL_CODE(35, t0)               # reached only if the trap did not happen
landed: FAIL_CODE(36, t0)               # reached only if the jump was performed
