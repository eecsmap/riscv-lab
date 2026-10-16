// Check macros shared by the directed tests (tests/cpu/tests, tests2) and the teaching steps.
//
// Exit protocol: tt_exit (dcrt.S) writes (a0 << 1) | 1 to tohost. a0 = 0 is PASS; any other value is the
// code of the FIRST check that failed, and the testbench prints it, so every check in a test carries a
// unique code and the log names the failing check without a waveform.
//
// Scratch register: CHECK_EQ needs one for its constant and uses gp, which no test uses for anything else.
// (P1 lesson: an earlier version loaded the constant into t6, so CHECK_EQ(t6, ...) compared t6 with itself
// and could not fail.)  Never pass gp as the register under test.
#define PASS                      li a0, 0; j tt_exit
#define FAIL_CODE(code, s)        li a0, code; la s, tt_exit; jr s
#define CHECK_EQ(reg, imm, code)  li gp, imm; beq reg, gp, 9f; FAIL_CODE(code, gp); 9:
#define CHECK_EQ_R(ra, rb, code)  beq ra, rb, 9f; FAIL_CODE(code, gp); 9:
