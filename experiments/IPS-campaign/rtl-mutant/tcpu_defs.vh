// M2-1: shared encodings for the teaching CPU. Plain Verilog-2001 subset (D1).
`ifndef TCPU_DEFS_VH
`define TCPU_DEFS_VH
// major opcodes actually implemented in M2-1 (RV64I integer / jump / load-store / fence)
`define OP_LOAD    7'b0000011
`define OP_MISCMEM 7'b0001111
`define OP_OPIMM   7'b0010011
`define OP_AUIPC   7'b0010111
`define OP_OPIMM32 7'b0011011
`define OP_STORE   7'b0100011
`define OP_OP      7'b0110011
`define OP_LUI     7'b0110111
`define OP_OP32    7'b0111011
`define OP_BRANCH  7'b1100011
`define OP_JALR    7'b1100111
`define OP_JAL     7'b1101111
`define OP_AMO     7'b0101111   // CPU-A: the A extension's single major opcode
`define OP_SYSTEM  7'b1110011
// trap causes (subset used by M2-1)
`define CAUSE_INSN_MISALIGNED 64'd0
`define CAUSE_INSN_ACCESS     64'd1
`define CAUSE_ILLEGAL         64'd2
`define CAUSE_BREAKPOINT      64'd3
`define CAUSE_ECALL_M         64'd11
`define CAUSE_LOAD_MISALIGNED 64'd4
`define CAUSE_LOAD_ACCESS     64'd5
`define CAUSE_STORE_MISALIGNED 64'd6
`define CAUSE_STORE_ACCESS    64'd7
// CPU-A: LR is a load-class access (4/5/13); SC and the AMOs are store-class (6/7/15)
`endif
