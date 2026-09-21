# c07: a fault inside the handler must not be able to report a pass. The handler installed here faults on
# every entry, so the machine makes no progress; the harness must reject the run on the trap-storm
# diagnostic rather than let anything reach tt_exit.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   la      t0, bad_handler
        csrw    mtvec, t0
        .option push
        .option norvc
        .word   0x00000000                      # first trap: enters the handler, which faults again
        .option pop
        PASS                                    # must be unreachable
        .align 2
bad_handler:
        .word   0x00000000                      # the handler's own first instruction is illegal
        j       bad_handler
