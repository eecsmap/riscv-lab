# A cached translation must not be reachable through a NON-CANONICAL alias.
#
# Codex's finding, reproduced at the core boundary. tcpu_tlb compares only va[38:12], so an entry
# filled by a canonical address is hit by a later alias with the same low VPN and different upper bits.
# Only tcpu_ptw checked va[63:39] == {25{va[38]}}, and a TLB hit skipped the walker entirely: the alias
# was translated and the access went through, where a page fault was required.
#
# Every case here WARMS a valid translation first -- that is the point. A cold non-canonical address
# faults on any core, with or without a TLB; only a warm one distinguishes the hit path. The cold case
# is kept anyway, as the control that says the warm result is about caching and not about addresses.
#
# Asserted at the core boundary: scause AND the full stval, not hit/miss in a component.
#include "m3lib.h"
#define PTE_V 0x01
#define PTE_R 0x02
#define PTE_W 0x04
#define PTE_X 0x08
#define PTE_U 0x10
#define PTE_A 0x40
#define PTE_D 0x80
#define LEAF  (PTE_V|PTE_R|PTE_W|PTE_X|PTE_A|PTE_D)

        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start
_start: la      sp, _stack_top

        # ---------- page tables ----------
        # root[2]   : 1 GiB identity for 0x80000000, so this code runs with translation on
        # root[1]   : 1 GiB leaf   -> VA 0x40000000        (the 1 GiB case)
        # root[3]   : -> l1a, whose entry 0 is a 2 MiB leaf at VA 0xC0000000   (the 2 MiB case)
        # root[4]   : -> l1b -> l0b, a 4 KiB leaf at VA 0x100000000            (the 4 KiB case)
        # root[256] : 1 GiB leaf   -> VA 0xFFFFFFC000000000 (the HIGH half, va[38]=1)
        la      s2, root
        li      t5, 0x80000000
        srli    t5, t5, 12
        slli    t5, t5, 10
        li      t6, LEAF
        or      s3, t5, t6              # s3 = a full-permission 1 GiB leaf for the DRAM gigabyte

        li      t4, 2*8
        add     t4, s2, t4
        sd      s3, 0(t4)               # identity, so execution survives
        li      t4, 1*8
        add     t4, s2, t4
        sd      s3, 0(t4)               # VA 0x40000000      -> PA 0x80000000
        li      t4, 256*8
        add     t4, s2, t4
        sd      s3, 0(t4)               # VA 0xFFFFFFC000000000 -> PA 0x80000000

        la      s4, l1a                 # root[3] -> l1a
        srli    t0, s4, 12
        slli    t0, t0, 10
        ori     t0, t0, PTE_V           # a POINTER: V only, no R/W/X
        li      t4, 3*8
        add     t4, s2, t4
        sd      t0, 0(t4)
        sd      s3, 0(s4)               # l1a[0] = a 2 MiB leaf at VA 0xC0000000 -> PA 0x80000000

        la      s5, l1b                 # root[4] -> l1b
        srli    t0, s5, 12
        slli    t0, t0, 10
        ori     t0, t0, PTE_V
        li      t4, 4*8
        add     t4, s2, t4
        sd      t0, 0(t4)
        la      s6, l0b                 # l1b[0] -> l0b
        srli    t0, s6, 12
        slli    t0, t0, 10
        ori     t0, t0, PTE_V
        sd      t0, 0(s5)
        sd      s3, 0(s6)               # l0b[0] = a 4 KiB leaf at VA 0x100000000 -> PA 0x80000000
        fence

        # ---------- delegate the page faults, or a fault lands in M-mode and the machine restarts ----
        li      t1, (1 << 12) | (1 << 13) | (1 << 15)
        csrw    medeleg, t1
        csrr    t2, medeleg
        bne     t2, t1, fail

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
        li      s7, 0                   # s7 = scause recorded by the handler
        li      s8, 0                   # s8 = stval  recorded by the handler
        li      s9, 0                   # s9 = traps taken since the last reset of it

        # ================= 1 GiB entry, low half =================
        li      s10, 0x40000000
        li      s11, 0x0000008000000000     # bit 39 set: same va[38:12], not canonical
        or      s11, s11, s10
        call    warm_and_check

        # ================= 2 MiB entry =================
        li      s10, 0xC0000000
        li      s11, 0x0000008000000000
        or      s11, s11, s10
        call    warm_and_check

        # ================= 4 KiB entry =================
        li      s10, 1
        slli    s10, s10, 32               # VA 0x100000000
        li      s11, 0x0000008000000000
        or      s11, s11, s10
        call    warm_and_check

        # ================= HIGH half: va[38] = 1, upper bits must be ALL ONES =================
        li      s10, -1
        slli    s10, s10, 38
        # s10 = 0xFFFFFFC000000000, canonical, maps through root[256]
        li      t0, 1
        slli    t0, t0, 63
        xor     s11, s10, t0               # clear bit 63: same va[38:12], no longer all-ones above
        call    warm_and_check

        # ================= cold control: never warmed, must still fault the same way =================
        li      s11, 0x0000008000000000
        li      t0, 0x20000000
        or      s11, s11, t0               # nothing was ever mapped or cached here
        li      a1, 13
        call    do_load
        bne     s7, a1, fail_cold
        bne     s8, s11, fail_cold
        li      t2, 1
        bne     s9, t2, fail_cold

        la      a0, marker
        call    htif_puts
        li      a0, 0
        call    htif_exit

# ---- warm the canonical VA in s10, then require the alias in s11 to fault on load / store / fetch.
warm_and_check:
        mv      s1, ra
        li      s7, 0
        li      s9, 0
        ld      t0, 0(s10)                 # WARM: this must succeed and fill the TLB
        bnez    s9, fail_warm

        li      a1, 13
        call    do_load
        bne     s7, a1, fail_load
        bne     s8, s11, fail_tval
        li      t2, 1
        bne     s9, t2, fail_load

        li      a1, 15
        call    do_store
        bne     s7, a1, fail_store
        bne     s8, s11, fail_tval

        li      a1, 12
        call    do_fetch
        bne     s7, a1, fail_fetch
        bne     s8, s11, fail_tval

        mv      ra, s1
        ret

do_load:  li s7, 0; li s9, 0; ld  t0, 0(s11); ret
do_store: li s7, 0; li s9, 0; sd  x0, 0(s11); ret
do_fetch: li s7, 0; li s9, 0; la s3, 1f; jalr x0, 0(s11); 1: ret

        .align 4
handler:csrr    s7, scause
        csrr    s8, stval
        addi    s9, s9, 1
        csrr    t0, sepc
        li      t1, 12
        beq     s7, t1, 2f                 # an instruction page fault: sepc is the bad address, so
        addi    t0, t0, 4                  # stepping over it is meaningless -- resume at the label
        csrw    sepc, t0
        sret
2:      csrw    sepc, s3
        sret

fail_warm:  la a0, fmW; j failout
fail_load:  la a0, fmL; j failout
fail_store: la a0, fmS; j failout
fail_fetch: la a0, fmF; j failout
fail_tval:  la a0, fmT; j failout
fail_cold:  la a0, fmC; j failout
fail:       la a0, failmark
failout:    call htif_puts
            la a0, failmark
            call htif_puts
            li a0, 1
            call htif_exit

        .section .rodata, "a", @progbits
marker:   .asciz "TEACHING-TLB-CANON-OK\n"
failmark: .asciz "TEACHING-TLB-CANON-FAIL\n"
fmW:      .asciz "the canonical warm-up itself faulted\n"
fmL:      .asciz "a LOAD through the non-canonical alias did not page-fault\n"
fmS:      .asciz "a STORE through the non-canonical alias did not page-fault\n"
fmF:      .asciz "a FETCH from the non-canonical alias did not page-fault\n"
fmT:      .asciz "the fault was raised but stval was not the offending address\n"
fmC:      .asciz "the cold control did not fault as expected\n"

        .section .data, "aw", @progbits
        .align 12
root:   .zero 4096
        .align 12
l1a:    .zero 4096
        .align 12
l1b:    .zero 4096
        .align 12
l0b:    .zero 4096
