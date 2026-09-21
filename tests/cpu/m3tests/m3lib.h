// Shared definitions for the M3 bare-metal programs. Self-contained: no library, no runtime.
#define CLINT_MSIP      0x02000000
#define CLINT_MSIP1     0x02000004      // no hart 1 here: the unimplemented hole inside the CLINT window
#define CLINT_MTIMECMP  0x02004000
#define CLINT_MTIME     0x0200bff8
#define MIE_MSIE  (1 << 3)
#define MIE_MTIE  (1 << 7)
#define MSTATUS_MIE (1 << 3)
#define MIP_MSIP  (1 << 3)
#define MIP_MTIP  (1 << 7)

#define FAIL(code, scratch)        \
        sub  a0, scratch, scratch; \
        addi a0, a0, code;         \
        call htif_exit
#define CHECK_EQ(reg, imm, code)   \
        li   a1, imm;              \
        beq  reg, a1, 90f;         \
        FAIL(code, a1);            \
90:
#define CHECK_EQ_R(r1, r2, code)   \
        beq  r1, r2, 91f;          \
        FAIL(code, r1);            \
91:
