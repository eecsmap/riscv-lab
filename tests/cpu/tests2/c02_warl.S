# c02: the WARL values this core actually implements, read back through software.
#   mtvec  - direct mode only, the low two bits are forced to 0
#   mepc   - no C extension, so the low two bits are forced to 0 on a software write too
#   mstatus- only MIE and MPIE are writable; MPP is hardwired to M; everything else reads 0
#   misa   - a fixed value: MXL = 2 (RV64) with the I bit only, and a write is accepted and discarded
#   mhartid- read-only zero
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        # ---- mtvec: writing an unaligned base must read back with the mode bits cleared
        la      s0, trap_handler
        ori     t0, s0, 3
        csrw    mtvec, t0
        csrr    t1, mtvec
        CHECK_EQ_R(t1, s0, 1)                  # handler address is 4-aligned, so this is base with mode = 0
        # ---- mepc: same rule on a software write
        li      t0, 0x80000006
        csrw    mepc, t0
        csrr    t1, mepc
        li      t2, 0x80000004
        CHECK_EQ_R(t1, t2, 2)
        # ---- mstatus: set every bit, read back only what is implemented
        li      t0, -1
        csrw    mstatus, t0
        csrr    t1, mstatus
        li      t2, 0x1888                     # MPP = 11 (bits 12:11), MPIE (7), MIE (3)
        CHECK_EQ_R(t1, t2, 3)
        # clearing everything must leave MPP at M and the rest zero
        li      t0, -1
        csrc    mstatus, t0
        csrr    t1, mstatus
        li      t2, 0x1800
        CHECK_EQ_R(t1, t2, 4)
        # ---- misa: fixed, and a write must be discarded rather than trap
        csrr    s1, misa
        li      t2, 0x8000000000000100          # MXL = 2, I only
        CHECK_EQ_R(s1, t2, 5)
        li      t0, -1
        csrw    misa, t0
        csrr    t1, misa
        CHECK_EQ_R(t1, s1, 6)
        # ---- mhartid: read-only zero
        csrr    t1, mhartid
        CHECK_EQ(t1, 0, 7)
        # none of the above may have trapped
        la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 0, 8)
        PASS
