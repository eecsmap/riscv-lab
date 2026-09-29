# PIPE-P2b: a data-side walk preempting a fetch-side walk, on purpose. Code pages cp0 and cp1 are mapped (4 KiB leaves)
# at VA X = TEST_REGION + 4 KiB and X + 4 KiB; the load near the END of cp0 misses the TLB (after an sfence.vma) while
# the front end has already run into cp1 and is walking it speculatively. The load reaches MEM as the oldest
# instruction and its data walk must preempt the fetch walk; the fetch walk restarts afterwards. The aliased code
# uses only absolute addresses held in registers (no pc-relative data references). Checks: the loaded values and
# the count of instructions (s2). The runner requires the pipeline's walks_preempted_by_data counter to be > 0.
#include "sv_env.h"
#define VX  (TEST_REGION + 1 * 4096)
#define VD  (TEST_REGION + 5 * 4096)
        .section .text, "ax", @progbits
        .option norvc
        .globl main
main:   call    su_init
        TEST_ROOT(root0, l1_0, l0_0)
        MAP4K(l0_0, 1, cp0, PTE_X_A)
        MAP4K(l0_0, 2, cp1, PTE_X_A)
        MAP4K(l0_0, 5, dpg, PTE_RW_AD)
        la      t0, dpg
        li      t1, 1000
        sd      t1, 0(t0)
        ENABLE_SV39(root0)
        ENTER_S(s1)
s1:     li      s2, 0
        li      t2, VD
        .irp off, 0xff0, 0xff4, 0xff8, 0xfe8, 0xfec
        la      s3, 1f
        sfence.vma
        li      t0, VX + \off
        jr      t0
1:
        .endr
        RET_M(done)
done:   li      t0, 5 * (1000 + 1)
        add     t1, s2, zero
        CHECK_EQ_R(t1, t0, 1)
        PASS

        .balign 4096
cp0:    .rept 1018                          # never executed from here: entries are near the page end
        nop
        .endr
        addi    s2, s2, 0                   # +0xfe8
        addi    s2, s2, 0                   # +0xfec
        addi    s2, s2, 0                   # +0xff0
        addi    s2, s2, 0                   # +0xff4
        ld      t1, 0(t2)                   # +0xff8: misses the TLB (after the sfence): a data walk
        add     s2, s2, t1                  # +0xffc
cp1:    addi    s2, s2, 1                   # +0 of the next page: fetched (and walked) speculatively
        jr      s3
        .balign 4096

        .section .data, "aw", @progbits
        .balign 4096
        .globl root0, l1_0, l0_0
root0:  .space 4096
l1_0:   .space 4096
l0_0:   .space 4096
dpg:    .space 4096
