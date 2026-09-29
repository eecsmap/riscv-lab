// PIPE-P1: an in-order pipelined teaching core -- F1 / F2 / FB front end, then ID / EX / MEM / WB.
//
// Contract: experiments/pipeline/p0/CONTRACT.md (rev. 2). Scope of P1 (codex-pipe-p1-standalone): RV64I, Zicsr,
// MRET, ECALL/EBREAK, FENCE/FENCE.I/WFI, machine-level traps and interrupts, Bare addressing only. Not implemented
// in P1, and therefore ILLEGAL here: M, A, C (compressed parcels), SRET, SFENCE.VMA. misa reads back what IS
// implemented (RV64I). IALIGN is 32: a taken branch or jump to an address with bit 1 set raises cause 0.
//
// Same 61 ports and the same parameter names as the multicycle tcpu_core, under a different module name, so a
// build can never silently substitute one for the other. Parameters that name a mechanism this core does not have
// are REFUSED at elaboration when non-zero (a missing-module error names the parameter).
//
// Shared RTL used unchanged: tcpu_regfile, tcpu_csr, tcpu_icache, tcpu_cacheable, tcpu_defs.vh.
//
// Physical port (PHYSICAL_PORT_V2, unchanged): one holding register; a raised request stays valid with a fixed
// payload until its handshake; one request in flight; responses always accepted (resp_ready = 1).
`timescale 1ns/1ps
`include "tcpu_defs.vh"

module tcpu_core_pipe #(
  parameter [63:0] RESET_PC      = 64'h0000_0000_8000_0000,
  parameter        TLB_ENTRIES   = 8,     // accepted for port/parameter compatibility; P1 is Bare only (no TLB)
  parameter        ICACHE_BYTES  = 1024,  // 0 = no instruction cache (direct fetches)
  parameter [63:0] HART_ID       = 64'd0,
  parameter        X0_WRITABLE   = 0,
  parameter        NO_LOAD_SEXT  = 0,
  parameter        REQ_WITHDRAW  = 0,     // monitor self-test
  parameter        LOAD_WDATA_LEAK = 0,   // monitor self-test
  parameter        STOP_ON_TRAP  = 0,
  parameter        TRAP_BAD_MEPC = 0,
  parameter        TRAP_COUNTS_RET = 0,
  parameter        FAULT_W_SEXT    = 0,
  parameter        FAULT_MULH_SIGN = 0,
  parameter        FAULT_C_IMM     = 0,
  parameter        FAULT_C_REG     = 0,
  parameter        ALLOW_RO_WRITE = 0,
  parameter        EARLY_IRQ      = 0,
  parameter        IRQ_BAD_MEPC   = 0,
  parameter        STALE_MIE      = 0,
  parameter        FAULT_NO_DELEG = 0,
  parameter        FAULT_S_IRQ_IN_M = 0,
  parameter        FAULT_SRET_SPP = 0,
  parameter        FAULT_PTW_NO_PERM = 0,
  parameter        FAULT_IF2_NO_XLATE = 0,
  parameter        FAULT_PPN_TRUNC = 0,
  parameter        MISA_A = 0,
  parameter        FAULT_A_W_NOSEXT   = 0,
  parameter        FAULT_A_SC_RESULT  = 0,
  parameter        FAULT_A_AMO_AS_LOAD = 0,
  parameter        FAULT_A_EARLY_RETIRE = 0,
  parameter        FAULT_A_NO_RESV_CLEAR = 0,
  // ---- pipeline-only negative controls (one defect each; 0 = the design as specified)
  //  1 WB_HOLD           WB keeps a committed instruction while MEM does not fire (re-commits it)
  //  2 REDIRECT_REPEAT   a taken branch held in EX redirects every cycle
  //  3 EPOCH_BIT         fetch responses told apart by a 1-bit epoch instead of the sticky per-transaction kill
  //  4 STORE_UNDER_TRAP  MEM may raise a data request in the cycle an older instruction traps in WB
  //  5 NO_LOADUSE        no load-use interlock
  //  6 NO_FWD_EXMEM      no forwarding from the EX/MEM register
  //  7 NO_FWD_MEMWB      no forwarding from the MEM/WB register
  //  8 NO_WB_BYPASS      no WB-to-ID bypass of the register-file read
  //  9 X0_FWD            a write to x0 is forwarded
  // 10 IRQ_EPC_FETCHPTR  a synthesised interrupt token takes the fetch pointer as its epc
  // 11 CSR_NO_DRAIN      a serialising instruction does not wait for the port / fetch engine to drain
  // 12 SPEC_MMIO_FETCH   an uncached fetch may be issued while the front end is speculative
  // 13 FLUSH_FILL        a refill whose final beat answers in a flush cycle still fills the I-cache
  // 14 FLUSH_ALLOC       the fetch engine may raise its request in a flush cycle (the request is left unowned)
  // 15 MD_STALE_RESULT   (M) a flush does not abandon the mul/div unit, and its result goes to whichever M
  //                      instruction occupies EX when it arrives (no ownership)
  // 16 MD_RESTART        (M) the unit is started again whenever it is idle and EX still holds an M instruction
  // 17 C_LINK_LEN        (C) a compressed jump links pc + 4 instead of pc + 2
  // 18 C_CARRY_DROP      (C) the lower parcel of a 32-bit instruction that crosses a fetch word is dropped
  // 19 C_TVAL_FIRST      (C) a fetch fault on the SECOND parcel reports the first parcel's address in mtval
  // 20 C_NC_WORD         (C) an uncached fetch reads the whole aligned 8-byte word (bytes before the pc and after the
  //                      instruction) and the extractor takes every instruction in it
  // 21 TLB_NO_FLUSH      (SU) sfence.vma and satp writes do not flush the TLB
  // 22 TLB_HIT_NO_PERM   (SU) a TLB hit skips the permission check
  // 23 DRAIN_NO_WALKER   (SU) a serialising instruction does not wait for the walker or its port transaction
  parameter        PIPE_FAULT = 0,
  // ---- P2a extensions (0 = the accepted P1 configuration, RV64I)
  parameter        PIPE_EXT_M = 0,        // 1: M (mul/div) through the unchanged shared tcpu_muldiv
  parameter        PIPE_EXT_C = 0,        // 1: integer C through the unchanged shared tcpu_cdecode; IALIGN 16
  // ---- P2b
  parameter        PIPE_EXT_SU = 0        // 1: S and U modes through the shared tcpu_csr (delegation, SRET, SFENCE.VMA)
                                          //    and Sv39 (the pipeline's TLB, the shared walker through tcpu_ptw_wrap)
) (
  input             clk,
  input             rst,
  output            req_valid,
  input             req_ready,
  output     [31:0] req_addr,
  output            req_write,
  output     [1:0]  req_size,
  output     [63:0] req_wdata,
  output     [7:0]  req_wmask,
  output     [3:0]  req_amo,
  output     [1:0]  req_lrsc,
  input             resp_valid,
  output            resp_ready,
  input      [63:0] resp_rdata,
  input             resp_error,
  input             resp_scfail,
  output            resv_clear,
  output            commit_valid,
  output     [63:0] commit_pc,
  output     [31:0] commit_insn,
  output     [2:0]  commit_len,
  output            commit_rd_valid,
  output     [4:0]  commit_rd,
  output     [63:0] commit_rd_data,
  output            trap_valid,
  output            trap_interrupt,
  output     [63:0] trap_cause,
  output     [63:0] trap_epc,
  output     [63:0] trap_tval,
  output reg        halted,
  output            dbg_req_is_fetch,
  input      [4:0]  dbg_ra,
  output     [63:0] dbg_rd,
  input      [4:0]  dbg_ra2,
  output     [63:0] dbg_rd2,
  input      [4:0]  dbg_csr_sel,
  output     [63:0] dbg_csr_val,
  output     [1:0]  dbg_priv,
  input             irq_msip,
  input             irq_mtip,
  input             irq_meip,
  output     [3:0]  dbg_state,
  output            dbg_redirect,
  output     [63:0] dbg_pc,
  output            dbg_irq_enabled
);
  // ================================================================================================ refusals
  // A parameter that names a mechanism this core does not implement is refused, never ignored.
  generate
    if (MISA_A != 0)             begin : refuse_MISA_A             pipe_p1_unsupported_MISA_A             u (); end
    // the M fault injections exist only where the unit does
    if (FAULT_W_SEXT != 0 && PIPE_EXT_M == 0)    begin : refuse_FAULT_W_SEXT    pipe_p1_unsupported_FAULT_W_SEXT    u (); end
    if (FAULT_MULH_SIGN != 0 && PIPE_EXT_M == 0) begin : refuse_FAULT_MULH_SIGN pipe_p1_unsupported_FAULT_MULH_SIGN u (); end
    // the C fault injections exist only where the decoder does
    if (FAULT_C_IMM != 0 && PIPE_EXT_C == 0) begin : refuse_FAULT_C_IMM pipe_p1_unsupported_FAULT_C_IMM u (); end
    if (FAULT_C_REG != 0 && PIPE_EXT_C == 0) begin : refuse_FAULT_C_REG pipe_p1_unsupported_FAULT_C_REG u (); end
    if (EARLY_IRQ != 0)          begin : refuse_EARLY_IRQ          pipe_p1_unsupported_EARLY_IRQ          u (); end
    if (IRQ_BAD_MEPC != 0)       begin : refuse_IRQ_BAD_MEPC       pipe_p1_unsupported_IRQ_BAD_MEPC       u (); end
    if (STALE_MIE != 0)          begin : refuse_STALE_MIE          pipe_p1_unsupported_STALE_MIE          u (); end
    // the CPU-SU fault injections exist only where S and U do
    if (FAULT_NO_DELEG != 0 && PIPE_EXT_SU == 0)   begin : refuse_FAULT_NO_DELEG   pipe_p1_unsupported_FAULT_NO_DELEG   u (); end
    if (FAULT_S_IRQ_IN_M != 0 && PIPE_EXT_SU == 0) begin : refuse_FAULT_S_IRQ_IN_M pipe_p1_unsupported_FAULT_S_IRQ_IN_M u (); end
    if (FAULT_SRET_SPP != 0 && PIPE_EXT_SU == 0)   begin : refuse_FAULT_SRET_SPP   pipe_p1_unsupported_FAULT_SRET_SPP   u (); end
    if (PIPE_EXT_SU != 0 && PIPE_EXT_SU != 1) begin : refuse_PIPE_EXT_SU pipe_p1_unsupported_PIPE_EXT_SU u (); end
    // the CPU-SV39 fault injections exist only where Sv39 does
    if (FAULT_PTW_NO_PERM != 0 && PIPE_EXT_SU == 0)  begin : refuse_FAULT_PTW_NO_PERM  pipe_p1_unsupported_FAULT_PTW_NO_PERM  u (); end
    if (FAULT_IF2_NO_XLATE != 0 && PIPE_EXT_SU == 0) begin : refuse_FAULT_IF2_NO_XLATE pipe_p1_unsupported_FAULT_IF2_NO_XLATE u (); end
    if (FAULT_PPN_TRUNC != 0 && PIPE_EXT_SU == 0)    begin : refuse_FAULT_PPN_TRUNC    pipe_p1_unsupported_FAULT_PPN_TRUNC    u (); end
    if (PIPE_EXT_SU != 0 && TLB_ENTRIES != 8)        begin : refuse_TLB_ENTRIES        pipe_p2b_unsupported_TLB_ENTRIES       u (); end
    if (FAULT_A_W_NOSEXT != 0)   begin : refuse_FAULT_A_W_NOSEXT   pipe_p1_unsupported_FAULT_A_W_NOSEXT   u (); end
    if (FAULT_A_SC_RESULT != 0)  begin : refuse_FAULT_A_SC_RESULT  pipe_p1_unsupported_FAULT_A_SC_RESULT  u (); end
    if (FAULT_A_AMO_AS_LOAD != 0) begin : refuse_FAULT_A_AMO_AS_LOAD pipe_p1_unsupported_FAULT_A_AMO_AS_LOAD u (); end
    if (FAULT_A_EARLY_RETIRE != 0) begin : refuse_FAULT_A_EARLY_RETIRE pipe_p1_unsupported_FAULT_A_EARLY_RETIRE u (); end
    if (FAULT_A_NO_RESV_CLEAR != 0) begin : refuse_FAULT_A_NO_RESV_CLEAR pipe_p1_unsupported_FAULT_A_NO_RESV_CLEAR u (); end
    if (ICACHE_BYTES != 0 && ICACHE_BYTES != 1024) begin : refuse_ICACHE_BYTES pipe_p1_unsupported_ICACHE_BYTES u (); end
    if (PIPE_FAULT < 0 || PIPE_FAULT > 23) begin : refuse_PIPE_FAULT pipe_p1_unsupported_PIPE_FAULT u (); end
    if (PIPE_FAULT >= 21 && PIPE_FAULT <= 23 && PIPE_EXT_SU == 0) begin : refuse_PIPE_FAULT_SU pipe_p1_unsupported_PIPE_FAULT_needs_SU u (); end
    if (PIPE_FAULT >= 17 && PIPE_FAULT <= 20 && PIPE_EXT_C == 0) begin : refuse_PIPE_FAULT_C pipe_p1_unsupported_PIPE_FAULT_needs_C u (); end
    if ((PIPE_FAULT == 15 || PIPE_FAULT == 16) && PIPE_EXT_M == 0) begin : refuse_PIPE_FAULT_M pipe_p1_unsupported_PIPE_FAULT_needs_M u (); end
    if (PIPE_EXT_M != 0 && PIPE_EXT_M != 1) begin : refuse_PIPE_EXT_M pipe_p1_unsupported_PIPE_EXT_M u (); end
    if (PIPE_EXT_C != 0 && PIPE_EXT_C != 1) begin : refuse_PIPE_EXT_C pipe_p1_unsupported_PIPE_EXT_C u (); end
  endgenerate

  localparam PF_WB_HOLD = 1, PF_REDIRECT_REPEAT = 2, PF_EPOCH_BIT = 3, PF_STORE_UNDER_TRAP = 4,
             PF_NO_LOADUSE = 5, PF_NO_FWD_EXMEM = 6, PF_NO_FWD_MEMWB = 7, PF_NO_WB_BYPASS = 8,
             PF_X0_FWD = 9, PF_IRQ_EPC_FETCHPTR = 10, PF_CSR_NO_DRAIN = 11, PF_SPEC_MMIO_FETCH = 12,
             PF_FLUSH_FILL = 13, PF_FLUSH_ALLOC = 14, PF_MD_STALE_RESULT = 15, PF_MD_RESTART = 16,
             PF_C_LINK_LEN = 17, PF_C_CARRY_DROP = 18, PF_C_TVAL_FIRST = 19, PF_C_NC_WORD = 20,
             PF_TLB_NO_FLUSH = 21, PF_TLB_HIT_NO_PERM = 22, PF_DRAIN_NO_WALKER = 23;
  // C: an uncached (possibly device) instruction access reads exact 16-bit parcels, never bytes the executed
  // instruction does not occupy (codex-pipe-p2a-uncached-fetch)
  localparam NC_PARCEL = (PIPE_EXT_C != 0) && (PIPE_FAULT != PF_C_NC_WORD);
  localparam [63:0] MISA_P1 = 64'h8000_0000_0000_0100;     // MXL = 2, I only
  // misa reads back what this build implements: I, plus M and C when enabled
  localparam [63:0] MISA_P = MISA_P1 | ((PIPE_EXT_M != 0) ? 64'h1000 : 64'd0) | ((PIPE_EXT_C != 0) ? 64'h4 : 64'd0) |
                             ((PIPE_EXT_SU != 0) ? 64'h14_0000 : 64'd0);          // S (bit 18) and U (bit 20)
  wire x0z = (X0_WRITABLE == 0);                              // x0 reads 0 and is never written

  // ================================================================================================ shared units
  // ---- register file: read in ID (two ports), written in WB
  wire [4:0]  id_rs1, id_rs2;
  wire [63:0] rf_rd1, rf_rd2;
  wire        rf_we;
  wire [4:0]  rf_wa;
  wire [63:0] rf_wd;
  tcpu_regfile #(.X0_WRITABLE(X0_WRITABLE)) rf (
    .clk(clk), .ra1(id_rs1), .ra2(id_rs2), .rd1(rf_rd1), .rd2(rf_rd2),
    .we(rf_we), .wa(rf_wa), .wd(rf_wd), .dbg_ra(dbg_ra), .dbg_rd(dbg_rd), .dbg_ra2(dbg_ra2), .dbg_rd2(dbg_rd2));

  // ---- CSR file: every access, the trap entry and MRET happen in WB
  wire [11:0] csr_addr;
  wire        csr_access, csr_wi, csr_ri, csr_we;
  wire [63:0] csr_wdata;
  wire        csr_addr_illegal;
  wire [63:0] csr_rdata_raw, csr_trap_vector, csr_mepc, csr_irq_cause;
  wire        csr_irq_pending, csr_irq_enabled;
  wire [1:0]  priv;
  wire        wb_retire, wb_trap_take, wb_mret, wb_sret;
  wire [63:0] wb_trap_cause, wb_trap_epc, wb_trap_tval;
  wire [63:0] unused_mtvec, csr_sepc;
  wire [43:0] csr_satp_ppn;
  wire        csr_satp_mode, csr_sum, csr_mxr, csr_mprv;
  wire [1:0]  csr_mpp;
  tcpu_csr #(.HART_ID(HART_ID), .MISA_A(0), .TRAP_BAD_MEPC(TRAP_BAD_MEPC), .TRAP_COUNTS_RET(TRAP_COUNTS_RET),
             .ALLOW_RO_WRITE(ALLOW_RO_WRITE), .FAULT_NO_DELEG(FAULT_NO_DELEG), .FAULT_S_IRQ_IN_M(FAULT_S_IRQ_IN_M),
             .FAULT_SRET_SPP(FAULT_SRET_SPP)) csrfile (
    .clk(clk), .rst(rst),
    .addr(csr_addr), .access(csr_access), .write_intent(csr_wi), .read_intent(csr_ri),
    .addr_illegal(csr_addr_illegal), .rdata(csr_rdata_raw), .we(csr_we), .wdata(csr_wdata),
    .retire(wb_retire),
    .trap(wb_trap_take), .trap_cause(wb_trap_cause), .trap_epc(wb_trap_epc), .trap_tval(wb_trap_tval),
    .trap_vector(csr_trap_vector), .mret(wb_mret), .sret(wb_sret),
    .irq_msip(irq_msip), .irq_mtip(irq_mtip), .irq_meip(irq_meip),
    .irq_enabled(csr_irq_enabled), .irq_pending(csr_irq_pending), .irq_cause(csr_irq_cause),
    .priv(priv), .mtvec_base(unused_mtvec), .mepc_out(csr_mepc), .sepc_out(csr_sepc),
    .satp_mode(csr_satp_mode), .satp_ppn(csr_satp_ppn), .st_sum_o(csr_sum), .st_mxr_o(csr_mxr),
    .st_mprv_o(csr_mprv), .st_mpp_o(csr_mpp),
    .dbg_sel(dbg_csr_sel), .dbg_val(dbg_csr_val));
  assign dbg_priv = priv;
  assign dbg_irq_enabled = csr_irq_enabled;

  // ================================================================================================ state
  // ---- the port holding register
  reg         preq_valid, pwait, preq_owner_f, preq_killed;   // owner: 0 = MEM (data), 1 = fetch engine
  reg  [31:0] preq_addr;
  reg         preq_write;
  reg  [1:0]  preq_size;
  reg  [63:0] preq_wdata;
  reg  [7:0]  preq_wmask;
  reg         withdrawn, withdrawing;
  // P2b: the walker wrapper's holding register shares the one port (Sv39 only; tied off otherwise). The arbiter lets
  // only one of the two hold a transaction: the core allocates only when the wrapper's register is empty and the
  // wrapper forwards only when granted (the core's register empty and MEM not allocating this cycle).
  wire        wr_req_valid, wr_port_busy, wr_taking_port;
  wire [31:0] wr_req_addr;
  assign req_valid = (preq_valid && !withdrawing) || wr_req_valid;
  assign req_addr  = wr_req_valid ? wr_req_addr : preq_addr;
  assign req_write = wr_req_valid ? 1'b0 : preq_write;
  assign req_size  = wr_req_valid ? 2'd3 : preq_size;       // a PTE read: 8 bytes
  assign req_wdata = wr_req_valid ? 64'd0 : preq_wdata;
  assign req_wmask = wr_req_valid ? 8'd0 : preq_wmask;
  assign req_amo   = 4'd0;
  assign req_lrsc  = 2'd0;
  assign resp_ready = 1'b1;
  wire port_fire  = preq_valid && !withdrawing && req_ready;    // the core's own transaction
  wire port_resp  = resp_valid && pwait;
  wire core_port_idle = !preq_valid && !pwait && !wr_port_busy;
  wire port_free  = core_port_idle && !wr_taking_port;          // for the fetch engine: the walker goes first
  assign dbg_req_is_fetch = (preq_valid || pwait) && preq_owner_f;

  // ---- front end
  reg  [63:0] fe_pc;          // next instruction address to put into F1
  reg  [63:0] fe_next_pc;     // the pc ID will receive next (the architectural next pc when ID..WB are empty)
  reg         fe_park;        // parked behind an interrupt token
  reg         fe_ep;          // PF_EPOCH_BIT only: the 1-bit front-end epoch
  reg         f1_v;
  reg  [63:0] f1_pc;
  localparam F2_LOOK = 2'd0, F2_WAIT = 2'd1, F2_READY = 2'd2, F2_NC = 2'd3;
  reg         f2_v;
  reg  [1:0]  f2_st;
  reg  [63:0] f2_pc;          // virtual (the instructions' pcs)
  reg  [31:0] f2_pa;          // P2b: the word's physical address (= f2_pc without translation): I-cache, fetches
  reg         f2_pfault;      // F1 found this fetch un-issuable: fault carried, no access
  reg  [63:0] f2_pcause;
  reg  [63:0] f2_word;
  reg  [1:0]  f2_slots;
  reg         f2_err;         // the fetch response reported an error (access fault on this instruction)
  // fetch engine: a 2-beat I-cache refill, or one direct read (no cache / uncached space)
  localparam E_IDLE = 3'd0, E_NEED0 = 3'd1, E_WAIT0 = 3'd2, E_NEED1 = 3'd3, E_WAIT1 = 3'd4, E_NEEDD = 3'd5, E_WAITD = 3'd6;
  reg  [2:0]  eng_st;
  reg         eng_killed, eng_ep, eng_err;
  reg  [31:0] eng_pa;         // the requested fetch address (its line for a refill)
  reg  [63:0] eng_buf0;
  reg  [1:0]  eng_dsize;
  // fetch buffer: up to 4 instructions
  reg  [63:0] fbq_pc   [0:3];
  reg  [31:0] fbq_insn [0:3];
  reg         fbq_exc  [0:3];
  reg  [63:0] fbq_cause[0:3];
  reg  [63:0] fbq_tval [0:3];
  reg  [1:0]  fb_head;
  reg  [2:0]  fb_cnt;

  // ---- back end (valid, sequence number, pc, instruction, exception, interrupt token)
  reg         id_v, id_irq, id_exc;
  reg  [31:0] id_raw, ex_raw, mem_raw, wb_raw;   // the instruction as fetched: a 16-bit parcel zero-extended, or 32 bits
  reg         id_c, ex_c, mem_c, wb_c;           // C: the instruction is a compressed parcel (length 2)
  reg  [31:0] id_seq;
  reg  [63:0] id_pc, id_cause, id_tval;
  reg  [31:0] id_insn;
  reg         ex_v, ex_irq, ex_exc, ex_redirected;
  reg  [31:0] ex_seq;
  reg  [63:0] ex_pc, ex_cause, ex_tval, ex_a, ex_b;
  reg  [31:0] ex_insn;
  reg         mem_v, mem_irq, mem_exc, mem_we, mem_isld, mem_isst;
  reg  [31:0] mem_seq;
  reg  [63:0] mem_pc, mem_cause, mem_tval, mem_res, mem_addr, mem_sdata;
  reg  [31:0] mem_insn;
  reg  [4:0]  mem_rd;
  localparam M_FIRST = 2'd0, M_ISSUE = 2'd1, M_PEND = 2'd2, M_DONE = 2'd3;
  reg  [1:0]  mem_st;
  reg         wb_v, wb_irq, wb_exc, wb_we;
  reg  [31:0] wb_seq;
  reg  [63:0] wb_pc, wb_cause, wb_tval, wb_val, wb_src;
  reg  [31:0] wb_insn;
  reg  [4:0]  wb_rd;
  reg  [31:0] seq_ctr;

  // ================================================================================================ decode helper
  // M (PIPE_EXT_M only): OP funct7 0000001, any funct3; OP-32 funct7 0000001 with funct3 0 (MULW) or 4..7
  function is_md; input [31:0] i; begin
    is_md = (PIPE_EXT_M != 0) && (i[31:25] == 7'b0000001) &&
            ((i[6:0] == `OP_OP) || ((i[6:0] == `OP_OP32) && (i[14:12] == 3'b000 || i[14] == 1'b1)));
  end endfunction
  // decode of one 32-bit instruction: class bits and legality (P1: RV64I + Zicsr + MRET/ECALL/EBREAK/WFI/FENCE[.I])
  // {is_sret, is_sfence, illegal, is_ld, is_st, is_br, is_jal, is_jalr, is_lui, is_auipc, is_alu, is_csr, is_ecall, is_ebreak,
  //  is_mret, is_wfi, is_fence, is_fencei}. SRET and SFENCE.VMA exist only with S/U (PIPE_EXT_SU), as in the reference
  // core (tcpu_core.v): TSR = TVM = TW = 0, so SRET and SFENCE.VMA are illegal only in U, WFI is legal everywhere.
  function [17:0] dec;
    input [31:0] i;
    input [1:0]  pv;
    reg [6:0] op; reg [2:0] f3; reg [6:0] f7; reg [4:0] rd, rs1;
    reg ld, st, br, jal, jalr, lui, auipc, alu, csr, ecall, ebreak, mret, wfi, fence, fencei, md, sret, sfence, known, bad;
    begin
      op = i[6:0]; f3 = i[14:12]; f7 = i[31:25]; rd = i[11:7]; rs1 = i[19:15];
      ld = (op == `OP_LOAD) && (f3 != 3'b111);
      st = (op == `OP_STORE) && (f3 <= 3'b011);
      br = (op == `OP_BRANCH) && (f3 != 3'b010) && (f3 != 3'b011);
      jal = (op == `OP_JAL);
      jalr = (op == `OP_JALR) && (f3 == 3'b000);
      lui = (op == `OP_LUI); auipc = (op == `OP_AUIPC);
      alu = ((op == `OP_OPIMM) && !((f3 == 3'b001 && i[31:26] != 6'b000000) ||
                                   (f3 == 3'b101 && i[31:26] != 6'b000000 && i[31:26] != 6'b010000))) ||
            ((op == `OP_OP) && ((f7 == 7'b0000000) || (f7 == 7'b0100000 && (f3 == 3'b000 || f3 == 3'b101)))) ||
            ((op == `OP_OPIMM32) && ((f3 == 3'b000) || (f3 == 3'b001 && f7 == 7'b0000000) ||
                                     (f3 == 3'b101 && (f7 == 7'b0000000 || f7 == 7'b0100000)))) ||
            ((op == `OP_OP32) && ((f7 == 7'b0000000 && (f3 == 3'b000 || f3 == 3'b001 || f3 == 3'b101)) ||
                                  (f7 == 7'b0100000 && (f3 == 3'b000 || f3 == 3'b101))));
      csr = (op == `OP_SYSTEM) && (f3 != 3'b000) && (f3[1:0] != 2'b00);
      ecall  = (i == 32'h00000073);
      ebreak = (i == 32'h00100073);
      mret   = (i == 32'h30200073);
      wfi    = (i == 32'h10500073);
      fence  = (op == `OP_MISCMEM) && (f3 == 3'b000);
      fencei = (op == `OP_MISCMEM) && (f3 == 3'b001);
      md     = is_md(i);
      sret   = (PIPE_EXT_SU != 0) && (i == 32'h10200073);
      sfence = (PIPE_EXT_SU != 0) && (op == `OP_SYSTEM) && (f3 == 3'b000) && (f7 == 7'b0001001) && (rd == 5'd0);
      known  = ld | st | br | jal | jalr | lui | auipc | alu | csr | ecall | ebreak | mret | wfi | fence | fencei | md | sret | sfence;
      bad    = (i[1:0] != 2'b11) || !known || (mret && pv != 2'd3) ||   // a compressed parcel is illegal in P1
               (sret && pv == 2'd0) || (sfence && pv == 2'd0);
      dec = {sret, sfence, bad, ld, st, br, jal, jalr, lui, auipc, alu, csr, ecall, ebreak, mret, wfi, fence, fencei};
    end
  endfunction
  // does the instruction read rs1 / rs2 (for the interlock; a false match would only cost a cycle)
  function uses_rs1; input [31:0] i; reg [6:0] op; begin op = i[6:0];
    uses_rs1 = (op == `OP_LOAD) || (op == `OP_STORE) || (op == `OP_BRANCH) || (op == `OP_JALR) ||
               (op == `OP_OPIMM) || (op == `OP_OP) || (op == `OP_OPIMM32) || (op == `OP_OP32) ||
               ((op == `OP_SYSTEM) && (i[14:12] != 3'b000) && !i[14]);
  end endfunction
  function uses_rs2; input [31:0] i; reg [6:0] op; begin op = i[6:0];
    uses_rs2 = (op == `OP_STORE) || (op == `OP_BRANCH) || (op == `OP_OP) || (op == `OP_OP32);
  end endfunction
  function writes_rd; input [31:0] i; reg [6:0] op; begin op = i[6:0];
    writes_rd = (i[11:7] != 5'd0 || X0_WRITABLE != 0 || PIPE_FAULT == PF_X0_FWD) &&
                ((op == `OP_LOAD) || (op == `OP_JAL) || (op == `OP_JALR) || (op == `OP_LUI) || (op == `OP_AUIPC) ||
                 (op == `OP_OPIMM) || (op == `OP_OP) || (op == `OP_OPIMM32) || (op == `OP_OP32));
  end endfunction
  function is_serial; input [31:0] i; reg [17:0] d; begin d = dec(i, 2'd3);
    is_serial = d[17] | d[16] | d[6] | d[3] | d[2] | d[1] | d[0];    // sret, sfence.vma, csr, mret, wfi, fence, fence.i
  end endfunction

  // ================================================================================================ WB
  wire [17:0] wb_d = dec(wb_insn, priv);
  wire wb_is_csr = wb_d[6], wb_is_mret = wb_d[3], wb_is_wfi = wb_d[2], wb_is_fence = wb_d[1], wb_is_fencei = wb_d[0];
  wire wb_is_sret = wb_d[17], wb_is_sfence = wb_d[16];
  wire [2:0] wb_f3 = wb_insn[14:12];
  assign csr_addr   = wb_insn[31:20];
  assign csr_access = wb_v && !wb_irq && !wb_exc && wb_is_csr;
  assign csr_wi     = csr_access && ((wb_f3[1:0] == 2'b01) || (wb_insn[19:15] != 5'd0));
  assign csr_ri     = csr_access && ((wb_f3[1:0] == 2'b01) ? (wb_insn[11:7] != 5'd0) : 1'b1);
  wire [63:0] csr_rdata = (csr_addr == 12'h301) ? MISA_P : csr_rdata_raw;
  wire [63:0] csr_src   = wb_f3[2] ? {59'd0, wb_insn[19:15]} : wb_src;
  assign csr_wdata = (wb_f3[1:0] == 2'b01) ? csr_src : (wb_f3[1:0] == 2'b10) ? (csr_rdata | csr_src) : (csr_rdata & ~csr_src);
  // the interrupt token: taken only if an interrupt is still pending and enabled now; otherwise it is cancelled
  // (the instruction it replaced is refetched) -- the level may have been quieted by an older store meanwhile
  wire wb_irq_take   = wb_v && wb_irq && csr_irq_pending;
  wire wb_irq_cancel = wb_v && wb_irq && !csr_irq_pending;
  wire wb_csr_bad    = csr_access && csr_addr_illegal;
  wire wb_sync_trap  = wb_v && !wb_irq && (wb_exc || wb_csr_bad);
  assign wb_trap_take = (wb_irq_take || wb_sync_trap) && !halted;
  assign wb_trap_cause = wb_irq_take ? csr_irq_cause : (wb_exc ? wb_cause : `CAUSE_ILLEGAL);
  assign wb_trap_epc   = wb_pc;
  assign wb_trap_tval  = wb_irq_take ? 64'd0 : (wb_exc ? wb_tval : {32'd0, wb_raw});
  wire wb_commit     = wb_v && !wb_irq && !wb_sync_trap && !halted;
  wire wb_serial     = wb_commit && (wb_is_csr || wb_is_mret || wb_is_wfi || wb_is_fence || wb_is_fencei ||
                                    wb_is_sret || wb_is_sfence);
  assign wb_mret     = wb_commit && wb_is_mret;
  assign wb_sret     = wb_commit && wb_is_sret;
  assign csr_we      = wb_commit && wb_is_csr;
  assign wb_retire   = wb_commit;
  wire wb_flush      = wb_trap_take || wb_irq_cancel || wb_serial;
  wire [63:0] wb_flush_to = wb_trap_take ? csr_trap_vector : wb_irq_cancel ? wb_pc : wb_mret ? csr_mepc : wb_sret ? csr_sepc : (wb_pc + (wb_c ? 64'd2 : 64'd4));
  wire wb_normal     = wb_commit && !wb_serial;         // commits and flushes nothing
  wire [63:0] wb_rdval = wb_is_csr ? csr_rdata : wb_val;
  assign rf_we = wb_commit && ((wb_we && (wb_rd != 5'd0 || X0_WRITABLE != 0)) || (wb_is_csr && csr_ri && wb_insn[11:7] != 5'd0));
  assign rf_wa = wb_is_csr ? wb_insn[11:7] : wb_rd;
  assign rf_wd = wb_rdval;
  assign commit_valid    = wb_commit;
  assign commit_pc       = wb_pc;
  assign commit_insn     = wb_raw;
  assign commit_len      = wb_c ? 3'd2 : 3'd4;
  assign commit_rd_valid = rf_we && (rf_wa != 5'd0);
  assign commit_rd       = rf_wa;
  assign commit_rd_data  = wb_rdval;
  assign trap_valid      = wb_trap_take;
  assign trap_interrupt  = wb_irq_take;
  assign trap_cause      = wb_trap_cause;
  assign trap_epc        = wb_trap_epc;
  assign trap_tval       = wb_trap_tval;
  assign resv_clear      = (FAULT_A_NO_RESV_CLEAR != 0) ? 1'b0 : (rst || wb_trap_take);
  // WB always fires: it commits or traps once and is vacated in the same cycle (PF_WB_HOLD breaks exactly this)

  // ================================================================================================ MEM
  wire [2:0]  mem_f3 = mem_insn[14:12];
  wire        mem_memop = mem_isld || mem_isst;
  // Sv39 (assigned in the translation block below): whether this access is translated, whether its translation is
  // known and permitted, whether it page-faults, and its physical address
  wire        mem_xd, mem_xl_ok, mem_xl_pf;
  wire [55:0] mem_pa;
  wire        mem_pa_bad = mem_xl_ok && (mem_xd ? (mem_pa[55:32] != 24'd0 && FAULT_PPN_TRUNC == 0) : (mem_addr[63:32] != 32'd0));
  wire        mem_bad_now = mem_v && !mem_exc && !mem_irq && (mem_isld || mem_isst) && (mem_xl_pf || mem_pa_bad);
  // the MEM instruction is the oldest in the machine: WB is empty, or commits this cycle without a flush
  wire        oldest_true = !wb_v || wb_normal;
  wire        oldest_ok   = (PIPE_FAULT == PF_STORE_UNDER_TRAP) ? 1'b1 : oldest_true;
  wire        mem_want_req = mem_v && !mem_exc && !mem_irq && mem_memop && mem_xl_ok && !mem_xl_pf && !mem_pa_bad &&
                             (mem_st == M_FIRST || mem_st == M_ISSUE) && !halted;
  wire        mem_alloc = mem_want_req && oldest_ok && core_port_idle;   // MEM has priority over the walker
  wire [5:0]  mem_lsh = {mem_addr[2:0], 3'b000};
  wire [7:0]  mem_mbase = (mem_f3[1:0] == 2'b00) ? 8'h01 : (mem_f3[1:0] == 2'b01) ? 8'h03 :
                          (mem_f3[1:0] == 2'b10) ? 8'h0f : 8'hff;
  wire [63:0] ld_sh = resp_rdata >> mem_lsh;
  reg  [63:0] ld_val;
  always @(*) begin
    case (mem_f3)
      3'b000: ld_val = NO_LOAD_SEXT ? {56'd0, ld_sh[7:0]}  : {{56{ld_sh[7]}},  ld_sh[7:0]};
      3'b001: ld_val = NO_LOAD_SEXT ? {48'd0, ld_sh[15:0]} : {{48{ld_sh[15]}}, ld_sh[15:0]};
      3'b010: ld_val = NO_LOAD_SEXT ? {32'd0, ld_sh[31:0]} : {{32{ld_sh[31]}}, ld_sh[31:0]};
      3'b011: ld_val = ld_sh;
      3'b100: ld_val = {56'd0, ld_sh[7:0]};
      3'b101: ld_val = {48'd0, ld_sh[15:0]};
      3'b110: ld_val = {32'd0, ld_sh[31:0]};
      default: ld_val = 64'd0;
    endcase
  end
  wire mem_resp_now = port_resp && !preq_owner_f;
  wire mem_done = mem_v && (mem_exc || mem_irq || !mem_memop || mem_bad_now || mem_st == M_DONE ||
                            (mem_st == M_PEND && mem_resp_now));
  wire wb_hold = (PIPE_FAULT == PF_WB_HOLD) && wb_commit && !mem_done;
  wire mem_fire = mem_done && !wb_hold;

  // ================================================================================================ EX
  wire [17:0] ex_d = dec(ex_insn, priv);
  wire ex_isld = ex_d[14], ex_isst = ex_d[13], ex_isbr = ex_d[12], ex_isjal = ex_d[11], ex_isjalr = ex_d[10];
  wire ex_serial = ex_v && !ex_exc && !ex_irq && is_serial(ex_insn);
  wire [4:0] ex_rs1 = ex_insn[19:15], ex_rs2 = ex_insn[24:20];
  // forwarding: EX/MEM (an ALU result), then MEM/WB (a result or a load value), then the held operand
  wire mem_fwd_ok = mem_v && !mem_irq && !mem_exc && mem_we && (PIPE_FAULT != PF_NO_FWD_EXMEM);
  wire wb_fwd_ok  = wb_v && !wb_irq && !wb_exc && wb_we && (PIPE_FAULT != PF_NO_FWD_MEMWB);
  function [64:0] fwd;   // {hazard, value}
    input [4:0] rs; input [63:0] held;
    begin
      if (rs == 5'd0 && x0z && PIPE_FAULT != PF_X0_FWD) fwd = {1'b0, 64'd0};
      else if (mem_fwd_ok && mem_rd == rs) fwd = mem_isld ? {1'b1, held} : {1'b0, mem_res};
      else if (wb_fwd_ok && wb_rd == rs) fwd = {1'b0, wb_val};
      else fwd = {1'b0, held};
    end
  endfunction
  wire [64:0] fa = fwd(ex_rs1, ex_a);
  wire [64:0] fb = fwd(ex_rs2, ex_b);
`ifndef SYNTHESIS
  // the value the CORRECT forwarding would give (simulation only): lets a negative control prove that the knob,
  // and not something else, changed the operand an instruction actually used
  function [64:0] fwd_true;
    input [4:0] rs; input [63:0] held;
    begin
      if (rs == 5'd0 && x0z) fwd_true = {1'b0, 64'd0};
      else if (mem_v && !mem_irq && !mem_exc && mem_we && mem_rd == rs && (rs != 5'd0 || !x0z)) fwd_true = mem_isld ? {1'b1, held} : {1'b0, mem_res};
      else if (wb_v && !wb_irq && !wb_exc && wb_we && wb_rd == rs && (rs != 5'd0 || !x0z)) fwd_true = {1'b0, wb_val};
      else fwd_true = {1'b0, held};
    end
  endfunction
  wire [64:0] fa_true = fwd_true(ex_rs1, ex_a);
  wire [64:0] fb_true = fwd_true(ex_rs2, ex_b);
`endif
  wire lu_haz_true = ex_v && !ex_exc && !ex_irq && ((uses_rs1(ex_insn) && fa[64]) || (uses_rs2(ex_insn) && fb[64]));
  wire lu_haz = (PIPE_FAULT == PF_NO_LOADUSE) ? 1'b0 : lu_haz_true;
  wire [63:0] a = fa[63:0], b_reg = fb[63:0];
  // ALU (the multicycle core's expressions, tcpu_core.v:241-286)
  wire [6:0] ex_op = ex_insn[6:0];
  wire [2:0] ex_f3 = ex_insn[14:12];
  wire [63:0] imm_i = {{52{ex_insn[31]}}, ex_insn[31:20]};
  wire [63:0] imm_s = {{52{ex_insn[31]}}, ex_insn[31:25], ex_insn[11:7]};
  wire [63:0] imm_b = {{51{ex_insn[31]}}, ex_insn[31], ex_insn[7], ex_insn[30:25], ex_insn[11:8], 1'b0};
  wire [63:0] imm_u = {{32{ex_insn[31]}}, ex_insn[31:12], 12'b0};
  wire [63:0] imm_j = {{43{ex_insn[31]}}, ex_insn[31], ex_insn[19:12], ex_insn[20], ex_insn[30:21], 1'b0};
  wire [63:0] op_b   = (ex_op == `OP_OP || ex_op == `OP_OP32) ? b_reg : imm_i;
  wire [5:0]  shamt6 = (ex_op == `OP_OP) ? b_reg[5:0] : ex_insn[25:20];
  wire [4:0]  shamt5 = (ex_op == `OP_OP32) ? b_reg[4:0] : ex_insn[24:20];
  wire        alt    = ex_insn[30];
  wire [63:0] sum    = a + op_b;
  wire [63:0] diff   = a - b_reg;
  wire [31:0] w_a = a[31:0], w_b = op_b[31:0];
  wire [31:0] w_sum = w_a + w_b, w_diff = w_a - b_reg[31:0];
  wire [31:0] w_sll = w_a << shamt5, w_srl = w_a >> shamt5, w_sra = $signed(w_a) >>> shamt5;
  // shifts as separate wires: inside a ?: with an unsigned operand, >>> would silently become a logical shift
  wire [63:0] sll64 = a << shamt6;
  wire [63:0] srl64 = a >> shamt6;
  wire [63:0] sra64 = $signed(a) >>> shamt6;
  wire        lt_s  = ($signed(a) < $signed(op_b));
  wire        lt_u  = (a < op_b);
  reg  [63:0] alu_out;
  always @(*) begin
    alu_out = 64'd0;
    case (ex_op)
      `OP_OPIMM, `OP_OP: case (ex_f3)
        3'b000: alu_out = (ex_op == `OP_OP && alt) ? diff : sum;
        3'b001: alu_out = sll64;
        3'b010: alu_out = {63'd0, lt_s};
        3'b011: alu_out = {63'd0, lt_u};
        3'b100: alu_out = a ^ op_b;
        3'b101: alu_out = alt ? sra64 : srl64;
        3'b110: alu_out = a | op_b;
        3'b111: alu_out = a & op_b;
      endcase
      `OP_OPIMM32, `OP_OP32: case (ex_f3)
        3'b000: alu_out = (ex_op == `OP_OP32 && alt) ? {{32{w_diff[31]}}, w_diff} : {{32{w_sum[31]}}, w_sum};
        3'b001: alu_out = {{32{w_sll[31]}}, w_sll};
        3'b101: alu_out = alt ? {{32{w_sra[31]}}, w_sra} : {{32{w_srl[31]}}, w_srl};
        default: alu_out = 64'd0;
      endcase
      `OP_LUI:   alu_out = imm_u;
      `OP_AUIPC: alu_out = ex_pc + imm_u;
      `OP_JAL, `OP_JALR: alu_out = ex_pc + ((ex_c && PIPE_FAULT != PF_C_LINK_LEN) ? 64'd2 : 64'd4);
      default: ;
    endcase
  end
  reg br_taken;
  always @(*) begin
    case (ex_f3)
      3'b000: br_taken = (a == b_reg);
      3'b001: br_taken = (a != b_reg);
      3'b100: br_taken = ($signed(a) <  $signed(b_reg));
      3'b101: br_taken = ($signed(a) >= $signed(b_reg));
      3'b110: br_taken = (a <  b_reg);
      3'b111: br_taken = (a >= b_reg);
      default: br_taken = 1'b0;
    endcase
  end
  wire        ex_taken  = ex_isjal || ex_isjalr || (ex_isbr && br_taken);
  wire [63:0] ex_target = ex_isjal ? (ex_pc + imm_j) : ex_isjalr ? ((a + imm_i) & ~64'd1) : (ex_pc + imm_b);
  // IALIGN = 32 in the P1 configuration; 16 with C (a target's bit 0 is always clear: JALR clears it, offsets are even)
  wire        ex_tmis   = ex_taken && ((PIPE_EXT_C != 0) ? ex_target[0] : (ex_target[1:0] != 2'b00));
  wire [63:0] ex_maddr  = a + (ex_isst ? imm_s : imm_i);
  reg ex_mmis;
  always @(*) case (ex_f3[1:0])
    2'b00: ex_mmis = 1'b0;
    2'b01: ex_mmis = ex_maddr[0];
    2'b10: ex_mmis = |ex_maddr[1:0];
    2'b11: ex_mmis = |ex_maddr[2:0];
  endcase
  // ---- M: the unchanged shared unit. One start per EX occupant, in the first cycle its operands are final and the
  // unit is idle; the occupant owns the result until it leaves EX. A WB flush removes the occupant and abandons the
  // unit through its own synchronous reset (tcpu_muldiv.v: "reset abandons the operation"), so a flushed operation
  // can never complete into a later instruction.
  wire        ex_ismd = ex_v && !ex_exc && !ex_irq && is_md(ex_insn);
  reg         ex_md_started, ex_md_have;
  reg  [63:0] ex_md_res;
  reg  [31:0] md_owner_seq;                  // simulation check: the EX occupant that started the unit
  wire        md_busy, md_done;
  wire [63:0] md_result;
  wire        ex_flushed_by_wb = wb_flush && !halted;
  wire        md_abort = ex_flushed_by_wb && (PIPE_FAULT != PF_MD_STALE_RESULT);
  wire        md_start = ex_ismd && !lu_haz && !md_busy && !ex_flushed_by_wb &&
                         (!ex_md_started || PIPE_FAULT == PF_MD_RESTART);
  wire [3:0]  md_op = (ex_insn[6:0] == `OP_OP) ? {1'b0, ex_f3} :
                      (ex_f3 == 3'b000) ? 4'd8 : (ex_f3 == 3'b100) ? 4'd9 : (ex_f3 == 3'b101) ? 4'd10 :
                      (ex_f3 == 3'b110) ? 4'd11 : 4'd12;
  // the result belongs to the occupant that started the unit (PF_MD_STALE_RESULT: to whoever is in EX)
  wire        md_claim = md_done && ex_ismd && !ex_md_have && (ex_md_started || PIPE_FAULT == PF_MD_STALE_RESULT);
  wire        md_have_now = ex_md_have || md_claim;
  wire [63:0] md_value = ex_md_have ? ex_md_res : md_result;
  // only an M build contains the unit: the P1 configuration elaborates, and names its sources, exactly as before
  generate
    if (PIPE_EXT_M != 0) begin : g_md
      tcpu_muldiv #(.FAULT_W_SEXT(FAULT_W_SEXT), .FAULT_MULH_SIGN(FAULT_MULH_SIGN)) muldiv (
        .clk(clk), .rst(rst || md_abort), .start(md_start), .op(md_op), .a(a), .b(b_reg),
        .busy(md_busy), .done(md_done), .result(md_result));
    end else begin : g_no_md
      assign md_busy = 1'b0; assign md_done = 1'b0; assign md_result = 64'd0;
    end
  endgenerate
  // computed from forwarded operands, so it is only meaningful when no load-use hazard holds EX
  wire ex_newexc = ex_v && !ex_exc && !ex_irq && !lu_haz && ((ex_tmis) || ((ex_isld || ex_isst) && ex_mmis));
  // serialisation: drain everything older AND everything already raised on the port
  wire walker_idle;     // Sv39: no walk and no walker port transaction, live or killed (assigned below)
  wire drained_true = !mem_v && !wb_v && !preq_valid && !pwait && (eng_st == E_IDLE) && walker_idle;
  // what EX actually waits for: the real drain, or a negative control's weakened one (the assertion keeps the real)
  wire drained      = (PIPE_FAULT == PF_CSR_NO_DRAIN) ? (!mem_v && !wb_v) :
                      (PIPE_FAULT == PF_DRAIN_NO_WALKER) ? (!mem_v && !wb_v && !preq_valid && !pwait && (eng_st == E_IDLE)) :
                      drained_true;
  wire ex_done = ex_v && (ex_exc || ex_irq || ex_newexc || (ex_serial ? drained : ex_ismd ? md_have_now : !lu_haz));
  wire mem_ready = !mem_v || mem_fire;
  wire ex_fire = ex_done && mem_ready;
  // the one-shot redirect: in the first cycle the operands are available, even while EX is held by MEM
  wire ex_redirect = ex_v && !ex_exc && !ex_irq && !ex_newexc && ex_taken && !lu_haz &&
                     (!ex_redirected || PIPE_FAULT == PF_REDIRECT_REPEAT) && !wb_flush;
  wire frozen = ex_serial;

  // ================================================================================================ ID
  wire [17:0] id_d = dec(id_insn, priv);
  assign id_rs1 = id_insn[19:15];
  assign id_rs2 = id_insn[24:20];
  wire wb_byp_ok = wb_v && !wb_irq && !wb_exc && wb_we && (PIPE_FAULT != PF_NO_WB_BYPASS);
  wire [63:0] id_a = (id_rs1 == 5'd0 && x0z) ? 64'd0 : (wb_byp_ok && wb_rd == id_rs1) ? wb_val : rf_rd1;
  wire [63:0] id_b = (id_rs2 == 5'd0 && x0z) ? 64'd0 : (wb_byp_ok && wb_rd == id_rs2) ? wb_val : rf_rd2;
  wire ex_ready = !ex_v || ex_fire;
  wire id_fire = id_v && ex_ready;
  // the exception the instruction carries into EX
  wire        id_ill = id_d[15];
  wire [63:0] id_ecause = (priv == 2'd3) ? `CAUSE_ECALL_M : (priv == 2'd1) ? 64'd9 : 64'd8;
  wire        id_xexc = id_exc || id_ill || id_d[5] || id_d[4];
  wire [63:0] id_xcause = id_exc ? id_cause : id_ill ? `CAUSE_ILLEGAL : id_d[5] ? id_ecause : `CAUSE_BREAKPOINT;
  wire [63:0] id_xtval  = id_exc ? id_tval  : id_ill ? {32'd0, id_insn} : id_d[5] ? 64'd0 : id_pc;

  // ================================================================================================ front end
  wire f1_pa_bad = (f1_pc[63:32] != 32'd0);
  wire f1_mis    = (PIPE_EXT_C != 0) ? f1_pc[0] : (f1_pc[1:0] != 2'b00);
  wire f2_cacheable;
  tcpu_cacheable cb (.pa(f2_pa), .cacheable(f2_cacheable));
  wire         ic_hit;
  wire [127:0] ic_line;
  reg          ic_fill;
  reg  [31:0]  ic_fill_pa;
  reg  [127:0] ic_fill_data;
  wire         ic_inval = wb_commit && wb_is_fencei;
  tcpu_icache #(.BYTES(ICACHE_BYTES), .LINE_BYTES(16)) icache (
    .clk(clk), .rst(rst), .invalidate(ic_inval), .pa(f2_pa), .hit(ic_hit), .line_data(ic_line),
    .fill(ic_fill), .fill_pa(ic_fill_pa), .fill_data(ic_fill_data));
  wire f2_look_hit = f2_v && f2_st == F2_LOOK && !f2_pfault && f2_cacheable && ICACHE_BYTES != 0 && ic_hit;
  wire f2_avail = f2_v && (f2_st == F2_READY || f2_look_hit || (f2_st == F2_LOOK && f2_pfault));
  wire [63:0] f2_word_now = f2_look_hit ? (f2_pc[3] ? ic_line[127:64] : ic_line[63:0]) : f2_word;
  wire [1:0]  f2_slots_now = (f2_st == F2_READY) ? f2_slots : (f2_pc[2] ? 2'b10 : (f2_pfault ? 2'b01 : 2'b11));
  wire        f2_bad_now = (f2_st == F2_LOOK && f2_pfault) || (f2_st == F2_READY && (f2_err || f2_pfault));
  wire [63:0] f2_bad_cause = f2_pfault ? f2_pcause : `CAUSE_INSN_ACCESS;
  // the front end is non-speculative when nothing older than F2 exists
  wire nonspec_f2 = !id_v && !ex_v && !mem_v && !wb_v && (fb_cnt == 3'd0);

  // interrupt attachment
  wire irq_inflight = (id_v && id_irq) || (ex_v && ex_irq) || (mem_v && mem_irq) || (wb_v && wb_irq);
  wire serial_in_flight = (ex_v && !ex_exc && !ex_irq && is_serial(ex_insn)) ||
                          (mem_v && !mem_exc && !mem_irq && is_serial(mem_insn)) ||
                          (wb_v && !wb_exc && !wb_irq && is_serial(wb_insn));
  wire can_irq = csr_irq_pending && !irq_inflight && !serial_in_flight && !halted;

  // the ID load: from the fetch buffer head, else bypassed from a ready F2
  wire id_space = !id_v || id_fire;
  wire fb_has = (fb_cnt != 3'd0);
  wire [63:0] fbh_pc = fbq_pc[fb_head];
  wire [31:0] fbh_insn = fbq_insn[fb_head];
  wire        fbh_exc = fbq_exc[fb_head];
  wire [63:0] fbh_cause = fbq_cause[fb_head], fbh_tval = fbq_tval[fb_head];
  wire [63:0] f2_base = {f2_pc[63:3], 3'b000};
  wire        f2_first_slot = f2_slots_now[0] ? 1'b0 : 1'b1;
  wire [63:0] f2_i0_pc = f2_base + {61'd0, f2_first_slot, 2'b00};
  wire [31:0] f2_i0 = f2_first_slot ? f2_word_now[63:32] : f2_word_now[31:0];
  wire        f2_two = (f2_slots_now == 2'b11);
  wire [63:0] f2_i1_pc = f2_base + 64'd4;
  wire [31:0] f2_i1 = f2_word_now[63:32];

  // ---- C: the parcel extractor (PIPE_EXT_C only). F2's 8-byte word holds four 16-bit parcels; up to two
  // instructions are taken per cycle starting at parcel f2_pos. A 32-bit instruction whose lower parcel is the
  // word's last is CARRIED: its lower parcel waits in fe_carry_* and the instruction completes with the first parcel
  // of the next (sequential) word -- across a word, a cache line or a page boundary alike. A fetch fault on the word
  // is one faulting instruction: with a carry, epc is the first parcel and mtval the second (the faulting address).
  reg         fe_carry_v;
  reg  [15:0] fe_carry_par;
  reg  [63:0] fe_carry_pc;
  reg  [1:0]  f2_pos;
  reg         f2_isnc;        // C: F2's word is uncached: it is read parcel by parcel, one instruction at a time
  reg         f2_ncp;         // C, uncached: the next parcel to read is the SECOND parcel of the instruction at f2_pos
  reg         f2_errsec;      // C, uncached: the access error was on that second parcel
  function [15:0] parcel; input [63:0] w; input [1:0] k; parcel = w[{k, 4'b0000} +: 16]; endfunction
  reg         cx_r0_v, cx_r1_v, cx_done, cx_cap, cx_use_carry;
  reg  [63:0] cx_r0_pc, cx_r1_pc, cx_r0_tval, cx_cap_pc;
  reg  [31:0] cx_r0_insn, cx_r1_insn;
  reg  [15:0] cx_cap_par, cx_lo;
  reg  [2:0]  cx_pos;
  always @(*) begin
    cx_r0_v = 1'b0; cx_r1_v = 1'b0; cx_done = 1'b0; cx_cap = 1'b0; cx_use_carry = 1'b0;
    cx_r0_pc = 64'd0; cx_r1_pc = 64'd0; cx_r0_tval = 64'd0; cx_cap_pc = 64'd0; cx_r0_insn = 32'd0; cx_r1_insn = 32'd0;
    cx_cap_par = 16'd0; cx_lo = 16'd0; cx_pos = {1'b0, f2_pos};
    if (f2_bad_now) begin
      cx_r0_v = 1'b1; cx_use_carry = fe_carry_v; cx_done = 1'b1;
      cx_r0_pc = fe_carry_v ? fe_carry_pc : (f2_base + {61'd0, f2_pos, 1'b0});
      cx_r0_tval = !fe_carry_v ? (f2_errsec ? cx_r0_pc + 64'd2 : cx_r0_pc) :
                   (PIPE_FAULT == PF_C_TVAL_FIRST) ? fe_carry_pc : (fe_carry_pc + 64'd2);
    end else begin
      // step 0: the carried instruction, or the one at f2_pos
      if (fe_carry_v) begin
        cx_r0_v = 1'b1; cx_use_carry = 1'b1; cx_r0_pc = fe_carry_pc; cx_r0_insn = {parcel(f2_word_now, 2'd0), fe_carry_par};
        cx_pos = 3'd1;
      end else begin
        cx_lo = parcel(f2_word_now, cx_pos[1:0]);
        if (cx_lo[1:0] != 2'b11) begin
          cx_r0_v = 1'b1; cx_r0_pc = f2_base + {60'd0, cx_pos, 1'b0}; cx_r0_insn = {16'd0, cx_lo}; cx_pos = cx_pos + 3'd1;
        end else if (cx_pos != 3'd3) begin
          cx_r0_v = 1'b1; cx_r0_pc = f2_base + {60'd0, cx_pos, 1'b0};
          cx_r0_insn = {parcel(f2_word_now, cx_pos[1:0] + 2'd1), cx_lo}; cx_pos = cx_pos + 3'd2;
        end else begin
          cx_cap = 1'b1; cx_cap_par = cx_lo; cx_cap_pc = f2_base + 64'd6; cx_pos = 3'd4;
        end
      end
      cx_r0_tval = cx_r0_pc;
      // step 1: the next instruction, if the word has one
      if (cx_r0_v && !cx_cap && cx_pos <= 3'd3 && !(NC_PARCEL && f2_isnc)) begin     // uncached: one at a time
        cx_lo = parcel(f2_word_now, cx_pos[1:0]);
        if (cx_lo[1:0] != 2'b11) begin
          cx_r1_v = 1'b1; cx_r1_pc = f2_base + {60'd0, cx_pos, 1'b0}; cx_r1_insn = {16'd0, cx_lo}; cx_pos = cx_pos + 3'd1;
        end else if (cx_pos != 3'd3) begin
          cx_r1_v = 1'b1; cx_r1_pc = f2_base + {60'd0, cx_pos, 1'b0};
          cx_r1_insn = {parcel(f2_word_now, cx_pos[1:0] + 2'd1), cx_lo}; cx_pos = cx_pos + 3'd2;
        end else begin
          cx_cap = 1'b1; cx_cap_par = cx_lo; cx_cap_pc = f2_base + 64'd6; cx_pos = 3'd4;
        end
      end
      cx_done = (cx_pos >= 3'd4);
    end
  end
  // ---- the records F2 offers this cycle: the C extractor's, or the P1 two-slot word's (identical to P1 when C = 0)
  wire        rec0_v    = (PIPE_EXT_C != 0) ? cx_r0_v    : 1'b1;
  wire [63:0] rec0_pc   = (PIPE_EXT_C != 0) ? cx_r0_pc   : f2_i0_pc;
  wire [31:0] rec0_insn = (PIPE_EXT_C != 0) ? cx_r0_insn : f2_i0;
  wire [63:0] rec0_tval = (PIPE_EXT_C != 0) ? cx_r0_tval : f2_i0_pc;
  wire        rec1_v    = (PIPE_EXT_C != 0) ? cx_r1_v    : f2_two;
  wire [63:0] rec1_pc   = (PIPE_EXT_C != 0) ? cx_r1_pc   : f2_i1_pc;
  wire [31:0] rec1_insn = (PIPE_EXT_C != 0) ? cx_r1_insn : f2_i1;
  wire        rec_done  = (PIPE_EXT_C != 0) ? cx_done    : 1'b1;
  // ---- C: the instruction entering ID is expanded by the unchanged decoder; ID..WB see the 32-bit form, and the
  // raw parcel and the length go with it (commit record, mtval, link, next pc). An illegal parcel stays raw, so the
  // decode rejects it (cause 2, mtval = the parcel).
  wire [31:0] idsrc_raw = fb_has ? fbh_insn : rec0_insn;
  wire        idsrc_exc = fb_has ? fbh_exc : f2_bad_now;
  wire        idsrc_c   = (PIPE_EXT_C != 0) && !idsrc_exc && (idsrc_raw[1:0] != 2'b11);
  wire [31:0] cd_insn;
  wire        cd_ill, cd_hint;
  generate
    if (PIPE_EXT_C != 0) begin : g_cdec
      tcpu_cdecode #(.FAULT_C_IMM(FAULT_C_IMM), .FAULT_C_REG(FAULT_C_REG)) cdec (
        .c(idsrc_raw[15:0]), .insn(cd_insn), .illegal(cd_ill), .hint(cd_hint));
    end else begin : g_no_cdec
      assign cd_insn = 32'd0; assign cd_ill = 1'b0; assign cd_hint = 1'b0;
    end
  endgenerate
  wire [31:0] idsrc_x = (idsrc_c && !cd_ill) ? cd_insn : idsrc_raw;

  // ================================================================================================ Sv39 (PIPE_EXT_SU)
  // Translation as in the reference core (tcpu_xlate.v): the TLB caches leaf PTE bits, the permission check
  // (the shared tcpu_permcheck) runs on every hit with the access's own type, privilege, SUM and MXR; a
  // non-canonical address never uses a hit; A/D are software-managed (A = 0, or D = 0 for a store, faults); only a
  // walk that produced a PA fills; every sfence.vma and satp write flushes the whole TLB.
  // Fetch: F1 translates its word (fetch privilege = priv; off in M). A miss starts a FETCH-side walk, speculative
  // unless nothing older is in flight (the wrapper then forwards only cacheable PTE addresses); F1 holds meanwhile.
  // Data: MEM translates on its first cycle (MPRV: the effective privilege is MPP). A miss starts a DATA-side walk
  // only when MEM holds the oldest instruction; it preempts a fetch walk (abort through the wrapper).
  // One walker (tcpu_ptw, unchanged, inside tcpu_ptw_wrap): a front-end flush or a serialisation freeze aborts a fetch
  // walk; a killed PTE transaction stays on the port until answered and is drained before a serialiser proceeds.
  localparam WK_NONE = 2'd0, WK_F = 2'd1, WK_D = 2'd2;
  reg  [1:0]  wk_own;                 // the walk in progress belongs to fetch (F1) or data (MEM)
  reg  [63:0] wk_va;                  // its virtual address (the TLB fill's tag)
  reg         wr_port_f;              // the wrapper's port transaction belongs to a fetch-side walk (owner metadata)
  reg         f1_wf_v;                // F1's walk faulted: the word goes to F2 as a fetch fault
  reg  [63:0] f1_wf_cause;
  reg         mem_xl_have;            // MEM's translation is done: its PA is in mem_pa_r (the TLB may change later)
  reg  [55:0] mem_pa_r;
  wire        su = (PIPE_EXT_SU != 0);
  // ---- the translation context (privilege and satp change only through serialising instructions and traps)
  wire        xf = su && csr_satp_mode && (priv != 2'd3);
  wire [1:0]  eff_priv_d = (csr_mprv && priv == 2'd3) ? csr_mpp : priv;
  assign      mem_xd = su && csr_satp_mode && (eff_priv_d != 2'd3);
  // ---- the TLB, both lookups, and the per-access permission checks
  wire        tlb_hit_f, tlb_hit_d;
  wire [43:0] tlb_ppn_f, tlb_ppn_d;
  wire [1:0]  tlb_lvl_f, tlb_lvl_d;
  wire [5:0]  tlb_perm_f, tlb_perm_d;
  wire        permok_f_raw, permok_d_raw;
  wire        wr_start_ok, wr_busy, wr_done, wr_fault;
  wire [3:0]  wr_cause;
  wire [55:0] wr_pa;
  wire [43:0] wr_leaf_ppn;
  wire [1:0]  wr_leaf_lvl;
  wire [5:0]  wr_leaf_perm;
  wire        wr_killed_pending, wr_unforwarded;
  wire        wk_abort, wk_start_f, wk_start_d;
  wire        tlb_flush = wb_commit && (wb_is_sfence || (wb_is_csr && csr_wi && csr_addr == 12'h180));
  wire        tlb_fill = su && wr_done && !wr_fault && (wk_own != WK_NONE);
  // ---- fetch translation of F1's word
  wire        f1_canon = (f1_pc[63:39] == {25{f1_pc[38]}});
  wire        permok_f = permok_f_raw || (PIPE_FAULT == PF_TLB_HIT_NO_PERM);
  wire [55:0] f1_hit_pa = (tlb_lvl_f == 2'd2) ? {tlb_ppn_f[43:18], f1_pc[29:0]} :
                          (tlb_lvl_f == 2'd1) ? {tlb_ppn_f[43:9], f1_pc[20:0]} : {tlb_ppn_f, f1_pc[11:0]};
  wire        f1_tr_pf    = xf && !f1_wf_v && (!f1_canon || (tlb_hit_f && !permok_f));   // page fault (12)
  wire        f1_tr_ready = !xf || f1_wf_v || !f1_canon || tlb_hit_f;
  wire        f1_tr_pabad = xf ? (!f1_wf_v && f1_canon && tlb_hit_f && permok_f && f1_hit_pa[55:32] != 24'd0 &&
                                  FAULT_PPN_TRUNC == 0) : f1_pa_bad;
  wire [31:0] f1_pa32 = xf ? f1_hit_pa[31:0] : f1_pc[31:0];
  wire        f1_fault = f1_mis || f1_tr_pf || (xf && f1_wf_v) || f1_tr_pabad;
  wire [63:0] f1_fcause = f1_mis ? `CAUSE_INSN_MISALIGNED : f1_tr_pf ? 64'd12 : (xf && f1_wf_v) ? f1_wf_cause : `CAUSE_INSN_ACCESS;
  // ---- data translation of MEM's access
  wire        d_canon = (mem_addr[63:39] == {25{mem_addr[38]}});
  wire        permok_d = permok_d_raw || (PIPE_FAULT == PF_TLB_HIT_NO_PERM);
  wire [55:0] d_hit_pa = (tlb_lvl_d == 2'd2) ? {tlb_ppn_d[43:18], mem_addr[29:0]} :
                         (tlb_lvl_d == 2'd1) ? {tlb_ppn_d[43:9], mem_addr[20:0]} : {tlb_ppn_d, mem_addr[11:0]};
  wire        mem_xl_need  = mem_v && !mem_exc && !mem_irq && mem_memop && mem_xd && !mem_xl_have;
  assign      mem_xl_pf    = mem_xl_need && (!d_canon || (tlb_hit_d && !permok_d));
  wire        mem_xl_hitok = mem_xl_need && d_canon && tlb_hit_d && permok_d;
  wire        mem_xl_miss  = mem_xl_need && d_canon && !tlb_hit_d;
  assign      mem_xl_ok = !mem_xd || mem_xl_have || mem_xl_hitok;
  assign      mem_pa = mem_xl_have ? mem_pa_r : mem_xd ? d_hit_pa : {24'd0, mem_addr[31:0]};
  // ---- the walker: a data walk (MEM oldest) preempts; a fetch walk is aborted by any front-end flush or freeze
  wire        irq_attach_w = id_space && !(wb_flush && !halted) && !ex_redirect && !fe_park && !halted && can_irq;
  wire        fe_flush_w   = (wb_flush && !halted) || ex_redirect || irq_attach_w;
  wire        nonspec_f1   = nonspec_f2 && !f2_v;
  wire        d_walk_req   = su && mem_xl_miss && oldest_true && !halted;
  wire        f_walk_req   = su && f1_v && xf && f1_canon && !tlb_hit_f && !f1_wf_v && !frozen && !fe_park && !halted;
  assign      wk_abort     = su && (((wk_own == WK_F) && (fe_flush_w || frozen || d_walk_req)) ||
                                    ((wk_own == WK_D) && (wb_flush && !halted)));
  assign      wk_start_d   = d_walk_req && (wk_own == WK_NONE) && wr_start_ok;
  assign      wk_start_f   = f_walk_req && !d_walk_req && (wk_own == WK_NONE) && wr_start_ok && !fe_flush_w;
  wire        wk_grant     = core_port_idle && !mem_alloc;          // MEM data first, then the walker, then refills
  generate
    if (PIPE_EXT_SU != 0) begin : g_sv39
      tcpu_tlb2 #(.ENTRIES(TLB_ENTRIES), .NO_FLUSH(PIPE_FAULT == PF_TLB_NO_FLUSH)) tlb (
        .clk(clk), .rst(rst), .flush(tlb_flush),
        .va_a(f1_pc), .hit_a(tlb_hit_f), .ppn_a(tlb_ppn_f), .lvl_a(tlb_lvl_f), .perm_a(tlb_perm_f),
        .va_b(mem_addr), .hit_b(tlb_hit_d), .ppn_b(tlb_ppn_d), .lvl_b(tlb_lvl_d), .perm_b(tlb_perm_d),
        .fill(tlb_fill && !tlb_flush), .fill_va(wk_va), .fill_level(wr_leaf_lvl), .fill_ppn(wr_leaf_ppn),
        .fill_perm(wr_leaf_perm));
      tcpu_permcheck pc_f (.acc_type(2'd0), .eff_priv(priv), .sum(csr_sum), .mxr(csr_mxr),
        .pte_r(tlb_perm_f[5]), .pte_w(tlb_perm_f[4]), .pte_x(tlb_perm_f[3]), .pte_u(tlb_perm_f[2]),
        .pte_a(tlb_perm_f[1]), .pte_d(tlb_perm_f[0]), .ok(permok_f_raw));
      tcpu_permcheck pc_d (.acc_type(mem_isst ? 2'd2 : 2'd1), .eff_priv(eff_priv_d), .sum(csr_sum), .mxr(csr_mxr),
        .pte_r(tlb_perm_d[5]), .pte_w(tlb_perm_d[4]), .pte_x(tlb_perm_d[3]), .pte_u(tlb_perm_d[2]),
        .pte_a(tlb_perm_d[1]), .pte_d(tlb_perm_d[0]), .ok(permok_d_raw));
      tcpu_ptw_wrap #(.FAULT_PTW_NO_PERM(FAULT_PTW_NO_PERM)) walk (
        .clk(clk), .rst(rst), .start(wk_start_d || wk_start_f),
        .va(wk_start_d ? mem_addr : f1_pc), .acc_type(wk_start_d ? (mem_isst ? 2'd2 : 2'd1) : 2'd0),
        .eff_priv(wk_start_d ? eff_priv_d : priv), .sum(csr_sum), .mxr(csr_mxr), .root_ppn(csr_satp_ppn),
        .spec((wk_own == WK_F) && !nonspec_f1), .abort(wk_abort), .grant(wk_grant),
        .start_ok(wr_start_ok), .busy(wr_busy), .done(wr_done), .fault(wr_fault), .cause(wr_cause), .pa(wr_pa),
        .leaf_ppn(wr_leaf_ppn), .leaf_level(wr_leaf_lvl), .leaf_perm(wr_leaf_perm), .taking_port(wr_taking_port),
        .req_valid(wr_req_valid), .req_ready(req_ready), .req_addr(wr_req_addr),
        .resp_valid(resp_valid), .resp_rdata(resp_rdata), .resp_error(resp_error),
        .dbg_killed_pending(wr_killed_pending), .dbg_unforwarded(wr_unforwarded), .port_busy(wr_port_busy));
    end else begin : g_no_sv39
      assign tlb_hit_f = 1'b0; assign tlb_ppn_f = 44'd0; assign tlb_lvl_f = 2'd0; assign tlb_perm_f = 6'd0;
      assign tlb_hit_d = 1'b0; assign tlb_ppn_d = 44'd0; assign tlb_lvl_d = 2'd0; assign tlb_perm_d = 6'd0;
      assign permok_f_raw = 1'b0; assign permok_d_raw = 1'b0;
      assign wr_start_ok = 1'b0; assign wr_busy = 1'b0; assign wr_done = 1'b0; assign wr_fault = 1'b0;
      assign wr_cause = 4'd0; assign wr_pa = 56'd0; assign wr_leaf_ppn = 44'd0; assign wr_leaf_lvl = 2'd0;
      assign wr_leaf_perm = 6'd0; assign wr_taking_port = 1'b0; assign wr_req_valid = 1'b0; assign wr_req_addr = 32'd0;
      assign wr_killed_pending = 1'b0; assign wr_unforwarded = 1'b0; assign wr_port_busy = 1'b0;
    end
  endgenerate
  // the walker's work, for a serialising instruction's drain (PF_DRAIN_NO_WALKER forgets it)
  assign      walker_idle = !wr_busy && !wr_port_busy && (wk_own == WK_NONE);

  // ================================================================================================ sequential
  integer k;
  // coverage (simulation only)
  reg [63:0] cv_redirect, cv_killed_resp, cv_irq_token, cv_irq_synth, cv_irq_cancel, cv_drain_wait, cv_loaduse,
             cv_fwd_exmem, cv_fwd_memwb, cv_wb_bypass, cv_two_flush, cv_nc_wait, cv_flush_pending_valid, cv_redirect_held,
             cv_irq_synth_ahead;
  reg [63:0] cv_walk_f, cv_walk_d, cv_walk_preempt, cv_walk_abort, cv_tlb_flush, cv_pte_killed;   // Sv39
  reg [7:0]  flushes_since_eng;
  reg        fe_flush_q;     // simulation check only: a front-end flush happened in the previous cycle
  reg [31:0] last_ret_seq;
  reg        ex_redir_count;

  always @(posedge clk) begin : seq
    reg        fe_flush, fe_kill;
    reg [63:0] fe_target;
    reg        take_from_fb, take_from_f2, f2_consumed;
    reg        push0, push1;
    reg [2:0]  cnt_n;
    reg [1:0]  head_n;
    reg [1:0]  tail;
    reg        new_id_v, new_id_irq, new_id_exc;
    reg [63:0] new_id_pc, new_id_cause, new_id_tval;
    reg [31:0] new_id_insn, new_id_raw;
    reg        new_id_c, f2_step;
    ic_fill <= 1'b0;
    if (rst) begin
      preq_valid <= 1'b0; pwait <= 1'b0; preq_owner_f <= 1'b0; preq_killed <= 1'b0; preq_addr <= 32'd0;
      preq_write <= 1'b0; preq_size <= 2'd0; preq_wdata <= 64'd0; preq_wmask <= 8'd0;
      withdrawn <= 1'b0; withdrawing <= 1'b0;
      fe_pc <= RESET_PC; fe_next_pc <= RESET_PC; fe_park <= 1'b0; fe_ep <= 1'b0;
      f1_v <= 1'b0; f1_pc <= 64'd0; f2_v <= 1'b0; f2_st <= F2_LOOK; f2_pc <= 64'd0; f2_pa <= 32'd0; f2_pfault <= 1'b0;
      f2_pcause <= 64'd0; f2_word <= 64'd0; f2_slots <= 2'b00; f2_err <= 1'b0;
      eng_st <= E_IDLE; eng_killed <= 1'b0; eng_ep <= 1'b0; eng_err <= 1'b0; eng_pa <= 32'd0; eng_buf0 <= 64'd0; eng_dsize <= 2'd0;
      fb_head <= 2'd0; fb_cnt <= 3'd0;
      id_v <= 1'b0; ex_v <= 1'b0; mem_v <= 1'b0; wb_v <= 1'b0; halted <= 1'b0; seq_ctr <= 32'd1;
      id_irq <= 1'b0; id_exc <= 1'b0; ex_irq <= 1'b0; ex_exc <= 1'b0; ex_redirected <= 1'b0;
      mem_irq <= 1'b0; mem_exc <= 1'b0; wb_irq <= 1'b0; wb_exc <= 1'b0; mem_st <= M_FIRST;
      cv_redirect <= 0; cv_killed_resp <= 0; cv_irq_token <= 0; cv_irq_synth <= 0; cv_irq_cancel <= 0;
      cv_drain_wait <= 0; cv_loaduse <= 0; cv_fwd_exmem <= 0; cv_fwd_memwb <= 0; cv_wb_bypass <= 0;
      cv_two_flush <= 0; cv_nc_wait <= 0; cv_flush_pending_valid <= 0; cv_redirect_held <= 0; cv_irq_synth_ahead <= 0;
      cv_walk_f <= 0; cv_walk_d <= 0; cv_walk_preempt <= 0; cv_walk_abort <= 0; cv_tlb_flush <= 0; cv_pte_killed <= 0;
      flushes_since_eng <= 0; last_ret_seq <= 32'd0; fe_flush_q <= 1'b0;
      ex_md_started <= 1'b0; ex_md_have <= 1'b0; ex_md_res <= 64'd0; md_owner_seq <= 32'd0;
      fe_carry_v <= 1'b0; fe_carry_par <= 16'd0; fe_carry_pc <= 64'd0; f2_pos <= 2'd0;
      f2_isnc <= 1'b0; f2_ncp <= 1'b0; f2_errsec <= 1'b0;
      wk_own <= WK_NONE; wk_va <= 64'd0; wr_port_f <= 1'b0; f1_wf_v <= 1'b0; f1_wf_cause <= 64'd0;
      mem_xl_have <= 1'b0; mem_pa_r <= 56'd0;
      id_raw <= 32'd0; ex_raw <= 32'd0; mem_raw <= 32'd0; wb_raw <= 32'd0; id_c <= 1'b0; ex_c <= 1'b0; mem_c <= 1'b0; wb_c <= 1'b0;
    end else begin
      fe_flush = 1'b0; fe_kill = 1'b0; fe_target = fe_pc;
      // ---- fetch-transaction ownership (CONTRACT rev. 3 section 3.1): a fetch request is raised or outstanding exactly
      // when the engine waits for it, and the request and the engine agree on whether it is killed. A flushed refill
      // fills nothing, including one whose final beat answers in the flush cycle itself.
      if ((preq_owner_f && (preq_valid || pwait)) != (eng_st == E_WAIT0 || eng_st == E_WAIT1 || eng_st == E_WAITD))
        $display("PIPE ASSERT fetch-owner: fetch request valid=%0d outstanding=%0d, fetch engine state %0d",
                 preq_owner_f && preq_valid, preq_owner_f && pwait, eng_st);
      else if (PIPE_FAULT != PF_EPOCH_BIT && preq_owner_f && (preq_valid || pwait) && preq_killed != eng_killed)
        $display("PIPE ASSERT fetch-owner: request killed=%0d, engine killed=%0d", preq_killed, eng_killed);
      if (ic_fill && fe_flush_q)
        $display("PIPE ASSERT fill-after-flush: line 0x%08x filled from a refill answered in a flush cycle", ic_fill_pa);

      // ---------------------------------------------------------------- port: handshake and response
      if (REQ_WITHDRAW != 0 && preq_valid && !req_ready && !withdrawn && !preq_owner_f) begin
        withdrawing <= 1'b1; withdrawn <= 1'b1;                 // monitor self-test only
      end else withdrawing <= 1'b0;
      if (port_fire) begin preq_valid <= 1'b0; pwait <= 1'b1; end
      if (port_resp) begin
        pwait <= 1'b0; preq_killed <= 1'b0;
        if (preq_owner_f) begin : fresp
          reg dead;
          dead = (PIPE_FAULT == PF_EPOCH_BIT) ? (eng_ep != fe_ep) : (preq_killed || eng_killed);
          if (dead) begin
            eng_st <= E_IDLE; eng_killed <= 1'b0; cv_killed_resp <= cv_killed_resp + 1;
            if (flushes_since_eng >= 2) cv_two_flush <= cv_two_flush + 1;
          end else if (eng_st == E_WAIT0) begin
            eng_buf0 <= resp_rdata; eng_err <= resp_error; eng_st <= E_NEED1;
          end else if (eng_st == E_WAIT1 || eng_st == E_WAITD) begin
            // deliver to F2 (it is the requester: a live engine belongs to the current F2)
            if (!(f2_v && f2_st == F2_WAIT && f2_pa[31:4] == eng_pa[31:4])) begin
              $display("PIPE ASSERT fetch-delivery: engine line 0x%08x delivered, F2 %0s waiting for 0x%08x",
                       {eng_pa[31:4], 4'd0}, (f2_v && f2_st == F2_WAIT) ? "is" : "is NOT", {f2_pa[31:4], 4'd0});
            end
            if (f2_v && f2_st == F2_WAIT) begin
              f2_st <= F2_READY;
              if (eng_st == E_WAIT1) begin
                f2_word <= f2_pc[3] ? resp_rdata : eng_buf0;
                f2_slots <= f2_pc[2] ? 2'b10 : 2'b11;
                f2_err <= eng_err || resp_error;
                if (!(eng_err || resp_error)) begin
                  ic_fill <= 1'b1; ic_fill_pa <= {eng_pa[31:4], 4'd0}; ic_fill_data <= {resp_rdata, eng_buf0};
                end
              end else if (eng_dsize == 2'd1) begin : nc_parcel
                // C, uncached: one parcel, in its lane of the word; ask for the second parcel only if this one opens
                // a 32-bit instruction inside the word (at the word's last parcel the carry takes over)
                reg [15:0] par;
                par = resp_rdata[{eng_pa[2:1], 4'b0000} +: 16];
                f2_word[{eng_pa[2:1], 4'b0000} +: 16] <= par;
                if (resp_error) begin f2_err <= 1'b1; f2_errsec <= f2_ncp; end
                else if (!fe_carry_v && !f2_ncp && f2_pos != 2'd3 && par[1:0] == 2'b11) begin f2_ncp <= 1'b1; f2_st <= F2_NC; end
              end else begin
                f2_word <= resp_rdata;
                f2_slots <= (eng_dsize == 2'd3) ? (f2_pc[2] ? 2'b10 : 2'b11) : (f2_pc[2] ? 2'b10 : 2'b01);
                f2_err <= resp_error;
              end
            end
            eng_st <= E_IDLE;
          end
        end else begin
          if (!(mem_v && mem_st == M_PEND))
            $display("PIPE ASSERT data-response: a data response arrived with no MEM requester waiting");
        end
      end

      // ---------------------------------------------------------------- WB
      if (wb_v) begin
        if (wb_seq <= last_ret_seq && !wb_irq_cancel)
          $display("PIPE ASSERT once-only: seq %0d retired again (pc 0x%0h)", wb_seq, wb_pc);
        if (wb_commit || wb_trap_take) last_ret_seq <= wb_seq;
        if (wb_trap_take && STOP_ON_TRAP != 0) halted <= 1'b1;
        if (wb_irq_cancel) cv_irq_cancel <= cv_irq_cancel + 1;
      end
      if (!wb_hold) wb_v <= 1'b0;
      if (wb_flush && !halted) begin fe_flush = 1'b1; fe_target = wb_flush_to; end

      // ---------------------------------------------------------------- MEM
      if (mem_v && mem_st == M_FIRST && mem_want_req && !mem_alloc) mem_st <= M_ISSUE;
      if (mem_alloc) begin
        if (!oldest_true) $display("PIPE ASSERT oldest-issue: data request for pc 0x%0h raised while WB (pc 0x%0h) does not commit cleanly", mem_pc, wb_pc);
        preq_valid <= 1'b1; preq_owner_f <= 1'b0; preq_killed <= 1'b0;
        preq_addr <= mem_pa[31:0]; preq_write <= mem_isst; preq_size <= mem_f3[1:0];
        preq_wdata <= (mem_isst || LOAD_WDATA_LEAK != 0) ? (mem_sdata << mem_lsh) : 64'd0;
        preq_wmask <= mem_isst ? (mem_mbase << mem_addr[2:0]) : 8'd0;
        if (!wb_flush) mem_st <= M_PEND;
      end
      // ---- Sv39: MEM keeps its translation once known (a later fill may evict the TLB entry)
      if (mem_xl_hitok) begin mem_xl_have <= 1'b1; mem_pa_r <= d_hit_pa; end
      // ---- the walker: start, abort, result
      if (wr_taking_port) wr_port_f <= (wk_own == WK_F);
      if (wk_start_d) cv_walk_d <= cv_walk_d + 1;
      if (wk_start_f) cv_walk_f <= cv_walk_f + 1;
      if (wk_abort && d_walk_req) cv_walk_preempt <= cv_walk_preempt + 1;
      if (wk_abort) cv_walk_abort <= cv_walk_abort + 1;
      if (wk_abort && wr_port_busy && !wr_killed_pending) cv_pte_killed <= cv_pte_killed + 1;   // a PTE transaction killed
      if (tlb_flush) cv_tlb_flush <= cv_tlb_flush + 1;
      if (wk_start_d) begin wk_own <= WK_D; wk_va <= mem_addr; end
      else if (wk_start_f) begin wk_own <= WK_F; wk_va <= f1_pc; end
      if (wk_abort) wk_own <= WK_NONE;
      else if (wr_done && wk_own != WK_NONE) begin
        wk_own <= WK_NONE;
        if (wr_fault) begin
          if (wk_own == WK_F) begin f1_wf_v <= 1'b1; f1_wf_cause <= {60'd0, wr_cause}; end
          else begin mem_exc <= 1'b1; mem_cause <= {60'd0, wr_cause}; mem_tval <= mem_addr; end
        end
      end
      if (mem_v && mem_st == M_PEND && mem_resp_now) begin
        mem_st <= M_DONE;
        if (resp_error) begin mem_exc <= 1'b1; mem_cause <= mem_isst ? `CAUSE_STORE_ACCESS : `CAUSE_LOAD_ACCESS; mem_tval <= mem_addr; end
        else if (mem_isld) mem_res <= ld_val;
      end
      if (mem_fire) begin
        wb_v <= 1'b1; wb_seq <= mem_seq; wb_pc <= mem_pc; wb_insn <= mem_insn; wb_irq <= mem_irq; wb_raw <= mem_raw; wb_c <= mem_c;
        wb_rd <= mem_rd; wb_src <= mem_sdata;
        if (mem_bad_now) begin
          // a page fault (Sv39) or a physical address outside the 32-bit space; mtval = the virtual address
          wb_exc <= 1'b1; wb_tval <= mem_addr;
          wb_cause <= mem_xl_pf ? (mem_isst ? 64'd15 : 64'd13) : (mem_isst ? `CAUSE_STORE_ACCESS : `CAUSE_LOAD_ACCESS);
          wb_we <= 1'b0; wb_val <= 64'd0;
        end else if (mem_st == M_PEND && mem_resp_now) begin
          wb_exc <= resp_error; wb_cause <= mem_isst ? `CAUSE_STORE_ACCESS : `CAUSE_LOAD_ACCESS; wb_tval <= mem_addr;
          wb_we <= mem_we && !resp_error; wb_val <= mem_isld ? ld_val : mem_res;
        end else begin
          wb_exc <= mem_exc; wb_cause <= mem_cause; wb_tval <= mem_tval; wb_we <= mem_we && !mem_exc; wb_val <= mem_res;
        end
        mem_v <= 1'b0;
      end

      // ---------------------------------------------------------------- EX
      if (ex_v && ex_serial && !drained_true) cv_drain_wait <= cv_drain_wait + 1;
      if (ex_v && lu_haz_true) cv_loaduse <= cv_loaduse + 1;
      if (ex_fire && ex_serial && !drained_true) $display("PIPE ASSERT drain: serialising pc 0x%0h left EX with the port or fetch engine busy", ex_pc);
      if (ex_fire && lu_haz_true) $display("PIPE ASSERT load-use: pc 0x%0h left EX with its load producer still in MEM", ex_pc);
`ifndef SYNTHESIS
      if ((PIPE_FAULT == PF_NO_FWD_EXMEM || PIPE_FAULT == PF_NO_FWD_MEMWB || PIPE_FAULT == PF_X0_FWD) && ex_fire && !ex_exc && !ex_irq &&
          ((uses_rs1(ex_insn) && fa[63:0] != fa_true[63:0]) || (uses_rs2(ex_insn) && fb[63:0] != fb_true[63:0])))
        $display("PIPE FAULT-EFFECT knob=%0d pc=%h: the operand used differs from the correct forwarded value", PIPE_FAULT, ex_pc);
      if (PIPE_FAULT == PF_NO_WB_BYPASS && id_fire && !id_irq &&
          ((uses_rs1(id_insn) && id_rs1 != 5'd0 && wb_v && !wb_irq && !wb_exc && wb_we && wb_rd == id_rs1 && rf_rd1 != wb_val) ||
           (uses_rs2(id_insn) && id_rs2 != 5'd0 && wb_v && !wb_irq && !wb_exc && wb_we && wb_rd == id_rs2 && rf_rd2 != wb_val)))
        $display("PIPE FAULT-EFFECT knob=%0d pc=%h: the operand read in ID misses the value retiring in WB", PIPE_FAULT, id_pc);
`endif
      if (ex_v && !ex_fire) begin ex_a <= a; ex_b <= b_reg; end      // hold: keep the forwarded values current
      // ---- M: start once, claim the result once; both belong to this EX occupant only
      if (md_start) begin
        if (ex_md_started) $display("PIPE ASSERT md-once: seq %0d (pc 0x%0h) started the mul/div unit a second time", ex_seq, ex_pc);
        ex_md_started <= 1'b1; md_owner_seq <= ex_seq;
      end
      if (md_claim) begin
        if (!ex_md_started || md_owner_seq != ex_seq)
          $display("PIPE ASSERT md-owner: seq %0d (pc 0x%0h) took a mul/div result it did not start", ex_seq, ex_pc);
        ex_md_have <= 1'b1; ex_md_res <= md_result;
      end
      if (ex_redirect && !fe_flush) begin
        if (ex_redirected) $display("PIPE ASSERT redirect-once: pc 0x%0h redirected again", ex_pc);
        ex_redirected <= 1'b1; cv_redirect <= cv_redirect + 1;
        if (!ex_fire) cv_redirect_held <= cv_redirect_held + 1;
        fe_flush = 1'b1; fe_kill = 1'b1; fe_target = ex_target;
      end
      if (ex_fire) begin
        mem_v <= 1'b1; mem_seq <= ex_seq; mem_pc <= ex_pc; mem_insn <= ex_insn; mem_irq <= ex_irq; mem_raw <= ex_raw; mem_c <= ex_c;
        mem_exc <= ex_exc || ex_newexc;
        mem_cause <= ex_exc ? ex_cause : ex_tmis ? `CAUSE_INSN_MISALIGNED : ex_isst ? `CAUSE_STORE_MISALIGNED : `CAUSE_LOAD_MISALIGNED;
        mem_tval  <= ex_exc ? ex_tval  : ex_tmis ? ex_target : ex_maddr;
        mem_isld <= ex_isld && !ex_exc && !ex_irq && !ex_newexc; mem_isst <= ex_isst && !ex_exc && !ex_irq && !ex_newexc;
        mem_we <= writes_rd(ex_insn) && !ex_exc && !ex_irq && !ex_newexc;
        mem_rd <= ex_insn[11:7]; mem_res <= ex_ismd ? md_value : alu_out; mem_addr <= ex_maddr; mem_sdata <= ex_isst ? b_reg : a;
        mem_st <= M_FIRST; mem_xl_have <= 1'b0;
        ex_v <= 1'b0; ex_redirected <= 1'b0; ex_md_started <= 1'b0; ex_md_have <= 1'b0;
      end
      if (ex_v) begin
        if (fa[64] == 1'b0 && mem_fwd_ok && mem_rd == ex_rs1 && uses_rs1(ex_insn) && ex_rs1 != 5'd0) cv_fwd_exmem <= cv_fwd_exmem + 1;
        if (wb_fwd_ok && wb_rd == ex_rs1 && !(mem_fwd_ok && mem_rd == ex_rs1) && uses_rs1(ex_insn) && ex_rs1 != 5'd0) cv_fwd_memwb <= cv_fwd_memwb + 1;
      end

      // ---------------------------------------------------------------- ID -> EX
      if (id_fire) begin
        ex_v <= 1'b1; ex_seq <= id_seq; ex_pc <= id_pc; ex_insn <= id_insn; ex_irq <= id_irq; ex_raw <= id_raw; ex_c <= id_c;
        ex_exc <= !id_irq && id_xexc; ex_cause <= id_xcause; ex_tval <= id_xtval;
        ex_a <= id_a; ex_b <= id_b; ex_redirected <= 1'b0; ex_md_started <= 1'b0; ex_md_have <= 1'b0;
        if (wb_byp_ok && ((wb_rd == id_rs1 && id_rs1 != 5'd0) || (wb_rd == id_rs2 && id_rs2 != 5'd0))) cv_wb_bypass <= cv_wb_bypass + 1;
        id_v <= 1'b0;
      end

      // ---------------------------------------------------------------- the ID load (and interrupt attachment)
      take_from_fb = 1'b0; take_from_f2 = 1'b0; f2_consumed = 1'b0;
      new_id_v = 1'b0; new_id_irq = 1'b0; new_id_exc = 1'b0; new_id_pc = 64'd0; new_id_insn = 32'd0;
      new_id_cause = 64'd0; new_id_tval = 64'd0; new_id_raw = 32'd0; new_id_c = 1'b0;
      if (id_space && !fe_flush && !fe_park && !halted) begin
        if (fb_has) begin
          take_from_fb = 1'b1; new_id_v = 1'b1; new_id_pc = fbh_pc; new_id_insn = idsrc_x; new_id_raw = idsrc_raw; new_id_c = idsrc_c;
          new_id_exc = fbh_exc; new_id_cause = fbh_cause; new_id_tval = fbh_tval;
        end else if (f2_avail && rec0_v) begin
          take_from_f2 = 1'b1; new_id_v = 1'b1; new_id_pc = rec0_pc; new_id_insn = idsrc_x; new_id_raw = idsrc_raw; new_id_c = idsrc_c;
          new_id_exc = f2_bad_now; new_id_cause = f2_bad_cause; new_id_tval = rec0_tval;
        end
        if (can_irq) begin
          if (new_id_v) begin
            new_id_irq = 1'b1; cv_irq_token <= cv_irq_token + 1;
          end else begin
            // no instruction to attach to: synthesise a token at the architectural next pc
            new_id_v = 1'b1; new_id_irq = 1'b1; new_id_insn = 32'h00000013; new_id_raw = 32'h00000013; new_id_c = 1'b0;
            new_id_pc = (PIPE_FAULT == PF_IRQ_EPC_FETCHPTR) ? (f1_v ? f1_pc : fe_pc) : fe_next_pc;
            cv_irq_synth <= cv_irq_synth + 1;
            if ((f1_v ? f1_pc : fe_pc) != fe_next_pc) cv_irq_synth_ahead <= cv_irq_synth_ahead + 1;   // the fetch pointer is ahead
          end
          fe_flush = 1'b1; fe_kill = 1'b1;               // park the front end behind the token
        end
      end
      if (new_id_v) begin
        id_v <= 1'b1; id_seq <= seq_ctr; seq_ctr <= seq_ctr + 32'd1;
        id_pc <= new_id_pc; id_insn <= new_id_insn; id_irq <= new_id_irq; id_raw <= new_id_raw; id_c <= new_id_c;
        id_exc <= new_id_exc && !new_id_irq; id_cause <= new_id_cause; id_tval <= new_id_tval;
        fe_next_pc <= new_id_pc + (new_id_c ? 64'd2 : 64'd4);
      end

      // ---------------------------------------------------------------- F2 / FB bookkeeping
      cnt_n = fb_cnt; head_n = fb_head;
      if (take_from_fb) begin cnt_n = cnt_n - 3'd1; head_n = head_n + 2'd1; end
      push0 = 1'b0; push1 = 1'b0; f2_step = 1'b0;
      if (f2_avail && !fe_flush) begin
        if (take_from_f2) begin
          push1 = rec1_v; f2_step = 1'b1;                         // the buffer is empty when the bypass is used
        end else if ({1'b0, cnt_n} + {3'd0, rec0_v} + {3'd0, rec1_v} <= 4'd4) begin
          push0 = rec0_v; push1 = rec1_v; f2_step = 1'b1;
        end
      end
      // the word is finished, or (C) it still has parcels and stays in F2 at its next position
      if (f2_step) begin
        if (rec_done) f2_consumed = 1'b1;
        else begin
          f2_pos <= cx_pos[1:0];
          if (NC_PARCEL && f2_isnc) begin f2_st <= F2_NC; f2_ncp <= 1'b0; f2_err <= 1'b0; f2_errsec <= 1'b0; end
        end
        if (PIPE_EXT_C != 0) begin
          if (cx_use_carry) fe_carry_v <= 1'b0;
          if (cx_cap && PIPE_FAULT != PF_C_CARRY_DROP) begin fe_carry_v <= 1'b1; fe_carry_par <= cx_cap_par; fe_carry_pc <= cx_cap_pc; end
        end
      end
      tail = head_n + cnt_n[1:0];
      if (push0) begin
        fbq_pc[tail] <= rec0_pc; fbq_insn[tail] <= rec0_insn; fbq_exc[tail] <= f2_bad_now;
        fbq_cause[tail] <= f2_bad_cause; fbq_tval[tail] <= rec0_tval;
      end
      if (push1) begin
        fbq_pc[tail + {1'b0, push0}] <= rec1_pc; fbq_insn[tail + {1'b0, push0}] <= rec1_insn; fbq_exc[tail + {1'b0, push0}] <= f2_bad_now;
        fbq_cause[tail + {1'b0, push0}] <= f2_bad_cause; fbq_tval[tail + {1'b0, push0}] <= rec1_pc;
      end
      fb_cnt <= cnt_n + {2'd0, push0} + {2'd0, push1}; fb_head <= head_n;

      // ---------------------------------------------------------------- F2
      if (f2_v && !f2_consumed) begin
        if (f2_st == F2_LOOK && !f2_pfault) begin
          if (f2_cacheable && ICACHE_BYTES != 0) begin
            if (ic_hit) begin f2_st <= F2_READY; f2_word <= f2_word_now; f2_slots <= f2_slots_now; f2_err <= 1'b0; end
            else f2_st <= F2_WAIT;
          end else if (f2_cacheable) f2_st <= F2_WAIT;          // direct 8-byte read of cacheable RAM, speculative
          else begin f2_st <= F2_NC; f2_isnc <= 1'b1; end         // uncached: only when non-speculative
        end else if (f2_st == F2_LOOK && f2_pfault) begin
          f2_st <= F2_READY; f2_slots <= f2_slots_now; f2_err <= 1'b0;
        end
      end
      if (f2_consumed) f2_v <= 1'b0;

      // start the engine for F2 (not while frozen; one engine, idle only)
      if (f2_v && !f2_consumed && !frozen && !fe_flush && eng_st == E_IDLE) begin
        if (f2_st == F2_WAIT) begin
          eng_pa <= f2_pa; eng_killed <= 1'b0; eng_ep <= fe_ep; eng_err <= 1'b0; flushes_since_eng <= 0;
          if (f2_cacheable && ICACHE_BYTES != 0) eng_st <= E_NEED0;
          else begin eng_st <= E_NEEDD; eng_dsize <= 2'd3; end
        end else if (f2_st == F2_NC) begin
          if (nonspec_f2 || PIPE_FAULT == PF_SPEC_MMIO_FETCH) begin
            if (!nonspec_f2) $display("PIPE ASSERT spec-uncached: uncached fetch of 0x%0h raised while the front end is speculative", f2_pc);
            // C: exactly the parcel needed now (the first of the instruction at f2_pos, or its second); without C
            // the 4-byte instruction; PF_C_NC_WORD: the whole 8-byte word
            eng_pa <= NC_PARCEL ? ({f2_pa[31:3], 3'b000} + {29'd0, f2_pos + {1'b0, f2_ncp}, 1'b0}) : f2_pa;
            eng_killed <= 1'b0; eng_ep <= fe_ep; eng_err <= 1'b0; flushes_since_eng <= 0;
            eng_st <= E_NEEDD; eng_dsize <= NC_PARCEL ? 2'd1 : (PIPE_EXT_C != 0) ? 2'd3 : 2'd2; f2_st <= F2_WAIT;
          end else cv_nc_wait <= cv_nc_wait + 1;
        end
      end
      // the engine takes the port when MEM does not (MEM has priority). Never in a flush cycle: the flush below
      // drops an engine with nothing outstanding, so a request raised now would be left with no owner and no kill
      // (the request is not yet visible on the port, so nothing is withdrawn).
      if (!mem_alloc && port_free && !frozen && !(fe_flush && PIPE_FAULT != PF_FLUSH_ALLOC) &&
          !(PIPE_FAULT != PF_EPOCH_BIT && eng_killed)) begin
        if (eng_st == E_NEED0 || eng_st == E_NEED1) begin
          preq_valid <= 1'b1; preq_owner_f <= 1'b1; preq_killed <= 1'b0; preq_write <= 1'b0; preq_size <= 2'd3;
          preq_addr <= {eng_pa[31:4], (eng_st == E_NEED1), 3'b000}; preq_wdata <= 64'd0; preq_wmask <= 8'd0;
          eng_st <= (eng_st == E_NEED0) ? E_WAIT0 : E_WAIT1;
        end else if (eng_st == E_NEEDD) begin
          preq_valid <= 1'b1; preq_owner_f <= 1'b1; preq_killed <= 1'b0; preq_write <= 1'b0; preq_size <= eng_dsize;
          preq_addr <= (eng_dsize == 2'd3) ? {eng_pa[31:3], 3'b000} : (eng_dsize == 2'd1) ? {eng_pa[31:1], 1'b0} : {eng_pa[31:2], 2'b00};
          preq_wdata <= 64'd0; preq_wmask <= 8'd0;
          eng_st <= E_WAITD;
        end
      end
      if (eng_killed && (eng_st == E_NEED0 || eng_st == E_NEED1 || eng_st == E_NEEDD))
        $display("PIPE ASSERT engine-state: the fetch engine is killed and still needs a request (it can never finish)");
      // serialisation freeze: an engine with nothing outstanding is abandoned
      if (frozen && (eng_st == E_NEED0 || eng_st == E_NEED1 || eng_st == E_NEEDD)) eng_st <= E_IDLE;

      // ---------------------------------------------------------------- F1
      if (f1_v && (!f2_v || f2_consumed) && !fe_flush && f1_tr_ready) begin
        f2_v <= 1'b1; f2_st <= F2_LOOK; f2_pc <= f1_pc; f2_pfault <= f1_fault; f2_pos <= f1_pc[2:1];
        // FAULT_IF2_NO_XLATE: the word completing a carried 32-bit instruction is fetched at the previous word's PA
        // + 8 instead of its own translation (the multicycle core's fault: the second parcel at the first PA + 2)
        // (the carry is pending: captured in this cycle's step, or earlier while this word's page was being walked)
        f2_pa <= (FAULT_IF2_NO_XLATE != 0 && xf && (fe_carry_v || (cx_cap && f2_step))) ? (f2_pa + 32'd8) : f1_pa32;
        f2_isnc <= 1'b0; f2_ncp <= 1'b0; f2_errsec <= 1'b0;
        f2_pcause <= f1_fcause; f2_err <= 1'b0; f1_wf_v <= 1'b0;
        f1_v <= 1'b0;
        if (!frozen && !fe_park && !halted) begin
          f1_v <= 1'b1; f1_pc <= fe_pc; fe_pc <= {fe_pc[63:3], 3'b000} + 64'd8;
        end
      end else if (!f1_v && !frozen && !fe_park && !halted && !fe_flush) begin
        f1_v <= 1'b1; f1_pc <= fe_pc; fe_pc <= {fe_pc[63:3], 3'b000} + 64'd8; f1_wf_v <= 1'b0;
      end

      // ---------------------------------------------------------------- flushes (applied last: they win)
      if (wb_flush && !halted) begin
        // everything younger than the retiring WB instruction, including what MEM handed to WB this cycle
        id_v <= 1'b0; ex_v <= 1'b0; mem_v <= 1'b0; wb_v <= 1'b0; ex_redirected <= 1'b0; mem_xl_have <= 1'b0;
        if (PIPE_FAULT != PF_MD_STALE_RESULT) begin ex_md_started <= 1'b0; ex_md_have <= 1'b0; end
      end
      if (ex_redirect && !(wb_flush && !halted) && ex_fire) begin
        // the branch moved to MEM this cycle; what ID handed to EX behind it is on the wrong path
        ex_v <= 1'b0; ex_md_started <= 1'b0; ex_md_have <= 1'b0;
      end
      if (fe_flush) begin
        // every younger fetch-side thing: F1, F2, the buffer; the raised or outstanding fetch transaction is killed
        f1_v <= 1'b0; f2_v <= 1'b0; fb_cnt <= 3'd0; fb_head <= 2'd0; fe_carry_v <= 1'b0; f1_wf_v <= 1'b0;
        if (!(wb_flush && !halted) && ex_redirect && !new_id_irq) id_v <= 1'b0;  // an EX redirect also removes ID
        fe_ep <= ~fe_ep;
        if (flushes_since_eng != 8'hff) flushes_since_eng <= flushes_since_eng + 8'd1;
        if (PIPE_FAULT != PF_EPOCH_BIT) begin
          // Kill only what is STILL outstanding after this cycle. A fetch response arriving in the flush cycle
          // itself completes that transaction now: the engine simply stops (nothing is left to drain). Killing it
          // instead left an engine that was both killed and "needing" its next beat -- never issued, never idle,
          // and every later drain waited for it forever (found by the hazard differential, hz22/28/29, run-1).
          if (preq_owner_f && (preq_valid || (pwait && !port_resp))) begin
            preq_killed <= 1'b1;
            if (preq_valid) cv_flush_pending_valid <= cv_flush_pending_valid + 1;
          end
          if ((eng_st == E_WAIT0 || eng_st == E_WAIT1 || eng_st == E_WAITD) && !(port_resp && preq_owner_f)) eng_killed <= 1'b1;
          else if (eng_st != E_IDLE) begin eng_st <= E_IDLE; eng_killed <= 1'b0; end
        end else begin
          if (!(eng_st == E_WAIT0 || eng_st == E_WAIT1 || eng_st == E_WAITD) && eng_st != E_IDLE) eng_st <= E_IDLE;
        end
        // a refill whose final beat answers in this cycle belongs to the flushed front end: it fills nothing
        if (PIPE_FAULT != PF_FLUSH_FILL) ic_fill <= 1'b0;
        if (new_id_irq) begin
          fe_park <= 1'b1;                                 // the token keeps its place in ID
        end else begin
          fe_park <= 1'b0;
          fe_pc <= fe_target; fe_next_pc <= fe_target;
          f1_v <= 1'b1; f1_pc <= fe_target; fe_pc <= {fe_target[63:3], 3'b000} + 64'd8;
          if (halted || (wb_trap_take && STOP_ON_TRAP != 0)) f1_v <= 1'b0;
        end
      end
      fe_flush_q <= fe_flush;
    end
  end

  // WB is loaded by MEM in the same always block; the ID stage after an EX redirect must not keep the instruction
  // it just loaded (it is younger than the branch) -- handled above by clearing id_v under fe_flush from EX.

  // ================================================================================================ observation
  // P2b owner metadata: a PTE read on the port is 13 (fetch-side walk) or 14 (data-side walk), so a harness never takes
  // a PTE read for a data access; 0 otherwise (and always 0 without Sv39: the accepted configurations are unchanged)
  assign dbg_state = (su && wr_port_busy) ? (wr_port_f ? 4'd13 : 4'd14) : 4'd0;
  assign dbg_redirect = 1'b0;
  assign dbg_pc = wb_v ? wb_pc : mem_v ? mem_pc : ex_v ? ex_pc : id_v ? id_pc : fe_next_pc;

`ifndef SYNTHESIS
  // +pipe-debug: one line per cycle with every stage's state (simulation only)
  reg dbg_on; reg [63:0] dbg_cyc;
  initial dbg_on = $test$plusargs("pipe-debug");
  always @(posedge clk) begin
    if (rst) dbg_cyc <= 0; else dbg_cyc <= dbg_cyc + 1;
    if (dbg_on && !rst)
      $display("PDBG %0d fe_pc=%h park=%0d f1=%0d:%h f2=%0d:%h st=%0d fb=%0d | id=%0d:%h%s ex=%0d:%h%s ser=%0d drn=%0d lu=%0d | mem=%0d:%h st=%0d | wb=%0d:%h | port v=%0d w=%0d f=%0d k=%0d eng=%0d ek=%0d frz=%0d",
               dbg_cyc, fe_pc, fe_park, f1_v, f1_pc, f2_v, f2_pc, f2_st, fb_cnt, id_v, id_pc, id_irq ? "!" : "",
               ex_v, ex_pc, ex_irq ? "!" : "", ex_serial, drained_true, lu_haz_true, mem_v, mem_pc, mem_st, wb_v, wb_pc,
               preq_valid, pwait, preq_owner_f, preq_killed, eng_st, eng_killed, frozen);
  end
  final begin
    $display("PIPE COVERAGE redirects=%0d redirect_while_held=%0d killed_fetch_responses=%0d killed_after_two_flushes=%0d flush_with_pending_valid=%0d irq_tokens=%0d irq_synthetic=%0d irq_synthetic_fetch_ahead=%0d irq_cancelled=%0d drain_wait_cycles=%0d loaduse_stall_cycles=%0d fwd_exmem=%0d fwd_memwb=%0d wb_bypass=%0d uncached_wait_cycles=%0d",
             cv_redirect, cv_redirect_held, cv_killed_resp, cv_two_flush, cv_flush_pending_valid, cv_irq_token, cv_irq_synth, cv_irq_synth_ahead,
             cv_irq_cancel, cv_drain_wait, cv_loaduse, cv_fwd_exmem, cv_fwd_memwb, cv_wb_bypass, cv_nc_wait);
    if (PIPE_EXT_SU != 0)
      $display("PIPE COVERAGE-SV39 fetch_walks=%0d data_walks=%0d walks_preempted_by_data=%0d walks_aborted=%0d pte_transactions_killed=%0d tlb_flushes=%0d",
               cv_walk_f, cv_walk_d, cv_walk_preempt, cv_walk_abort, cv_pte_killed, cv_tlb_flush);
  end
`endif
endmodule
