# MCU-0 crt0 for the preemptive scheduler (tasks.c): stack, zero bss, point mtvec at trap_entry, call main.
#
# trap_entry saves the WHOLE register state of the interrupted task, not just the caller-saved half: the handler may
# return to a different task, and that task's s-registers must not be the ones left over from this one.
# The saved state is a 256-byte frame on the interrupted task's own stack:
#     frame[0] = mepc (where the task resumes), frame[n] = xn for n = 1, 3..31 (frame[2], sp, is the frame itself)
# Then
#     uint64_t *trap_handler(uint64_t *frame, uint64_t mcause)
# returns the frame to resume -- the same one, or another task's -- and trap_entry restores from it and mrets.
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
        csrw    mtvec, t0
        call    main
3:      j       3b

        .text
        .align  2
        .globl  trap_entry
trap_entry:
        addi    sp, sp, -256
        .irp    n, 1,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
        sd      x\n, (\n*8)(sp)
        .endr
        csrr    t0, mepc
        sd      t0, 0(sp)
        mv      a0, sp
        csrr    a1, mcause
        call    trap_handler
        mv      sp, a0                  # switch stacks: from here on we are restoring the task the handler chose
        ld      t0, 0(sp)
        csrw    mepc, t0
        .irp    n, 1,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
        ld      x\n, (\n*8)(sp)
        .endr
        addi    sp, sp, 256
        mret

        .section .htif, "aw", @progbits
        .align 6
        .globl tohost
tohost: .dword 0
