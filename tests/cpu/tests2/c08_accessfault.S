# c08: the three access faults, each caused by a real error response from the bus rather than by a range
# check inside the CPU. The addresses below are valid 32-bit physical addresses that the memory model does
# not implement, so the request is issued, handshakes, and comes back with error set -- which is the only
# point at which the core may report the fault.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        la      t0, recover
        la      t1, fetch_recover
        sd      t0, 0(t1)
        li      s0, 0x90000000                  # a well-formed 32-bit address with no memory behind it
        # ---- load access fault: cause 5, mtval = the faulting address
        .option push
        .option norvc
        ld      t2, 0(s0)
        .option pop
        la      t0, last_cause
        ld      t1, 0(t0)
        CHECK_EQ(t1, 5, 1)
        la      t0, last_tval
        ld      t1, 0(t0)
        CHECK_EQ_R(t1, s0, 2)
        # ---- store access fault: cause 7
        .option push
        .option norvc
        sd      t2, 0(s0)
        .option pop
        la      t0, last_cause
        ld      t1, 0(t0)
        CHECK_EQ(t1, 7, 3)
        la      t0, last_tval
        ld      t1, 0(t0)
        CHECK_EQ_R(t1, s0, 4)
        # ---- instruction access fault: cause 1, mepc and mtval are the unfetchable address
        .option push
        .option norvc
        jalr    x1, 0(s0)
        .option pop
        FAIL_CODE(5, s0)                        # the jump succeeded, so no fetch fault was reported
recover:
        la      t0, last_cause
        ld      t1, 0(t0)
        CHECK_EQ(t1, 1, 6)
        la      t0, last_epc
        ld      t1, 0(t0)
        CHECK_EQ_R(t1, s0, 7)
        la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 3, 8)
        PASS
