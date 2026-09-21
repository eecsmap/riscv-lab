# d02: a misaligned load must trap before issuing a request (cause 4), never as a split or truncated access.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   la      t0, scratch
        addi    t0, t0, 1
        lw      t1, 0(t0)           # misaligned: trap, no bus request
        FAIL_CODE(32, t0)
        .section .data, "aw", @progbits
        .align 3
scratch: .dword 0x1122334455667788
