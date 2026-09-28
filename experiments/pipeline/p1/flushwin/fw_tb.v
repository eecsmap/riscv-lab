// PIPE-P1 flush-window bench (codex-pipe-p1-flush-boundary).
//
// Drives tcpu_core_pipe directly: a 64 KiB RAM at 0x8000_0000, one request in flight, fixed ready / response delays
// (+ready-delay, +resp-delay), fetches of one line (+errline) answered with a bus error, and an interrupt line
// raised at a swept cycle (0 = none) and quieted by a store to 0x6000_0000. One process sweeps every interrupt cycle
// from 1 to the length of the interrupt-free run, resetting the core and reloading memory between runs.
//
// Everything below is observed from OUTSIDE the core's own assertions, through hierarchical references to its
// state, so the same bench judges the original RTL and the fixed one:
//   * a front-end flush in cycle t is seen at the next edge as a toggle of dut.fe_ep (the flush block toggles it
//     on every flush, in every mode);
//   * the five same-cycle windows are classified from cycle t's state when its flush is seen;
//   * FW ERROR lines name the property that failed.
`timescale 1ns/1ps
module fw_tb;
  parameter ICB = 1024;       // I-cache bytes (0 = direct fetches)
  parameter PF  = 0;          // PIPE_FAULT of the core under test
  localparam MW = 8192;

  reg clk = 1'b0;
  always #5 clk = ~clk;
  reg rst = 1'b1;
  reg [63:0] mem [0:MW-1];

  wire        req_valid, req_write, resp_ready, dbg_req_is_fetch, halted_o, resv_clear;
  wire [31:0] req_addr;
  wire [1:0]  req_size, req_lrsc, dbg_priv;
  wire [63:0] req_wdata, dbg_rd, dbg_rd2, dbg_csr_val, dbg_pc;
  wire [7:0]  req_wmask;
  wire [3:0]  req_amo, dbg_state;
  reg         req_ready = 1'b0, resp_valid = 1'b0, resp_error = 1'b0;
  reg  [63:0] resp_rdata = 64'd0;
  reg         irq_msip = 1'b0;
  wire        commit_valid, commit_rd_valid, trap_valid, trap_interrupt, dbg_redirect, dbg_irq_enabled;
  wire [63:0] commit_pc, commit_rd_data, trap_cause, trap_epc, trap_tval;
  wire [31:0] commit_insn;
  wire [2:0]  commit_len;
  wire [4:0]  commit_rd;

  tcpu_core_pipe #(.ICACHE_BYTES(ICB), .PIPE_FAULT(PF)) dut (
    .clk(clk), .rst(rst), .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr), .req_write(req_write),
    .req_size(req_size), .req_wdata(req_wdata), .req_wmask(req_wmask), .req_amo(req_amo), .req_lrsc(req_lrsc),
    .resp_valid(resp_valid), .resp_ready(resp_ready), .resp_rdata(resp_rdata), .resp_error(resp_error), .resp_scfail(1'b0),
    .resv_clear(resv_clear), .commit_valid(commit_valid), .commit_pc(commit_pc), .commit_insn(commit_insn),
    .commit_len(commit_len), .commit_rd_valid(commit_rd_valid), .commit_rd(commit_rd), .commit_rd_data(commit_rd_data),
    .trap_valid(trap_valid), .trap_interrupt(trap_interrupt), .trap_cause(trap_cause), .trap_epc(trap_epc),
    .trap_tval(trap_tval), .halted(halted_o), .dbg_req_is_fetch(dbg_req_is_fetch), .dbg_ra(5'd0), .dbg_rd(dbg_rd),
    .dbg_ra2(5'd0), .dbg_rd2(dbg_rd2), .dbg_csr_sel(5'd0), .dbg_csr_val(dbg_csr_val), .dbg_priv(dbg_priv),
    .irq_msip(irq_msip), .irq_mtip(1'b0), .irq_meip(1'b0), .dbg_state(dbg_state), .dbg_redirect(dbg_redirect),
    .dbg_pc(dbg_pc), .dbg_irq_enabled(dbg_irq_enabled));

  // ------------------------------------------------------------------------------------------------ configuration
  integer ready_delay, resp_delay, max_cycles, irq_cycle, pt;
  reg [31:0] TOHOST, RESULT, IRQN, ERRLINE;
  reg [8*256-1:0] hexfile;

  // ------------------------------------------------------------------------------------------------ memory model
  integer    wcnt, rcnt, cyc;
  reg        busy, done;
  reg [31:0] a_addr;
  reg        a_fetch;
  reg [63:0] exit_val;
  integer    b;
  always @(posedge clk) begin
    if (rst) begin
      req_ready <= 1'b0; resp_valid <= 1'b0; resp_error <= 1'b0; busy <= 1'b0; wcnt <= 0; rcnt <= 0; done <= 1'b0;
      cyc <= 0; irq_msip <= 1'b0;
    end else begin
      cyc <= cyc + 1;
      if (irq_cycle != 0 && cyc == irq_cycle) irq_msip <= 1'b1;
      resp_valid <= 1'b0; resp_error <= 1'b0;
      if (busy) begin
        if (rcnt <= 1) begin
          busy <= 1'b0; resp_valid <= 1'b1;
          resp_rdata <= (a_addr[31:16] == 16'h8000) ? mem[a_addr[15:3]] : 64'd0;
          resp_error <= a_fetch ? (a_addr[31:16] != 16'h8000 || a_addr[31:4] == ERRLINE[31:4])
                                : (a_addr[31:16] != 16'h8000 && a_addr != 32'h6000_0000);
        end else rcnt <= rcnt - 1;
      end
      if (req_valid && req_ready) begin
        busy <= 1'b1; rcnt <= resp_delay; req_ready <= 1'b0; wcnt <= 0;
        a_addr <= req_addr; a_fetch <= dbg_req_is_fetch;
        if (req_write) begin
          if (req_addr[31:16] == 16'h8000)
            for (b = 0; b < 8; b = b + 1) if (req_wmask[b]) mem[req_addr[15:3]][b*8 +: 8] <= req_wdata[b*8 +: 8];
          if (req_addr == 32'h6000_0000) irq_msip <= 1'b0;
          if (req_addr == TOHOST) begin done <= 1'b1; exit_val <= req_wdata; end
        end
      end else if (req_valid && !busy && !req_ready) begin
        if (wcnt >= ready_delay) req_ready <= 1'b1; else wcnt <= wcnt + 1;
      end
    end
  end

  // ------------------------------------------------------------------------------------------------ observation
  localparam NW = 6;        // windows: 0 final-beat response, 1 first-beat response, 2 engine allocation,
                            //          3 fetch request offered and not ready, 4 offered and handshaking, 5 error response
  localparam NS = 3;        // flush sources: 0 WB (trap, serialiser, cancel), 1 EX redirect, 2 interrupt-token attachment
  integer cov [0:NW*NS-1];
  integer run_err, tot_err, tot_runs, irq_taken, i;
  reg     s_valid, s_ep, s_txn, s_respf;
  reg     s_w [0:NW-1];
  integer s_src;
  reg     bk, nofill_next;
  reg     p_pend;
  reg [31:0] p_addr; reg p_write; reg [1:0] p_size; reg [63:0] p_wdata; reg [7:0] p_wmask;

  int run_seen [string];      // properties already reported in this run (each is printed once per run)
  int tot_count [string];     // total failing cycles per property over the whole sweep
  int run_count [string];     // runs in which the property failed
  task err(input string name, input string detail);
    begin
      run_err = run_err + 1;
      if (tot_count.exists(name)) tot_count[name] = tot_count[name] + 1; else tot_count[name] = 1;
      if (!run_seen.exists(name)) begin
        run_seen[name] = 1;
        if (run_count.exists(name)) run_count[name] = run_count[name] + 1; else run_count[name] = 1;
        $display("FW ERROR pt=%0d rd=%0d rs=%0d cyc=%0d %0s: %0s", pt, ready_delay, resp_delay, cyc, name, detail);
      end
    end
  endtask

  always @(posedge clk) begin : chk
    reg txn, respf, live, waitst, flushed;
    reg [31:0] exp;
    reg [63:0] pc;
    reg [31:0] fpa;
    if (rst) begin
      s_valid <= 1'b0; bk = 1'b0; nofill_next = 1'b0; p_pend = 1'b0;
    end else begin
      txn    = dut.preq_owner_f && (dut.preq_valid || dut.pwait);
      respf  = dut.port_resp && dut.preq_owner_f;
      live   = !(dut.preq_killed || dut.eng_killed);
      waitst = (dut.eng_st == 3'd2 || dut.eng_st == 3'd4 || dut.eng_st == 3'd6);
      // ---- a flush in the previous cycle (seen now), classified from that cycle's state
      flushed = s_valid && (dut.fe_ep != s_ep);
      if (flushed) begin
        for (i = 0; i < NW; i = i + 1) if (s_w[i]) cov[i*NS + s_src] = cov[i*NS + s_src] + 1;
        if (dut.ic_fill) err("fill-after-flush", $sformatf("an I-cache fill of line 0x%08x follows a flush cycle (the refill response was in that cycle)", dut.ic_fill_pa));
        if (s_txn && !s_respf) bk = 1'b1;           // that fetch transaction is still outstanding: it is killed now
      end
      // ---- a killed transaction's response must fill nothing
      if (nofill_next && dut.ic_fill) err("killed-fill", $sformatf("line 0x%08x filled from a flushed refill", dut.ic_fill_pa));
      nofill_next = 1'b0;
      if (respf && bk) begin nofill_next = 1'b1; bk = 1'b0; end
      if (bk && txn && PF != 3 && !dut.preq_killed) err("not-killed", "a fetch transaction outstanding across a flush is not marked killed");
      // ---- ownership: a fetch transaction exists exactly when the engine waits for it, with the same kill state
      if (txn != waitst)
        err("fetch-owner", $sformatf("fetch transaction outstanding=%0d (valid=%0d wait=%0d) but engine state=%0d killed=%0d",
                                     txn, dut.preq_valid, dut.pwait, dut.eng_st, dut.eng_killed));
      else if (PF != 3 && txn && (dut.preq_killed != dut.eng_killed))
        err("killed-mismatch", $sformatf("request killed=%0d, engine killed=%0d", dut.preq_killed, dut.eng_killed));
      // ---- every fill carries the memory line at its address, and never the error line
      if (dut.ic_fill) begin
        fpa = dut.ic_fill_pa;
        if (dut.ic_fill_data != {mem[{fpa[15:4], 1'b1}], mem[{fpa[15:4], 1'b0}]}) err("fill-data", $sformatf("line 0x%08x filled with data that is not memory", fpa));
        if (fpa[31:4] == ERRLINE[31:4]) err("fill-errline", "the error line was filled");
      end
      // ---- the offered payload is stable until the handshake, and never withdrawn
      if (p_pend) begin
        if (!req_valid) err("withdraw", "a request was withdrawn before its handshake");
        else if (req_addr != p_addr || req_write != p_write || req_size != p_size || req_wdata != p_wdata || req_wmask != p_wmask)
          err("payload", "the offered payload changed before the handshake");
      end
      p_pend = req_valid && !req_ready;
      p_addr = req_addr; p_write = req_write; p_size = req_size; p_wdata = req_wdata; p_wmask = req_wmask;
      // ---- no stray delivery: an instruction reaching ID is the memory word at its pc; a fetch fault only on the error line
      if (dut.id_v && !dut.id_irq) begin
        pc = dut.id_pc;
        if (dut.id_exc) begin
          if (pc[31:4] != ERRLINE[31:4]) err("id-fetch-fault", $sformatf("pc 0x%0h carries a fetch fault", pc));
        end else if (pc[31:16] == 16'h8000) begin
          exp = pc[2] ? mem[pc[15:3]][63:32] : mem[pc[15:3]][31:0];
          if (dut.id_insn != exp) err("id-content", $sformatf("pc 0x%0h holds %08x, memory has %08x", pc, dut.id_insn, exp));
        end
      end
      // interrupts up to the exit store only: one taken in the exit spin loop is after the program's own count
      if (trap_valid && trap_interrupt && !done) irq_taken = irq_taken + 1;
      // ---- this cycle's state, for the flush seen at the next edge
      s_valid <= 1'b1; s_ep <= dut.fe_ep; s_txn <= txn; s_respf <= respf;
      s_w[0] <= respf && live && (dut.eng_st == 3'd4 || dut.eng_st == 3'd6) && !resp_error;
      s_w[1] <= respf && live && dut.eng_st == 3'd2 && !resp_error;
      s_w[2] <= (dut.eng_st == 3'd1 || dut.eng_st == 3'd3 || dut.eng_st == 3'd5) && dut.port_free && !dut.mem_alloc &&
                !dut.frozen && !dut.eng_killed;
      s_w[3] <= dut.preq_valid && dut.preq_owner_f && !req_ready;
      s_w[4] <= dut.preq_valid && dut.preq_owner_f && req_ready;
      s_w[5] <= respf && resp_error;
      s_src  <= (dut.wb_flush && !dut.halted) ? 0 : dut.ex_redirect ? 1 : 2;
    end
  end

  // ------------------------------------------------------------------------------------------------ the sweep
  integer base_len, first, last, step;
  task one_run(input integer at);
    integer k;
    begin
      pt = at; irq_cycle = at; run_err = 0; irq_taken = 0; run_seen.delete();
      rst = 1'b1;
      $readmemh(hexfile, mem);
      repeat (4) @(posedge clk);
      #1 rst = 1'b0;
      k = 0;
      while (!done && k < max_cycles) begin @(posedge clk); k = k + 1; end
      repeat (4) @(posedge clk);                   // let the tohost store's response arrive
      if (!done) err("timeout", $sformatf("no exit within %0d cycles", max_cycles));
      else if ((exit_val >> 1) != 0) err("exit-code", $sformatf("the program's self-check %0d failed", exit_val >> 1));
      if (irq_taken != mem[IRQN[15:3]]) err("irq-count", $sformatf("%0d interrupts on the trap port, the program counted %0d", irq_taken, mem[IRQN[15:3]]));
      $display("FW RUN pt=%0d rd=%0d rs=%0d code=%0d cycles=%0d irq_taken=%0d sum=%016h errors=%0d",
               at, ready_delay, resp_delay, done ? (exit_val >> 1) : 64'd999, k, irq_taken, mem[RESULT[15:3]], run_err);
      tot_err = tot_err + run_err; tot_runs = tot_runs + 1;
    end
  endtask

  initial begin
    if (!$value$plusargs("hex=%s", hexfile)) begin $display("FW USAGE: +hex= missing"); $finish; end
    if (!$value$plusargs("tohost=%h", TOHOST) || !$value$plusargs("result=%h", RESULT) ||
        !$value$plusargs("irqn=%h", IRQN) || !$value$plusargs("errline=%h", ERRLINE)) begin
      $display("FW USAGE: +tohost= +result= +irqn= +errline= are required"); $finish;
    end
    if (!$value$plusargs("ready-delay=%d", ready_delay)) ready_delay = 0;
    if (!$value$plusargs("resp-delay=%d", resp_delay)) resp_delay = 1;
    if (resp_delay < 1) resp_delay = 1;
    if (!$value$plusargs("max-cycles=%d", max_cycles)) max_cycles = 200000;
    if (!$value$plusargs("step=%d", step)) step = 1;
    for (i = 0; i < NW*NS; i = i + 1) cov[i] = 0;
    tot_err = 0; tot_runs = 0; irq_cycle = 0;
    one_run(0);                                  // the interrupt-free run sets the sweep length
    base_len = 0;
    if (done) base_len = cyc;
    for (first = 1; first <= base_len; first = first + step) one_run(first);
    $display("FW COVER icache=%0d pf=%0d rd=%0d rs=%0d final=%0d/%0d/%0d first=%0d/%0d/%0d alloc=%0d/%0d/%0d offered=%0d/%0d/%0d handshake=%0d/%0d/%0d error=%0d/%0d/%0d (per window: WB/EX/IRQ flushes)",
             ICB, PF, ready_delay, resp_delay, cov[0], cov[1], cov[2], cov[3], cov[4], cov[5], cov[6], cov[7], cov[8],
             cov[9], cov[10], cov[11], cov[12], cov[13], cov[14], cov[15], cov[16], cov[17]);
    begin : counts
      string nm;
      if (tot_count.first(nm)) do $display("FW ERRCOUNT %0s runs=%0d cycles=%0d", nm, run_count[nm], tot_count[nm]); while (tot_count.next(nm));
    end
    $display("FW TOTAL runs=%0d errors=%0d", tot_runs, tot_err);
    $finish;
  end
endmodule
