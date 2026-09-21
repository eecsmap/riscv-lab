# Extension probe: A. One of each shape that matters -- an AMO's effect *and* its return value, a .W form's
# sign extension, and an LR/SC pair that succeeds and one that fails because the reservation was broken.
# Checking the returned old value matters: an AMO that writes the right word and returns the wrong one is
# still wrong, and that is exactly the fault the simulation fault-injection modelled.
#include "m3lib.h"
        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start
_start: la      sp, _stack_top
        la      s0, scratch

        li      t0, 5
        sd      t0, 0(s0)
        fence
        li      t1, 7
        amoadd.d t2, t1, (s0)           # returns the OLD value
        li      t3, 5
        bne     t2, t3, fail
        ld      t4, 0(s0)               # and memory holds the sum
        li      t5, 12
        bne     t4, t5, fail

        li      t0, -1                  # 0xffffffffffffffff
        sd      t0, 0(s0)
        fence
        li      t1, 1
        amoadd.w t2, t1, (s0)           # .W: old low word is -1, sign-extended
        li      t3, -1
        bne     t2, t3, fail

        li      t0, 0x11
        sd      t0, 0(s0)
        fence
        li      t1, 0x22
        amoswap.d t2, t1, (s0)
        li      t3, 0x11
        bne     t2, t3, fail
        ld      t4, 0(s0)
        li      t5, 0x22
        bne     t4, t5, fail

        li      t0, 100                 # LR/SC that should succeed
        sd      t0, 0(s0)
        fence
1:      lr.d    t1, (s0)
        addi    t1, t1, 1
        sc.d    t2, t1, (s0)
        bnez    t2, 1b                  # retry on a spurious failure
        ld      t3, 0(s0)
        li      t4, 101
        bne     t3, t4, fail

        lr.d    t1, (s0)                # a reservation broken by an intervening store
        li      t2, 55
        sd      t2, 0(s0)
        li      t3, 99
        sc.d    t4, t3, (s0)
        beqz    t4, fail                # SC must report failure (non-zero)
        ld      t5, 0(s0)
        li      t6, 55                  # and must not have written
        bne     t5, t6, fail

        la      a0, marker
        call    htif_puts
        li      a0, 0
        call    htif_exit
fail:   la      a0, failmark
        call    htif_puts
        li      a0, 1
        call    htif_exit

        .section .data, "aw", @progbits
        .align 3
scratch: .dword 0
        .section .rodata, "a", @progbits
marker:   .asciz "TEACHING-EXT-A-OK\n"
failmark: .asciz "TEACHING-EXT-A-FAIL\n"
