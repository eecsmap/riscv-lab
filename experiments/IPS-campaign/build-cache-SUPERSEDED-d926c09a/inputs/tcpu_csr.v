// The CSR file and privilege state of the teaching CPU.
//
// M2-2 gave it the M-mode set; M2-3 mie/mip; CPU-M/CPU-C misa bits. CPU-SU (this version) adds the three
// privilege levels M/S/U, delegation, the S-level CSRs as views of the same state, and the cross-mode
// interrupt rules -- at the Bare step: satp supports MODE = 0 only, no PMP, no A, no time CSR
// (experiments/teaching-cpu/cpu-su-prep/SPEC.md as ruled in CODEX_DECISIONS.md; The RISC-V Privileged
// Architecture v20240411, §3.1.6 mstatus, §3.1.8 medeleg/mideleg, §3.1.9 mip/mie, §3.3.2 xRET,
// §10.1 sstatus/sie/sip, §10.1.11 satp).
//
// Timing, unchanged: the core evaluates a CSR access in S_WB (`rdata` combinational, the value before this
// instruction's effect); the write enable is registered and the new value lands at the end of S_ARCH
// together with the register-file write and the retirement. Trap entry and xRET land on the same edge.
// Nothing here is decided on state that has not landed: the core samples interrupts in S_IF_REQ, after.
//
// Views, not copies: sstatus/sie/sip read and write the same flip-flops as mstatus/mie/mip through a mask.
// mip: MSIP/MTIP/MEIP are the external levels (read-only); SSIP/STIP/SEIP are software-pending bits
// writable at the M address (0x344); at the S address (0x144) only a delegated SSIP is writable.
`timescale 1ns/1ps
module tcpu_csr #(
  parameter MISA_A          = 0,   // CPU-A: 1 only where an atomic path really exists (see tcpu_core.v)
  parameter TRAP_BAD_MEPC   = 0,   // fault injection: mepc records the *next* instruction
  parameter TRAP_COUNTS_RET = 0,   // fault injection: a trap bumps minstret
  parameter ALLOW_RO_WRITE  = 0,   // fault injection: writes to read-only CSRs are let through
  parameter FAULT_NO_DELEG  = 0,   // CPU-SU fault injection: medeleg/mideleg ignored, every trap goes to M
  parameter FAULT_S_IRQ_IN_M = 0,  // CPU-SU fault injection: a delegated S-level interrupt is taken in M-mode
  parameter FAULT_SRET_SPP  = 0    // CPU-SU fault injection: sret leaves SPP as it was
) (
  input             clk,
  input             rst,

  // ---- access from the CSR instruction, all valid in the access cycle
  input      [11:0] addr,
  input             access,          // this instruction is a Zicsr instruction
  input             write_intent,    // it intends to write (CSRRW[I] always; S/C only when the source is non-zero)
  input             read_intent,     // it intends to read (CSRRW[I] only when rd != x0)
  output            addr_illegal,    // unimplemented / privileged / read-only-written / gated counter
  output reg [63:0] rdata,
  input             we,              // perform the write (asserted only in the retiring cycle)
  input      [63:0] wdata,

  // ---- retirement and the counters
  input             retire,          // a normal retirement happens this cycle

  // ---- trap entry and the two returns
  input             trap,
  input      [63:0] trap_cause,      // bit 63 = interrupt
  input      [63:0] trap_epc,
  input      [63:0] trap_tval,
  output     [63:0] trap_vector,     // where this trap goes (mtvec or stvec), decided from cause and level
  input             mret,
  input             sret,
  // ---- interrupts: level inputs in this clock domain, and the acceptance decision derived from them
  input             irq_msip,
  input             irq_mtip,
  input             irq_meip,
  output            irq_enabled,      // an M-level line would be accepted right now if asserted
  output            irq_pending,      // an interrupt is pending, enabled and acceptable at this level
  output     [63:0] irq_cause,        // bit 63 set, with the highest-priority acceptable cause

  output     [1:0]  priv,             // the current privilege level: 3 M, 1 S, 0 U
  output     [63:0] mtvec_base,
  output     [63:0] mepc_out,
  output     [63:0] sepc_out,
  // ---- CPU-SV39: what the translation needs
  output            satp_mode,        // 0 Bare, 1 Sv39
  output     [43:0] satp_ppn,
  output            st_sum_o, st_mxr_o, st_mprv_o,
  output     [1:0]  st_mpp_o,

  // ---- read-back for the harness: the real registers, not a copy of the trap outputs
  input      [4:0]  dbg_sel,
  output reg [63:0] dbg_val
);
  // ---- addresses ------------------------------------------------------
  localparam [11:0] CSR_MSTATUS  = 12'h300, CSR_MISA     = 12'h301, CSR_MEDELEG = 12'h302,
                    CSR_MIDELEG  = 12'h303, CSR_MIE      = 12'h304, CSR_MTVEC   = 12'h305,
                    CSR_MCOUNTEREN = 12'h306,
                    CSR_MSCRATCH = 12'h340, CSR_MEPC     = 12'h341, CSR_MCAUSE  = 12'h342,
                    CSR_MTVAL    = 12'h343, CSR_MIP      = 12'h344,
                    CSR_MCYCLE   = 12'hB00, CSR_MINSTRET = 12'hB02,
                    CSR_CYCLE    = 12'hC00, CSR_INSTRET  = 12'hC02, CSR_MHARTID = 12'hF14,
                    CSR_SSTATUS  = 12'h100, CSR_SIE      = 12'h104, CSR_STVEC   = 12'h105,
                    CSR_SCOUNTEREN = 12'h106,
                    CSR_SSCRATCH = 12'h140, CSR_SEPC     = 12'h141, CSR_SCAUSE  = 12'h142,
                    CSR_STVAL    = 12'h143, CSR_SIP      = 12'h144, CSR_SATP    = 12'h180;
  localparam [1:0] PRV_U = 2'd0, PRV_S = 2'd1, PRV_M = 2'd3;

  // ---- state ----------------------------------------------------------
  reg [1:0]  cur_priv;
  reg        st_sie, st_mie, st_spie, st_mpie, st_spp, st_mprv, st_mxr, st_sum;
  reg        satp_mode_r;
  reg [43:0] satp_ppn_r;
  assign satp_mode = satp_mode_r; assign satp_ppn = satp_ppn_r;
  assign st_sum_o = st_sum; assign st_mxr_o = st_mxr; assign st_mprv_o = st_mprv; assign st_mpp_o = st_mpp;
  reg [1:0]  st_mpp;
  reg        mie_ssie, mie_msie, mie_stie, mie_mtie, mie_seie, mie_meie;
  reg        sw_ssip, sw_stip, sw_seip;      // the software-pending bits
  reg [15:0] medeleg;                        // masked to 0xB3FF
  reg [11:0] mideleg;                        // masked to 0x222
  reg [63:0] mtvec, mscratch, mepc, mcause, mtval, mcycle, minstret;
  reg [63:0] stvec, sscratch, sepc, scause, stval;
  reg        mcnt_cy, mcnt_ir, scnt_cy, scnt_ir;
  assign priv = cur_priv;

  localparam [15:0] MEDELEG_MASK = 16'hB3FF;   // causes 0-9, 12, 13, 15; 11 (ecall from M) and reserved 10/14 read 0
  localparam [11:0] MIDELEG_MASK = 12'h222;    // SSI STI SEI; M-level interrupts are never delegable

  // misa: fixed WARL. MXL = 2 (RV64); C I M S U = bits 2, 8, 12, 18, 20. CPU-A adds A (bit 0) -- but only
  // in a configuration that really has the atomic path: where MISA_A is 0 the A instructions are illegal
  // and the bit stays 0, so no configuration claims support it does not have.
  wire [63:0] MISA_VALUE = {2'b10, 36'd0, 26'h141104} | ((MISA_A != 0) ? 64'd1 : 64'd0);

  // mstatus: SIE 1, MIE 3, SPIE 5, MPIE 7, SPP 8, MPP 12:11, MPRV 17, MXR 19, UXL 33:32 = 2, SXL 35:34 = 2.
  // SUM (18) is a real bit now that Sv39 exists (CPU-SV39); TVM/TW/TSR 20-22 hardwired 0 (D-4/D-5);
  // FS/XS/VS/SD 0 (no FPU); MBE/SBE/UBE 0.
  wire [63:0] mstatus_value = {28'd0, 2'b10, 2'b10, 12'd0, st_mxr, st_sum, st_mprv, 4'd0, st_mpp,
                               2'd0, st_spp, st_mpie, 1'b0, st_spie, 1'b0, st_mie, 1'b0, st_sie, 1'b0};
  wire [63:0] sstatus_value = mstatus_value & 64'h0000_0002_000C_0122;
  wire [63:0] mie_value = {52'd0, mie_meie, 1'b0, mie_seie, 1'b0, mie_mtie, 1'b0, mie_stie, 1'b0,
                           mie_msie, 1'b0, mie_ssie, 1'b0};
  wire [63:0] mip_value = {52'd0, irq_meip, 1'b0, sw_seip, 1'b0, irq_mtip, 1'b0, sw_stip, 1'b0,
                           irq_msip, 1'b0, sw_ssip, 1'b0};
  wire [63:0] mideleg64 = {52'd0, mideleg};
  wire [63:0] sie_value = mie_value & mideleg64;
  wire [63:0] sip_value = mip_value & mideleg64;

  // ---- decode of the address: existence, read-only, required level, counter gating -------------------
  reg known, read_only, counter_gated;
  wire [1:0] need_priv = addr[9:8];
  always @(*) begin
    known = 1'b1; read_only = 1'b0; counter_gated = 1'b0;
    case (addr)
      CSR_MSTATUS, CSR_MISA, CSR_MEDELEG, CSR_MIDELEG, CSR_MIE, CSR_MTVEC, CSR_MCOUNTEREN,
      CSR_MSCRATCH, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL, CSR_MIP, CSR_MCYCLE, CSR_MINSTRET,
      CSR_SSTATUS, CSR_SIE, CSR_STVEC, CSR_SCOUNTEREN, CSR_SSCRATCH, CSR_SEPC, CSR_SCAUSE,
      CSR_STVAL, CSR_SIP, CSR_SATP: ;
      CSR_MHARTID: read_only = 1'b1;
      // cycle/instret: read-only, and below M gated by mcounteren (S) and by both counterens (U)
      CSR_CYCLE:   begin read_only = 1'b1; counter_gated = (cur_priv < PRV_M && !mcnt_cy) || (cur_priv == PRV_U && !scnt_cy); end
      CSR_INSTRET: begin read_only = 1'b1; counter_gated = (cur_priv < PRV_M && !mcnt_ir) || (cur_priv == PRV_U && !scnt_ir); end
      default: known = 1'b0;   // includes pmpcfg/pmpaddr, menvcfg, time (0xC01), and everything else
    endcase
  end
  // The privilege of an address is its bits [9:8]; a lower level may not touch it. TVM = 0 so satp and
  // sfence are not additionally trapped in S. All of this is settled before any side effect.
  assign addr_illegal = access && (!known || (write_intent && read_only && (ALLOW_RO_WRITE == 0)) ||
                                   (cur_priv < need_priv) || counter_gated);

  always @(*) begin
    case (addr)
      CSR_MSTATUS:  rdata = mstatus_value;
      CSR_MISA:     rdata = MISA_VALUE;
      CSR_MEDELEG:  rdata = {48'd0, medeleg};
      CSR_MIDELEG:  rdata = mideleg64;
      CSR_MIE:      rdata = mie_value;
      CSR_MTVEC:    rdata = mtvec;
      CSR_MCOUNTEREN: rdata = {61'd0, mcnt_ir, 1'b0, mcnt_cy};
      CSR_MSCRATCH: rdata = mscratch;
      CSR_MEPC:     rdata = mepc;
      CSR_MCAUSE:   rdata = mcause;
      CSR_MTVAL:    rdata = mtval;
      CSR_MIP:      rdata = mip_value;
      CSR_MCYCLE, CSR_CYCLE:     rdata = mcycle;
      CSR_MINSTRET, CSR_INSTRET: rdata = minstret;
      CSR_MHARTID:  rdata = 64'd0;
      CSR_SSTATUS:  rdata = sstatus_value;
      CSR_SIE:      rdata = sie_value;
      CSR_STVEC:    rdata = stvec;
      CSR_SCOUNTEREN: rdata = {61'd0, scnt_ir, 1'b0, scnt_cy};
      CSR_SSCRATCH: rdata = sscratch;
      CSR_SEPC:     rdata = sepc;
      CSR_SCAUSE:   rdata = scause;
      CSR_STVAL:    rdata = stval;
      CSR_SIP:      rdata = sip_value;
      CSR_SATP:     rdata = {satp_mode_r ? 4'd8 : 4'd0, 16'd0, satp_ppn_r};   // ASIDLEN = 0
      default:      rdata = 64'd0;
    endcase
  end

  // ---- interrupts (v20240411 §3.1.6.1, §3.1.9) --------------------------------------------------------
  // pending & enabled, split by level: an M-level interrupt is taken in M only with MIE and always below M;
  // an S-level one never in M, in S only with SIE, always in U; M-level first; within a level
  // MEI > MSI > MTI > SEI > SSI > STI.
  wire [11:0] pend    = mip_value[11:0] & mie_value[11:0];
  wire [11:0] pend_m  = pend & ~mideleg;
  wire [11:0] pend_s  = pend &  mideleg;
  wire take_m = (|pend_m) && ((cur_priv < PRV_M) || st_mie);
  wire take_s = (|pend_s) && !take_m &&
                ((cur_priv < PRV_S) || (cur_priv == PRV_S && st_sie) ||
                 (FAULT_S_IRQ_IN_M != 0 && cur_priv == PRV_M && st_mie));   // fault: also in M (gated by MIE like an M-level one)
  assign irq_pending = take_m | take_s;
  wire [11:0] sel = take_m ? pend_m : pend_s;
  wire [5:0] irq_n = sel[11] ? 6'd11 : sel[3] ? 6'd3 : sel[7] ? 6'd7 :
                     sel[9]  ? 6'd9  : sel[1] ? 6'd1 : 6'd5;
  assign irq_cause = {1'b1, 57'd0, irq_n};
  // "would an M-level line be accepted if it were asserted": what the injector reports as `enabled`
  assign irq_enabled = ((cur_priv < PRV_M) || st_mie) && (mie_meie || mie_msie || mie_mtie);

  // ---- where a trap goes ----------------------------------------------------------------------------
  wire trap_is_irq = trap_cause[63];
  wire [3:0] cause_lo = trap_cause[3:0];
  wire deleg_bit = trap_is_irq ? mideleg[cause_lo] : medeleg[cause_lo];
  wire delegate  = (FAULT_NO_DELEG == 0) && (cur_priv <= PRV_S) && deleg_bit;
  assign trap_vector = delegate ? stvec : mtvec;

  assign mtvec_base = mtvec;
  assign mepc_out   = mepc;
  assign sepc_out   = sepc;

  wire wr = we && write_intent && !addr_illegal;

  // ---- update ----------------------------------------------------------
  always @(posedge clk) begin
    if (rst) begin
      cur_priv <= PRV_M;
      st_sie <= 1'b0; st_mie <= 1'b0; st_spie <= 1'b0; st_mpie <= 1'b0; st_spp <= 1'b0;
      st_mpp <= 2'd0; st_mprv <= 1'b0; st_mxr <= 1'b0; st_sum <= 1'b0;
      satp_mode_r <= 1'b0; satp_ppn_r <= 44'd0;
      mie_ssie <= 1'b0; mie_msie <= 1'b0; mie_stie <= 1'b0; mie_mtie <= 1'b0; mie_seie <= 1'b0; mie_meie <= 1'b0;
      sw_ssip <= 1'b0; sw_stip <= 1'b0; sw_seip <= 1'b0;
      medeleg <= 16'd0; mideleg <= 12'd0;
      mtvec <= 64'd0; mscratch <= 64'd0; mepc <= 64'd0; mcause <= 64'd0; mtval <= 64'd0;
      stvec <= 64'd0; sscratch <= 64'd0; sepc <= 64'd0; scause <= 64'd0; stval <= 64'd0;
      mcycle <= 64'd0; minstret <= 64'd0;
      mcnt_cy <= 1'b0; mcnt_ir <= 1'b0; scnt_cy <= 1'b0; scnt_ir <= 1'b0;
    end else begin
      if (wr && (addr == CSR_MCYCLE)) mcycle <= wdata;
      else                            mcycle <= mcycle + 64'd1;
      if (wr && (addr == CSR_MINSTRET))       minstret <= wdata;
      else if (retire || (TRAP_COUNTS_RET != 0 && trap)) minstret <= minstret + 64'd1;

      if (trap) begin
        if (delegate) begin
          sepc    <= TRAP_BAD_MEPC ? (trap_epc + 64'd4) : {trap_epc[63:1], 1'b0};
          scause  <= trap_cause;
          stval   <= trap_tval;
          st_spie <= st_sie;
          st_sie  <= 1'b0;
          st_spp  <= (cur_priv == PRV_S);
          cur_priv <= PRV_S;
        end else begin
          mepc    <= TRAP_BAD_MEPC ? (trap_epc + 64'd4) : {trap_epc[63:1], 1'b0};
          mcause  <= trap_cause;
          mtval   <= trap_tval;
          st_mpie <= st_mie;
          st_mie  <= 1'b0;
          st_mpp  <= cur_priv;
          cur_priv <= PRV_M;
        end
      end else if (mret) begin
        // priv <- MPP, MIE <- MPIE, MPIE <- 1, MPP <- U; MPRV <- 0 when the new level is not M
        cur_priv <= st_mpp;
        st_mie   <= st_mpie;
        st_mpie  <= 1'b1;
        st_mpp   <= PRV_U;
        if (st_mpp != PRV_M) st_mprv <= 1'b0;
      end else if (sret) begin
        cur_priv <= st_spp ? PRV_S : PRV_U;
        st_sie   <= st_spie;
        st_spie  <= 1'b1;
        if (FAULT_SRET_SPP == 0) st_spp <= 1'b0;
        st_mprv  <= 1'b0;
      end else if (wr) begin
        case (addr)
          CSR_MSTATUS: begin
            st_sie <= wdata[1]; st_mie <= wdata[3]; st_spie <= wdata[5]; st_mpie <= wdata[7];
            st_spp <= wdata[8]; st_mpp <= (wdata[12:11] == 2'd2) ? 2'd0 : wdata[12:11];   // D-3: 2 -> U
            st_mprv <= wdata[17]; st_sum <= wdata[18]; st_mxr <= wdata[19];
          end
          CSR_SSTATUS: begin st_sie <= wdata[1]; st_spie <= wdata[5]; st_spp <= wdata[8]; st_sum <= wdata[18]; st_mxr <= wdata[19]; end
          CSR_MISA:     ;                                    // fixed WARL value: accepted, discarded
          CSR_MEDELEG:  medeleg <= wdata[15:0] & MEDELEG_MASK;
          CSR_MIDELEG:  mideleg <= wdata[11:0] & MIDELEG_MASK;
          CSR_MIE: begin
            mie_ssie <= wdata[1]; mie_msie <= wdata[3]; mie_stie <= wdata[5];
            mie_mtie <= wdata[7]; mie_seie <= wdata[9]; mie_meie <= wdata[11];
          end
          // sie: only the delegated bits are visible and writable through the S address
          CSR_SIE: begin
            if (mideleg[1]) mie_ssie <= wdata[1];
            if (mideleg[5]) mie_stie <= wdata[5];
            if (mideleg[9]) mie_seie <= wdata[9];
          end
          // mip: the software-pending bits; the M-level bits are input levels and are not stored
          CSR_MIP: begin sw_ssip <= wdata[1]; sw_stip <= wdata[5]; sw_seip <= wdata[9]; end
          // sip: SSIP only, and only when delegated; STIP/SEIP are read-only at this address
          CSR_SIP:      if (mideleg[1]) sw_ssip <= wdata[1];
          CSR_MTVEC:    mtvec <= {wdata[63:2], 2'b00};
          CSR_STVEC:    stvec <= {wdata[63:2], 2'b00};
          CSR_MCOUNTEREN: begin mcnt_cy <= wdata[0]; mcnt_ir <= wdata[2]; end
          CSR_SCOUNTEREN: begin scnt_cy <= wdata[0]; scnt_ir <= wdata[2]; end
          CSR_MSCRATCH: mscratch <= wdata;
          CSR_SSCRATCH: sscratch <= wdata;
          CSR_MEPC:     mepc <= {wdata[63:1], 1'b0};
          CSR_SEPC:     sepc <= {wdata[63:1], 1'b0};
          CSR_MCAUSE:   mcause <= wdata;
          CSR_SCAUSE:   scause <= wdata;
          CSR_MTVAL:    mtval <= wdata;
          CSR_STVAL:    stval <= wdata;
          // satp: MODE 0 stores 0 everywhere (D-2), MODE 8 stores the PPN (all 44 bits, read back as written;
          // a PPN beyond the 32-bit physical space faults at use, it is never truncated), any other MODE
          // ignores the whole write (spec)
          CSR_SATP: begin
            if (wdata[63:60] == 4'd0) begin satp_mode_r <= 1'b0; satp_ppn_r <= 44'd0; end
            else if (wdata[63:60] == 4'd8) begin satp_mode_r <= 1'b1; satp_ppn_r <= wdata[43:0]; end
          end
          default: ;
        endcase
      end
    end
  end

  // ---- harness read-back ----------------------------------------------
  always @(*) case (dbg_sel)
    5'd0: dbg_val = mstatus_value;
    5'd1: dbg_val = mtvec;
    5'd2: dbg_val = mepc;
    5'd3: dbg_val = mcause;
    5'd4: dbg_val = mtval;
    5'd5: dbg_val = mscratch;
    5'd6: dbg_val = mcycle;
    5'd7: dbg_val = minstret;
    5'd8: dbg_val = MISA_VALUE;
    5'd9: dbg_val = mie_value;
    5'd10: dbg_val = mip_value;
    5'd11: dbg_val = {48'd0, medeleg};
    5'd12: dbg_val = mideleg64;
    5'd13: dbg_val = sstatus_value;
    5'd14: dbg_val = sie_value;
    5'd15: dbg_val = sip_value;
    5'd16: dbg_val = stvec;
    5'd17: dbg_val = sepc;
    5'd18: dbg_val = scause;
    5'd19: dbg_val = stval;
    5'd20: dbg_val = sscratch;
    5'd21: dbg_val = {satp_mode_r ? 4'd8 : 4'd0, 16'd0, satp_ppn_r};
    5'd22: dbg_val = {61'd0, mcnt_ir, 1'b0, mcnt_cy};
    5'd23: dbg_val = {61'd0, scnt_ir, 1'b0, scnt_cy};
    5'd24: dbg_val = {62'd0, cur_priv};
    default: dbg_val = 64'd0;
  endcase
endmodule
