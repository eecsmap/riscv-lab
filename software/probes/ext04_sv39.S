# Extension probe: Sv39. Builds a two-entry page table, turns translation on in S-mode, and proves it is
# really translating by reading the SAME virtual address through two different mappings and getting two
# different values. A probe that merely enabled satp and survived would prove nothing -- the CPU could be
# ignoring it entirely.
#
# Layout: a root table with one entry covering VA 0x00000000_40000000 (a 1 GiB megapage), mapped to the
# physical gigabyte that contains DRAM. So VA 0x4xxxxxxx aliases PA 0x8xxxxxxx.
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

        # A known value at a known physical address inside DRAM. The address comes from the linker, not
        # from a number typed here: an earlier version used 0x80002000, which is where htif.S puts
        # `tohost`, so the probe overwrote the HTIF mailbox and the console spun for ever waiting for it
        # to clear. Picking addresses by hand inside a program's own image is how that happens.
        la      s1, scratch             # the physical address
        li      t1, 0x5A5A5A5A
        sd      t1, 0(s1)
        fence

        # Two 1 GiB leaves in the root table. VPN[2] is bits 38:30 of the VA, so:
        #   entry 1 -> VA 0x40000000 : the alias used to prove translation is really happening
        #   entry 2 -> VA 0x80000000 : the identity mapping of the gigabyte this code, its stack and its
        #                              HTIF variables live in. Without it, execution faults on the very
        #                              first instruction after translation is enabled -- which is what
        #                              happened when this probe was first written.
        la      t2, root
        srli    t3, t2, 12              # PPN of the root table
        li      t5, 0x80000000
        srli    t5, t5, 12              # PPN of the target gigabyte
        slli    t5, t5, 10              # a PTE's ppn field starts at bit 10
        li      t6, PTE_V|PTE_R|PTE_W|PTE_X|PTE_A|PTE_D
        or      t5, t5, t6              # the leaf PTE, used for both entries

        li      t4, 1*8
        add     t4, t2, t4
        sd      t5, 0(t4)               # VA 0x40000000 -> PA 0x80000000
        li      t4, 2*8
        add     t4, t2, t4
        sd      t5, 0(t4)               # VA 0x80000000 -> PA 0x80000000 (identity)
        fence

        # satp = MODE_Sv39 | PPN(root)
        li      t6, 8
        slli    t6, t6, 60
        or      t6, t6, t3
        # drop to S-mode with translation on: set MPP=S, MEPC=cont, then mret
        la      t0, cont
        csrw    mepc, t0
        # MPP is mstatus[12:11]. To return to S-mode it must read 01: clear both bits, then set bit 11.
        # An earlier version cleared bit 11 and set bit 11, leaving bit 12 alone -- so MPP stayed 11 and
        # mret went back to M-mode, where satp is ignored entirely and the probe proved nothing.
        li      t1, (3 << 11)
        csrc    mstatus, t1             # MPP = 00
        li      t1, (1 << 11)
        csrs    mstatus, t1             # MPP = 01 (S)
        csrw    satp, t6
        sfence.vma
        mret

cont:   # Now in S-mode with Sv39 on. The alias of physical P is VA = P - 0x80000000 + 0x40000000.
        li      t6, 0x80000000
        sub     t0, s1, t6
        li      t6, 0x40000000
        add     t0, t0, t6              # t0 = the alias VA of `scratch`

        ld      t1, 0(t0)               # read the value written before translation was on
        li      t2, 0x5A5A5A5A
        bne     t1, t2, fail

        # write through the alias, read back through the identity mapping: the same memory, two routes
        li      t3, 0xA5A5A5A5
        sd      t3, 0(t0)
        fence
        ld      t5, 0(s1)
        bne     t5, t3, fail

        la      a0, marker
        call    htif_puts
        li      a0, 0
        call    htif_exit
fail:   la      a0, failmark
        call    htif_puts
        li      a0, 1
        call    htif_exit

        .section .data, "aw", @progbits
        .align 12
root:   .zero 4096
        .align 3
scratch: .dword 0                       # the linker decides where this lives, not a hand-picked address
        .section .rodata, "a", @progbits
marker:   .asciz "TEACHING-EXT-SV39-OK\n"
failmark: .asciz "TEACHING-EXT-SV39-FAIL\n"
