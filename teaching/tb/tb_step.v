// Testbench for the teaching steps: loads a program image into the harness memory, runs the core, and
// decides PASS / FAIL from the tohost word and the harness's own error counters.
//
//   +hex=<file>        64-bit little-endian words, one per line, image base 0x8000_0000 (tools/elf2hex.py)
//   +tohost=<addr>     the ELF's tohost word; the program ends by writing (code << 1) | 1 to it
//   +maxcycles=<n>     give up after this many cycles (default 200000); a timeout is a FAIL
//   +vcd=<file>        optional waveform dump
//
// The verdict needs all of: tohost code 0, proto_errors == 0, obs_errors == 0, at least one retirement.
// Fault-injection and timing parameters are passed through to the harness: iverilog -P tb_step.NAME=value.
`timescale 1ns/1ps
module tb_step #(
  parameter READY_DELAY = 0, parameter RESP_DELAY = 1, parameter RANDOM = 0, parameter SEED = 1,
  parameter X0_WRITABLE = 0, parameter NO_LOAD_SEXT = 0, parameter MEM_SAME_CYCLE = 0,
  parameter REQ_WITHDRAW = 0, parameter LOAD_WDATA_LEAK = 0, parameter TAIL_ERR = 0, parameter TAIL_DROP = 0,
  parameter STOP_ON_TRAP = 0, parameter TRAP_BAD_MEPC = 0, parameter TRAP_COUNTS_RET = 0,
  parameter ALLOW_RO_WRITE = 0, parameter EARLY_IRQ = 0, parameter IRQ_BAD_MEPC = 0, parameter STALE_MIE = 0,
  parameter IRQ_POINT = 0, parameter IRQ_LINE = 0, parameter IRQ_TIMES = 1, parameter IRQ_AFTER = 0,
  parameter IRQ_ARM_REQUIRED = 0, parameter IRQ_NEED_ENABLED = 0, parameter FETCH_ERR_AFTER = 0,
  parameter FETCH_ERR_ADDR = 0
);
  reg clk = 1'b0, rst = 1'b1;
  always #5 clk = ~clk;

  wire        commit_valid, commit_rd_valid, trap_valid, trap_interrupt, halted;
  wire [63:0] commit_pc, commit_rd_data, trap_cause, trap_epc, trap_tval;
  wire [31:0] commit_insn;
  wire [2:0]  commit_len;
  wire [4:0]  commit_rd;
  wire [63:0] proto_errors, n_req, n_resp, n_data_req, obs_errors, n_discard;
  wire [63:0] irq_hits, irq_fires, irq_clears, fire_cycle, fire_pc, apply_seq, apply1_cycle, apply2_cycle;
  wire [63:0] apply1_data, apply2_data, watch_req, watch_wreq, watch_resp, watch_writes;
  wire [3:0]  fire_state, cpu_state;
  wire [1:0]  fire_priv, cpu_priv;
  wire        fire_enabled, fire_req_valid, fire_req_ready, fire_outstanding, fire_is_write;
  wire [31:0] fire_addr;
  wire [63:0] cpu_pc, bd_rd_data, bd_reg_data, bd_csr_data;
  reg  [31:0] tohost_addr = 32'd0;

  tcpu_harness #(.READY_DELAY(READY_DELAY), .RESP_DELAY(RESP_DELAY), .RANDOM(RANDOM), .SEED(SEED),
    .X0_WRITABLE(X0_WRITABLE), .NO_LOAD_SEXT(NO_LOAD_SEXT), .MEM_SAME_CYCLE(MEM_SAME_CYCLE),
    .REQ_WITHDRAW(REQ_WITHDRAW), .LOAD_WDATA_LEAK(LOAD_WDATA_LEAK), .TAIL_ERR(TAIL_ERR), .TAIL_DROP(TAIL_DROP),
    .STOP_ON_TRAP(STOP_ON_TRAP), .TRAP_BAD_MEPC(TRAP_BAD_MEPC), .TRAP_COUNTS_RET(TRAP_COUNTS_RET),
    .ALLOW_RO_WRITE(ALLOW_RO_WRITE), .EARLY_IRQ(EARLY_IRQ), .IRQ_BAD_MEPC(IRQ_BAD_MEPC), .STALE_MIE(STALE_MIE),
    .IRQ_POINT(IRQ_POINT), .IRQ_LINE(IRQ_LINE), .IRQ_TIMES(IRQ_TIMES), .IRQ_AFTER(IRQ_AFTER),
    .IRQ_ARM_REQUIRED(IRQ_ARM_REQUIRED), .IRQ_NEED_ENABLED(IRQ_NEED_ENABLED),
    .FETCH_ERR_AFTER(FETCH_ERR_AFTER), .FETCH_ERR_ADDR(FETCH_ERR_ADDR)) h (
    .clk(clk), .rst(rst),
    .bd_we(1'b0), .bd_addr(16'd0), .bd_data(64'd0), .bd_rd_addr(16'd0), .bd_rd_data(bd_rd_data),
    .bd_fault_addr(tohost_addr), .bd_watch_addr(32'd0), .bd_inject_pc(64'd0), .bd_core_rst(1'b0),
    .cpu_state_o(cpu_state), .cpu_pc_o(cpu_pc), .bd_reg_addr(5'd0), .bd_reg_data(bd_reg_data),
    .bd_csr_sel(5'd0), .bd_csr_data(bd_csr_data), .cpu_priv_o(cpu_priv),
    .commit_valid(commit_valid), .commit_pc(commit_pc), .commit_insn(commit_insn), .commit_len(commit_len),
    .commit_rd_valid(commit_rd_valid), .commit_rd(commit_rd), .commit_rd_data(commit_rd_data),
    .trap_valid(trap_valid), .trap_interrupt(trap_interrupt), .trap_cause(trap_cause), .trap_epc(trap_epc),
    .trap_tval(trap_tval), .halted(halted), .proto_errors(proto_errors), .n_req(n_req), .n_resp(n_resp),
    .n_data_req(n_data_req), .obs_errors(obs_errors), .n_discard(n_discard),
    .irq_hits(irq_hits), .irq_fires(irq_fires), .irq_clears(irq_clears),
    .fire_cycle(fire_cycle), .fire_pc(fire_pc), .fire_state(fire_state), .fire_enabled(fire_enabled),
    .fire_priv(fire_priv), .fire_req_valid(fire_req_valid), .fire_req_ready(fire_req_ready),
    .fire_outstanding(fire_outstanding), .fire_is_write(fire_is_write), .fire_addr(fire_addr),
    .apply_seq(apply_seq), .apply1_cycle(apply1_cycle), .apply2_cycle(apply2_cycle),
    .apply1_data(apply1_data), .apply2_data(apply2_data),
    .watch_req(watch_req), .watch_wreq(watch_wreq), .watch_resp(watch_resp), .watch_writes(watch_writes));

  localparam [31:0] MEM_BASE = 32'h8000_0000;
  integer cycles = 0, commits = 0, traps = 0, maxcycles = 200000, i;
  reg [1023:0] hexfile, vcdfile;
  reg [63:0] tohost_val;
  wire [15:0] tohost_idx = (tohost_addr - MEM_BASE) >> 3;

  initial begin
    if (!$value$plusargs("hex=%s", hexfile)) begin $display("tb_step: +hex=<file> is required"); $finish; end
    if (!$value$plusargs("tohost=%h", tohost_addr)) begin $display("tb_step: +tohost=<addr> is required"); $finish; end
    if ($value$plusargs("maxcycles=%d", maxcycles)) ;
    $display("PARAMS READY_DELAY=%0d RESP_DELAY=%0d RANDOM=%0d SEED=%0d REQ_WITHDRAW=%0d X0_WRITABLE=%0d NO_LOAD_SEXT=%0d STOP_ON_TRAP=%0d IRQ_POINT=%0d",
             READY_DELAY, RESP_DELAY, RANDOM, SEED, REQ_WITHDRAW, X0_WRITABLE, NO_LOAD_SEXT, STOP_ON_TRAP, IRQ_POINT);
    for (i = 0; i < (1 << 16); i = i + 1) h.mem[i] = 64'd0;   // no X in memory: an unwritten word reads 0
    $readmemh(hexfile, h.mem);
    if ($value$plusargs("vcd=%s", vcdfile)) begin $dumpfile(vcdfile); $dumpvars(0, tb_step); end
    repeat (3) @(posedge clk);
    #1 rst = 1'b0;
  end

  // the commit stream, one line per retirement or trap, is the student's first debugging tool
  always @(posedge clk) if (!rst) begin
    cycles = cycles + 1;
    if (commit_valid) begin
      commits = commits + 1;
      if (commit_rd_valid) $display("COMMIT cyc=%0d pc=%h insn=%h x%0d=%h", cycles, commit_pc[31:0], commit_insn, commit_rd, commit_rd_data);
      else                 $display("COMMIT cyc=%0d pc=%h insn=%h", cycles, commit_pc[31:0], commit_insn);
    end
    if (trap_valid) begin
      traps = traps + 1;
      $display("TRAP   cyc=%0d cause=%0d epc=%h tval=%h%s", cycles, trap_cause[62:0], trap_epc[31:0], trap_tval, trap_interrupt ? " (interrupt)" : "");
    end
    tohost_val = h.mem[tohost_idx];
    if (tohost_val != 64'd0) begin
      // let the response to the tohost store return, so a write that is never answered still shows up
      repeat (8) @(posedge clk);
      finish_run(tohost_val);
    end
    if (cycles >= maxcycles) begin
      $display("TIMEOUT after %0d cycles: tohost never written (pc=%h state=%0d)", cycles, cpu_pc[31:0], cpu_state);
      finish_run(64'd0);
    end
  end

  task finish_run; input [63:0] th; reg ok; begin
    ok = (th == 64'd1) && (proto_errors == 64'd0) && (obs_errors == 64'd0) && (commits > 0);
    $display("SUMMARY cycles=%0d commits=%0d traps=%0d requests=%0d responses=%0d proto_errors=%0d obs_errors=%0d",
             cycles, commits, traps, n_req, n_resp, proto_errors, obs_errors);
    if (th == 64'd0)          $display("TOHOST never written");
    else if (th[0] == 1'b0)   $display("TOHOST malformed value %h (bit 0 must be 1)", th);
    else                      $display("TOHOST code=%0d", th >> 1);
    if (ok) $display("RESULT PASS"); else $display("RESULT FAIL");
    $finish;
  end endtask
endmodule
