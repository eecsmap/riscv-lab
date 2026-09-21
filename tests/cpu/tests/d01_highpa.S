# d01: an address whose bits [63:32] are non-zero must NOT be truncated into the 32-bit physical port.
# Expected: store access fault (cause 7), and zero data requests on the bus.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   li      t0, 0x180000000
        li      t1, 0x1234
        sd      t1, 0(t0)           # must trap before any bus request
        FAIL_CODE(31, t0)           # reaching here means the address was truncated
