// PIPE-P2a uncached instruction-access footprint bench (codex-pipe-p2a-uncached-fetch).
//
// tcpu_core_pipe (M off, C on) with 64 KiB of RAM at 0x8000_0000 and a 4 KiB "device" window at 0x4000_0000
// (uncached per tcpu_cacheable, so every fetch there is an uncached instruction access). Fixed ready / response
// delays (+ready-delay, +resp-delay). Reads of the device addresses +err1/+err2/+err3 answer with an error.
// Every device read is recorded (address, size). Footprint, per 16-bit halfword h of the window:
//   reads(h) = number of device reads covering h
//   uses(h)  = number of times h belonged to an instruction the core committed, or to the parcels of an instruction
//              that trapped with an instruction access fault (from its epc up to its mtval, the faulting parcel)
// The access is exact when reads(h) == uses(h) for every h: nothing before the pc, nothing after the instruction,
// nothing past a taken branch, no parcel read twice. Also checked: every device read is 2 bytes (a parcel), a
// request keeps its payload until its handshake, and the program's own checks pass (exit 0).
`timescale 1ns/1ps
module nc_tb;
  parameter PF = 0;
  reg clk = 1'b0; always #5 clk = ~clk;
  reg rst = 1'b1;
  reg [63:0] ram [0:8191];
  reg [63:0] dev [0:511];
  wire        req_valid, req_write, resp_ready, dbg_req_is_fetch, halted_o, resv_clear;
  wire [31:0] req_addr;
  wire [1:0]  req_size, req_lrsc, dbg_priv;
  wire [63:0] req_wdata, dbg_rd, dbg_rd2, dbg_csr_val, dbg_pc;
  wire [7:0]  req_wmask;
  wire [3:0]  req_amo, dbg_state;
  reg         req_ready = 1'b0, resp_valid = 1'b0, resp_error = 1'b0;
  reg  [63:0] resp_rdata = 64'd0;
  wire        commit_valid, commit_rd_valid, trap_valid, trap_interrupt, dbg_redirect, dbg_irq_enabled;
  wire [63:0] commit_pc, commit_rd_data, trap_cause, trap_epc, trap_tval;
  wire [31:0] commit_insn;
  wire [2:0]  commit_len;
  wire [4:0]  commit_rd;
  tcpu_core_pipe #(.PIPE_EXT_C(1), .PIPE_FAULT(PF)) dut (
    .clk(clk), .rst(rst), .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr), .req_write(req_write),
    .req_size(req_size), .req_wdata(req_wdata), .req_wmask(req_wmask), .req_amo(req_amo), .req_lrsc(req_lrsc),
    .resp_valid(resp_valid), .resp_ready(resp_ready), .resp_rdata(resp_rdata), .resp_error(resp_error), .resp_scfail(1'b0),
    .resv_clear(resv_clear), .commit_valid(commit_valid), .commit_pc(commit_pc), .commit_insn(commit_insn),
    .commit_len(commit_len), .commit_rd_valid(commit_rd_valid), .commit_rd(commit_rd), .commit_rd_data(commit_rd_data),
    .trap_valid(trap_valid), .trap_interrupt(trap_interrupt), .trap_cause(trap_cause), .trap_epc(trap_epc),
    .trap_tval(trap_tval), .halted(halted_o), .dbg_req_is_fetch(dbg_req_is_fetch), .dbg_ra(5'd0), .dbg_rd(dbg_rd),
    .dbg_ra2(5'd0), .dbg_rd2(dbg_rd2), .dbg_csr_sel(5'd0), .dbg_csr_val(dbg_csr_val), .dbg_priv(dbg_priv),
    .irq_msip(1'b0), .irq_mtip(1'b0), .irq_meip(1'b0), .dbg_state(dbg_state), .dbg_redirect(dbg_redirect),
    .dbg_pc(dbg_pc), .dbg_irq_enabled(dbg_irq_enabled));

  integer ready_delay, resp_delay, max_cycles, wcnt, rcnt, cyc, b, h;
  reg [31:0] TOHOST, ERR1, ERR2, ERR3;
  reg [8*256-1:0] ramhex, devhex;
  reg busy, done; reg [31:0] a_addr; reg [1:0] a_size; reg [63:0] exit_val;
  integer reads [0:2047]; integer uses [0:2047];
  integer n_dev_reads, n_wide_reads, n_payload_err;
  function in_dev(input [31:0] a); in_dev = (a[31:12] == 20'h40000); endfunction
  always @(posedge clk) begin
    if (rst) begin req_ready <= 0; resp_valid <= 0; resp_error <= 0; busy <= 0; wcnt <= 0; rcnt <= 0; done <= 0; cyc <= 0; end
    else begin
      cyc <= cyc + 1;
      resp_valid <= 0; resp_error <= 0;
      if (busy) begin
        if (rcnt <= 1) begin
          busy <= 0; resp_valid <= 1;
          if (a_addr[31:16] == 16'h8000) begin resp_rdata <= ram[a_addr[15:3]]; resp_error <= 0; end
          else if (in_dev(a_addr)) begin
            resp_rdata <= dev[a_addr[11:3]];
            resp_error <= (a_addr == ERR1 || a_addr == ERR2 || a_addr == ERR3);
          end else begin resp_rdata <= 64'd0; resp_error <= (a_addr != 32'h6000_0000); end
        end else rcnt <= rcnt - 1;
      end
      if (req_valid && req_ready) begin
        busy <= 1; rcnt <= resp_delay; req_ready <= 0; wcnt <= 0; a_addr <= req_addr; a_size <= req_size;
        if (in_dev(req_addr)) begin
          n_dev_reads = n_dev_reads + 1;
          if (req_size != 2'd1) n_wide_reads = n_wide_reads + 1;
          // every halfword the access touches
          for (b = 0; b < (1 << req_size); b = b + 2) reads[req_addr[11:1] + b / 2] = reads[req_addr[11:1] + b / 2] + 1;
          $display("NC READ cyc=%0d addr=%08x size=%0d%s", cyc, req_addr, 1 << req_size,
                   (req_addr == ERR1 || req_addr == ERR2 || req_addr == ERR3) ? " (answered with error)" : "");
        end
        if (req_write) begin
          if (req_addr[31:16] == 16'h8000)
            for (b = 0; b < 8; b = b + 1) if (req_wmask[b]) ram[req_addr[15:3]][b*8 +: 8] <= req_wdata[b*8 +: 8];
          if (req_addr == TOHOST) begin done <= 1; exit_val <= req_wdata; end
        end
      end else if (req_valid && !busy && !req_ready) begin
        if (wcnt >= ready_delay) req_ready <= 1; else wcnt <= wcnt + 1;
      end
    end
  end
  // ---- uses: committed device instructions, and the fetched parcels of a device instruction that faulted
  reg p_pend; reg [31:0] p_addr; reg [1:0] p_size;
  always @(posedge clk) if (!rst) begin
    if (commit_valid && in_dev(commit_pc[31:0])) begin
      uses[commit_pc[11:1]] = uses[commit_pc[11:1]] + 1;
      if (commit_len == 3'd4) uses[commit_pc[11:1] + 1] = uses[commit_pc[11:1] + 1] + 1;
    end
    if (trap_valid && !trap_interrupt && trap_cause == 64'd1 && in_dev(trap_epc[31:0])) begin
      uses[trap_epc[11:1]] = uses[trap_epc[11:1]] + 1;
      if (trap_tval == trap_epc + 64'd2) uses[trap_epc[11:1] + 1] = uses[trap_epc[11:1] + 1] + 1;
    end
    if (p_pend && (!req_valid || req_addr != p_addr || req_size != p_size)) n_payload_err = n_payload_err + 1;
    p_pend = req_valid && !req_ready; p_addr = req_addr; p_size = req_size;
  end

  integer k, viol, asserts, ncyc;
  initial begin
    if (!$value$plusargs("ram=%s", ramhex) || !$value$plusargs("dev=%s", devhex) || !$value$plusargs("tohost=%h", TOHOST) ||
        !$value$plusargs("err1=%h", ERR1) || !$value$plusargs("err2=%h", ERR2) || !$value$plusargs("err3=%h", ERR3)) begin
      $display("NC USAGE: +ram= +dev= +tohost= +err1= +err2= +err3= are required"); $finish;
    end
    if (!$value$plusargs("ready-delay=%d", ready_delay)) ready_delay = 0;
    if (!$value$plusargs("resp-delay=%d", resp_delay)) resp_delay = 1;
    if (resp_delay < 1) resp_delay = 1;
    if (!$value$plusargs("max-cycles=%d", max_cycles)) max_cycles = 200000;
    for (k = 0; k < 2048; k = k + 1) begin reads[k] = 0; uses[k] = 0; end
    n_dev_reads = 0; n_wide_reads = 0; n_payload_err = 0; p_pend = 0;
    $readmemh(ramhex, ram); $readmemh(devhex, dev);
    repeat (4) @(posedge clk); #1 rst = 0;
    k = 0; while (!done && k < max_cycles) begin @(posedge clk); k = k + 1; end
    ncyc = k;
    repeat (6) @(posedge clk);
    viol = 0;
    for (k = 0; k < 2048; k = k + 1) if (reads[k] != uses[k]) begin
      viol = viol + 1;
      if (viol <= 8) $display("NC FOOTPRINT halfword 0x%08x: read %0d time(s), used by executed or faulting instructions %0d time(s)",
                              32'h4000_0000 + 2 * k, reads[k], uses[k]);
    end
    $display("NC END pf=%0d rd=%0d rs=%0d code=%0d cycles=%0d device_reads=%0d non_parcel_reads=%0d footprint_violations=%0d payload_errors=%0d",
             PF, ready_delay, resp_delay, done ? (exit_val >> 1) : 64'd999, ncyc, n_dev_reads, n_wide_reads, viol, n_payload_err);
    $finish;
  end
endmodule
