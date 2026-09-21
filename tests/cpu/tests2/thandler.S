# Shared M-mode trap handler for the M2-2 tests: it records what the hardware reported, counts the trap and
# resumes at the following instruction. Every faulting instruction in these tests is 4 bytes (.option norvc),
# so the handler advances by a fixed width instead of decoding a length.
        .section .text, "ax", @progbits
        .globl trap_handler
        .align 2
trap_handler:
        csrrw   sp, mscratch, sp        # borrow mscratch as the handler's scratch pointer
        sd      t0, -8(sp)
        sd      t1, -16(sp)
        # Record minstret as early as possible. Exactly three handler instructions have retired by now --
        # the mscratch swap and the two stores above -- which is what lets a test decide, from the counter
        # alone, whether taking the trap itself was wrongly counted as a retirement.
        csrr    t0, minstret
        la      t1, handler_entry_instret
        sd      t0, 0(t1)
        csrr    t0, mcause
        la      t1, last_cause
        sd      t0, 0(t1)
        csrr    t0, mepc
        la      t1, last_epc
        sd      t0, 0(t1)
        csrr    t0, mtval
        la      t1, last_tval
        sd      t0, 0(t1)
        la      t1, trap_count
        ld      t0, 0(t1)
        addi    t0, t0, 1
        sd      t0, 0(t1)
        # An instruction-access fault means mepc points at an address that cannot be fetched, so resuming
        # four bytes later would fault again forever. For that one cause the handler resumes at a recovery
        # address the test supplies; everything else resumes after the faulting instruction.
        csrr    t0, mcause
        li      t1, 1
        beq     t0, t1, 9f
        csrr    t0, mepc
        addi    t0, t0, 4
        csrw    mepc, t0
        j       8f
9:      la      t1, fetch_recover
        ld      t0, 0(t1)
        csrw    mepc, t0
8:
        ld      t0, -8(sp)
        ld      t1, -16(sp)
        csrrw   sp, mscratch, sp
        mret

# install_handler: point mtvec at the handler and give it a scratch area. Clobbers t0.
        .globl install_handler
install_handler:
        la      t0, trap_handler
        csrw    mtvec, t0
        la      t0, handler_stack_top
        csrw    mscratch, t0
        ret

        .section .data, "aw", @progbits
        .align 3
        .globl trap_count, last_cause, last_epc, last_tval
trap_count: .dword 0
last_cause: .dword 0
last_epc:   .dword 0
last_tval:  .dword 0
        .globl fetch_recover
fetch_recover: .dword 0
        .globl handler_entry_instret
handler_entry_instret: .dword 0
        .align 3
        .space 256
        .globl handler_stack_top
handler_stack_top:
        .space 64   # the handler saves below this pointer; the padding keeps it clear of test data
