# PIPE-P1 flush-window bench program (codex-pipe-p1-flush-boundary). Standalone: its own startup and handler.
# Every iteration: FENCE.I (serialising flush + I-cache invalidation, so every line below is refilled again), taken
# jumps and branches over lines that the front end prefetches on the wrong path (one of them, fw_errline, is answered
# with a bus ERROR by the bench and must never trap), ECALL (a WB trap flush, then MRET), CSR accesses (serialising),
# loads and stores. The bench raises the interrupt line at a swept cycle; the handler quiets it.
# Architectural result: fw_result (a control-flow-dependent checksum), ecall_n, irq_n, bad_n. Exit 0 = self-checks pass.
#define ITER 4
        .option norvc
        .section .text.start, "ax", @progbits
        .globl _start
_start:
        la      sp, _stack_top
        la      t0, fw_handler
        csrw    mtvec, t0
        li      t0, 8
        csrs    mie, t0                 # MSIE
        csrsi   mstatus, 8              # MIE
        li      s0, ITER
        li      s1, 0
        la      s2, fw_data
        j       loop

        .text
        .align 4
loop:   fence.i
        addi    s1, s1, 1
        ld      t1, 0(s2)
        add     s1, s1, t1
        .align 4
b1:     addi    s1, s1, 3
        slli    t2, s1, 1
        xor     s1, s1, t2
        j       b1_over                 # last slot of its line: the next line is fetched on the wrong path
        .align 4
        .globl fw_errline
fw_errline:                             # the bench answers every fetch of this line with an error: never executed
        addi    s1, s1, 0x100
        addi    s1, s1, 0x100
        addi    s1, s1, 0x100
        addi    s1, s1, 0x100
        .align 4
b1_over:
        addi    s1, s1, 5
        andi    t3, s1, 1
        srli    t4, s1, 3
        bnez    t3, b2_over             # data-dependent: both paths occur
        .align 4
b2_pad: addi    s1, s1, 7
        xori    s1, s1, 0x55
        add     s1, s1, t4
        addi    s1, s1, 9
        .align 4
b2_over:
        ecall                           # WB trap flush; the handler counts it and resumes after it
        addi    s1, s1, 11
        sd      s1, 8(s2)
        ld      t5, 8(s2)
        .align 4
b3:     add     s1, s1, t5
        csrr    t6, mhartid             # serialising reads and an idempotent write (not misa: it differs by design)
        la      t4, fw_handler
        csrw    mtvec, t4
        .align 4
b3b:    csrr    t5, mtvec
        sub     t5, t5, t4
        add     s1, s1, t5
        add     s1, s1, t6
        .align 4
b4:     andi    t3, s1, 2
        beqz    t3, b4_over
        addi    s1, s1, 13
        slli    t2, s1, 2
        .align 4
b4_pad: xor     s1, s1, t2
        addi    s1, s1, 17
        nop
        nop
        .align 4
b4_over:
        addi    s0, s0, -1
        sw      s1, 16(s2)
        lw      t1, 16(s2)
        add     s1, s1, t1
        bnez    s0, loop                # EX redirect, backwards
        .align 4
        la      t0, fw_result
        sd      s1, 0(t0)
        la      t0, ecall_n
        ld      t1, 0(t0)
        li      t2, ITER
        li      a0, 2
        bne     t1, t2, fw_exit
        la      t0, bad_n
        ld      t1, 0(t0)
        li      a0, 3
        bnez    t1, fw_exit
        la      t0, irq_n
        ld      t1, 0(t0)
        li      t2, 2
        li      a0, 4
        bgeu    t1, t2, fw_exit
        li      a0, 0
fw_exit:
        slli    a0, a0, 1
        ori     a0, a0, 1
        la      t0, tohost
        sd      a0, 0(t0)
1:      j       1b

        .align 4
fw_handler:                             # not re-entrant (MIE is off inside); mscratch holds t0
        csrw    mscratch, t0
        la      t0, fw_save
        sd      t1, 0(t0)
        sd      t2, 8(t0)
        csrr    t1, mcause
        bltz    t1, 7f
        li      t2, 11
        bne     t1, t2, 5f
        la      t1, ecall_n
        ld      t2, 0(t1)
        addi    t2, t2, 1
        sd      t2, 0(t1)
        j       6f
5:      la      t2, bad_cause           # anything else (a fetch access fault from the error line, ...) is a failure
        sd      t1, 0(t2)
        la      t1, bad_n
        ld      t2, 0(t1)
        addi    t2, t2, 1
        sd      t2, 0(t1)
6:      csrr    t1, mepc
        addi    t1, t1, 4
        csrw    mepc, t1
        j       9f
7:      la      t1, irq_n
        ld      t2, 0(t1)
        addi    t2, t2, 1
        sd      t2, 0(t1)
        li      t1, 0x60000000          # quiet the bench's interrupt source
        li      t2, 7
        sd      t2, 0(t1)
9:      ld      t1, 0(t0)
        ld      t2, 8(t0)
        csrr    t0, mscratch
        mret

        .data
        .align 3
        .globl fw_result, ecall_n, irq_n, bad_n, bad_cause
fw_data:   .dword 0x0123456789abcdef, 0, 0, 0
fw_result: .dword 0
ecall_n:   .dword 0
irq_n:     .dword 0
bad_n:     .dword 0
bad_cause: .dword 0
fw_save:   .dword 0, 0

        .section .htif, "aw", @progbits
        .align 6
        .globl tohost
tohost: .dword 0
