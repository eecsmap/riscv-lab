# d07: this core counts retired instructions and nothing else. Reading `cycle` used to be accepted and
# answered 0, which is a fabricated value; it must now be an illegal instruction.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   li      s1, 0x5A5A5A5A
        .option push
        .option norvc
        csrr    s1, cycle
        .option pop
        FAIL_CODE(38, s1)
