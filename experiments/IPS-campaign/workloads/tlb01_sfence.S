# Stage 2 targeted probe: a TLB hit must re-check permissions, must honour A/D, and must not survive
# an sfence.vma or a satp write.
#
# Each case is built so that ONLY a defect in the hit path can pass it:
#
#   A  a page is CACHED by a successful load, then its PTE is edited to drop W and sfence.vma is
#      issued. A store must now fault. If the flush did nothing, the stale entry still says W.
#   B  a page whose PTE has A=1 and D=0 is CACHED by a successful load. A store must fault. If the hit
#      path skips the A/D check, it succeeds -- and the walker cannot catch it, because the walk
#      already happened and already passed for a load.
#   C  satp is pointed at a second root table where the alias is INVALID. An access must fault. If a
#      satp write does not flush, the entry from the first address space is still there.
#
# Layout follows ext04_sv39: 1 GiB leaves, entry 2 identity-maps the gigabyte this code lives in so
# execution survives translation, entry 1 is the alias under test.
#include "m3lib.h"
#define PTE_V 0x01
#define PTE_R 0x02
#define PTE_W 0x04
#define PTE_X 0x08
#define PTE_A 0x40
#define PTE_D 0x80

        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start
_start: la      sp, _stack_top
        la      s1, scratch
        li      t1, 0x5A5A5A5A
        sd      t1, 0(s1)
        fence

        # ---- root table 1: entry 1 = alias (RWX A D), entry 2 = identity (RWX A D)
        la      s2, root1
        li      t5, 0x80000000
        srli    t5, t5, 12
        slli    t5, t5, 10
        li      t6, PTE_V|PTE_R|PTE_W|PTE_X|PTE_A|PTE_D
        or      s3, t5, t6              # s3 = a full-permission leaf for the DRAM gigabyte
        li      t4, 1*8
        add     t4, s2, t4
        sd      s3, 0(t4)
        li      t4, 2*8
        add     t4, s2, t4
        sd      s3, 0(t4)

        # ---- root table 2: entry 1 INVALID, entry 2 identity (so code still runs)
        la      s4, root2
        li      t4, 2*8
        add     t4, s4, t4
        sd      s3, 0(t4)
        li      t4, 1*8
        add     t4, s4, t4
        sd      zero, 0(t4)             # the alias is not mapped in address space 2
        fence

        # ---- delegate the page faults to S-mode, or none of this works
        #
        # Without this, a page fault taken in S-mode goes to M-mode's mtvec, which nothing here sets,
        # and the machine restarts from _start. That is exactly what happened on the first run: the
        # trace ended with COMMIT pc=0x80000000, on EVERY core including the baseline, which is how it
        # was clear the defect was the probe's and not the TLB's.
        #
        # medeleg is masked to 0xB3FF by tcpu_csr, so bits 12 (instruction), 13 (load) and 15 (store)
        # page fault are all delegatable. The write is read back and checked: a probe that silently
        # failed to delegate would trap to the wrong place and look like a hang.
        li      t1, (1 << 12) | (1 << 13) | (1 << 15)
        csrw    medeleg, t1
        csrr    t2, medeleg
        bne     t2, t1, fail

        # ---- S-mode with Sv39 on root1
        la      t0, cont
        csrw    mepc, t0
        li      t1, (3 << 11)
        csrc    mstatus, t1
        li      t1, (1 << 11)
        csrs    mstatus, t1
        srli    t3, s2, 12
        li      t6, 8
        slli    t6, t6, 60
        or      t6, t6, t3
        csrw    satp, t6
        sfence.vma
        mret

cont:   la      t0, handler
        csrw    stvec, t0
        li      s5, 0                   # s5 = the cause the handler last recorded
        li      s6, 0                   # s6 = traps taken SINCE THIS CASE BEGAN.
                                        # Both are reset at the start of every case. The first version
                                        # reset only s5, so case B saw case A's trap still counted and
                                        # failed before doing anything -- on every core including the
                                        # baseline, which is how it was clear the fault was the probe's.

        # the alias VA of `scratch`
        li      t6, 0x80000000
        sub     s7, s1, t6
        li      t6, 0x40000000
        add     s7, s7, t6

        # ================= A: sfence.vma must invalidate a cached entry =================
        ld      t1, 0(s7)               # CACHES the alias, with W set
        li      t2, 0x5A5A5A5A
        bne     t1, t2, fail
        sd      t1, 0(s7)               # a store now succeeds; the entry is warm and writable
        li      t3, 1
        bne     s6, zero, fail          # nothing should have trapped yet

        li      t4, 1*8                 # drop W from the alias PTE
        add     t4, s2, t4
        li      t6, PTE_V|PTE_R|PTE_X|PTE_A|PTE_D
        li      t5, 0x80000000
        srli    t5, t5, 12
        slli    t5, t5, 10
        or      t5, t5, t6
        sd      t5, 0(t4)
        fence
        sfence.vma                      # <-- the thing under test

        li      s5, 0
        li      s6, 0                   # the COUNT is per-case too; case A's own trap is not case B's
        sd      t1, 0(s7)               # must FAULT: store page fault, cause 15
        li      t2, 15
        bne     s5, t2, fail_A
        li      t2, 1
        bne     s6, t2, fail_A          # exactly one trap

        # ================= B: a hit must honour A/D =================
        li      t4, 1*8                 # alias PTE: R W X, A set, D CLEAR
        add     t4, s2, t4
        li      t6, PTE_V|PTE_R|PTE_W|PTE_X|PTE_A
        li      t5, 0x80000000
        srli    t5, t5, 12
        slli    t5, t5, 10
        or      t5, t5, t6
        sd      t5, 0(t4)
        fence
        sfence.vma

        li      s5, 0
        li      s6, 0
        ld      t1, 0(s7)               # a LOAD succeeds and caches the entry (A=1, R=1)
        bne     s6, zero, fail_B        # it must not have trapped
        sd      t1, 0(s7)               # a STORE on the cached entry must fault: D is clear
        li      t2, 15
        bne     s5, t2, fail_B
        li      t2, 1
        bne     s6, t2, fail_B

        # ================= C: a satp write must invalidate =================
        li      t4, 1*8                 # restore full permissions in address space 1
        add     t4, s2, t4
        sd      s3, 0(t4)
        fence
        sfence.vma
        li      s5, 0
        li      s6, 0
        ld      t1, 0(s7)               # caches the alias again, fully permitted
        bne     s6, zero, fail_C

        srli    t3, s4, 12              # switch to root2, where the alias is invalid
        li      t6, 8
        slli    t6, t6, 60
        or      t6, t6, t3
        csrw    satp, t6                # <-- the thing under test; NO sfence.vma here on purpose
        li      s5, 0
        li      s6, 0
        ld      t1, 0(s7)               # must FAULT: load page fault, cause 13
        li      t2, 13
        bne     s5, t2, fail_C
        li      t2, 1
        bne     s6, t2, fail_C

        # ================= D: a SAME-VALUE satp write must invalidate too =================
        #
        # STAGE2-DESIGN.md promises a flush on EVERY satp write. The first RTL watched the satp VALUE,
        # so a write that changed nothing flushed nothing -- not an ISA violation on its own, since
        # sfence.vma is still required, but not what the document said either. Codex asked for the
        # promise to be implemented and tested rather than quietly narrowed. This is the test: the
        # page table is edited and satp is rewritten with the value it already has, with NO
        # sfence.vma anywhere. Only a per-write flush makes the edit visible.
        srli    t3, s2, 12                 # back to address space 1 (this write does change satp)
        li      t6, 8
        slli    t6, t6, 60
        or      t6, t6, t3
        csrw    satp, t6
        sfence.vma
        li      t4, 1*8                    # full permissions again
        add     t4, s2, t4
        sd      s3, 0(t4)
        fence
        sfence.vma
        li      s5, 0
        li      s6, 0
        ld      t1, 0(s7)                  # WARM the alias with W present
        bne     s6, zero, fail_D

        li      t4, 1*8                    # drop W, and deliberately do NOT sfence
        add     t4, s2, t4
        li      t6, PTE_V|PTE_R|PTE_X|PTE_A|PTE_D
        li      t5, 0x80000000
        srli    t5, t5, 12
        slli    t5, t5, 10
        or      t5, t5, t6
        sd      t5, 0(t4)
        fence

        csrr    t0, satp
        csrw    satp, t0                   # <-- a SAME-VALUE write, and nothing else
        li      s5, 0
        li      s6, 0
        sd      t1, 0(s7)                  # must FAULT: the stale entry must be gone
        li      t2, 15
        bne     s5, t2, fail_D
        li      t2, 1
        bne     s6, t2, fail_D

        la      a0, marker
        call    htif_puts
        li      a0, 0
        call    htif_exit

fail_D: la      a0, fmD
        j       failout
fail_A: la      a0, fmA
        j       failout
fail_B: la      a0, fmB
        j       failout
fail_C: la      a0, fmC
        j       failout
fail:   la      a0, failmark
failout:call    htif_puts
        la      a0, failmark
        call    htif_puts
        li      a0, 1
        call    htif_exit

        # ---- the S-mode trap handler: record the cause, count it, step over the faulting instruction
        .align 4
handler:csrr    s5, scause
        addi    s6, s6, 1
        csrr    t0, sepc
        addi    t0, t0, 4
        csrw    sepc, t0
        sret

        .section .rodata, "a", @progbits
marker:   .asciz "TEACHING-TLB-SFENCE-OK\n"
failmark: .asciz "TEACHING-TLB-SFENCE-FAIL\n"
fmA:      .asciz "case A (sfence.vma did not invalidate a cached entry)\n"
fmB:      .asciz "case B (a hit ignored A/D)\n"
fmC:      .asciz "case C (a satp write did not invalidate)\n"
fmD:      .asciz "case D (a SAME-VALUE satp write did not invalidate)\n"

        .section .data, "aw", @progbits
        .align 12
root1:  .zero 4096
        .align 12
root2:  .zero 4096
        .align 3
scratch: .zero 64
