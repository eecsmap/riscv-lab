# c02 (step-3 edition): the WARL values the core implements, read back through software. The expectations
# depend on which extensions the core has, so they are selected by -D flags: a step-3 core has none of them
# (M-mode only, no C); the reference core is built with -DHAS_C -DHAS_S -DHAS_M. Steps 6 and 12 turn the
# flags on for the student's core, and the same test keeps passing with its expectations moved.
#   mtvec   - direct mode only: the low two bits read 0
#   mepc    - no C: the low two bits read 0 on a software write; with C only bit 0 is forced to 0
#   mstatus - M-only: MIE, MPIE writable, MPP reads M; with S/U: SIE SPIE SPP MPRV SUM MXR too, UXL/SXL = 2
#   misa    - fixed; a write is accepted and discarded
#   mhartid - read-only zero
#include "testmac.h"
#ifdef HAS_C
#define MEPC_EXPECT 0x80000006
#define MISA_C 0x4
#else
#define MEPC_EXPECT 0x80000004
#define MISA_C 0
#endif
#ifdef HAS_M
#define MISA_M 0x1000
#else
#define MISA_M 0
#endif
#ifdef HAS_A
#define MISA_A 0x1
#else
#define MISA_A 0
#endif
#ifdef HAS_S
#define MISA_SU 0x140000
#define MSTATUS_ALL1  0x0000000A000E19AA
#define MSTATUS_ALL0  0x0000000A00000000
#else
#define MISA_SU 0
#define MSTATUS_ALL1  0x1888
#define MSTATUS_ALL0  0x1800
#endif
#define MISA_EXPECT (0x8000000000000100 | MISA_C | MISA_M | MISA_A | MISA_SU)
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        # ---- mtvec: writing an unaligned base must read back with the mode bits cleared
        la      s0, trap_handler
        ori     t0, s0, 3
        csrw    mtvec, t0
        csrr    t1, mtvec
        CHECK_EQ_R(t1, s0, 1)
        # ---- mepc: the alignment rule on a software write
        li      t0, 0x80000006
        csrw    mepc, t0
        csrr    t1, mepc
        li      t2, MEPC_EXPECT
        CHECK_EQ_R(t1, t2, 2)
        # ---- mstatus: set every bit, read back only what is implemented
        li      t0, -1
        csrw    mstatus, t0
        csrr    t1, mstatus
        li      t2, MSTATUS_ALL1
        CHECK_EQ_R(t1, t2, 3)
        li      t0, -1
        csrc    mstatus, t0
        csrr    t1, mstatus
        li      t2, MSTATUS_ALL0
        CHECK_EQ_R(t1, t2, 4)
        # ---- misa: fixed, and a write must be discarded rather than trap
        csrr    s1, misa
        li      t2, MISA_EXPECT
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
