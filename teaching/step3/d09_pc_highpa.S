# d09: a jump to an address outside the 32-bit physical space must not be fetched. The jump itself is legal and
# retires; the NEXT fetch, at 0x1_0000_0000, must raise an instruction access fault (cause 1) with
# mtval = that address, before anything is asked of the bus.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   li      t0, 0x100000000          # 1 << 32
        jalr    x0, 0(t0)                # legal jump; the fault belongs to the fetch that follows
        FAIL_CODE(41, t1)                # reached only if the jump was not taken
