# Performance probe: what address translation costs when there is no TLB.
#
# perf01 measured the core bare. This measures the SAME two loops, in the same binary, at the same
# addresses, under three regimes -- so the differences are translation and nothing else:
#
#   1  bare        satp = 0, M-mode
#   2  Sv39 1 GiB  a megapage leaf at level 2: the walk terminates immediately, ONE PTE read
#   3  Sv39 4 KiB  a full three-level walk to a 4 KiB leaf: THREE PTE reads
#
# Regime 3 is what xv6 runs under. tcpu_ptw.v is explicit -- "Serial, no TLB, no cache: one 8-byte PTE
# read per level" -- so there is no translation caching of any kind and every fetch pays the walk again,
# as does every load. Comparing 3 against 1 gives the per-access cost of a three-level walk; comparing 2
# against 1 gives the cost of a single-level one, and 3 minus 2 is what the extra two levels cost.
#
# All three mappings are IDENTITY over the gigabyte this image lives in, so the code executes at the same
# virtual addresses throughout and no loop is measured at a different location than another.
#
# Counters are read as `cycle`/`instret` (0xC00/0xC02) rather than `mcycle`/`minstret`, because regimes 2
# and 3 run in S-mode where the M-mode counters are not accessible at all. mcounteren.CY and .IR are set
# in M-mode first, or those reads would trap.
#include "m3lib.h"
#define PTE_V 0x01
#define PTE_R 0x02
#define PTE_W 0x04
#define PTE_X 0x08
#define PTE_A 0x40
#define PTE_D 0x80

        .equ ITERS,  10000
        .equ NPAGES, 64             # 256 KiB of 4 KiB leaves: the image, its tables and its stack over

        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start
_start: la      sp, _stack_top
        la      s8, results
        la      s9, scratch

        # S-mode must be allowed to read the counters, or regimes 2 and 3 trap instead of measuring.
        li      t0, 0x5                 # bit0 CY, bit2 IR
        csrw    mcounteren, t0

# ---- regime 1: bare ----------------------------------------------------------------------------------
        li      a0, ITERS
        call    measure_alu
        sd      a0, 0(s8)
        sd      a1, 8(s8)
        li      a0, ITERS
        call    measure_ld
        sd      a0, 16(s8)
        sd      a1, 24(s8)

# ---- build both page tables --------------------------------------------------------------------------
        # (a) the megapage root: one 1 GiB leaf identity-mapping the gigabyte at 0x80000000.
        #     VPN[2] of 0x80000000 is bits 38:30 = 2.
        li      t1, 0x80000000
        srli    t1, t1, 12
        slli    t1, t1, 10              # a PTE's ppn field begins at bit 10
        li      t2, PTE_V|PTE_R|PTE_W|PTE_X|PTE_A|PTE_D
        or      t1, t1, t2
        la      t0, root_sp
        addi    t0, t0, 2*8
        sd      t1, 0(t0)

        # (b) the three-level root: root_4k[2] -> l1, l1[0] -> l0, l0[i] -> 4 KiB leaves.
        #     VPN[1] and VPN[0] of 0x80000000 are both 0.
        la      t0, root_4k
        addi    t0, t0, 2*8
        la      t1, l1
        srli    t1, t1, 12
        slli    t1, t1, 10
        ori     t1, t1, PTE_V           # a non-leaf PTE: V with no R/W/X
        sd      t1, 0(t0)

        la      t0, l1
        la      t1, l0
        srli    t1, t1, 12
        slli    t1, t1, 10
        ori     t1, t1, PTE_V
        sd      t1, 0(t0)

        la      t0, l0
        li      t1, 0x80000000
        srli    t1, t1, 12
        slli    t1, t1, 10
        li      t2, PTE_V|PTE_R|PTE_W|PTE_X|PTE_A|PTE_D
        or      t1, t1, t2
        li      t3, NPAGES
        li      t4, (1 << 10)           # one page onward in the ppn field
1:      sd      t1, 0(t0)
        add     t1, t1, t4
        addi    t0, t0, 8
        addi    t3, t3, -1
        bnez    t3, 1b
        fence

# ---- regime 2: Sv39, megapage. Drop to S-mode with translation on ------------------------------------
        la      t0, l_sp
        csrw    mepc, t0
        li      t1, (3 << 11)
        csrc    mstatus, t1             # MPP = 00
        li      t1, (1 << 11)
        csrs    mstatus, t1             # MPP = 01, S-mode
        la      t2, root_sp
        srli    t2, t2, 12
        li      t6, 8
        slli    t6, t6, 60              # MODE = Sv39
        or      t6, t6, t2
        csrw    satp, t6
        sfence.vma
        mret

l_sp:   li      a0, ITERS
        call    measure_alu
        sd      a0, 32(s8)
        sd      a1, 40(s8)
        li      a0, ITERS
        call    measure_ld
        sd      a0, 48(s8)
        sd      a1, 56(s8)

# ---- regime 3: Sv39, 4 KiB leaves. satp is writable from S-mode; both maps are identity here, so the
#      instruction after the switch is mapped by the new table exactly as it was by the old one.
        la      t2, root_4k
        srli    t2, t2, 12
        li      t6, 8
        slli    t6, t6, 60
        or      t6, t6, t2
        csrw    satp, t6
        sfence.vma

        li      a0, ITERS
        call    measure_alu
        sd      a0, 64(s8)
        sd      a1, 72(s8)
        li      a0, ITERS
        call    measure_ld
        sd      a0, 80(s8)
        sd      a1, 88(s8)

# ---- every window must have retired exactly what it was supposed to ----------------------------------
        li      t3, (ITERS * 3 + 2)
        li      t4, 6
        la      t0, results
        addi    t0, t0, 8
2:      ld      t5, 0(t0)
        bne     t5, t3, fail
        addi    t0, t0, 16
        addi    t4, t4, -1
        bnez    t4, 2b

# ---- report ------------------------------------------------------------------------------------------
        la      s2, labels
        la      s3, results
        li      s4, 12
3:      mv      a0, s2
        call    htif_puts
        ld      a0, 0(s3)
        call    puthex
        addi    s3, s3, 8
4:      lbu     t0, 0(s2)               # step over this label's NUL to reach the next
        addi    s2, s2, 1
        bnez    t0, 4b
        addi    s4, s4, -1
        bnez    s4, 3b

        la      a0, marker
        call    htif_puts
        li      a0, 0
        call    htif_exit
fail:   la      a0, failmark
        call    htif_puts
        li      a0, 1
        call    htif_exit

# ---- the two measured loops --------------------------------------------------------------------------
# a0 = iterations. Returns a0 = elapsed cycles, a1 = retired instructions. The two differ in exactly one
# instruction so that the difference between their CPIs is that instruction and nothing else.
measure_alu:
        mv      t6, a0
        csrr    t4, cycle
        csrr    t5, instret
1:      addi    t1, t1, 1
        addi    t6, t6, -1
        bnez    t6, 1b
        csrr    a0, cycle
        csrr    a1, instret
        sub     a0, a0, t4
        sub     a1, a1, t5
        ret

measure_ld:
        mv      t6, a0
        csrr    t4, cycle
        csrr    t5, instret
1:      ld      t1, 0(s9)
        addi    t6, t6, -1
        bnez    t6, 1b
        csrr    a0, cycle
        csrr    a1, instret
        sub     a0, a0, t4
        sub     a1, a1, t5
        ret

# ---- a0 as 16 hex digits then a newline. htif_putc clobbers t0-t3 and a0 and preserves ra; htif_puts
# also uses s10/s11. State that must survive the calls lives in s5-s7.
puthex: mv      s5, a0
        mv      s7, ra
        li      s6, 60
1:      srl     t0, s5, s6
        andi    t0, t0, 15
        li      t1, 10
        blt     t0, t1, 2f
        addi    t0, t0, 87
        j       3f
2:      addi    t0, t0, 48
3:      mv      a0, t0
        call    htif_putc
        addi    s6, s6, -4
        bgez    s6, 1b
        li      a0, 10
        call    htif_putc
        mv      ra, s7
        ret

        .section .rodata, "a", @progbits
labels: .asciz "SV39-CYC-BARE-ALU="
        .asciz "SV39-INS-BARE-ALU="
        .asciz "SV39-CYC-BARE-LD="
        .asciz "SV39-INS-BARE-LD="
        .asciz "SV39-CYC-MEGA-ALU="
        .asciz "SV39-INS-MEGA-ALU="
        .asciz "SV39-CYC-MEGA-LD="
        .asciz "SV39-INS-MEGA-LD="
        .asciz "SV39-CYC-4K-ALU="
        .asciz "SV39-INS-4K-ALU="
        .asciz "SV39-CYC-4K-LD="
        .asciz "SV39-INS-4K-LD="
marker:   .asciz "TEACHING-PERF-SV39-OK\n"
failmark: .asciz "TEACHING-PERF-SV39-FAIL\n"

        .section .data, "aw", @progbits
        .align 12
root_sp: .zero 4096
        .align 12
root_4k: .zero 4096
        .align 12
l1:      .zero 4096
        .align 12
l0:      .zero 4096
        .align 3
results: .zero 96
scratch: .dword 0x0123456789abcdef
