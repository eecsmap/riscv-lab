# MCU-0 crt0 for programs that take traps (step 4 and later): stack, zero bss, point mtvec at trap_entry, call main.
#
# trap_entry saves the registers a C function may clobber (ra, t0-t6, a0-a7), calls
#     void trap_handler(uint64_t mcause, uint64_t mepc)
# on the interrupted code's stack, restores them and returns with mret. The callee-saved registers (s0-s11) are
# preserved by trap_handler itself, as the calling convention promises, so they need no saving here.
        .section .text.start, "ax", @progbits
        .globl _start
_start: la      sp, _stack_top
        la      t0, _bss_start
        la      t1, _bss_end
1:      bgeu    t0, t1, 2f
        sd      zero, 0(t0)
        addi    t0, t0, 8
        j       1b
2:      la      t0, trap_entry
        csrw    mtvec, t0               # direct mode: every trap starts at trap_entry
        call    main
3:      j       3b

        .text
        .align  2                       # mtvec's low two bits are the mode, so the entry must be 4-byte aligned
        .globl  trap_entry
trap_entry:
        addi    sp, sp, -128
        sd      ra,   0(sp)
        sd      t0,   8(sp)
        sd      t1,  16(sp)
        sd      t2,  24(sp)
        sd      t3,  32(sp)
        sd      t4,  40(sp)
        sd      t5,  48(sp)
        sd      t6,  56(sp)
        sd      a0,  64(sp)
        sd      a1,  72(sp)
        sd      a2,  80(sp)
        sd      a3,  88(sp)
        sd      a4,  96(sp)
        sd      a5, 104(sp)
        sd      a6, 112(sp)
        sd      a7, 120(sp)
        csrr    a0, mcause
        csrr    a1, mepc
        call    trap_handler
        ld      ra,   0(sp)
        ld      t0,   8(sp)
        ld      t1,  16(sp)
        ld      t2,  24(sp)
        ld      t3,  32(sp)
        ld      t4,  40(sp)
        ld      t5,  48(sp)
        ld      t6,  56(sp)
        ld      a0,  64(sp)
        ld      a1,  72(sp)
        ld      a2,  80(sp)
        ld      a3,  88(sp)
        ld      a4,  96(sp)
        ld      a5, 104(sp)
        ld      a6, 112(sp)
        ld      a7, 120(sp)
        addi    sp, sp, 128
        mret

        # the tools expect a tohost word in every image; these programs never write it
        .section .htif, "aw", @progbits
        .align 6
        .globl tohost
tohost: .dword 0
