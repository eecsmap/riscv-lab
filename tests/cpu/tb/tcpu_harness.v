// M2-1: standalone CPU harness -- CPU -> PHYSICAL_PORT_V1 -> simple memory model. No SoC, no TileLink.
// The memory model NEVER answers in the request cycle (the contract's "no earlier than the next cycle"),
// and can delay both req.ready and resp.valid so the same program runs under several timing profiles.
`timescale 1ns/1ps
module tcpu_harness #(
  parameter        MEM_WORDS    = 1 << 16,     // 64K 64-bit words = 512 KiB at MEM_BASE
  parameter [31:0] MEM_BASE     = 32'h8000_0000,
  parameter        READY_DELAY  = 0,           // fixed cycles req.ready is held low
  parameter        RESP_DELAY   = 1,           // cycles from accept to response (>= 1)
  parameter        RANDOM       = 0,           // 1 = pseudo-random ready/response delays
  parameter        SEED         = 1,
  parameter        X0_WRITABLE  = 0,
  parameter        NO_LOAD_SEXT = 0,
  parameter        MEM_SAME_CYCLE = 0,   // monitor self-test: answer in the request handshake cycle
  parameter        REQ_WITHDRAW   = 0,   // monitor self-test: core withdraws a request before its handshake
  parameter        LOAD_WDATA_LEAK = 0,  // monitor self-test: a load carries a write payload
  parameter        TAIL_ERR       = 0,   // completion control: the write to fault_addr comes back with error
  parameter        TAIL_DROP      = 0,   // completion control: the write to fault_addr is never answered
  parameter        STOP_ON_TRAP   = 0,   // halt on the first trap so a directed test can observe it
  parameter        TRAP_BAD_MEPC  = 0,   // fault injection: mepc records the next instruction
  parameter        TRAP_COUNTS_RET = 0,  // fault injection: a trap bumps minstret
  parameter FAULT_W_SEXT = 0,      // CPU-M fault injection
  parameter FAULT_MULH_SIGN = 0,
  parameter FAULT_C_IMM = 0,       // CPU-C fault injection
  parameter FAULT_C_REG = 0,
  parameter FAULT_NO_DELEG = 0,     // CPU-SU fault injection
  parameter FAULT_S_IRQ_IN_M = 0,
  parameter FAULT_SRET_SPP = 0,
  parameter FAULT_PTW_NO_PERM = 0,  // CPU-SV39 fault injection
  parameter FAULT_IF2_NO_XLATE = 0,
  parameter FAULT_PPN_TRUNC = 0,
  parameter        CLINT_BASE     = 32'h0200_0000,  // CPU-SU: a precisely defined CLINT model (msip +0, mtimecmp +0x4000, mtime +0xBFF8)
  parameter        ALLOW_RO_WRITE = 0,   // fault injection: writes to read-only CSRs are let through
  parameter        EARLY_IRQ      = 0,   // fault injection: accept an interrupt during a committed access
  parameter        IRQ_BAD_MEPC   = 0,   // fault injection: the interrupt records the wrong mepc
  parameter        STALE_MIE      = 0,   // fault injection: decide on enables that have not landed
  parameter        FETCH_ERR_AFTER = 0,  // bus control: fetches fail with error once this many have passed
  parameter [31:0] FETCH_ERR_ADDR  = 0,  // CPU-C: a fetch of exactly this address fails (0 = none); aims at either parcel
  // ---- interrupt injection. IRQ_POINT names a microarchitectural moment; the line is raised the first
  // IRQ_TIMES times the core is in that moment and the line is low again. irq_hits counts how often the
  // moment occurred at all, so a run cannot claim coverage it did not have.
  parameter        IRQ_POINT      = 0,   // 0 none, 1 fetch req awaiting ready, 2 fetch response outstanding,
                                         // 3 data req awaiting ready, 4 data response outstanding,
                                         // 5 the writeback cycle, where the updates are scheduled,
                                         // 6 the writeback of a taken branch, jump or MRET,
                                         // 7 the architectural-boundary cycle, where they land
                                         // 8 (CPU-M) while a multiply/divide is in progress
                                         // 9 (CPU-C) second parcel requested and awaiting ready
                                         // 10 (CPU-C) second parcel response outstanding
                                         // 11 (CPU-SV39) a page-table read is outstanding or awaiting ready
                                         // 12 (CPU-A) an atomic has been accepted and its answer is outstanding
  parameter        IRQ_LINE       = 0,   // 0 = msip, 1 = mtip, 2 = meip
  parameter        IRQ_TIMES      = 1,   // bound: how many times the source is allowed to assert
  parameter        IRQ_AFTER      = 0,   // skip this many occurrences of the moment before raising the line
  parameter        IRQ_ARM_REQUIRED = 0, // when set, the injector stays disarmed until the program arms it
  parameter        IRQ_NEED_ENABLED = 0, // when set, only fire while MIE and the line's enable are in effect
  parameter        DUP_STORE      = 0,   // fault injection: apply the watched write twice
  parameter        IRQ_NEED_WRITE = 0,   // only fire while the in-flight access is a write to WATCH_ADDR
  parameter        IRQ_ALL_LINES  = 0,   // assert all three together, to exercise the priority order
  parameter [31:0] IRQ_MMIO_BASE  = 32'h6000_0000,
  // ---- CPU-A: the reservation/atomic memory model and an external writer that can race with it.
  // This model implements the frozen rules (cpu-a/DESIGN.md sections 2 and 5) at core level; the end-to-end
  // proof through the accepted backend is the SoC stage, not this one.
  parameter        EXT_POINT      = 0,   // 0 none; 1 = while the core's atomic request awaits ready,
                                         // 2 = while its response is outstanding, 3 = at a fixed cycle
  parameter        EXT_TIMES      = 1,   // bound: how many external writes the injector may perform
  parameter        EXT_AT_CYCLE   = 0,   // EXT_POINT 3: the cycle to write at
  parameter        EXT_AFTER      = 0,   // skip this many qualifying moments before the first write
  parameter [31:0] EXT_ADDR       = 32'h8000_0100,
  parameter [63:0] EXT_DATA       = 64'hAAAA_AAAA_AAAA_AAAA,
  parameter        FAULT_MODEL_NO_KILL = 0, // model fault injection: an external write leaves the reservation
  parameter        FAULT_MODEL_SC_ALWAYS_OK = 0, // model fault injection: every SC succeeds
  // ---- CPU-A: core fault injections, passed straight through to tcpu_core
  parameter        MISA_A = 0,                  // CPU-A: the core-level A tests build with -GMISA_A=1
  parameter        FAULT_A_W_NOSEXT = 0,
  parameter        FAULT_A_SC_RESULT = 0,
  parameter        FAULT_A_AMO_AS_LOAD = 0,
  parameter        FAULT_A_EARLY_RETIRE = 0,
  parameter        FAULT_A_NO_RESV_CLEAR = 0
) (
  input clk,
  input rst,
  // backdoor: ELF pre-load and tohost polling only; not part of PHYSICAL_PORT_V1
  input         bd_we,
  input  [15:0] bd_addr,
  input  [63:0] bd_data,
  input  [15:0] bd_rd_addr,
  output [63:0] bd_rd_data,
  input  [31:0] bd_fault_addr,     // the driver points this at the ELF's tohost word
  input  [31:0] bd_watch_addr,     // count transactions aimed at exactly this address (0 = none)
  // Two different questions, two different inputs: where to inject, and which instruction the ordered
  // chain is about. They differ at the architectural boundary, where the PC has already advanced.
  input  [63:0] bd_inject_pc,      // only inject while the PC is this (0 = any)
  // CPU-M closeout: a reset applied to the core (and therefore to the multiply/divide unit, which takes the
  // core's reset) and to nothing else -- the memory model, its counters and the injector keep running, which
  // is the existing memory reset boundary. Driven by the simulation main at a chosen moment.
  input         bd_core_rst,
  output [3:0]  cpu_state_o,       // the core's current state, so the main can aim at S_MUL
  output [63:0] cpu_pc_o,
  input  [4:0]  bd_reg_addr,       // architectural register read-back
  output [63:0] bd_reg_data,
  input  [4:0]  bd_csr_sel,        // architectural CSR read-back: the real registers, not the trap outputs
  output [63:0] bd_csr_data,
  output [1:0]  cpu_priv_o,        // CPU-SU: the current privilege level
  output        commit_valid,
  output [63:0] commit_pc,
  output [31:0] commit_insn,
  output [2:0]  commit_len,       // CPU-C: 2 or 4
  output        commit_rd_valid,
  output [4:0]  commit_rd,
  output [63:0] commit_rd_data,
  output        trap_valid,
  output        trap_interrupt,
  output [63:0] trap_cause,
  output [63:0] trap_epc,
  output [63:0] trap_tval,
  output        halted,
  output reg [63:0] proto_errors,
  output reg [63:0] n_req,
  output reg [63:0] n_resp,
  output reg [63:0] n_data_req,    // accepted requests that are NOT instruction fetches
  output reg [63:0] obs_errors,   // observation port disagreed with the architectural register file
  output reg [63:0] n_discard,    // CPU-C: responses the bridge model swallowed because the core was reset mid-transaction
  output reg [63:0] irq_hits,     // cycles the chosen injection moment occurred
  output reg [63:0] irq_fires,    // times the source was actually raised
  output reg [63:0] irq_clears,   // times software quieted the source through the test MMIO
  // ---- the context of the actual fire, latched once. Aggregate hit counts cannot show that an interrupt
  // arrived while the enables were really in effect, in the intended wait state, against a known instruction.
  output reg [63:0] fire_cycle,
  output reg [63:0] fire_pc,
  output reg [3:0]  fire_state,
  output reg        fire_enabled,
  output reg [1:0]  fire_priv,        // CPU-SU: the privilege level at the moment the line was raised
  output reg        fire_req_valid,
  output reg        fire_req_ready,
  output reg        fire_outstanding,
  output reg        fire_is_write,
  output reg [31:0] fire_addr,
  // ---- transactions aimed at one named address: requests, responses, and writes the model really applied
  output reg [63:0] watch_req,
  output reg [63:0] watch_wreq,
  output reg [63:0] watch_resp,
  output reg [63:0] watch_writes,
  // every write side effect at the watched address, as events with their own cycles
  output reg [63:0] apply_seq,
  output reg [63:0] apply1_cycle,
  output reg [63:0] apply2_cycle,
  output reg [63:0] apply1_data,
  output reg [63:0] apply2_data
);
  wire        req_valid, req_write, resp_ready;
  wire [31:0] req_addr;
  wire [1:0]  req_size;
  wire [63:0] req_wdata;
  wire [7:0]  req_wmask;
  wire [3:0]  req_amo;           // CPU-A (PHYSICAL_PORT_V2)
  wire [1:0]  req_lrsc;
  wire        resv_clear;
  reg         resp_scfail_r;
  wire        resp_scfail = resp_scfail_r;
  reg         req_ready, resp_valid_r, resp_error_r;
  reg  [63:0] resp_rdata_r;
  // MEM_SAME_CYCLE drives the response combinationally in the accept cycle. That is a real violation of
  // "no earlier than the next cycle"; a registered injection would only look like a legal 1-cycle response.
  wire same_cycle_inject = (MEM_SAME_CYCLE != 0) && req_valid && req_ready;
  wire        resp_valid = resp_valid_r | same_cycle_inject;
  wire        resp_error = same_cycle_inject ? !in_range : resp_error_r;
  wire [63:0] resp_rdata = same_cycle_inject ? (in_range ? mem[widx[15:0]] : 64'd0) : resp_rdata_r;

  tcpu_core #(.MISA_A(MISA_A), .FAULT_A_W_NOSEXT(FAULT_A_W_NOSEXT), .FAULT_A_SC_RESULT(FAULT_A_SC_RESULT),
              .FAULT_A_AMO_AS_LOAD(FAULT_A_AMO_AS_LOAD), .FAULT_A_EARLY_RETIRE(FAULT_A_EARLY_RETIRE),
              .FAULT_A_NO_RESV_CLEAR(FAULT_A_NO_RESV_CLEAR),
              .X0_WRITABLE(X0_WRITABLE), .NO_LOAD_SEXT(NO_LOAD_SEXT), .REQ_WITHDRAW(REQ_WITHDRAW),
                                       .LOAD_WDATA_LEAK(LOAD_WDATA_LEAK), .STOP_ON_TRAP(STOP_ON_TRAP),
                                       .TRAP_BAD_MEPC(TRAP_BAD_MEPC), .TRAP_COUNTS_RET(TRAP_COUNTS_RET), .FAULT_W_SEXT(FAULT_W_SEXT), .FAULT_MULH_SIGN(FAULT_MULH_SIGN), .FAULT_C_IMM(FAULT_C_IMM), .FAULT_C_REG(FAULT_C_REG),
                                       .FAULT_NO_DELEG(FAULT_NO_DELEG), .FAULT_S_IRQ_IN_M(FAULT_S_IRQ_IN_M), .FAULT_SRET_SPP(FAULT_SRET_SPP),
                                       .FAULT_PTW_NO_PERM(FAULT_PTW_NO_PERM), .FAULT_IF2_NO_XLATE(FAULT_IF2_NO_XLATE), .FAULT_PPN_TRUNC(FAULT_PPN_TRUNC),
                                       .ALLOW_RO_WRITE(ALLOW_RO_WRITE), .EARLY_IRQ(EARLY_IRQ),
                                       .IRQ_BAD_MEPC(IRQ_BAD_MEPC), .STALE_MIE(STALE_MIE)) cpu (
    .clk(clk), .rst(rst | bd_core_rst),
    .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr), .req_write(req_write),
    .req_size(req_size), .req_wdata(req_wdata), .req_wmask(req_wmask),
    .req_amo(req_amo), .req_lrsc(req_lrsc), .resp_scfail(resp_scfail), .resv_clear(resv_clear),
    .resp_valid(resp_valid), .resp_ready(resp_ready), .resp_rdata(resp_rdata), .resp_error(resp_error),
    .commit_valid(commit_valid), .commit_pc(commit_pc), .commit_insn(commit_insn), .commit_len(commit_len),
    .commit_rd_valid(commit_rd_valid), .commit_rd(commit_rd), .commit_rd_data(commit_rd_data),
    .trap_valid(trap_valid), .trap_interrupt(trap_interrupt), .trap_cause(trap_cause), .trap_epc(trap_epc),
    .trap_tval(trap_tval), .halted(halted), .dbg_req_is_fetch(req_is_fetch),
    .dbg_ra(dbg_ra), .dbg_rd(dbg_rd), .dbg_ra2(bd_reg_addr), .dbg_rd2(bd_reg_data),
    .dbg_csr_sel(bd_csr_sel), .dbg_csr_val(bd_csr_data), .dbg_priv(cpu_priv_o),
    .irq_msip(irq_msip | clint_msip), .irq_mtip(irq_mtip | clint_mtip), .irq_meip(irq_meip), .dbg_state(cpu_state),
    .dbg_redirect(cpu_redirect),
    .dbg_pc(cpu_pc), .dbg_irq_enabled(cpu_irq_enabled));
  wire [3:0] cpu_state;
  wire cpu_redirect, cpu_irq_enabled;
  wire [63:0] cpu_pc;
  assign cpu_state_o = cpu_state;
  assign cpu_pc_o = cpu_pc;
  wire req_is_fetch;
  reg  [4:0]  dbg_ra;          // driven by the observation-port cross-check below
  wire [63:0] dbg_rd;

  // ---- interrupt sources -----------------------------------------------
  // A source is a level. There is no sticky pending bit anywhere: once raised it stays raised until the
  // handler writes the test MMIO below, which is a stand-in for a platform interrupt controller and is not
  // a claim about CLINT or PLIC wiring.
  localparam S_IF_REQ_ = 4'd0, S_IF_WAIT_ = 4'd1, S_MEM_WAIT_ = 4'd4, S_WB_ = 4'd5, S_ARCH_ = 4'd8,
             S_MUL_ = 4'd9,   // CPU-M: the core is waiting for the multiply/divide unit
             S_IF2_REQ_ = 4'd10, S_IF2_WAIT_ = 4'd11,   // CPU-C: the second parcel of a 32-bit instruction
             S_XLATE_ = 4'd12;   // CPU-SV39: a page-table walk
  reg irq_msip, irq_mtip, irq_meip;
  reg [63:0] irq_raised;
  // Counting occurrences from reset is fragile: the startup code's own branches are occurrences too. A test
  // that needs the interrupt at a particular instruction arms the injector from software instead, by writing
  // the arm word, and then the very next occurrence is the one it meant.
  // Arming takes effect only once the core is back at a fetch boundary, so the arming store itself -- its
  // request phase, its response wait and its writeback -- can never be the moment that gets injected into.
  reg irq_armed, irq_arm_pending;
  wire irq_moment =
      (IRQ_POINT == 1) ? (cpu_state == S_IF_WAIT_  &&  req_valid && !req_ready) :
      (IRQ_POINT == 2) ? (cpu_state == S_IF_WAIT_  && !req_valid && !resp_valid) :
      // The request phase can look at the live request fields; the response phase must not, because they
      // no longer describe the outstanding transaction. It uses the metadata latched at the handshake.
      (IRQ_POINT == 3) ? (cpu_state == S_MEM_WAIT_ &&  req_valid && !req_ready &&
                          (IRQ_NEED_WRITE == 0 || (req_write && watch_hit))) :
      (IRQ_POINT == 4) ? (cpu_state == S_MEM_WAIT_ && !req_valid && !resp_valid &&
                          (IRQ_NEED_WRITE == 0 || (acc_write && (acc_addr == bd_watch_addr)))) :
      (IRQ_POINT == 5) ? (cpu_state == S_WB_) :
      (IRQ_POINT == 6) ? cpu_redirect :
      (IRQ_POINT == 7) ? (cpu_state == S_ARCH_) :
      (IRQ_POINT == 8) ? (cpu_state == S_MUL_) :          // CPU-M: during a long operation
      (IRQ_POINT == 9) ? (cpu_state == S_IF2_REQ_ || (cpu_state == S_IF2_WAIT_ && req_valid && !req_ready)) :
      (IRQ_POINT == 10) ? (cpu_state == S_IF2_WAIT_ && !req_valid && !resp_valid) :   // CPU-C: second parcel
      (IRQ_POINT == 11) ? (cpu_state == S_XLATE_ && busy && !resp_valid) :   // CPU-SV39: a PTE read accepted, its answer outstanding
      // CPU-A: 12 = an *atomic* has been accepted and its answer is outstanding. Naming the atomic rather
      // than "a data access" is what puts the interrupt inside the AMO and not inside a nearby store.
      (IRQ_POINT == 12) ? (cpu_state == S_MEM_WAIT_ && busy && !resp_valid &&
                           (acc_amo != 4'd0 || acc_lrsc != 2'd0)) : 1'b0;
  wire irq_any_high = irq_msip | irq_mtip | irq_meip;
  wire irq_mmio_hit = (req_addr & 32'hFFFF_F000) == IRQ_MMIO_BASE;
  // ---- CPU-SU: the CLINT model. A 64 KiB window: msip[0] at +0 (bit 0 of a 32-bit word), mtimecmp at
  // +0x4000 (64-bit), mtime at +0xBFF8 (64-bit, one tick per cycle). Any other offset reads 0 and ignores
  // writes, like the hole in the real device. mtip is the level (mtime >= mtimecmp); msip is the stored
  // bit. Unlike the real CLINT mtimecmp *is* reset here, to all ones, so a program that never sets it sees
  // no timer -- the SoC runs use the real device, which is not reset.
  wire clint_hit = (req_addr & 32'hFFFF_0000) == CLINT_BASE;
  wire [15:0] clint_off = req_addr[15:0];
  reg        clint_msip;
  reg [63:0] clint_mtimecmp, clint_mtime;
  wire       clint_mtip = (clint_mtime >= clint_mtimecmp);
  wire [63:0] clint_rdata = (clint_off[15:3] == 13'd0) ? {63'd0, clint_msip} :
                            (clint_off == 16'h4000)   ? clint_mtimecmp :
                            (clint_off == 16'hBFF8)   ? clint_mtime : 64'd0;

  // ---- memory ---------------------------------------------------------
  reg [63:0] mem [0:MEM_WORDS-1];
  assign bd_rd_data = mem[bd_rd_addr];
  always @(posedge clk) if (bd_we) mem[bd_addr] <= bd_data;
  wire [31:0] off   = req_addr - MEM_BASE;
  wire [63:0] widx  = {32'd0, off} >> 3;
  // the interrupt MMIO window is a real, answerable address: it must not look like an access fault
  wire in_range = ((req_addr >= MEM_BASE) && ({32'd0, off} < (MEM_WORDS * 8))) || irq_mmio_hit || clint_hit;

  // ---- timing profile --------------------------------------------------
  reg [31:0] lfsr;
  reg [7:0]  ready_cnt, resp_cnt;
  reg        busy;          // a request has been accepted, its response is pending
  reg        acc_write;
  reg [63:0] acc_widx, acc_wdata;
  reg [7:0]  acc_wmask;
  // ---- CPU-A: the reservation and the atomic in flight -------------------------------------------------
  reg         resv_valid;            // one reservation, for the core
  reg  [15:0] resv_word;             // its 64-bit word index
  reg  [3:0]  acc_amo;               // the accepted request's atomic fields
  reg  [1:0]  acc_lrsc;
  reg         acc_scfail;            // the SC decision taken at acceptance
  reg  [63:0] acc_old;               // the word as it was when the atomic was accepted
  reg         acc_is_fetch;          // the accepted request was an instruction fetch
  reg         a_inflight;            // an atomic has been offered and not yet answered
  reg  [63:0] n_amo, n_lr, n_sc_ok, n_sc_fail, n_resv_kill, n_ext_write;   // evidence counters
  reg  [15:0] ext_done;
  reg        acc_in_range, acc_mmio, acc_watch, acc_clint;
  reg [63:0] acc_clint_rdata;
  wire [63:0] wmask_bits = {{8{req_wmask[7]}}, {8{req_wmask[6]}}, {8{req_wmask[5]}}, {8{req_wmask[4]}},
                            {8{req_wmask[3]}}, {8{req_wmask[2]}}, {8{req_wmask[1]}}, {8{req_wmask[0]}}};
  // CPU-A: the AMO is computed on the request's byte lanes only; .W works on the addressed half and the
  // comparison is signed for MIN/MAX and unsigned for MINU/MAXU, on that half's width.
  wire [63:0] amo_cur  = mem[widx[15:0]];
  wire        amo_is_w = (req_size == 2'd2);
  wire [5:0]  amo_sh   = {req_addr[2:0], 3'b000};
  wire [63:0] amo_o64  = amo_cur  >> amo_sh;
  wire [63:0] amo_d64  = req_wdata >> amo_sh;
  wire [31:0] amo_o32  = amo_o64[31:0];
  wire [31:0] amo_d32  = amo_d64[31:0];
  reg  [63:0] amo_res;                       // the result on the lane, right-aligned
  always @(*) begin
    amo_res = 64'd0;
    case (req_amo)
      4'd1: amo_res = amo_is_w ? {32'd0, amo_d32} : amo_d64;                                   // SWAP
      4'd2: amo_res = amo_is_w ? {32'd0, (amo_o32 + amo_d32)} : (amo_o64 + amo_d64);           // ADD
      4'd3: amo_res = amo_is_w ? {32'd0, (amo_o32 ^ amo_d32)} : (amo_o64 ^ amo_d64);           // XOR
      4'd4: amo_res = amo_is_w ? {32'd0, (amo_o32 & amo_d32)} : (amo_o64 & amo_d64);           // AND
      4'd5: amo_res = amo_is_w ? {32'd0, (amo_o32 | amo_d32)} : (amo_o64 | amo_d64);           // OR
      4'd6: amo_res = amo_is_w ? {32'd0, (($signed(amo_o32) < $signed(amo_d32)) ? amo_o32 : amo_d32)}
                               : (($signed(amo_o64) < $signed(amo_d64)) ? amo_o64 : amo_d64);  // MIN
      4'd7: amo_res = amo_is_w ? {32'd0, (($signed(amo_o32) > $signed(amo_d32)) ? amo_o32 : amo_d32)}
                               : (($signed(amo_o64) > $signed(amo_d64)) ? amo_o64 : amo_d64);  // MAX
      4'd8: amo_res = amo_is_w ? {32'd0, ((amo_o32 < amo_d32) ? amo_o32 : amo_d32)}
                               : ((amo_o64 < amo_d64) ? amo_o64 : amo_d64);                    // MINU
      4'd9: amo_res = amo_is_w ? {32'd0, ((amo_o32 > amo_d32) ? amo_o32 : amo_d32)}
                               : ((amo_o64 > amo_d64) ? amo_o64 : amo_d64);                    // MAXU
      default: amo_res = 64'd0;
    endcase
  end
  wire [63:0] amo_new = (amo_cur & ~wmask_bits) | ((amo_res << amo_sh) & wmask_bits);
  reg [31:0] acc_addr;
  reg [63:0] acc_pc;
  reg [7:0]  resp_target;
  reg        tail_hit;        // the accepted request is the one the completion controls target
  reg        fetch_hit;       // the accepted request is a fetch the bus control is told to fail
  reg [63:0] n_fetch;
  // CPU-C: FETCH_ERR_AFTER counts instructions (first parcels); FETCH_ERR_ADDR may aim at either parcel
  wire       req_is_fetch1 = req_is_fetch && (cpu_state == S_IF_REQ_ || cpu_state == S_IF_WAIT_);
  // The bridge model for a core-only reset (R-BOOT's split domains): an offer that never fired is dropped,
  // an accepted request is answered by the memory and the answer swallowed, and no new request is accepted
  // until that has happened -- the restarted core can never receive a parcel it did not ask for.
  reg        p_core_rst, discard_resp;
  wire       resp_due    = busy && !(TAIL_DROP != 0 && tail_hit) && (resp_cnt + 8'd1 >= resp_target);
  wire       discard_now = resp_due && (discard_resp || bd_core_rst);
  reg [63:0] cyc;
  // CPU-A: when the external writer fires. Points 1 and 2 are relative to the core's *atomic* request, so a
  // race is placed exactly where the reservation is live rather than at an arbitrary cycle.
  wire [31:0] ext_widx = (EXT_ADDR - MEM_BASE) >> 3;
  reg  [15:0] ext_seen;                 // how often the moment occurred at all, armed or not
  wire        ext_moment =
      ((EXT_POINT == 1) ? (req_valid && !req_ready && (req_lrsc != 2'd0 || req_amo != 4'd0)) :
       (EXT_POINT == 2) ? (busy && !resp_valid && (acc_lrsc != 2'd0 || acc_amo != 4'd0) &&
                           (acc_widx[15:0] == ext_widx[15:0])) :   // only the word the race is aimed at
       (EXT_POINT == 3) ? (cyc == EXT_AT_CYCLE) :
       (EXT_POINT == 4) ? (resv_valid && !busy) : 1'b0);
  wire        ext_armed = (EXT_POINT != 0) && (ext_done < EXT_TIMES) && (ext_seen >= EXT_AFTER);
  wire        ext_fire = ext_armed && ext_moment;
  wire watch_hit = (bd_watch_addr != 32'd0) && (req_addr == bd_watch_addr);
  // the single apply path and the replay queue
  reg        apply_go, apply_watch, replay_go, dup_done;
  reg [63:0] apply_widx, apply_data, replay_widx, replay_data;
  reg [7:0]  apply_mask, replay_mask, replay_wait;

  function [7:0] rnd_delay; input [31:0] l; input [7:0] base; begin
    rnd_delay = base + (l[2:0]);
  end endfunction

  // ---- protocol monitor ------------------------------------------------
  reg        p_req_valid;
  reg [31:0] p_req_addr;
  reg [63:0] p_req_wdata;
  reg [7:0]  p_req_wmask;
  reg [1:0]  p_req_size;
  reg        p_req_write, p_req_fire, p_resp_valid, p_outstanding;
  reg        p_commit_rd_valid;
  reg [4:0]  p_commit_rd;
  reg [63:0] p_commit_rd_data;

  always @(posedge clk) begin
    if (rst) begin
      req_ready <= 1'b0; resp_valid_r <= 1'b0; resp_error_r <= 1'b0; resp_rdata_r <= 64'd0;
      resv_valid <= 1'b0; resv_word <= 16'd0; resp_scfail_r <= 1'b0;
      acc_amo <= 4'd0; acc_lrsc <= 2'd0; acc_scfail <= 1'b0; acc_old <= 64'd0; acc_is_fetch <= 1'b0;
      a_inflight <= 1'b0;
      n_amo <= 64'd0; n_lr <= 64'd0; n_sc_ok <= 64'd0; n_sc_fail <= 64'd0; n_resv_kill <= 64'd0;
      n_ext_write <= 64'd0; ext_done <= 16'd0; ext_seen <= 16'd0;
      lfsr <= SEED[31:0] | 32'd1; ready_cnt <= 8'd0; resp_cnt <= 8'd0; busy <= 1'b0;
      proto_errors <= 64'd0; n_req <= 64'd0; n_resp <= 64'd0; n_data_req <= 64'd0;
      obs_errors <= 64'd0; tail_hit <= 1'b0; fetch_hit <= 1'b0; n_fetch <= 64'd0;
      n_discard <= 64'd0; p_core_rst <= 1'b0; discard_resp <= 1'b0;
      irq_msip <= 1'b0; irq_mtip <= 1'b0; irq_meip <= 1'b0;
      clint_msip <= 1'b0; clint_mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF; clint_mtime <= 64'd0; acc_clint <= 1'b0; acc_clint_rdata <= 64'd0;
      irq_hits <= 64'd0; irq_fires <= 64'd0; irq_clears <= 64'd0; irq_raised <= 64'd0;
      irq_armed <= 1'b0; irq_arm_pending <= 1'b0; cyc <= 64'd0;
      fire_cycle <= 64'd0; fire_pc <= 64'd0; fire_state <= 4'd0; fire_enabled <= 1'b0; fire_priv <= 2'd0;
      fire_req_valid <= 1'b0; fire_req_ready <= 1'b0; fire_outstanding <= 1'b0;
      fire_is_write <= 1'b0; fire_addr <= 32'd0;
      watch_req <= 64'd0; watch_wreq <= 64'd0; watch_resp <= 64'd0; watch_writes <= 64'd0;
      apply_go <= 1'b0; apply_watch <= 1'b0; replay_go <= 1'b0; dup_done <= 1'b0; replay_wait <= 8'd0;
      apply_seq <= 64'd0; apply1_cycle <= 64'd0; apply2_cycle <= 64'd0;
      apply1_data <= 64'd0; apply2_data <= 64'd0;
      acc_addr <= 32'd0; acc_pc <= 64'd0;
      dbg_ra <= 5'd0; p_commit_rd_valid <= 1'b0;
      p_commit_rd <= 5'd0; p_commit_rd_data <= 64'd0;
      p_req_valid <= 1'b0; p_req_fire <= 1'b0; p_resp_valid <= 1'b0; p_outstanding <= 1'b0;
      resp_target <= 8'd1;
    end else begin
      clint_mtime <= clint_mtime + 64'd1;
      lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
      apply_go <= 1'b0;                      // default; the setters below and the replay override it

      // raise the source at the chosen moment, at most IRQ_TIMES times, and only while it is not already up
      cyc <= cyc + 64'd1;
      if (irq_arm_pending && cpu_state == S_IF_REQ_) begin irq_armed <= 1'b1; irq_arm_pending <= 1'b0; end
      if (IRQ_POINT != 0 && irq_moment && (IRQ_ARM_REQUIRED == 0 || irq_armed) &&
          (IRQ_NEED_ENABLED == 0 || cpu_irq_enabled) &&
          (bd_inject_pc == 64'd0 || cpu_pc == bd_inject_pc)) begin
        irq_hits <= irq_hits + 64'd1;
        if (!irq_any_high && irq_raised < IRQ_TIMES && irq_hits >= IRQ_AFTER) begin
          fire_cycle <= cyc; fire_pc <= cpu_pc; fire_state <= cpu_state;
          fire_enabled <= cpu_irq_enabled; fire_priv <= cpu_priv_o;
          fire_req_valid <= req_valid; fire_req_ready <= req_ready;
          fire_outstanding <= p_outstanding;
          // in the request phase the live fields describe the access; in the response phase the latched ones do
          fire_is_write <= req_valid ? req_write : acc_write;
          fire_addr     <= req_valid ? req_addr  : acc_addr;
          irq_raised <= irq_raised + 64'd1;
          irq_fires  <= irq_fires + 64'd1;
          if (IRQ_ALL_LINES != 0) begin irq_msip <= 1'b1; irq_mtip <= 1'b1; irq_meip <= 1'b1; end
          else case (IRQ_LINE)
            0: irq_msip <= 1'b1;
            1: irq_mtip <= 1'b1;
            default: irq_meip <= 1'b1;
          endcase
        end
      end
      resp_valid_r <= 1'b0;

      // --- request side: ready after READY_DELAY (or a random number of) cycles of offer
      p_core_rst <= bd_core_rst;
      if (!busy && req_valid && !bd_core_rst && !discard_resp) begin
        if (ready_cnt >= (RANDOM ? rnd_delay(lfsr, READY_DELAY[7:0]) : READY_DELAY[7:0])) begin
          req_ready <= 1'b1;
        end else begin
          req_ready <= 1'b0; ready_cnt <= ready_cnt + 8'd1;
        end
      end else begin
        req_ready <= 1'b0;
      end

      // --- accept
      if (req_valid && req_ready && !busy) begin
        tail_hit  <= (TAIL_ERR != 0 || TAIL_DROP != 0) && req_write && (req_addr == bd_fault_addr);
        fetch_hit <= ((FETCH_ERR_AFTER != 0) && req_is_fetch1 && (n_fetch + 64'd1 > FETCH_ERR_AFTER)) ||
                     ((FETCH_ERR_ADDR != 0) && req_is_fetch && (req_addr == FETCH_ERR_ADDR));
        if (req_is_fetch1) n_fetch <= n_fetch + 64'd1;
        busy <= 1'b1; ready_cnt <= 8'd0; resp_cnt <= 8'd0;
        acc_write <= req_write; acc_widx <= widx; acc_wdata <= req_wdata; acc_wmask <= req_wmask;
        // ---- CPU-A: the atomic is decided here, at acceptance, and takes effect once
        acc_amo <= req_amo; acc_lrsc <= req_lrsc; acc_old <= amo_cur; acc_is_fetch <= req_is_fetch;
        acc_scfail <= 1'b0;
        if (in_range && !irq_mmio_hit && !clint_hit) begin
          if (req_lrsc == 2'd1) begin                                   // LR: the reservation is a candidate
            resv_valid <= 1'b1; resv_word <= widx[15:0]; n_lr <= n_lr + 64'd1;
            $display("A_MODEL LR word=0x%08x cycle=%0d", {widx[15:0], 3'd0} + MEM_BASE, cyc);
          end else if (req_lrsc == 2'd2) begin                          // SC: decided, then consumed
            if ((resv_valid && resv_word == widx[15:0]) || FAULT_MODEL_SC_ALWAYS_OK != 0) begin
              acc_scfail <= 1'b0; n_sc_ok <= n_sc_ok + 64'd1;
              $display("A_MODEL SC_OK word=0x%08x cycle=%0d", {widx[15:0], 3'd0} + MEM_BASE, cyc);
            end else begin
              acc_scfail <= 1'b1; n_sc_fail <= n_sc_fail + 64'd1;
              $display("A_MODEL SC_FAIL word=0x%08x cycle=%0d", {widx[15:0], 3'd0} + MEM_BASE, cyc);
            end
            resv_valid <= 1'b0;                                         // every SC consumes it
          end else if (req_amo != 4'd0) begin
            n_amo <= n_amo + 64'd1;
            if (resv_valid && resv_word == widx[15:0]) begin resv_valid <= 1'b0; n_resv_kill <= n_resv_kill + 64'd1; end
            $display("A_MODEL AMO op=%0d word=0x%08x old=0x%016x new=0x%016x cycle=%0d",
                     req_amo, {widx[15:0], 3'd0} + MEM_BASE, amo_cur, amo_new, cyc);
          end else if (req_write && resv_valid && resv_word == widx[15:0]) begin
            resv_valid <= 1'b0; n_resv_kill <= n_resv_kill + 64'd1;     // the core's own store to the word
            $display("A_MODEL RESV_KILL why=own-store word=0x%08x cycle=%0d", {widx[15:0], 3'd0} + MEM_BASE, cyc);
          end
        end
        acc_in_range <= in_range; acc_mmio <= irq_mmio_hit; acc_clint <= clint_hit; acc_clint_rdata <= clint_rdata;
        // CLINT writes take effect at the accept edge; the read value was sampled in the same cycle
        if (req_write && clint_hit) begin
          if (clint_off[15:3] == 13'd0 && req_wmask[0]) clint_msip <= req_wdata[0];
          if (clint_off == 16'h4000) clint_mtimecmp <= (clint_mtimecmp & ~wmask_bits) | (req_wdata & wmask_bits);
        end
        acc_addr <= req_addr; acc_pc <= cpu_pc;   // valid for the whole response phase
        resp_target <= RANDOM ? rnd_delay(lfsr, (RESP_DELAY < 1) ? 8'd1 : RESP_DELAY[7:0])
                              : ((RESP_DELAY < 1) ? 8'd1 : RESP_DELAY[7:0]);
        n_req <= n_req + 64'd1;
        if (!req_is_fetch) n_data_req <= n_data_req + 64'd1;
        if (watch_hit) begin
          watch_req <= watch_req + 64'd1;
          if (req_write) watch_wreq <= watch_wreq + 64'd1;
        end
        acc_watch <= watch_hit;
        // the test interrupt controller: writing a 1 to a bit quiets that source
        if (req_write && irq_mmio_hit && req_addr[3]) irq_arm_pending <= req_wdata[0];   // +8 = the arm word
        if (req_write && irq_mmio_hit && !req_addr[3]) begin
          if (req_wdata[0]) irq_msip <= 1'b0;
          if (req_wdata[1]) irq_mtip <= 1'b0;
          if (req_wdata[2]) irq_meip <= 1'b0;
          irq_clears <= irq_clears + 64'd1;
        end
        // A write reaching the model is queued for the single apply path below rather than written here,
        // so that every write side effect -- whether it came from the bus or from a replay -- is one event
        // on one path, counted once, with its own cycle.
        // an SC that lost its reservation writes nothing at all; an AMO writes the computed word
        if (req_write && in_range && !irq_mmio_hit && !clint_hit &&
            !(req_lrsc == 2'd2 && !((resv_valid && resv_word == widx[15:0]) || FAULT_MODEL_SC_ALWAYS_OK != 0))) begin
          apply_go <= 1'b1; apply_widx <= widx;
          apply_data <= (req_amo != 4'd0) ? amo_new : req_wdata;
          apply_mask <= (req_amo != 4'd0) ? 8'hff   : req_wmask;
          apply_watch <= watch_hit;
          // DUP_STORE picks one watched write and queues a genuine second application of the same value,
          // on a later cycle. The bus still sees one request and one response and memory still ends up
          // with the same contents; what differs is that the side effect really happened twice.
          if (DUP_STORE != 0 && watch_hit && !dup_done) begin
            replay_go <= 1'b1; replay_widx <= widx; replay_data <= req_wdata; replay_mask <= req_wmask;
            replay_wait <= 8'd3; dup_done <= 1'b1;
          end
        end
      end

      // --- CPU-A: the core's own clear (a trap, or the core held in reset) drops the reservation. An
      // ordinary fetch or a page-table read never reaches this.
      if (resv_clear && resv_valid) begin
        resv_valid <= 1'b0; n_resv_kill <= n_resv_kill + 64'd1;
        $display("A_MODEL RESV_KILL why=resv-clear cycle=%0d", cyc);
      end
      // --- CPU-A: an external writer, racing with the core at a named moment. Its write is a real write
      // to the model's memory and it kills an overlapping reservation, exactly as another master would.
      if (ext_moment && ext_seen < 16'hffff) ext_seen <= ext_seen + 16'd1;
      if (ext_fire) begin : do_ext
        integer eb;
        ext_done <= ext_done + 16'd1; n_ext_write <= n_ext_write + 64'd1;
        for (eb = 0; eb < 8; eb = eb + 1) mem[ext_widx[15:0]][eb*8 +: 8] <= EXT_DATA[eb*8 +: 8];
        $display("A_MODEL EXT_WRITE addr=0x%08x data=0x%016x cycle=%0d", EXT_ADDR, EXT_DATA, cyc);
        if (resv_valid && resv_word == ext_widx[15:0] && FAULT_MODEL_NO_KILL == 0) begin
          resv_valid <= 1'b0; n_resv_kill <= n_resv_kill + 64'd1;
          $display("A_MODEL RESV_KILL why=external-write cycle=%0d", cyc);
        end
      end

      // --- the single write-apply path. Every event here counts once, unconditionally: the counter does
      // not know about any fault switch, which is the only way it can be evidence about one.
      if (apply_go) begin : do_apply
        integer b;
        for (b = 0; b < 8; b = b + 1)
          if (apply_mask[b]) mem[apply_widx[15:0]][b*8 +: 8] <= apply_data[b*8 +: 8];
        if (apply_watch) begin
          watch_writes <= watch_writes + 64'd1;
          apply_seq    <= apply_seq + 64'd1;
          if (apply_seq == 64'd0) begin apply1_cycle <= cyc; apply1_data <= apply_data; end
          else if (apply_seq == 64'd1) begin apply2_cycle <= cyc; apply2_data <= apply_data; end
        end
      end
      // the queued replay, deliberately some cycles later so the two events cannot be one edge
      if (replay_go) begin
        if (replay_wait != 8'd0) replay_wait <= replay_wait - 8'd1;
        else begin
          replay_go <= 1'b0;
          apply_go <= 1'b1; apply_widx <= replay_widx; apply_data <= replay_data;
          apply_mask <= replay_mask; apply_watch <= 1'b1;
        end
      end

      // --- response: never in the accept cycle (resp_cnt starts at 0 and must reach >= 1)
      // TAIL_DROP: the write to the completion address is accepted and never answered, so a driver that
      // stops as soon as the value appears in memory would still call the run a pass.
      // a request accepted at, or still in flight across, the core reset belongs to nobody: its answer will be
      // swallowed (an answer due in this very cycle is swallowed right here, so the flag cannot outlive it)
      if (bd_core_rst && ((busy && !resp_due) || (req_valid && req_ready && !busy))) discard_resp <= 1'b1;
      if (discard_now) begin
        discard_resp <= 1'b0; busy <= 1'b0; n_resp <= n_resp + 64'd1; n_discard <= n_discard + 64'd1; p_outstanding <= 1'b0;
        $display("BRIDGE MODEL: stale response to 0x%08x discarded after the core reset", acc_addr);
      end else if (busy && !(TAIL_DROP != 0 && tail_hit)) begin
        if (resp_due) begin
          resp_valid_r <= 1'b1;
          resp_error_r <= !acc_in_range || (TAIL_ERR != 0 && tail_hit) || fetch_hit;
          // CPU-A: an LR or an AMO answers with the old value (latched at acceptance, before the write);
          // an SC answers with no data and its scFail result
          resp_scfail_r <= (acc_lrsc == 2'd2) ? acc_scfail : 1'b0;
          resp_rdata_r <= acc_mmio ? {61'd0, irq_meip, irq_mtip, irq_msip} :
                          acc_clint ? (acc_write ? 64'd0 : acc_clint_rdata) :
                          (acc_amo != 4'd0) ? acc_old :
                          acc_in_range ? (acc_write ? 64'd0 : mem[acc_widx[15:0]]) : 64'd0;
          busy <= 1'b0;
          n_resp <= n_resp + 64'd1;
          if (acc_watch) watch_resp <= watch_resp + 64'd1;
        end else begin
          resp_cnt <= resp_cnt + 8'd1;
        end
      end

      // --- monitor: payload held until the handshake, single outstanding, response not same-cycle
      p_req_valid  <= req_valid;
      p_req_addr   <= req_addr; p_req_wdata <= req_wdata; p_req_wmask <= req_wmask;
      p_req_size   <= req_size; p_req_write <= req_write;
      p_req_fire   <= req_valid && req_ready;
      p_resp_valid <= resp_valid;
      if (p_req_valid && !p_req_fire && !req_valid && !bd_core_rst && !p_core_rst) begin   // a reset core drops its offer: the bridge's business
        proto_errors <= proto_errors + 64'd1;
        $display("PROTO ERROR: request withdrawn before the handshake");
      end
      if (p_req_valid && !p_req_fire && req_valid &&
          (req_addr != p_req_addr || req_wdata != p_req_wdata || req_wmask != p_req_wmask ||
           req_size != p_req_size || req_write != p_req_write)) begin
        proto_errors <= proto_errors + 64'd1;
        $display("PROTO ERROR: request payload changed while waiting for ready");
      end
      if (req_valid && req_ready && p_outstanding) begin
        proto_errors <= proto_errors + 64'd1;
        $display("PROTO ERROR: second request accepted while one was outstanding");
      end
      if (resp_valid && !p_outstanding && !(req_valid && req_ready)) begin
        proto_errors <= proto_errors + 64'd1;
        $display("PROTO ERROR: response with nothing outstanding");
      end
      if (req_valid && req_ready && resp_valid) begin
        proto_errors <= proto_errors + 64'd1;
        $display("PROTO ERROR: response in the request handshake cycle");
      end
      if (req_valid && req_ready) p_outstanding <= 1'b1;
      else if (resp_valid) p_outstanding <= 1'b0;
      else if (discard_now) p_outstanding <= 1'b0;
      // A read must carry no write payload: the rs2 field of a load is immediate bits, not a register.
      if (req_valid && req_ready && !req_write && (req_wdata != 64'd0 || req_wmask != 8'd0)) begin
        proto_errors <= proto_errors + 64'd1;
        $display("PROTO ERROR: read request carried a write payload wdata=%h wmask=%h", req_wdata, req_wmask);
      end
      // The observation port is checked against the architectural register file one cycle later, so a
      // passing trace cannot be produced by the observation port alone.
      p_commit_rd_valid <= commit_valid && commit_rd_valid;
      p_commit_rd       <= commit_rd;
      p_commit_rd_data  <= commit_rd_data;
      if (commit_valid && commit_rd_valid) dbg_ra <= commit_rd;
      if (p_commit_rd_valid && dbg_rd !== p_commit_rd_data) begin
        obs_errors <= obs_errors + 64'd1;
        $display("OBS ERROR: x%0d reads %h, the commit port reported %h", p_commit_rd, dbg_rd, p_commit_rd_data);
      end
      if (commit_valid && trap_valid) begin
        proto_errors <= proto_errors + 64'd1;
        $display("PROTO ERROR: commit and trap in the same cycle");
      end
      // CPU-A: an atomic must not retire before the memory has answered it. a_inflight is raised the moment
      // the core offers an atomic request and cleared when its response is delivered, so a commit of an
      // A-opcode instruction while it is still up is exactly an atomic that retired early.
      if (req_valid && (req_amo != 4'd0 || req_lrsc != 2'd0)) a_inflight <= 1'b1;
      if (resp_valid && a_inflight) a_inflight <= 1'b0;
      if (commit_valid && (commit_insn[6:0] == 7'b0101111) && a_inflight && !resp_valid) begin
        obs_errors <= obs_errors + 64'd1;
        $display("A_OBS_FAIL early-retire pc=0x%08x insn=0x%08x: the atomic retired while its response was outstanding",
                 commit_pc[31:0], commit_insn);
      end
    end
  end
endmodule
