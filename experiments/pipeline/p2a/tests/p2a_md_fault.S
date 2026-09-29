# PIPE-P2a M: an OLDER instruction traps or serialises while a younger long mul/div is already running in EX.
# The flush must abandon the operation (nothing of it may land anywhere), and the instruction must run again
# after the handler returns and produce the right value exactly once. Case 6: a wrong-path divide behind an MRET must
# never deliver its result to the multiply at the MRET's target (the stale-result negative control fails here). Checks: values, the trap log (cause, epc),
# the trap count. The handler (p1crt.S) resumes an exception at mepc + 4.
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        li      s0, 1000003
        li      s1, 7
        la      s2, fd_data
        # 1. a misaligned load traps in WB while the divide behind it has started
f1:     ld      t1, 1(s2)
        div     a1, s0, s1              # 142857
        # 2. a load access fault (physical address above 32 bits) with a multiply behind it
        li      t2, 1
        slli    t2, t2, 32
f2:     ld      t1, 0(t2)
        mul     a2, s0, s1              # 7000021
        # 3. ECALL with a remainder behind it
f3:     ecall
        remu    a3, s0, s1              # 1000003 % 7 = 4
        # 4. a serialising CSR read (flush and refetch, no trap) with a divide behind it
        csrr    t3, mtval
        divw    a4, s0, s1              # 142857
        # 5. two faults in a row, then a long chain
f5:     lw      t1, 2(s2)
f6:     lh      t1, 1(s2)
        div     a5, s0, s1
        div     a6, a5, s1              # 20408
        # 6. MRET: the divide after it is on the WRONG path. It starts in EX while the MRET drains, and is flushed
        #    when the MRET commits. The multiply at the target has other operands: had the abandoned divide's
        #    quotient reached it, a7 would be 142857, not 5000.
        li      t0, 0x1800
        csrs    mstatus, t0             # MPP = M: the MRET stays in machine mode
        la      t0, mret_tgt
        csrw    mepc, t0
        li      s3, 5
        li      s4, 1000
        .align 3                        # the MRET and the divide share one 8-byte fetch word: both are already
        mret                            # fetched when the front end freezes behind the MRET
        div     a7, s0, s1              # never executed architecturally
        li      a7, 77
        j       mret_tgt
mret_tgt:
        mul     a7, s3, s4
        CHECK_EQ(a7, 5000, 15)
        CHECK_EQ(a1, 142857, 1)
        CHECK_EQ(a2, 7000021, 2)
        CHECK_EQ(a3, 4, 3)
        CHECK_EQ(a4, 142857, 4)
        CHECK_EQ(a6, 20408, 5)
        la      t0, trap_n
        ld      t0, 0(t0)
        CHECK_EQ(t0, 5, 6)
        LOG_ENTRY(0)
        CHECK_EQ(t4, 4, 7)              # load address misaligned
        la      gp, f1
        CHECK_REG(t5, gp, 8)
        LOG_ENTRY(1)
        CHECK_EQ(t4, 5, 9)              # load access fault
        la      gp, f2
        CHECK_REG(t5, gp, 10)
        LOG_ENTRY(2)
        CHECK_EQ(t4, 11, 11)            # ECALL from M
        la      gp, f3
        CHECK_REG(t5, gp, 12)
        LOG_ENTRY(3)
        la      gp, f5
        CHECK_REG(t5, gp, 13)
        LOG_ENTRY(4)
        la      gp, f6
        CHECK_REG(t5, gp, 14)
        li      a0, 0
        ret
        .data
        .align 3
fd_data: .dword 0x1122334455667788
