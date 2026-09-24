// Port-level test: request stability, and byte lanes outside the request -- in BOTH the bare and the
// translated fetch paths.
//
// Why the translated path matters: the first version of OPT01 widened only S_IF_REQ. Under Sv39 the
// fetch is issued after the walk instead, and that issue stayed at two bytes while S_IF_WAIT consumed
// four. An earlier version of THIS testbench ran a bare-mode program only, so it could not have caught
// the very defect it was written for. The program now runs both phases.
//
//   POISON   every byte OUTSIDE [addr, addr + 2^size) is driven 0xEE. A core that consumes a byte it did
//            not ask for executes garbage and cannot reach its sentinel.
//   STALL    req_ready is held low a varying number of cycles on every request.
//   MONITOR  the payload is latched when a request is first offered and compared on EVERY cycle it is
//            still offered, INCLUDING the accepting cycle -- an earlier version compared only while
//            valid && !ready and so could not see a change on the handshake edge. Withdrawal (valid
//            dropping without an accept) is a violation in its own right. amo and lrsc are compared too.
`timescale 1ns/1ps
module opt01_port_tb;
  localparam MEMBYTES = 1<<16;
  localparam [31:0] SENTINEL = 32'h0000_3000;
  localparam [31:0] MAGIC    = 32'h0000_600d;

  reg clk = 0, reset = 1;
  always #5 clk = ~clk;

  wire        req_valid, req_write, resp_ready;
  wire [31:0] req_addr;
  wire [1:0]  req_size;
  wire [63:0] req_wdata;
  wire [7:0]  req_wmask;
  wire [3:0]  req_amo;
  wire [1:0]  req_lrsc;
  reg         req_ready = 0, resp_valid = 0, resp_error = 0, resp_scfail = 0;
  reg  [63:0] resp_rdata = 0;

  reg [7:0] mem [0:MEMBYTES-1];
  integer violations = 0, withdrawals = 0, reqs = 0, wide_reqs = 0, sv39_wide = 0;
  integer i;
  reg sv39_on = 0;

  // ---- stability monitor: through acceptance, not merely up to it
  // Self-test hooks. MON_SKIP_ACCEPT reverts the monitor to the earlier, weaker form that compared only
  // while valid && !ready; EDGE_INJECT corrupts the held payload on the accepting cycle. Running with
  // both shows the strengthened monitor caches what the weak one missed: with EDGE_INJECT the strong
  // monitor reports a violation and the weak one does not.
  parameter MON_SKIP_ACCEPT = 0;
  parameter EDGE_INJECT     = 0;

  reg        h_valid = 0;
  wire [31:0] h_addr_eff;
  reg [31:0] h_addr;  reg [1:0] h_size; reg h_write;
  reg [63:0] h_wdata; reg [7:0] h_wmask; reg [3:0] h_amo; reg [1:0] h_lrsc;
  assign h_addr_eff = (EDGE_INJECT != 0 && req_ready) ? (h_addr ^ 32'h10) : h_addr;
  always @(posedge clk) if (!reset) begin
    if (req_valid) begin
      if (h_valid && !(MON_SKIP_ACCEPT != 0 && req_ready)) begin
        // The injection perturbs the value being COMPARED, combinationally, on the accepting cycle. A
        // non-blocking assignment to h_addr would not do: the comparison in this same block would still
        // read the old value, and h_valid clears before the next cycle, so nothing would ever differ.
        if (h_addr_eff !== req_addr || h_size !== req_size || h_write !== req_write ||
            h_wdata !== req_wdata || h_wmask !== req_wmask ||
            h_amo !== req_amo || h_lrsc !== req_lrsc) begin
          violations = violations + 1;
          $display("PORT-VIOLATION t=%0t payload moved while offered (ready=%0b)", $time, req_ready);
        end
      end else if (!h_valid) begin
        h_valid <= 1; h_addr <= req_addr; h_size <= req_size; h_write <= req_write;
        h_wdata <= req_wdata; h_wmask <= req_wmask; h_amo <= req_amo; h_lrsc <= req_lrsc;
      end
      if (req_ready) h_valid <= 0;                 // accepted: this request is over
    end else if (h_valid) begin
      // valid dropped without an accept in the same cycle: a withdrawal
      withdrawals = withdrawals + 1;
      violations  = violations + 1;
      $display("PORT-VIOLATION t=%0t request withdrawn before acceptance", $time);
      h_valid <= 0;
    end
  end

  // ---- memory: backpressure, latency, poisoned lanes
  integer stall = 0, lat = 0;
  reg [31:0] p_addr; reg [1:0] p_size; reg p_write; reg [63:0] p_wdata; reg [7:0] p_wmask;
  reg busy = 0;
  reg [3:0] lfsr = 4'b1011;

  always @(posedge clk) begin
    if (reset) begin req_ready <= 0; resp_valid <= 0; busy <= 0; stall <= 0; end
    else begin
      resp_valid <= 0;
      if (!busy) begin
        if (req_valid && !req_ready) begin
          if (stall == 0) begin
            req_ready <= 1; stall <= {28'd0, lfsr[2:0]};
            lfsr <= {lfsr[2:0], lfsr[3]^lfsr[2]};
          end else begin stall <= stall - 1; req_ready <= 0; end
        end else if (req_valid && req_ready) begin
          req_ready <= 0; busy <= 1; lat <= 3 + {28'd0, lfsr[1:0]};
          p_addr <= req_addr; p_size <= req_size; p_write <= req_write;
          p_wdata <= req_wdata; p_wmask <= req_wmask;
          reqs = reqs + 1;
          if (!req_write && req_size == 2'd2) begin
            wide_reqs = wide_reqs + 1;
            if (sv39_on) sv39_wide = sv39_wide + 1;
          end
        end
      end else begin
        if (lat > 0) lat <= lat - 1;
        else begin
          busy <= 0; resp_valid <= 1; resp_error <= 0;
          if (p_write) begin
            for (i = 0; i < 8; i = i + 1)
              if (p_wmask[i]) mem[(p_addr & ~32'd7) + i] <= p_wdata[i*8 +: 8];
            resp_rdata <= 64'd0;
          end else begin
            for (i = 0; i < 8; i = i + 1) begin
              if ((((p_addr & ~32'd7) + i) >= p_addr) &&
                  (((p_addr & ~32'd7) + i) < (p_addr + (32'd1 << p_size))))
                resp_rdata[i*8 +: 8] <= mem[(p_addr & ~32'd7) + i];
              else
                resp_rdata[i*8 +: 8] <= 8'hEE;     // poison: never asked for
            end
          end
        end
      end
    end
  end

  // The program writes a marker word immediately before enabling translation. Watching that rather than
  // reaching into the core keeps this test independent of any internal signal name.
  always @(posedge clk) if (!reset && mem[32'h3010] == 8'h01) sv39_on <= 1;

  // REQ_WITHDRAW is the core's own fault-injection parameter -- "withdraw a request before its
  // handshake" -- so the withdrawal detector is tested against a real RTL fault, not a bench-side fake.
  parameter CORE_REQ_WITHDRAW = 0;
  tcpu_core #(.RESET_PC(64'h0000_0000_0000_1000), .REQ_WITHDRAW(CORE_REQ_WITHDRAW)) dut (
    .clk(clk), .rst(reset),
    .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr), .req_write(req_write),
    .req_size(req_size), .req_wdata(req_wdata), .req_wmask(req_wmask),
    .req_amo(req_amo), .req_lrsc(req_lrsc),
    .resp_valid(resp_valid), .resp_ready(resp_ready), .resp_rdata(resp_rdata),
    .resp_error(resp_error), .resp_scfail(resp_scfail),
    .resv_clear(), .commit_valid(), .commit_pc(), .commit_insn(), .commit_len(),
    .commit_rd_valid(), .commit_rd(), .commit_rd_data(),
    .trap_valid(), .trap_interrupt(), .trap_cause(), .trap_epc(), .trap_tval(), .halted(),
    .dbg_req_is_fetch(), .dbg_ra(5'd0), .dbg_rd(), .dbg_ra2(5'd0), .dbg_rd2(),
    .dbg_csr_sel(5'd0), .dbg_csr_val(), .dbg_priv(),
    .irq_msip(1'b0), .irq_mtip(1'b0), .irq_meip(1'b0),
    .dbg_state(), .dbg_redirect(), .dbg_pc(), .dbg_irq_enabled()
  );

  reg [31:0] got;
  initial begin
    for (i = 0; i < MEMBYTES; i = i + 1) mem[i] = 8'h00;
    $readmemh("prog.hex", mem, 32'h1000);
    repeat (4) @(posedge clk);
    reset = 0;
    repeat (600000) @(posedge clk);

    got = {mem[SENTINEL+3], mem[SENTINEL+2], mem[SENTINEL+1], mem[SENTINEL]};
    $display("PORT_TB reqs=%0d wide=%0d sv39_wide=%0d violations=%0d withdrawals=%0d sentinel=%08x",
             reqs, wide_reqs, sv39_wide, violations, withdrawals, got);
    // CORRECTNESS only. Coverage -- how many wide requests, and whether any occurred under translation
    // -- is reported above and asserted by the runner, which knows what to expect of each core: the
    // accepted core legitimately issues none, so a coverage condition here would fail a correct core.
    if (got === MAGIC && violations == 0)
      $display("TEACHING-OPT01-PORT-OK");
    else begin
      if (got !== MAGIC)   $display("PORT-FAIL sentinel %08x, expected %08x", got, MAGIC);
      if (violations != 0) $display("PORT-FAIL %0d protocol violations", violations);
      $display("TEACHING-OPT01-PORT-FAIL");
      $finish(1);
    end
    $finish;
  end
endmodule
