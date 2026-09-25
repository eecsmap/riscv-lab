// RV64I multi-cycle execution core for the teaching CPU.
//
// Scope after M2-2 (codex-m2-2-csr-traps): RV64I integer / jump / load-store / FENCE, the six Zicsr forms
// over a limited M-mode CSR set, synchronous exceptions with a real handler, and MRET. No M/C/A, no MMU,
// no S/U, no interrupts. Anything unimplemented raises an illegal-instruction exception and may not retire.
// CPU-M/CPU-C added M and C; CPU-SU adds the M/S/U privilege levels at Bare (see tcpu_csr.v).
//
// Physical port: PHYSICAL_PORT_V1 (frozen) -- one outstanding request, payload latched and held until
// the handshake, response no earlier than the cycle after req.fire.
`timescale 1ns/1ps
`include "tcpu_defs.vh"

module tcpu_core #(
  parameter [63:0] RESET_PC      = 64'h0000_0000_8000_0000, // test harness entry; real reset is 0x10040
  parameter        TLB_ENTRIES   = 8,   // IPS-campaign stage 2: 0 disables translation caching entirely
  parameter        ICACHE_BYTES  = 1024,// IPS-campaign stage 3: 0 removes the instruction cache
  parameter        X0_WRITABLE   = 0,   // fault injection: x0 becomes an ordinary register
  parameter        NO_LOAD_SEXT  = 0,   // fault injection: loads stop sign-extending
  parameter        REQ_WITHDRAW  = 0,   // monitor self-test: withdraw a request before its handshake
  parameter        LOAD_WDATA_LEAK = 0, // monitor self-test: let a load carry a write payload
  parameter        STOP_ON_TRAP  = 0,   // test option: halt on the first trap so it can be observed
  parameter        TRAP_BAD_MEPC = 0,   // fault injection: mepc records the instruction after the faulting one
  parameter        TRAP_COUNTS_RET = 0, // fault injection: taking a trap bumps minstret
  parameter        FAULT_W_SEXT    = 0, // CPU-M fault injection: W results zero-extended
  parameter        FAULT_MULH_SIGN = 0, // CPU-M fault injection: signed high half not sign-corrected
  parameter        FAULT_C_IMM     = 0, // CPU-C fault injection: c.addi4spn immediate bits swapped
  parameter        FAULT_C_REG     = 0, // CPU-C fault injection: compact register field mapped to x0..x7
  parameter        ALLOW_RO_WRITE = 0,  // fault injection: a write to a read-only CSR is let through
  parameter        EARLY_IRQ      = 0,  // fault injection: accept an interrupt while a request is committed
  parameter        IRQ_BAD_MEPC   = 0,  // fault injection: mepc records the instruction already executed
  parameter        STALE_MIE      = 0,  // fault injection: decide on enables that have not taken effect yet
  parameter        FAULT_NO_DELEG = 0,  // CPU-SU fault injection: delegation ignored
  parameter        FAULT_S_IRQ_IN_M = 0, // CPU-SU fault injection: S-level interrupt taken in M
  parameter        FAULT_SRET_SPP = 0,  // CPU-SU fault injection: sret leaves SPP
  parameter        FAULT_PTW_NO_PERM = 0, // CPU-SV39 fault injection: leaf permission checks skipped
  parameter        FAULT_IF2_NO_XLATE = 0, // CPU-SV39 fault injection: second parcel fetched at first PA + 2
  parameter        FAULT_PPN_TRUNC = 0, // CPU-SV39 fault injection: a PA above the 32-bit space is truncated
  parameter        MISA_A = 0,          // CPU-A: 1 where the atomic path exists; 0 makes A illegal and misa.A 0
  // ---- CPU-A fault injections: each is one real defect in the A path, used as a negative control
  parameter        FAULT_A_W_NOSEXT   = 0, // an .W atomic's old value is zero-extended instead of sign-extended
  parameter        FAULT_A_SC_RESULT  = 0, // SC always writes 0 to rd -- a failed SC looks like a success
  parameter        FAULT_A_AMO_AS_LOAD = 0, // an AMO is issued as a plain load (amo = 0): wrong classification
  parameter        FAULT_A_EARLY_RETIRE = 0, // an AMO retires before its response arrives
  parameter        FAULT_A_NO_RESV_CLEAR = 0 // a trap does not drop the reservation
) (
  input             clk,
  input             rst,

  // --- PHYSICAL_PORT_V1 ---
  output            req_valid,
  input             req_ready,
  output     [31:0] req_addr,
  output            req_write,
  output     [1:0]  req_size,
  output     [63:0] req_wdata,
  output     [7:0]  req_wmask,
  // CPU-A (PHYSICAL_PORT_V2): the atomic/reservation fields. Ordinary fetches, loads, stores and every
  // page-table read carry amo = 0 and lrsc = 0.
  output     [3:0]  req_amo,          // 0 = not an AMO, else the AmoOp code (SWAP 1 .. MAXU 9)
  output     [1:0]  req_lrsc,         // 0 none, 1 LR, 2 SC (3 is reserved and never issued)
  input             resp_valid,
  output            resp_ready,
  input      [63:0] resp_rdata,
  input             resp_error,
  input             resp_scfail,      // the SC's result, valid with ic_resp_valid
  output            resv_clear,       // one-cycle pulse: a trap was taken (or the core is in reset)

  // --- observation: normal retirement and trap are mutually exclusive, never in the same cycle ---
  output reg        commit_valid,
  output reg [63:0] commit_pc,
  output reg [31:0] commit_insn,      // the original parcel (16-bit, zero-extended) or the 32-bit word
  output reg [2:0]  commit_len,       // CPU-C: 2 or 4
  output reg        commit_rd_valid,
  output reg [4:0]  commit_rd,
  output reg [63:0] commit_rd_data,
  output reg        trap_valid,
  output reg        trap_interrupt,
  output reg [63:0] trap_cause,
  output reg [63:0] trap_epc,
  output reg [63:0] trap_tval,
  output reg        halted,
  // observation only (not part of PHYSICAL_PORT_V1): 1 while the outstanding request is an instruction fetch
  output            dbg_req_is_fetch,
  input      [4:0]  dbg_ra,
  output     [63:0] dbg_rd,
  input      [4:0]  dbg_ra2,
  output     [63:0] dbg_rd2,
  input      [4:0]  dbg_csr_sel,
  output     [63:0] dbg_csr_val,
  output     [1:0]  dbg_priv,        // CPU-SU: the current privilege level
  // --- interrupts: levels in this clock domain, sampled only at an architectural boundary
  input             irq_msip,
  input             irq_mtip,
  input             irq_meip,
  output     [3:0]  dbg_state,
  // observation only: high while a redirecting instruction (taken branch, jump or MRET) is in writeback,
  // so a test can place an interrupt exactly at the boundary that follows one
  output            dbg_redirect,
  output     [63:0] dbg_pc,          // the PC of the instruction currently being executed
  output            dbg_irq_enabled  // MIE and a per-line enable are in effect right now
);
  localparam S_IF_REQ = 4'd0, S_IF_WAIT = 4'd1, S_EXEC = 4'd2,
             S_MEM_REQ = 4'd3, S_MEM_WAIT = 4'd4, S_WB = 4'd5,
             S_TRAP = 4'd6, S_HALT = 4'd7, S_ARCH = 4'd8,
             S_MUL = 4'd9,    // CPU-M: waiting for the multiply/divide unit; no bus traffic, no IRQ
             S_IF2_REQ = 4'd10, S_IF2_WAIT = 4'd11,   // CPU-C: the second halfword of a 32-bit instruction
             S_XLATE = 4'd12;  // CPU-SV39: a page-table walk is in progress (first parcel, second parcel or data)
  // S_ARCH is the architectural boundary, and the two cycles are distinct: S_WB is where the write enables
  // and values are *scheduled*, S_ARCH is where they are high and the values actually *land*, on its closing
  // edge. A test that injects during S_WB is exercising the scheduling window; one that injects during
  // S_ARCH is exercising the landing window; they are separate injection points and neither stands in for
  // the other. Only afterwards -- in S_IF_REQ, before
  // ic_req_valid is raised -- is an interrupt considered, which is what keeps the decision from being made on
  // a stale MIE, mtvec or mepc, and what stops an MRET or an enable-changing CSR write from being followed
  // by one more ordinary instruction.

  reg [3:0]  state;
  reg [63:0] pc, npc;
  reg [31:0] insn;
  // ---- CPU-SV39: the core's own request registers and the walker's, muxed onto the one port ----------
  reg         core_req_valid, core_req_write;
  reg  [31:0] core_req_addr;
  reg  [1:0]  core_req_size;
  reg  [63:0] core_req_wdata;
  reg  [7:0]  core_req_wmask;
  reg  [3:0]  core_req_amo;           // CPU-A
  reg  [1:0]  core_req_lrsc;
  wire        ptw_busy, ptw_done, ptw_fault, ptw_req_valid;
  wire [31:0] ptw_req_addr;
  wire [3:0]  ptw_cause;
  wire [55:0] ptw_pa;
  reg         ptw_start;
  reg  [63:0] ptw_va;
  reg  [1:0]  ptw_type, ptw_priv;
  reg  [1:0]  xl_kind;               // 0 first parcel, 1 second parcel, 2 data
  wire        csr_satp_mode, csr_sum, csr_mxr, csr_mprv;
  wire [43:0] csr_satp_ppn;
  wire [1:0]  csr_mpp;
  // IPS-campaign stage 3. The core's fetch states are unchanged: tcpu_ifill sits between this mux and
  // the module's port, answers a cacheable instruction fetch from a resident line without going out,
  // and passes everything else -- data, the walker's PTE reads, MMIO, writes -- straight through.
  //
  // `ic_is_fetch` excludes the walker deliberately: while ptw_busy the request is a PTE READ, which is
  // data and must never be cached as an instruction.
  wire        ic_req_valid, ic_req_write;
  wire [31:0] ic_req_addr;
  wire [1:0]  ic_req_size;
  wire        ic_req_ready, ic_resp_valid, ic_resp_error;
  wire [63:0] ic_resp_rdata;
  wire        icache_hit, icache_miss;

  assign ic_req_valid = ptw_busy ? ptw_req_valid : core_req_valid;
  assign ic_req_addr  = ptw_busy ? ptw_req_addr  : core_req_addr;
  assign ic_req_write = ptw_busy ? 1'b0          : core_req_write;
  assign ic_req_size  = ptw_busy ? 2'd3          : core_req_size;
  wire        ic_is_fetch = !ptw_busy && ((state == S_IF_REQ) || (state == S_IF_WAIT) ||
                                          (state == S_IF2_REQ) || (state == S_IF2_WAIT) ||
                                          (state == S_XLATE && xl_kind != 2'd2));
  // fence.i invalidates, and so does reset, which the cache does itself
  wire        icache_flush = (state == S_ARCH) && is_fencei;

  tcpu_ifill #(.BYTES(ICACHE_BYTES), .LINE_BYTES(16)) ifill (
    .clk(clk), .rst(rst), .invalidate(icache_flush),
    .c_req_valid(ic_req_valid), .c_req_ready(ic_req_ready), .c_req_addr(ic_req_addr),
    .c_req_size(ic_req_size), .c_req_write(ic_req_write), .c_is_fetch(ic_is_fetch),
    .c_resp_valid(ic_resp_valid), .c_resp_rdata(ic_resp_rdata), .c_resp_error(ic_resp_error),
    .m_req_valid(req_valid), .m_req_ready(req_ready), .m_req_addr(req_addr), .m_req_size(req_size),
    .m_resp_valid(resp_valid), .m_resp_rdata(resp_rdata), .m_resp_error(resp_error),
    .o_hit(icache_hit), .o_miss(icache_miss));
  assign req_write = ic_req_write;
  assign req_wdata = ptw_busy ? 64'd0         : core_req_wdata;
  assign req_wmask = ptw_busy ? 8'd0          : core_req_wmask;
  // a page-table read is an ordinary read: never an atomic, never a reservation
  assign req_amo   = ptw_busy ? 4'd0          : core_req_amo;
  assign req_lrsc  = ptw_busy ? 2'd0          : core_req_lrsc;
  // CPU-A: the reservation is dropped when a trap is taken (S_TRAP is one cycle) and for as long as the
  // core is held in reset -- the R-BOOT soft reset resets the core while the backend keeps running, so the
  // level is what makes a reservation from before the reset impossible to use afterwards. An ordinary
  // fetch or a page-table read never raises it. The core has at most one outstanding request and takes no
  // trap while an LR of its own is in flight, so a clear can never be overtaken by a late LR: asserted.
  assign resv_clear = (FAULT_A_NO_RESV_CLEAR != 0) ? 1'b0 : (rst || (state == S_TRAP));
  // the PA the walk produced, and whether it can exist at all in this SoC's 32-bit physical space
  wire        pa_too_high = (ptw_pa[55:32] != 24'd0) && (FAULT_PPN_TRUNC == 0);

  // decode
  wire [6:0] opcode = insn[6:0];
  wire [4:0] rd     = insn[11:7];
  wire [2:0] funct3 = insn[14:12];
  wire [4:0] rs1    = insn[19:15];
  wire [4:0] rs2    = insn[24:20];
  wire [6:0] funct7 = insn[31:25];
  wire [11:0] csr   = insn[31:20];
  // One definition of "how long is this instruction". It is 4 everywhere today because there is no C
  // extension; every sequential PC advance and every link value is derived from it, so adding compressed
  // instructions later is a change here and in the fetch path, not a hunt through the sequencer.
  // CPU-C: the length is a register set at fetch time -- 2 for a compressed parcel, 4 otherwise -- and every
  // sequential PC advance and every link value is derived from it. `raw_insn` is what was actually fetched
  // (the 16-bit parcel zero-extended, or the 32-bit word); `insn` is what the decode logic sees.
  reg [63:0] insn_len;
  reg [31:0] raw_insn;
  reg [15:0] half_lo;          // the first parcel of a 32-bit instruction, held while the second is fetched
  reg        fetch_wide_req;   // OPT01: this fetch request authorised four bytes, so four may be used
  reg [63:0] pc2;              // the second parcel's own address, kept for the exception report
  wire [15:0] fetched_half = pc[2] ? (pc[1] ? ic_resp_rdata[63:48] : ic_resp_rdata[47:32])
                                   : (pc[1] ? ic_resp_rdata[31:16] : ic_resp_rdata[15:0]);
  wire [15:0] fetched_half2 = pc2[2] ? (pc2[1] ? ic_resp_rdata[63:48] : ic_resp_rdata[47:32])
                                     : (pc2[1] ? ic_resp_rdata[31:16] : ic_resp_rdata[15:0]);
  wire        fetched_is_c = (fetched_half[1:0] != 2'b11);
  // OPT01: when pc is 4-byte aligned the whole 32-bit instruction lies inside ONE response. The response
  // bus is 64 bits wide and always was; the core simply never used more than 16 bits of it. pc[1]==0 puts
  // both halves in the same aligned word, selected by pc[2] exactly as fetched_half is.
  wire        pc_word_aligned = (pc[1] == 1'b0);
  //: The wide form may be consumed ONLY when the request that produced this response actually asked for
  //: four bytes. `fetch_wide_req` is latched at the moment of issue rather than read back from
  //: core_req_size, because the walker's own PTE reads drive that field during a translation -- so
  //: reading it back would be asking a signal somebody else has since written. This flag is the
  //: difference between reading what was asked for and reading what the bus happened to return.
  wire [31:0] fetched_word = pc[2] ? ic_resp_rdata[63:32] : ic_resp_rdata[31:0];
  wire [31:0] c_insn; wire c_illegal, c_hint;
  tcpu_cdecode #(.FAULT_C_IMM(FAULT_C_IMM), .FAULT_C_REG(FAULT_C_REG)) cdec (
    .c(fetched_half), .insn(c_insn), .illegal(c_illegal), .hint(c_hint));
  reg c_bad;                   // the parcel was a reserved / FP / custom compressed encoding

  wire [63:0] imm_i = {{52{insn[31]}}, insn[31:20]};
  wire [63:0] imm_s = {{52{insn[31]}}, insn[31:25], insn[11:7]};
  wire [63:0] imm_b = {{51{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};
  wire [63:0] imm_u = {{32{insn[31]}}, insn[31:12], 12'b0};
  wire [63:0] imm_j = {{43{insn[31]}}, insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};

  wire [63:0] rs1_val, rs2_val;
  reg         rf_we;
  reg [4:0]   rf_wa;
  reg [63:0]  rf_wd;
  tcpu_regfile #(.X0_WRITABLE(X0_WRITABLE)) rf (
    .clk(clk), .ra1(rs1), .ra2(rs2), .rd1(rs1_val), .rd2(rs2_val),
    .we(rf_we), .wa(rf_wa), .wd(rf_wd), .dbg_ra(dbg_ra), .dbg_rd(dbg_rd), .dbg_ra2(dbg_ra2), .dbg_rd2(dbg_rd2));

  // ---- ALU -------------------------------------------------------------
  wire [63:0] op_b   = (opcode == `OP_OP || opcode == `OP_OP32) ? rs2_val :
                       (opcode == `OP_OPIMM32) ? imm_i : imm_i;
  wire [5:0]  shamt6 = (opcode == `OP_OP || opcode == `OP_OP32) ? rs2_val[5:0] : insn[25:20];
  wire [4:0]  shamt5 = (opcode == `OP_OP32) ? rs2_val[4:0] : insn[24:20];
  wire        alt    = funct7[5];   // sub / sra selector
  wire [63:0] sum    = rs1_val + op_b;
  wire [63:0] diff   = rs1_val - rs2_val;
  wire        lt_s   = ($signed(rs1_val) < $signed(op_b));
  wire        lt_u   = (rs1_val < op_b);
  wire [63:0] sll64  = rs1_val << shamt6;
  wire [63:0] srl64  = rs1_val >> shamt6;
  wire [63:0] sra64  = $signed(rs1_val) >>> shamt6;
  wire [31:0] w_a    = rs1_val[31:0];
  wire [31:0] w_b    = op_b[31:0];
  wire [31:0] w_sum  = w_a + w_b;
  wire [31:0] w_diff = w_a - rs2_val[31:0];
  wire [31:0] w_sll  = w_a << shamt5;
  wire [31:0] w_srl  = w_a >> shamt5;
  wire [31:0] w_sra  = $signed(w_a) >>> shamt5;

  reg [63:0] alu_out;
  reg        alu_illegal;
  always @(*) begin
    alu_out = 64'd0; alu_illegal = 1'b0;
    case (opcode)
      `OP_OPIMM, `OP_OP: case (funct3)
        3'b000: alu_out = (opcode == `OP_OP && alt) ? diff : sum;
        3'b001: alu_out = sll64;
        3'b010: alu_out = {63'd0, lt_s};
        3'b011: alu_out = {63'd0, lt_u};
        3'b100: alu_out = rs1_val ^ op_b;
        3'b101: alu_out = alt ? sra64 : srl64;
        3'b110: alu_out = rs1_val | op_b;
        3'b111: alu_out = rs1_val & op_b;
      endcase
      `OP_OPIMM32, `OP_OP32: case (funct3)
        3'b000: alu_out = {{32{(opcode == `OP_OP32 && alt) ? w_diff[31] : w_sum[31]}},
                           (opcode == `OP_OP32 && alt) ? w_diff : w_sum};
        3'b001: alu_out = {{32{w_sll[31]}}, w_sll};
        3'b101: alu_out = alt ? {{32{w_sra[31]}}, w_sra} : {{32{w_srl[31]}}, w_srl};
        default: alu_illegal = 1'b1;
      endcase
      default: ;
    endcase
  end

  // ---- legality --------------------------------------------------------
  // ---- CPU-A: the A extension -------------------------------------------------------------------------
  // One major opcode. funct3 gives the width (.W 010, .D 011); funct5 = insn[31:27] gives the operation;
  // aq/rl are accepted in all four combinations and have no further effect in this core (one in-order
  // outstanding request, no cache -- there is nothing to reorder).
  wire        is_amo_op = (opcode == `OP_AMO);
  wire [4:0]  a_funct5  = insn[31:27];
  wire        a_w       = (funct3 == 3'b010);
  wire        a_d       = (funct3 == 3'b011);
  wire        a_width_ok = is_amo_op && (a_w || a_d);
  wire        is_lr     = is_amo_op && (a_funct5 == 5'b00010);
  wire        is_sc     = is_amo_op && (a_funct5 == 5'b00011);
  reg  [3:0]  amo_code;                                  // the AmoOp code the V2 port carries; 0 = not an AMO
  always @(*) case (a_funct5)
    5'b00001: amo_code = 4'd1;   // AMOSWAP
    5'b00000: amo_code = 4'd2;   // AMOADD
    5'b00100: amo_code = 4'd3;   // AMOXOR
    5'b01100: amo_code = 4'd4;   // AMOAND
    5'b01000: amo_code = 4'd5;   // AMOOR
    5'b10000: amo_code = 4'd6;   // AMOMIN
    5'b10100: amo_code = 4'd7;   // AMOMAX
    5'b11000: amo_code = 4'd8;   // AMOMINU
    5'b11100: amo_code = 4'd9;   // AMOMAXU
    default:  amo_code = 4'd0;
  endcase
  wire        is_amo    = is_amo_op && (amo_code != 4'd0);            // an arithmetic/logical AMO
  // LR's rs2 field is reserved and must be zero; every other funct5 is unknown
  // Legal only where this configuration has an atomic path. With MISA_A = 0 an A instruction is an unknown
  // opcode -- illegal, nothing on the bus -- which is what misa.A = 0 has to mean.
  wire        a_legal   = (MISA_A != 0) && a_width_ok && (is_amo || is_sc || (is_lr && (rs2 == 5'd0)));
  wire        is_amo_mem = is_lr || is_sc || is_amo;                  // reaches memory as one V2 request
  wire        is_load   = (opcode == `OP_LOAD);
  wire is_store  = (opcode == `OP_STORE);
  wire is_branch = (opcode == `OP_BRANCH);
  wire is_jal    = (opcode == `OP_JAL);
  // JALR is only defined for funct3 = 000. Any other funct3 is not an RV64I instruction and must trap:
  // leaving it out of `known_op` is what makes `illegal` fire (Codex review, blocking item 1).
  wire is_jalr   = (opcode == `OP_JALR) && (funct3 == 3'b000);
  wire is_lui    = (opcode == `OP_LUI);
  wire is_auipc  = (opcode == `OP_AUIPC);
  wire is_fence  = (opcode == `OP_MISCMEM) && (funct3 == 3'b000);
  // Zifencei. FENCE.I orders this hart's stores against its own later instruction fetches. This core has
  // no instruction cache, no store buffer and one in-order outstanding access: a store's response is taken
  // before the next fetch is issued, and nothing is prefetched, so the ordering it asks for already holds
  // and the instruction has no further work to do. It is therefore legal, retires exactly once, and writes
  // no register. Its rd/rs1/imm fields are reserved for future use and are ignored here, as the ISA says.
  // Only funct3 = 001 is added: every other MISC-MEM encoding stays illegal.
  wire is_fencei = (opcode == `OP_MISCMEM) && (funct3 == 3'b001);
  // ---- Zicsr ------------------------------------------------------------
  // Write intent is decided by the *encoding*, not by the value: CSRRS/CSRRC with rs1 = x0 do not write,
  // but rs1 = x5 holding zero still does. Read intent matters only for CSRRW[I], which skips the read when
  // rd = x0. Address, permission and write intent are all settled before any side effect happens.
  wire is_system   = (opcode == `OP_SYSTEM);
  wire is_csr      = is_system && (funct3 != 3'b000);
  wire csr_is_imm  = funct3[2];
  wire [63:0] csr_uimm = {59'd0, rs1};
  wire csr_form_ok = (funct3[1:0] != 2'b00);                 // 01 = RW, 10 = RS, 11 = RC
  // For both the register and the immediate forms the source sits in the rs1 field, so "the encoded source
  // is non-zero" is the same test: a register *number* of zero means no write, a register holding zero does not.
  wire csr_write_intent = is_csr && ((funct3[1:0] == 2'b01) || (rs1 != 5'd0));
  wire csr_read_intent  = is_csr && ((funct3[1:0] == 2'b01) ? (rd != 5'd0) : 1'b1);
  wire csr_addr_illegal;
  wire [63:0] csr_rdata, csr_mtvec, csr_mepc;
  wire [63:0] csr_src = csr_is_imm ? csr_uimm : rs1_val;
  wire [63:0] csr_wdata = (funct3[1:0] == 2'b01) ? csr_src :
                          (funct3[1:0] == 2'b10) ? (csr_rdata |  csr_src) :
                                                   (csr_rdata & ~csr_src);
  // SYSTEM with funct3 = 000: only these three encodings exist here, every other one is illegal.
  wire is_ecall  = is_system && (insn == 32'h00000073);
  wire is_ebreak = is_system && (insn == 32'h00100073);
  wire is_mret   = is_system && (insn == 32'h30200073);
  // CPU-SU: SRET, and SFENCE.VMA (funct7 0001001, rd = 0, any rs1/rs2) which at Bare is a legal no-op
  wire is_sret   = is_system && (insn == 32'h10200073);
  wire is_sfence = is_system && (funct3 == 3'b000) && (funct7 == 7'b0001001) && (rd == 5'd0);
  wire [1:0] priv;
  // privilege of the instruction itself: mret needs M; sret needs S (TSR = 0) -- illegal in U; sfence.vma
  // is illegal in U (TVM = 0 keeps it legal in S). wfi is legal at every level (TW = 0, bounded time 0).
  wire priv_illegal = (is_mret && priv != 2'd3) || (is_sret && priv == 2'd0) || (is_sfence && priv == 2'd0);
  // WFI is implemented as a legal no-op that retires once: the clock keeps running and nothing waits.
  // This is not a low-power implementation, and it must not make an interrupt acceptable on its own.
  wire is_wfi    = is_system && (insn == 32'h10500073);
  wire shift_imm_ok = !((opcode == `OP_OPIMM) && (funct3 == 3'b001 || funct3 == 3'b101) && (insn[31:26] != 6'b000000) && !(funct3 == 3'b101 && insn[31:26] == 6'b010000));
  // CPU-M: MUL..REMU (OP, all eight funct3) and MULW/DIVW/DIVUW/REMW/REMUW (OP-32, funct3 000,100..111)
  wire is_muldiv    = (funct7 == 7'b0000001) &&
                      ((opcode == `OP_OP) || (opcode == `OP_OP32 && (funct3 == 3'b000 || funct3[2])));
  wire op_funct7_ok = !(opcode == `OP_OP) || (funct7 == 7'b0000000) || is_muldiv ||
                      (funct7 == 7'b0100000 && (funct3 == 3'b000 || funct3 == 3'b101));
  wire op32_ok      = !(opcode == `OP_OP32) || is_muldiv ||
                      ((funct7 == 7'b0000000 && (funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b101)) ||
                       (funct7 == 7'b0100000 && (funct3 == 3'b000 || funct3 == 3'b101)));
  wire load_f3_ok   = !is_load  || (funct3 != 3'b111);
  wire store_f3_ok  = !is_store || (funct3 <= 3'b011);
  wire branch_f3_ok = !is_branch || (funct3 != 3'b010 && funct3 != 3'b011);
  wire opimm32_ok   = !(opcode == `OP_OPIMM32) || (funct3 == 3'b000 ||
                        (funct3 == 3'b001 && insn[31:25] == 7'b0000000) ||
                        (funct3 == 3'b101 && (insn[31:25] == 7'b0000000 || insn[31:25] == 7'b0100000)));
  wire known_op = a_legal | is_load | is_store | is_branch | is_jal | is_jalr | is_lui | is_auipc | is_fence | is_fencei |
                  (is_csr && csr_form_ok) | is_ecall | is_ebreak | is_mret | is_sret | is_sfence | is_wfi |
                  (opcode == `OP_OPIMM) | (opcode == `OP_OP) |
                  (opcode == `OP_OPIMM32) | (opcode == `OP_OP32);
  // An illegal encoding is decided before anything derived from it: a bad CSR address or a write aimed at a
  // read-only CSR is an illegal instruction, and it is settled here, not after a side effect.
  wire illegal = c_bad || !known_op || (alu_illegal && !is_muldiv) || !shift_imm_ok || !op_funct7_ok || !op32_ok ||
                 !load_f3_ok || !store_f3_ok || !branch_f3_ok || !opimm32_ok || csr_addr_illegal || priv_illegal;

  // ---- branch / jump ---------------------------------------------------
  reg branch_taken;
  always @(*) begin
    branch_taken = 1'b0;
    if (is_branch) case (funct3)
      3'b000: branch_taken = (rs1_val == rs2_val);
      3'b001: branch_taken = (rs1_val != rs2_val);
      3'b100: branch_taken = ($signed(rs1_val) <  $signed(rs2_val));
      3'b101: branch_taken = ($signed(rs1_val) >= $signed(rs2_val));
      3'b110: branch_taken = (rs1_val <  rs2_val);
      3'b111: branch_taken = (rs1_val >= rs2_val);
      default: branch_taken = 1'b0;
    endcase
  end
  wire [63:0] br_target   = pc + imm_b;
  wire [63:0] jal_target  = pc + imm_j;
  wire [63:0] jalr_target = (rs1_val + imm_i) & ~64'd1;
  wire [63:0] jump_target = is_jal ? jal_target : jalr_target;
  // Alignment is only checked for a target that is actually taken (Codex correction): an untaken branch
  // with a badly aligned target must not trap.
  // with C, IALIGN is 16: only bit 0 matters (and JAL/branch immediates are even, JALR clears bit 0)
  wire target_misaligned = (is_jal | is_jalr) ? jump_target[0] :
                           (is_branch && branch_taken) ? br_target[0] : 1'b0;
  wire [63:0] target_for_check = (is_jal | is_jalr) ? jump_target : br_target;

  // ---- address / physical-address range --------------------------------
  wire pc2_pa_bad;
  // CPU-A: an atomic addresses rs1 directly -- there is no immediate in the encoding
  wire [63:0] mem_vaddr = is_amo_mem ? rs1_val : (is_store ? (rs1_val + imm_s) : (rs1_val + imm_i));
  // the access class that names the trap causes: LR is a load (4/5/13), SC and the AMOs are stores (6/7/15)
  wire        mem_write_class = is_store || is_sc || is_amo;
  wire        mem_any = is_load || is_store || is_amo_mem;
  wire mem_pa_bad = (mem_vaddr[63:32] != 32'd0);          // no truncation into a 32-bit PA
  wire pc_pa_bad  = (pc[63:32] != 32'd0);
  // the second parcel's address is a 64-bit sum held in its own register, so an instruction at the top of
  // the physical range cannot wrap round and fetch its second half from a low address
  assign pc2_pa_bad = (pc2[63:32] != 32'd0);
  reg mem_misaligned;
  always @(*) case (funct3[1:0])
    2'b00: mem_misaligned = 1'b0;
    2'b01: mem_misaligned = mem_vaddr[0];
    2'b10: mem_misaligned = |mem_vaddr[1:0];
    2'b11: mem_misaligned = |mem_vaddr[2:0];
  endcase
  wire [7:0] store_mask_base = (funct3[1:0] == 2'b00) ? 8'h01 :
                               (funct3[1:0] == 2'b01) ? 8'h03 :
                               (funct3[1:0] == 2'b10) ? 8'h0f : 8'hff;

  // ---- load extension --------------------------------------------------
  wire [5:0]  lshift   = {mem_vaddr[2:0], 3'b000};
  wire [63:0] ld_shift = ic_resp_rdata >> lshift;
  // CPU-A: the old value comes back on the address's byte lanes. .W returns the 32-bit word
  // sign-extended -- including AMOMINU/AMOMAXU, where only the *comparison* is unsigned.
  wire [63:0] amo_old  = a_w ? {{32{(FAULT_A_W_NOSEXT != 0) ? 1'b0 : ld_shift[31]}}, ld_shift[31:0]} : ic_resp_rdata;
  reg  [63:0] load_data;
  always @(*) begin
    case (funct3)
      3'b000: load_data = NO_LOAD_SEXT ? {56'd0, ld_shift[7:0]}  : {{56{ld_shift[7]}},  ld_shift[7:0]};
      3'b001: load_data = NO_LOAD_SEXT ? {48'd0, ld_shift[15:0]} : {{48{ld_shift[15]}}, ld_shift[15:0]};
      3'b010: load_data = NO_LOAD_SEXT ? {32'd0, ld_shift[31:0]} : {{32{ld_shift[31]}}, ld_shift[31:0]};
      3'b011: load_data = ld_shift;
      3'b100: load_data = {56'd0, ld_shift[7:0]};
      3'b101: load_data = {48'd0, ld_shift[15:0]};
      3'b110: load_data = {32'd0, ld_shift[31:0]};
      default: load_data = 64'd0;
    endcase
  end

  assign resp_ready = 1'b1;   // single outstanding: the consumer can always take the response
  reg withdrawn;
  assign dbg_req_is_fetch = (state == S_IF_REQ) || (state == S_IF_WAIT) ||
                            (state == S_IF2_REQ) || (state == S_IF2_WAIT) ||   // CPU-C: either parcel
                            (state == S_XLATE && xl_kind != 2'd2 && !ptw_busy);   // CPU-SV39: the fetch after a walk (PTE reads are data)
  assign dbg_state = state;
  assign dbg_redirect = (state == S_WB) && (npc != pc + insn_len);
  assign dbg_pc = pc;

  // Interrupts are only ever sampled at the architectural boundary. EARLY_IRQ breaks exactly that rule by
  // also allowing acceptance while a request this instruction has already committed to is outstanding;
  // STALE_MIE moves the decision one cycle earlier, into S_ARCH, where the enables have not landed yet.
  wire irq_take = csr_irq_pending &&
                  ((state == S_IF_REQ) ||
                   (STALE_MIE != 0 && state == S_ARCH) ||
                   (EARLY_IRQ  != 0 && state == S_MEM_WAIT));
  wire csr_irq_pending, csr_irq_enabled;
  wire [63:0] csr_irq_cause;
  assign dbg_irq_enabled = csr_irq_enabled;

  // ---- CSR file ---------------------------------------------------------
  // The access happens in S_WB, the same cycle the instruction retires, so read-modify-write is atomic and
  // a software write to a counter wins over that cycle's automatic increment.
  // csr_wdata_r holds the value computed from the csr_rdata sampled in S_WB, so the CSR write and the
  // destination-register write use the same read and land on the same edge: the access is atomic even
  // though mcycle is ticking underneath it.
  reg csr_we_r, trap_enter, mret_go, sret_go, retire_now;
  reg [63:0] csr_wdata_r;
  wire [63:0] csr_sepc, csr_trap_vector;
  assign dbg_priv = priv;
  // CPU-SV39: when is an access translated. Fetch: the current level, never M. Data: the effective level
  // (MPRV selects MPP), never M. Bare mode: never.
  wire [1:0] eff_priv_data = csr_mprv ? csr_mpp : priv;
  wire xlate_fetch = csr_satp_mode && (priv != 2'd3);
  wire xlate_data  = csr_satp_mode && (eff_priv_data != 2'd3);

  // IPS-campaign stage 2 -- the TLB's invalidation, deliberately more than the architecture requires.
  //
  // Any sfence.vma, whatever its rs1/rs2, flushes everything; so does any CHANGE of satp. satp's value
  // is watched rather than its write strobe because the CSR file owns the write and ASIDLEN is 0 here,
  // so a write that changes nothing changes no mapping -- and a write that changes the root is exactly
  // what must flush. An sfence that traps also flushes, which is over-flushing, which is the safe
  // direction: the failure mode of over-flushing is a slower machine and of under-flushing a wrong one.
  // EVERY write to satp, not only one that changes it. The first version watched the VALUE, so a
  // same-value write did not flush -- which is not an ISA violation on its own, since sfence.vma is
  // still required, but it is not what STAGE2-DESIGN.md promised and a design document that does not
  // describe the RTL is worse than no document. csr_we_r is the actual write enable the CSR file acts
  // on, so this covers same-value writes and excludes a CSRRS/CSRRC with rs1=x0, which performs no
  // write at all.
  wire        satp_write = csr_we_r && (csr == 12'h180);
  wire        tlb_flush  = satp_write || ((state == S_ARCH) && is_sfence);

  wire xlate_hit, xlate_miss;      // observation only; nothing architectural reads these
  tcpu_xlate #(.TLB_ENTRIES(TLB_ENTRIES), .FAULT_PTW_NO_PERM(FAULT_PTW_NO_PERM)) ptw (
    .clk(clk), .rst(rst), .flush(tlb_flush),
    .start(ptw_start), .va(ptw_va), .acc_type(ptw_type), .eff_priv(ptw_priv),
    .sum(csr_sum), .mxr(csr_mxr), .root_ppn(csr_satp_ppn),
    .req_valid(ptw_req_valid), .req_ready(ic_req_ready), .req_addr(ptw_req_addr),
    .resp_valid(ic_resp_valid), .resp_rdata(ic_resp_rdata), .resp_error(ic_resp_error),
    .busy(ptw_busy), .done(ptw_done), .fault(ptw_fault), .cause(ptw_cause), .pa(ptw_pa),
    .o_hit(xlate_hit), .o_miss(xlate_miss));
  tcpu_csr #(.MISA_A(MISA_A), .TRAP_BAD_MEPC(TRAP_BAD_MEPC), .TRAP_COUNTS_RET(TRAP_COUNTS_RET),
             .ALLOW_RO_WRITE(ALLOW_RO_WRITE), .FAULT_NO_DELEG(FAULT_NO_DELEG),
             .FAULT_S_IRQ_IN_M(FAULT_S_IRQ_IN_M), .FAULT_SRET_SPP(FAULT_SRET_SPP)) csrfile (
    .clk(clk), .rst(rst),
    .addr(csr), .access(is_csr), .write_intent(csr_write_intent), .read_intent(csr_read_intent),
    .addr_illegal(csr_addr_illegal), .rdata(csr_rdata), .we(csr_we_r), .wdata(csr_wdata_r),
    .retire(retire_now),
    .trap(trap_enter), .trap_cause(trap_cause), .trap_epc(trap_epc), .trap_tval(trap_tval),
    .mret(mret_go), .sret(sret_go), .mtvec_base(csr_mtvec), .mepc_out(csr_mepc), .sepc_out(csr_sepc),
    .trap_vector(csr_trap_vector), .priv(priv),
    .satp_mode(csr_satp_mode), .satp_ppn(csr_satp_ppn), .st_sum_o(csr_sum), .st_mxr_o(csr_mxr), .st_mprv_o(csr_mprv), .st_mpp_o(csr_mpp),
    .irq_msip(irq_msip), .irq_mtip(irq_mtip), .irq_meip(irq_meip),
    .irq_enabled(csr_irq_enabled), .irq_pending(csr_irq_pending), .irq_cause(csr_irq_cause),
    .dbg_sel(dbg_csr_sel), .dbg_val(dbg_csr_val));

  // ---- CPU-M: the multiply/divide unit. Started from S_EXEC with a one-cycle pulse; the core sits in
  // S_MUL until `done`, then retires through the ordinary S_WB path. The unit's own contract is in
  // tcpu_muldiv.v; the core adds: operands are the register values of the cycle the pulse is raised, and
  // the pulse is raised exactly once per instruction.
  // unit opcode: OP uses funct3 directly (MUL..REMU = 0..7); OP-32 maps 000->MULW(8), 100..111->DIVW,
  // DIVUW, REMW, REMUW (9..12)
  reg [3:0] md_op;
  always @(*) begin
    if (opcode == `OP_OP32) case (funct3)
      3'b000:  md_op = 4'd8;
      3'b100:  md_op = 4'd9;
      3'b101:  md_op = 4'd10;
      3'b110:  md_op = 4'd11;
      default: md_op = 4'd12;
    endcase
    else md_op = {1'b0, funct3};
  end
  reg        md_start;
  wire       md_busy, md_done;
  wire [63:0] md_result;
  tcpu_muldiv #(.FAULT_W_SEXT(FAULT_W_SEXT), .FAULT_MULH_SIGN(FAULT_MULH_SIGN)) muldiv (
    .clk(clk), .rst(rst), .start(md_start), .op(md_op), .a(rs1_val), .b(rs2_val),
    .busy(md_busy), .done(md_done), .result(md_result));

  // ---- sequencing ------------------------------------------------------
  reg [63:0] wb_value;
  reg        wb_we;
  reg        wb_is_csr;      // the destination value is the CSR read performed in S_WB itself
  reg [4:0]  wb_rd;
  reg [63:0] trap_cause_n, trap_tval_n;
  reg        take_trap;

  always @(posedge clk) begin
    commit_valid <= 1'b0; trap_valid <= 1'b0; rf_we <= 1'b0;
    csr_we_r <= 1'b0; retire_now <= 1'b0; trap_enter <= 1'b0; mret_go <= 1'b0; sret_go <= 1'b0;
    md_start <= 1'b0; ptw_start <= 1'b0;
    // a synchronous exception is the default; the interrupt path sets this back to 1
    if (!rst && state != S_TRAP) trap_interrupt <= 1'b0;
    if (rst) begin
      state <= S_IF_REQ; pc <= RESET_PC; npc <= RESET_PC;
      wb_is_csr <= 1'b0;
      core_req_valid <= 1'b0; core_req_write <= 1'b0; core_req_addr <= 32'd0; core_req_size <= 2'd0; core_req_wdata <= 64'd0; core_req_amo <= 4'd0; core_req_lrsc <= 2'd0; core_req_wmask <= 8'd0; core_req_amo <= 4'd0; core_req_lrsc <= 2'd0;
      halted <= 1'b0; withdrawn <= 1'b0; xl_kind <= 2'd0; ptw_va <= 64'd0; ptw_type <= 2'd0; ptw_priv <= 2'd0;
      commit_rd_valid <= 1'b0; commit_rd <= 5'd0; commit_rd_data <= 64'd0;
      commit_pc <= 64'd0; commit_insn <= 32'd0; commit_len <= 3'd0;
      insn_len <= 64'd4; raw_insn <= 32'd0; half_lo <= 16'd0; pc2 <= 64'd0; c_bad <= 1'b0;
      fetch_wide_req <= 1'b0;
      trap_cause <= 64'd0; trap_epc <= 64'd0; trap_tval <= 64'd0;
    end else begin
      case (state)
        // ---- fetch: one naturally aligned 32-bit read from the test RAM (M2-1 scope: no C, no MMU)
        S_IF_REQ: begin
          // The only point at which an interrupt is accepted. Nothing is in flight here: the previous
          // instruction's architectural updates landed at the end of S_ARCH, and ic_req_valid has not been
          // raised yet, so nothing has to be cancelled or replayed. mepc is simply pc -- the address of the
          // instruction that has not run -- which already includes the effect of a preceding jump or MRET.
          if (irq_take) begin
            trap_cause     <= IRQ_BAD_MEPC ? csr_irq_cause : csr_irq_cause;
            trap_tval      <= 64'd0;
            trap_epc       <= IRQ_BAD_MEPC ? (pc - insn_len) : pc;
            trap_interrupt <= 1'b1;
            state          <= S_TRAP;
          end else if (pc[0]) begin
            trap_cause <= `CAUSE_INSN_MISALIGNED; trap_tval <= pc; trap_epc <= pc; state <= S_TRAP;
          end else if (xlate_fetch) begin
            // CPU-SV39: translate the first parcel's page before anything is asked of the bus
            ptw_start <= 1'b1; ptw_va <= pc; ptw_type <= 2'd0; ptw_priv <= priv; xl_kind <= 2'd0; state <= S_XLATE;
          end else if (pc_pa_bad) begin
            trap_cause <= `CAUSE_INSN_ACCESS; trap_tval <= pc; trap_epc <= pc; state <= S_TRAP;
          end else begin
            // OPT01: four bytes when the PC is 4-byte aligned, one parcel otherwise. perf05 measured that
            // size does not affect the cost of an access within a 64-bit beat (a 1-byte and an 8-byte
            // load differ by 0.2%), so the wider request is free and the saving is the request it removes.
            core_req_valid <= 1'b1; core_req_addr <= pc[31:0]; core_req_write <= 1'b0;
            core_req_size <= pc_word_aligned ? 2'd2 : 2'd1;
            fetch_wide_req <= pc_word_aligned;
            core_req_wdata <= 64'd0; core_req_wmask <= 8'd0; core_req_amo <= 4'd0; core_req_lrsc <= 2'd0; state <= S_IF_WAIT;
          end
        end
        S_IF_WAIT: begin
          if (core_req_valid && ic_req_ready) core_req_valid <= 1'b0;     // payload held until the handshake
          else if (REQ_WITHDRAW != 0 && core_req_valid && !ic_req_ready && !withdrawn) begin
            core_req_valid <= 1'b0; withdrawn <= 1'b1;             // deliberate violation, monitor self-test only
          end else if (REQ_WITHDRAW != 0 && withdrawn && !core_req_valid) core_req_valid <= 1'b1;
          if (ic_resp_valid) begin
            if (ic_resp_error) begin
              trap_cause <= `CAUSE_INSN_ACCESS; trap_tval <= pc; trap_epc <= pc; state <= S_TRAP;
            end else if (fetched_is_c) begin
              // a compressed parcel: expanded here, the original kept for the commit / exception record
              insn <= c_insn; raw_insn <= {16'd0, fetched_half}; insn_len <= 64'd2; c_bad <= c_illegal;
              state <= S_EXEC;
            end else if (fetch_wide_req) begin
              // OPT01: a 32-bit instruction that is 4-byte aligned. Both halves arrived together, so
              // S_IF2_REQ/S_IF2_WAIT are never entered and the instruction costs ONE round-trip.
              //
              // This is also why the second translation disappears under Sv39: a naturally aligned
              // 4-byte access cannot cross a 4 KiB page, so the single translation already covers the
              // whole instruction. The independent second walk exists for the unaligned case below,
              // which is untouched.
              insn <= fetched_word; raw_insn <= fetched_word; insn_len <= 64'd4; c_bad <= 1'b0;
              state <= S_EXEC;
            end else begin
              // a 32-bit instruction at a 2-byte-aligned PC: it may straddle a page, so the second parcel
              // is still fetched and translated on its own. Unchanged.
              half_lo <= fetched_half; pc2 <= pc + 64'd2; c_bad <= 1'b0;
              state <= S_IF2_REQ;
            end
          end
        end
        // ---- CPU-C: the second parcel. Its address is pc + 2, held separately; a failure here belongs to
        // the instruction at pc (mepc = pc) and names the address that actually failed (mtval = pc + 2).
        // No interrupt is sampled here: the instruction is half fetched, and the request is never withdrawn.
        S_IF2_REQ: begin
          if (xlate_fetch && FAULT_IF2_NO_XLATE == 0) begin
            // CPU-SV39: the second parcel's page is translated on its own; it may map anywhere
            ptw_start <= 1'b1; ptw_va <= pc2; ptw_type <= 2'd0; ptw_priv <= priv; xl_kind <= 2'd1; state <= S_XLATE;
          end else if (xlate_fetch) begin
            // fault injection: reuse the first parcel's physical address + 2 (wrong across a page boundary)
            core_req_valid <= 1'b1; core_req_addr <= core_req_addr + 32'd2; core_req_write <= 1'b0; core_req_size <= 2'd1;
            core_req_wdata <= 64'd0; core_req_wmask <= 8'd0; core_req_amo <= 4'd0; core_req_lrsc <= 2'd0; state <= S_IF2_WAIT;
          end else if (pc2_pa_bad) begin
            trap_cause <= `CAUSE_INSN_ACCESS; trap_tval <= pc2; trap_epc <= pc; state <= S_TRAP;
          end else begin
            core_req_valid <= 1'b1; core_req_addr <= pc2[31:0]; core_req_write <= 1'b0; core_req_size <= 2'd1;
            core_req_wdata <= 64'd0; core_req_wmask <= 8'd0; core_req_amo <= 4'd0; core_req_lrsc <= 2'd0;
            fetch_wide_req <= 1'b0; state <= S_IF2_WAIT;
          end
        end
        // ---- CPU-SV39: a walk in progress. The walker owns the port; nothing else happens, no interrupt is
        // looked at. On completion a fault is reported against the instruction (epc = pc, tval = the VA
        // that was being translated), or the access is issued at the physical address.
        S_XLATE: begin
          if (ptw_done) begin
            if (ptw_fault) begin
              trap_cause <= {60'd0, ptw_cause}; trap_tval <= ptw_va; trap_epc <= pc; state <= S_TRAP;
            end else if (pa_too_high) begin
              trap_cause <= (xl_kind == 2'd2) ? (mem_write_class ? `CAUSE_STORE_ACCESS : `CAUSE_LOAD_ACCESS) : `CAUSE_INSN_ACCESS;
              trap_tval <= ptw_va; trap_epc <= pc; state <= S_TRAP;
            end else if (xl_kind == 2'd2) begin
              core_req_valid <= 1'b1; core_req_addr <= ptw_pa[31:0]; core_req_write <= mem_write_class;
              core_req_size  <= funct3[1:0];
              core_req_wdata <= (mem_write_class || LOAD_WDATA_LEAK != 0) ? (rs2_val << lshift) : 64'd0;
              core_req_wmask <= mem_write_class ? (store_mask_base << mem_vaddr[2:0]) : 8'd0;
              core_req_amo   <= (is_amo && FAULT_A_AMO_AS_LOAD == 0) ? amo_code : 4'd0;
              core_req_lrsc  <= is_lr ? 2'd1 : is_sc ? 2'd2 : 2'd0;
              state <= S_MEM_WAIT;
            end else begin
              // OPT01: the TRANSLATED fetch must authorise four bytes too, exactly as the untranslated
              // one does. Without this the request asks for two bytes while S_IF_WAIT consumes four out
              // of the 64-bit response -- bytes the request never authorised. Simulation hides that,
              // because the model returns a full word whatever was asked for; a stricter model, a
              // monitor, or real fabric need not. Only the FIRST parcel (xl_kind==0) widens: the
              // second-parcel path is the unaligned fallback and stays at one parcel.
              core_req_valid <= 1'b1; core_req_addr <= ptw_pa[31:0]; core_req_write <= 1'b0;
              core_req_size  <= (xl_kind == 2'd0 && pc_word_aligned) ? 2'd2 : 2'd1;
              fetch_wide_req <= (xl_kind == 2'd0 && pc_word_aligned);
              core_req_wdata <= 64'd0; core_req_wmask <= 8'd0; core_req_amo <= 4'd0; core_req_lrsc <= 2'd0;
              state <= (xl_kind == 2'd0) ? S_IF_WAIT : S_IF2_WAIT;
            end
          end
        end
        S_IF2_WAIT: begin
          if (core_req_valid && ic_req_ready) core_req_valid <= 1'b0;
          if (ic_resp_valid) begin
            if (ic_resp_error) begin
              trap_cause <= `CAUSE_INSN_ACCESS; trap_tval <= pc2; trap_epc <= pc; state <= S_TRAP;
            end else begin
              insn <= {fetched_half2, half_lo}; raw_insn <= {fetched_half2, half_lo}; insn_len <= 64'd4;
              state <= S_EXEC;
            end
          end
        end
        // ---- execute: decide retire / memory / trap
        S_EXEC: begin
          wb_we <= 1'b0; wb_rd <= rd; take_trap = 1'b0;
          if (illegal) begin
            trap_cause <= `CAUSE_ILLEGAL; trap_tval <= {32'd0, raw_insn}; trap_epc <= pc; state <= S_TRAP;
          end else if (mem_any && mem_misaligned) begin
            // misaligned access traps *before* any bus request is issued. CPU-A: an SC is checked here like
            // any other store even when its reservation is already lost -- a fault is a fault, never scFail.
            trap_cause <= mem_write_class ? `CAUSE_STORE_MISALIGNED : `CAUSE_LOAD_MISALIGNED;
            trap_tval <= mem_vaddr; trap_epc <= pc; state <= S_TRAP;
          end else if (mem_any && xlate_data) begin
            // CPU-SV39: translate with the effective privilege (MPRV -> MPP); the request follows in S_XLATE
            // CPU-A: an AMO is its own access class (reads and writes: R and W, A and D, store-class causes)
            ptw_start <= 1'b1; ptw_va <= mem_vaddr; ptw_priv <= eff_priv_data;
            ptw_type <= is_amo ? 2'd3 : (mem_write_class ? 2'd2 : 2'd1);
            xl_kind <= 2'd2; state <= S_XLATE;
          end else if (mem_any && mem_pa_bad) begin
            trap_cause <= mem_write_class ? `CAUSE_STORE_ACCESS : `CAUSE_LOAD_ACCESS;
            trap_tval <= mem_vaddr; trap_epc <= pc; state <= S_TRAP;
          end else if (target_misaligned) begin
            trap_cause <= `CAUSE_INSN_MISALIGNED; trap_tval <= target_for_check; trap_epc <= pc; state <= S_TRAP;
          end else if (mem_any) begin
            core_req_valid <= 1'b1; core_req_addr <= mem_vaddr[31:0]; core_req_write <= mem_write_class;
            core_req_size  <= funct3[1:0];
            // A read carries no write payload. The rs2 field of a load is part of its immediate, so
            // forwarding rs2_val here leaked an unrelated register onto the bus (Codex review, item 2).
            // LOAD_WDATA_LEAK restores that behaviour so the monitor can be shown to catch it.
            core_req_wdata <= (mem_write_class || LOAD_WDATA_LEAK != 0) ? (rs2_val << lshift) : 64'd0;
            core_req_wmask <= mem_write_class ? (store_mask_base << mem_vaddr[2:0]) : 8'd0;
            // CPU-A: exactly one V2 request carries the whole atomic -- never a read/modify/write here
            core_req_amo   <= (is_amo && FAULT_A_AMO_AS_LOAD == 0) ? amo_code : 4'd0;
            core_req_lrsc  <= is_lr ? 2'd1 : is_sc ? 2'd2 : 2'd0;
            if (FAULT_A_EARLY_RETIRE != 0 && is_amo) begin
              // fault injection: the value is written back before the memory has answered
              wb_we <= 1'b1; wb_value <= 64'd0; npc <= pc + insn_len; state <= S_WB;
            end else state <= S_MEM_WAIT;
          end else if (is_ecall || is_ebreak) begin
            // The environment calls are exceptions, not retirements: mtval is 0 for ecall and the PC of the
            // instruction itself for ebreak.
            // CPU-SU: the ecall cause names the level it came from (8 U, 9 S, 11 M)
            trap_cause <= is_ecall ? (priv == 2'd3 ? `CAUSE_ECALL_M : priv == 2'd1 ? 64'd9 : 64'd8) : `CAUSE_BREAKPOINT;
            trap_tval  <= is_ecall ? 64'd0 : pc;
            trap_epc   <= pc; state <= S_TRAP;
          end else if (is_muldiv) begin
            // CPU-M: hand the operands to the unit once and wait; the writeback below happens in S_MUL
            md_start <= 1'b1; npc <= pc + insn_len; state <= S_MUL;
          end else begin
            // pure register instruction: value and next PC are final here
            wb_we     <= (is_branch || is_fence || is_fencei || is_mret || is_sret || is_sfence || is_wfi) ? 1'b0 : (is_csr ? csr_read_intent : 1'b1);
            wb_is_csr <= is_csr;
            wb_value  <= is_lui    ? imm_u :
                         is_auipc  ? (pc + imm_u) :
                         (is_jal || is_jalr) ? (pc + insn_len) :
                         alu_out;
            // MRET retires normally and its target comes from mepc. If that target later faults on fetch,
            // the fault belongs to the target, not to this MRET.
            npc <= is_mret ? csr_mepc : is_sret ? csr_sepc :
                   (is_jal || is_jalr) ? jump_target :
                   (is_branch && branch_taken) ? br_target : (pc + insn_len);
            state <= S_WB;
          end
        end
        S_MEM_WAIT: begin
          if (EARLY_IRQ != 0 && irq_take) begin      // fault injection only: abandons a committed access
            core_req_valid <= 1'b0;
            trap_cause <= csr_irq_cause; trap_tval <= 64'd0; trap_epc <= pc;
            trap_interrupt <= 1'b1; state <= S_TRAP;
          end
          if (core_req_valid && ic_req_ready) core_req_valid <= 1'b0;
          if (ic_resp_valid) begin
            if (ic_resp_error) begin
              // a bus error is a real access fault (7 for SC/AMO, 5 for a load or an LR), never scFail
              trap_cause <= mem_write_class ? `CAUSE_STORE_ACCESS : `CAUSE_LOAD_ACCESS;
              trap_tval <= mem_vaddr; trap_epc <= pc; state <= S_TRAP;
            end else begin
              // CPU-A: LR and the AMOs return the old value (rd = x0 still performed every side effect --
              // the regfile discards the write); SC returns 0 on success and 1 on failure, taken from the
              // side-band result the backend decided, never from an error
              wb_we    <= is_load || is_amo_mem;
              wb_value <= is_sc              ? {63'd0, (FAULT_A_SC_RESULT != 0) ? 1'b0 : resp_scfail} :
                          (is_lr || is_amo)  ? amo_old : load_data;
              npc      <= pc + insn_len;
              state    <= S_WB;
            end
          end
        end
        // ---- CPU-M: the long operation. Nothing else happens here: no request is issued, and interrupts
        // are not looked at (they are only ever sampled in S_IF_REQ, which follows this instruction's
        // retirement -- so a pending IRQ waits for the result to be written back first).
        S_MUL: begin
          if (md_done) begin
            wb_we <= 1'b1; wb_rd <= rd; wb_is_csr <= 1'b0; wb_value <= md_result;
            state <= S_WB;
          end
        end
        // ---- the only normal-retirement path
        S_WB: begin
          // The CSR read is combinational and therefore the value before this instruction's effect; the
          // write below lands at the end of this same cycle, together with the retirement.
          rf_we <= wb_we; rf_wa <= wb_rd; rf_wd <= wb_is_csr ? csr_rdata : wb_value;
          csr_we_r        <= wb_is_csr;
          csr_wdata_r     <= csr_wdata;
          retire_now      <= 1'b1;
          mret_go         <= is_mret;
          sret_go         <= is_sret;
          commit_valid    <= 1'b1;
          commit_pc       <= pc;
          commit_insn     <= raw_insn;
          commit_len      <= insn_len[2:0];
          commit_rd_valid <= wb_we && (wb_rd != 5'd0);
          commit_rd       <= wb_rd;
          commit_rd_data  <= wb_is_csr ? csr_rdata : wb_value;
          pc              <= npc;
          wb_is_csr       <= 1'b0;
          state           <= S_ARCH;
        end
        // ---- architectural boundary: the write enables scheduled above are high this cycle and land on
        // its closing edge. Nothing is decided here; the point is that the next state sees settled state.
        S_ARCH: begin
          if (STALE_MIE != 0 && irq_take) begin      // fault injection only: decides on enables not yet landed
            trap_cause <= csr_irq_cause; trap_tval <= 64'd0; trap_epc <= pc;
            trap_interrupt <= 1'b1; state <= S_TRAP;
          end else state <= S_IF_REQ;
        end
        // ---- trap entry: save the context, then vector to mtvec. The faulting instruction writes no
        // register and does not retire, so commit_valid stays low here -- the two are mutually exclusive.
        S_TRAP: begin
          trap_valid <= 1'b1;
          trap_enter <= 1'b1;
          pc         <= csr_trap_vector;      // CPU-SU: mtvec or stvec, by delegation and level
          wb_is_csr  <= 1'b0;
          // Leave through the architectural boundary, not straight back to fetch. trap_enter is high during
          // S_ARCH, so mepc/mcause/mtval and the mstatus update land on its closing edge -- before the next
          // interrupt check. Going directly to S_IF_REQ would decide that check on the MIE this trap is in
          // the middle of clearing, and the same interrupt would be taken twice.
          if (STOP_ON_TRAP != 0) begin halted <= 1'b1; state <= S_HALT; end
          else                        state <= S_ARCH;
        end
        S_HALT: begin
          halted <= 1'b1; core_req_valid <= 1'b0;
        end
        default: state <= S_IF_REQ;
      endcase
    end
  end
endmodule
