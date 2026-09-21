        #
        # interrupts and exceptions while in supervisor
        # mode come here.
        #
        # the current stack is a kernel stack.
        # push registers, call kerneltrap().
        # when kerneltrap() returns, restore registers, return.
        #
.globl kerneltrap
.globl kernelvec
.align 4
kernelvec:
        # make room to save registers.
        addi sp, sp, -256

        # save caller-saved registers.
        sd ra, 0(sp)
        # sd sp, 8(sp)
        sd gp, 16(sp)
        # sd tp, 24(sp)
        sd t0, 32(sp)
        sd t1, 40(sp)
        sd t2, 48(sp)
        sd a0, 72(sp)
        sd a1, 80(sp)
        sd a2, 88(sp)
        sd a3, 96(sp)
        sd a4, 104(sp)
        sd a5, 112(sp)
        sd a6, 120(sp)
        sd a7, 128(sp)
        sd t3, 216(sp)
        sd t4, 224(sp)
        sd t5, 232(sp)
        sd t6, 240(sp)

        # call the C trap handler in trap.c
        call kerneltrap

        # restore registers.
        ld ra, 0(sp)
        # ld sp, 8(sp)
        ld gp, 16(sp)
        # not tp (contains hartid), in case we moved CPUs
        ld t0, 32(sp)
        ld t1, 40(sp)
        ld t2, 48(sp)
        ld a0, 72(sp)
        ld a1, 80(sp)
        ld a2, 88(sp)
        ld a3, 96(sp)
        ld a4, 104(sp)
        ld a5, 112(sp)
        ld a6, 120(sp)
        ld a7, 128(sp)
        ld t3, 216(sp)
        ld t4, 224(sp)
        ld t5, 232(sp)
        ld t6, 240(sp)

        addi sp, sp, 256

        # return to whatever we were doing in the kernel.
        sret

        #
        # machine-mode timer interrupt.
        # Rocket port: restored from upstream 92e60dd^ because this core
        # has no Sstc (stimecmp), so timer interrupts must be taken in
        # M-mode here and reflected to supervisor as a software interrupt.
        #
.globl timervec
.align 4
        # This is mtvec, so it catches EVERY machine-mode trap, not just the
        # timer. That matters a great deal on this core.
        #
        # rocket-chip only lets a subset of exceptions be delegated: CSR.scala's
        # delegable_exceptions is {misaligned_fetch, breakpoint, user_ecall,
        # fetch_page_fault, load_page_fault, store_page_fault}, and a write to
        # medeleg is masked with it (`reg_medeleg := wdata & delegable_exceptions`).
        # So start.c's w_medeleg(0xffff) is silently stored as 0xB109, and
        # illegal instruction (2), misaligned load/store (4/6) and the access
        # faults (1/5/7) can NEVER reach S-mode. They always land here.
        #
        # Upstream's timervec assumes every machine trap is the timer. Doing
        # that with an exception rearms the CLINT and mret's straight back to
        # the faulting instruction, which faults again: the core livelocks
        # producing no output whatsoever. So dispatch on mcause, and hand
        # anything that is not the machine timer down to S-mode the way
        # hardware delegation would have.
timervec:
        # start.c has set up the memory that mscratch points to:
        # scratch[0,8,16] : register save area.
        # scratch[24] : address of CLINT's MTIMECMP register.
        # scratch[32] : desired interval between interrupts.
        # scratch[40] : address of CLINT's MTIME register.

        csrrw a0, mscratch, a0
        sd a1, 0(a0)
        sd a2, 8(a0)
        sd a3, 16(a0)

        csrr a1, mcause
        bgez a1, reflect                # MSB clear: an exception, never a timer
        andi a2, a1, 0xff
        li a3, 7                        # machine timer interrupt
        bne a2, a3, reflect

        # Schedule the next timer interrupt.
        #
        # Rocket port: upstream does mtimecmp += interval, i.e. it rearms
        # relative to the OLD compare value. That assumes the handler always
        # runs well within one interval. Here it does not: blkdev_rw() spins
        # with interrupts disabled for the length of a disk transfer, so mtime
        # can run past mtimecmp+interval. The next interrupt is then already
        # due the instant we return, and the core livelocks in the timer
        # handler and never gets back to user space -- which showed up as the
        # shell accepting a command and then hanging forever.
        #
        # Rearm from the CURRENT mtime instead, so a late tick is simply
        # dropped rather than compounding.
        ld a1, 24(a0) # CLINT_MTIMECMP(hart)
        ld a2, 32(a0) # interval
        ld a3, 40(a0) # CLINT_MTIME
        ld a3, 0(a3)  # a3 = current mtime
        add a3, a3, a2
        sd a3, 0(a1)

        # arrange for a supervisor software interrupt
        # after this handler returns.
        li a1, 2
        csrw sip, a1

        ld a3, 16(a0)
        ld a2, 8(a0)
        ld a1, 0(a0)
        csrrw a0, mscratch, a0

        mret

        # Reflect a non-timer machine trap into supervisor mode, mimicking what
        # hardware delegation does: copy mcause/mepc/mtval into their S-mode
        # counterparts, set sstatus.SPP from mstatus.MPP, move SIE into SPIE and
        # clear SIE, then mret to stvec with MPP=S.
        #
        # satp and sscratch are left alone, exactly as a real S-mode trap would
        # leave them, so entering through uservec (user trap) or kernelvec
        # (kernel trap) works unchanged. The result is that xv6 reports the
        # fault -- "usertrap(): unexpected scause 0x2" or a kerneltrap panic --
        # instead of silently spinning forever.
reflect:
        csrw scause, a1                 # a1 still holds mcause
        csrr a1, mepc
        csrw sepc, a1
        csrr a1, mtval
        csrw stval, a1

        csrr a1, mstatus
        srli a2, a1, 11
        andi a2, a2, 1                  # MPP low bit: 0 came from U, 1 from S
        slli a2, a2, 8                  # -> SPP position
        andi a3, a1, 2                  # old SIE (bit 1)
        slli a3, a3, 4                  # -> SPIE position (bit 5)
        andi a1, a1, -291               # clear SPP(8), SPIE(5), SIE(1) = ~0x122
        or a1, a1, a2
        or a1, a1, a3
        li a2, 3
        slli a2, a2, 11
        not a2, a2
        and a1, a1, a2                  # clear MPP
        li a2, 1
        slli a2, a2, 11
        or a1, a1, a2                   # MPP = S, so mret lands in S-mode
        csrw mstatus, a1

        csrr a1, stvec
        andi a1, a1, -4                 # direct mode: drop the mode bits
        csrw mepc, a1

        ld a3, 16(a0)
        ld a2, 8(a0)
        ld a1, 0(a0)
        csrrw a0, mscratch, a0

        mret
