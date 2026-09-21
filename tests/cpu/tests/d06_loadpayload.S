# d06: the rs2 field of a load is part of its immediate, not a register selector. With offset 8 that field
# names x8, so x8 is loaded with a conspicuous value first: if the core forwards rs2 onto the bus, the read
# request carries that value as a write payload and the harness' read-payload monitor must catch it.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   li      s0, 0xDEADBEEF          # x8: the register the load's rs2 field would name
        la      s2, buf
        ld      t1, 8(s2)               # rs2 field = 8 = x8
        li      t2, 0x1122334455667788
        CHECK_EQ_R(t1, t2, 37)
        PASS
        .section .data, "aw", @progbits
        .align 3
buf:    .dword 0
        .dword 0x1122334455667788
