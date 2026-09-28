# PIPE-P1 test support: startup, exit, and one trap handler that LOGS every trap (cause, epc, tval) in order.
# Architectural only: nothing here depends on how many cycles anything takes.
        .option norvc
        .section .text.start, "ax", @progbits
        .globl _start
_start:
        la      sp, _stack_top
        la      t0, _bss_start
        la      t1, _bss_end
1:      bgeu    t0, t1, 2f
        sd      zero, 0(t0)
        addi    t0, t0, 8
        j       1b
2:      la      t0, p1_handler
        csrw    mtvec, t0
        la      t0, _handler_stack
        csrw    mscratch, t0
        call    main                    # main's return value is the exit code (0 = pass)
        .globl  tt_exit
tt_exit:
        slli    a0, a0, 1
        ori     a0, a0, 1
        la      t0, tohost
        sd      a0, 0(t0)
3:      j       3b

# ---- the handler: log (mcause, mepc, mtval); interrupts: quiet the harness source unless `irq_hold` says to
# keep it raised for that many more entries; exceptions: resume at mepc + 4, or at `fetch_recover` for a fetch
# access fault (cause 1) or a fetch misalignment (cause 0) whose epc is not a real instruction.
        .section .text, "ax", @progbits
        .globl p1_handler
        .align 2
p1_handler:
        csrrw   sp, mscratch, sp
        sd      t0, -8(sp)
        sd      t1, -16(sp)
        sd      t2, -24(sp)
        la      t1, trap_n
        ld      t0, 0(t1)
        li      t2, 16
        bgeu    t0, t2, 5f              # log full: count only
        slli    t2, t0, 3
        slli    t0, t0, 4
        add     t0, t0, t2              # t0 = n * 24
        la      t2, trap_log
        add     t2, t2, t0
        csrr    t0, mcause
        sd      t0, 0(t2)
        csrr    t0, mepc
        sd      t0, 8(t2)
        csrr    t0, mtval
        sd      t0, 16(t2)
5:      ld      t0, 0(t1)
        addi    t0, t0, 1
        sd      t0, 0(t1)
        csrr    t0, mcause
        bltz    t0, 7f                  # interrupt
        li      t1, 1
        beq     t0, t1, 6f
        bnez    t0, 8f                  # anything else but cause 0: resume after the instruction
        csrr    t1, mtval
        csrr    t2, mepc
        bne     t1, t2, 8f              # cause 0 with tval != epc: a branch/jump to a bad target -> skip the jump
6:      la      t0, fetch_recover       # the epc itself cannot be fetched: go to the test's recovery point
        ld      t0, 0(t0)
        csrw    mepc, t0
        j       9f
8:      csrr    t0, mepc
        addi    t0, t0, 4
        csrw    mepc, t0
        j       9f
7:      la      t1, irq_n
        ld      t0, 0(t1)
        addi    t0, t0, 1
        sd      t0, 0(t1)
        la      t1, irq_hold
        ld      t0, 0(t1)
        beqz    t0, 71f
        addi    t0, t0, -1              # keep the line raised: the interrupt must be taken again
        sd      t0, 0(t1)
        j       9f
71:     li      t0, 0x60000000          # the harness's test interrupt source: write 1s to quiet msip/mtip/meip
        li      t1, 7
        sd      t1, 0(t0)
9:      ld      t2, -24(sp)
        ld      t1, -16(sp)
        ld      t0, -8(sp)
        csrrw   sp, mscratch, sp
        mret

        .section .data
        .align 3
        .globl trap_n, irq_n, irq_hold, fetch_recover, trap_log
trap_n:        .dword 0
irq_n:         .dword 0
irq_hold:      .dword 0
fetch_recover: .dword 0
trap_log:      .space 16*24
        .space 256
_handler_stack:

        .section .htif, "aw", @progbits
        .align 6
        .globl tohost
tohost: .dword 0
        .align 6
        .globl fromhost
fromhost: .dword 0
