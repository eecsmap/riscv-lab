# c03: CSR accesses that must raise an illegal-instruction exception, each checked one at a time through
# the handler. A write aimed at a read-only CSR is illegal even when the value would not change anything,
# and the check is on the encoding: `csrrs mhartid, x0` only reads, so it must NOT trap.
#include "testmac.h"
#define EXPECT_TRAP(n)                 \
        la   t0, trap_count;           \
        ld   t1, 0(t0);                \
        li   t2, n;                    \
        bne  t1, t2, 77f;              \
        la   t0, last_cause;           \
        ld   t1, 0(t0);                \
        li   t2, 2;                    \
        bne  t1, t2, 77f;              \
        j    78f;                      \
77:     li   a0, n;                    \
        call tt_exit;                  \
78:
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        .option push
        .option norvc
        # ---- a write aimed at a read-only counter alias
        li      t3, 1
        csrw    cycle, t3
        .option pop
        EXPECT_TRAP(1)
        .option push
        .option norvc
        csrw    instret, t3
        .option pop
        EXPECT_TRAP(2)
        .option push
        .option norvc
        csrw    mhartid, t3
        .option pop
        EXPECT_TRAP(3)
        # ---- a set with a non-zero register number is a write, even though it sets no bits
        .option push
        .option norvc
        li      s0, 0
        csrrs   t1, cycle, s0
        .option pop
        EXPECT_TRAP(4)
        # ---- an unimplemented address, read or write.
        # (step-3 edition) pmpcfg0 (0x3A0): this core has no PMP at any step, so the address is unimplemented on
        # every core the test will ever run on. (The original read mideleg, which exists once S-mode is added.)
        .option push
        .option norvc
        csrr    t1, 0x3a0
        .option pop
        EXPECT_TRAP(5)
        .option push
        .option norvc
        csrr    t1, 0x7c0
        .option pop
        EXPECT_TRAP(6)
        # ---- reads of the read-only aliases must NOT trap
        csrr    t1, cycle
        csrr    t1, instret
        csrrs   t1, mhartid, x0
        csrrsi  t1, cycle, 0
        la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 6, 7)                     # still six, none of the reads trapped
        PASS
