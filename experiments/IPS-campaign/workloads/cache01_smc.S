# Self-modifying code: after fence.i, the NEW instruction must be the one that runs.
#
# This is the case an instruction cache exists to get wrong. A small function is called until its line
# is certainly resident, then the instruction that produces its return value is overwritten and
# `fence.i` is issued. The next call must return the NEW value. A cache that ignores fence.i returns
# the old one, and nothing else in the campaign would notice.
#
# Bare metal, no translation: the point is the cache, and adding Sv39 would only add ways to fail for
# other reasons.
#include "m3lib.h"

        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start
_start: la      sp, _stack_top

        # ---- warm it: call the function enough times that its line is resident under any policy
        li      s1, 16
1:      call    target
        li      t0, 0x11111111
        bne     a0, t0, fail_warm
        addi    s1, s1, -1
        bnez    s1, 1b

        # ---- overwrite the immediate: `li a0, 0x11111111` becomes `li a0, 0x22222222`
        #
        # The instruction is rewritten as a whole word, from a template assembled here, rather than by
        # patching bits: an immediate the assembler chose is not something to take apart by hand.
        la      s2, target_li               # the address of the instruction to replace
        la      s3, new_li                  # the replacement, assembled below
        lw      t1, 0(s3)
        sw      t1, 0(s2)
        la      s4, target_li2
        la      s5, new_li2
        lw      t1, 0(s5)
        sw      t1, 0(s4)
        fence                               # the stores must be in memory before the invalidate

        # ---- WITHOUT fence.i the architecture says nothing, so nothing is asserted here.
        fence.i

        call    target
        li      t0, 0x22222222
        bne     a0, t0, fail_stale

        la      a0, marker
        call    htif_puts
        li      a0, 0
        call    htif_exit

fail_warm:  la a0, fmW; j failout
fail_stale: la a0, fmS; j failout
failout:    call htif_puts
            la a0, failmark
            call htif_puts
            li a0, 1
            call htif_exit

        # ---- the function under test. `li` of a 32-bit constant is lui + addi, so both halves are
        # replaced; they are adjacent and inside the same 16-byte line as long as the function is
        # aligned, which .align 4 guarantees.
        .align 4
target:
target_li:  lui  a0, 0x11111
target_li2: addi a0, a0, 0x111
        ret

        # the replacement instructions, assembled rather than hand-encoded
        .align 2
new_li:  lui  a0, 0x22222
new_li2: addi a0, a0, 0x222

        .section .rodata, "a", @progbits
marker:   .asciz "TEACHING-CACHE-SMC-OK\n"
failmark: .asciz "TEACHING-CACHE-SMC-FAIL\n"
fmW:      .asciz "the function returned the wrong value BEFORE any modification\n"
fmS:      .asciz "after fence.i the STALE instruction still ran\n"
