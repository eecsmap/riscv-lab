# d04: an unimplemented encoding must raise an illegal-instruction trap (cause 2) and must NOT retire.
# The retirement count up to the faulting instruction is checked externally by the harness.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   li      t0, 1
        li      t1, 2
        .option push
        .option norvc
        .word   0x0000007b          # custom-3 opcode: not implemented
        .option pop
        FAIL_CODE(34, t0)
