// PIPE-P1 check macros. A failed check exits through tohost with its number (never 0).
#define FAIL(n)            li a0, n; j tt_exit
// gp (x3) is the macro's scratch register: no test uses it, so no check can compare a register with itself
#define CHECK_EQ(r, v, n)  li gp, v; beq r, gp, 1f; FAIL(n); 1:
#define CHECK_REG(r, s, n) beq r, s, 1f; FAIL(n); 1:
// the i-th trap log entry (cause, epc, tval) into t4/t5/t6
#define LOG_ENTRY(i)       la t3, trap_log; ld t4, (24*(i))(t3); ld t5, (24*(i)+8)(t3); ld t6, (24*(i)+16)(t3)
#define MSIP_CAUSE         0x8000000000000003
