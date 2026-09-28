# dual01 (T3.1 boot through the real ROM, T3.2 independent stacks). Both harts come from the ROM's wake
# protocol: the host writes msip[0] only; hart 0 probes msip[1], msip[2], ... and wakes what exists; hart 1
# waits for msip[0] to clear. Each hart records its entry (mhartid + 0xA5), its sp, fills a canary block on
# its own stack, then -- after a barrier -- reads the OTHER hart's canary block, which must be that hart's
# pattern (no cross-pollution, both stacks live). Hart 0 reports; hart 1 parks.
#include "dual.h"
        .section .text, "ax", @progbits
        .option norvc
        .globl main
main:   mv      s0, a0                          # s0 = hartid
        # entry record
        la      t0, entry_flag
        slli    t1, s0, 3
        add     t0, t0, t1
        addi    t2, s0, 0xA5
        sd      t2, 0(t0)
        la      t0, sp_rec
        add     t0, t0, t1
        sd      sp, 0(t0)
        # canaries: 8 doublewords at sp-64..sp-8, pattern (h+1) * 0x0101010101010101
        li      t3, 0x0101010101010101
        addi    t4, s0, 1
        mul     t3, t3, t4
        addi    t5, sp, -64
        li      t6, 8
1:      sd      t3, 0(t5)
        addi    t5, t5, 8
        addi    t6, t6, -1
        bnez    t6, 1b
        fence   rw, rw
        BARRIER(arrived, NHARTS, t0)
        # read the other hart's canaries through its recorded sp
        li      t1, 1
        sub     t1, t1, s0                      # other = 1 - h
        la      t0, sp_rec
        slli    t2, t1, 3
        add     t0, t0, t2
        ld      t5, 0(t0)                       # other's sp
        addi    t5, t5, -64
        li      t3, 0x0101010101010101
        addi    t4, t1, 1
        mul     t3, t3, t4                      # other's pattern
        li      t6, 8
        li      a5, 1                           # ok
2:      ld      a6, 0(t5)
        bne     a6, t3, 3f
        addi    t5, t5, 8
        addi    t6, t6, -1
        bnez    t6, 2b
        j       4f
3:      li      a5, 2                           # cross-stack mismatch
4:      # own canaries still intact?
        addi    t5, sp, -64
        li      t3, 0x0101010101010101
        addi    t4, s0, 1
        mul     t3, t3, t4
        li      t6, 8
5:      ld      a6, 0(t5)
        bne     a6, t3, 6f
        addi    t5, t5, 8
        addi    t6, t6, -1
        bnez    t6, 5b
        j       7f
6:      li      a5, 3                           # own stack clobbered
7:      la      t0, ok
        slli    t1, s0, 3
        add     t0, t0, t1
        sd      a5, 0(t0)
        fence   rw, rw
        la      t0, done
        add     t0, t0, t1
        li      t2, 1
        sw      t2, 0(t0)
        bnez    s0, park                        # hart 1 parks here for ever
        # ---- hart 0: gather and report
        WAIT_EQ(done+8, 1, t0)
        la      t0, ok
        ld      t1, 0(t0)
        li      t2, 1
        bne     t1, t2, fail_ok0
        ld      t1, 8(t0)
        bne     t1, t2, fail_ok1
        la      t0, entry_flag
        ld      t1, 8(t0)
        li      t2, 0xA6
        bne     t1, t2, fail_entry
        la      t0, sp_rec
        ld      t1, 8(t0)                       # hart 1's sp must lie in its own stack
        la      t2, _stack_base
        li      t3, 0x1000
        add     t2, t2, t3
        blt     t1, t2, fail_sp
        add     t2, t2, t3
        bgt     t1, t2, fail_sp
        la      a0, msg_ok
        call    htif_puts
        la      t0, sp_rec
        ld      a0, 8(t0)
        call    htif_puthex
        la      a0, msg_nl
        call    htif_puts
        li      a0, 0
        call    htif_exit
fail_ok0:  la a0, msg_fail; call htif_puts; FAIL(10)
fail_ok1:  la a0, msg_fail; call htif_puts; FAIL(11)
fail_entry: la a0, msg_fail; call htif_puts; FAIL(12)
fail_sp:   la a0, msg_fail; call htif_puts; FAIL(13)
park:   wfi
        j       park
        .section .data
        .align 3
        .globl arrived
arrived:    .word 0
            .word 0
done:       .dword 0, 0
entry_flag: .dword 0, 0
sp_rec:     .dword 0, 0
ok:         .dword 0, 0
msg_ok:     .asciz "M2B-BOOT-OK sp1=0x"
msg_nl:     .asciz "\n"
msg_fail:   .asciz "M2B-BOOT-FAIL\n"
