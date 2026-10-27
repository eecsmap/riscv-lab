// Unit test for the step-3 CSR module (teaching/step3/TODO.md, TODO 6). Drives tcpu_csr's ports directly, no
// program, no core, and nothing but the ports (dbg_sel/dbg_val read the counters), so your internal names are
// free. Copy it next to your other unit tests and run them:
//     mkdir -p work/unit && cp step3/tb_csr.v work/unit/ && make unit
// Checks are grouped in the order you build the module; each line names its stage, so a half-built module
// shows which stage is done:
//   A  decode and read: reset values, misa, mhartid, unknown / read-only addresses
//   B  software writes: WARL masks on mtvec / mepc / mstatus, write intent, misa discards
//   C  counters: mcycle every cycle, minstret per retire, a software write beats the increment
//   D  trap and mret: mepc / mcause / mtval, MIE and MPIE, minstret does not count a trap
`timescale 1ns/1ps
module tb_csr;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg         rst = 1'b1, access = 1'b0, write_intent = 1'b0, read_intent = 1'b0, we = 1'b0;
  reg  [11:0] addr = 12'd0;
  reg  [63:0] wdata = 64'd0;
  reg         retire = 1'b0, trap = 1'b0, mret = 1'b0;
  reg  [63:0] trap_cause = 64'd0, trap_epc = 64'd0, trap_tval = 64'd0;
  reg  [4:0]  dbg_sel = 5'd0;
  wire        addr_illegal;
  wire [63:0] rdata, mtvec_base, mepc_out, dbg_val;

  tcpu_csr dut (.clk(clk), .rst(rst), .addr(addr), .access(access), .write_intent(write_intent),
    .read_intent(read_intent), .addr_illegal(addr_illegal), .rdata(rdata), .we(we), .wdata(wdata),
    .retire(retire), .trap(trap), .trap_cause(trap_cause), .trap_epc(trap_epc), .trap_tval(trap_tval),
    .mret(mret), .mtvec_base(mtvec_base), .mepc_out(mepc_out), .dbg_sel(dbg_sel), .dbg_val(dbg_val));

  localparam [11:0] MSTATUS = 12'h300, MISA = 12'h301, MTVEC = 12'h305, MSCRATCH = 12'h340, MEPC = 12'h341,
                    MCAUSE = 12'h342, MTVAL = 12'h343, MCYCLE = 12'hB00, MINSTRET = 12'hB02,
                    CYCLE = 12'hC00, INSTRET = 12'hC02, MHARTID = 12'hF14;

  integer pass [0:3], fail [0:3], i;
  // clock edges since reset, counted by the bench itself: expected counter deltas are derived from it, not
  // counted by hand (the first version of this test hand-counted 12 edges where there were 11)
  integer edges = 0, e0;
  always @(posedge clk) if (!rst) edges = edges + 1;
  reg [63:0] v, v0;
  reg        ill;

  task check; input integer stage; input [8*64-1:0] what; input [63:0] got, want; begin
    if (got === want) pass[stage] = pass[stage] + 1;
    else begin fail[stage] = fail[stage] + 1;
      $display("FAIL  %s  %0s: got %h, want %h", stage == 0 ? "A" : stage == 1 ? "B" : stage == 2 ? "C" : "D", what, got, want); end
  end endtask

  // a CSR read as the core does it: inputs settle mid-cycle, rdata and addr_illegal are combinational
  task rd; input [11:0] a; input wi; begin
    @(negedge clk); access = 1'b1; addr = a; read_intent = 1'b1; write_intent = wi; we = 1'b0; #1;
    v = rdata; ill = addr_illegal;
    @(negedge clk); access = 1'b0; read_intent = 1'b0; write_intent = 1'b0;
  end endtask
  // a csrrw as the core does it: write intent and we for exactly one clock edge
  task wr; input [11:0] a; input [63:0] d; begin
    @(negedge clk); access = 1'b1; addr = a; write_intent = 1'b1; read_intent = 1'b1; we = 1'b1; wdata = d;
    @(negedge clk); access = 1'b0; write_intent = 1'b0; read_intent = 1'b0; we = 1'b0;
  end endtask

  initial begin
    for (i = 0; i < 4; i = i + 1) begin pass[i] = 0; fail[i] = 0; end
    repeat (2) @(posedge clk); @(negedge clk); rst = 1'b0;

    // ---------------------------------------------------------------- A: decode and read
    rd(MISA, 0);     check(0, "misa reads RV64I",            v, 64'h8000_0000_0000_0100);
                     check(0, "misa is a legal address",     {63'd0, ill}, 64'd0);
    rd(MHARTID, 0);  check(0, "mhartid reads 0",             v, 64'd0);
    rd(MSTATUS, 0);  check(0, "mstatus after reset: MPP=M",  v, 64'h1800);
    rd(MTVEC, 0);    check(0, "mtvec after reset",           v, 64'd0);
    rd(12'h7C0, 0);  check(0, "0x7c0 unknown -> illegal",    {63'd0, ill}, 64'd1);
    rd(12'h3A0, 0);  check(0, "pmpcfg0 unknown -> illegal",  {63'd0, ill}, 64'd1);
    rd(12'hC01, 0);  check(0, "time unknown -> illegal",     {63'd0, ill}, 64'd1);
    rd(CYCLE, 0);    check(0, "read cycle is legal",         {63'd0, ill}, 64'd0);
    rd(CYCLE, 1);    check(0, "write cycle -> illegal",      {63'd0, ill}, 64'd1);
    rd(INSTRET, 1);  check(0, "write instret -> illegal",    {63'd0, ill}, 64'd1);
    rd(MHARTID, 1);  check(0, "write mhartid -> illegal",    {63'd0, ill}, 64'd1);
    rd(MSCRATCH, 1); check(0, "write mscratch is legal",     {63'd0, ill}, 64'd0);
    @(negedge clk); access = 1'b0; addr = 12'h7C0; write_intent = 1'b1; #1;
    check(0, "no access -> never illegal", {63'd0, addr_illegal}, 64'd0);
    write_intent = 1'b0;

    // ---------------------------------------------------------------- B: software writes
    wr(MTVEC, 64'h8000_0103);       rd(MTVEC, 0);    check(1, "mtvec low 2 bits cleared", v, 64'h8000_0100);
    check(1, "mtvec_base output follows mtvec", mtvec_base, 64'h8000_0100);
    wr(MEPC, 64'h8000_0006);        rd(MEPC, 0);     check(1, "mepc low 2 bits cleared (no C)", v, 64'h8000_0004);
    check(1, "mepc_out output follows mepc", mepc_out, 64'h8000_0004);
    wr(MSTATUS, ~64'd0);            rd(MSTATUS, 0);  check(1, "mstatus all ones -> MIE MPIE MPP", v, 64'h1888);
    wr(MSTATUS, 64'd0);             rd(MSTATUS, 0);  check(1, "mstatus zero -> MPP stays M", v, 64'h1800);
    wr(MSCRATCH, 64'h0123_4567_89AB_CDEF); rd(MSCRATCH, 0); check(1, "mscratch round trip", v, 64'h0123_4567_89AB_CDEF);
    wr(MCAUSE, 64'h8000_0000_0000_0007);   rd(MCAUSE, 0);   check(1, "mcause round trip", v, 64'h8000_0000_0000_0007);
    wr(MTVAL, 64'hDEAD_BEEF);       rd(MTVAL, 0);    check(1, "mtval round trip", v, 64'hDEAD_BEEF);
    wr(MISA, ~64'd0);               rd(MISA, 0);     check(1, "misa write discarded", v, 64'h8000_0000_0000_0100);
    // csrrs with rs1 = x0: the core raises we in S_WB but write_intent is 0 -> nothing is written
    @(negedge clk); access = 1'b1; addr = MSCRATCH; write_intent = 1'b0; read_intent = 1'b1; we = 1'b1; wdata = 64'd0;
    @(negedge clk); access = 1'b0; read_intent = 1'b0; we = 1'b0;
    rd(MSCRATCH, 0);                check(1, "we without write intent writes nothing", v, 64'h0123_4567_89AB_CDEF);
    // an illegal write must change nothing: aim at mhartid, then confirm mscratch and mhartid unchanged
    wr(MHARTID, 64'h55);            rd(MHARTID, 0);  check(1, "write to read-only mhartid has no effect", v, 64'd0);

    // ---------------------------------------------------------------- C: counters
    rd(MCYCLE, 0); v0 = v; e0 = edges; repeat (10) @(posedge clk); rd(MCYCLE, 0);
    check(2, "mcycle advances once per clock edge", v - v0, edges - e0);
    rd(CYCLE, 0);  check(2, "cycle reads mcycle", v - v0, edges - e0);
    rd(MINSTRET, 0); v0 = v;
    @(negedge clk); retire = 1'b1; repeat (3) @(negedge clk); retire = 1'b0;
    rd(MINSTRET, 0); check(2, "minstret +3 after three retire cycles", v - v0, 64'd3);
    rd(INSTRET, 0);  check(2, "instret reads minstret", v - v0, 64'd3);
    // software write and the increment in the same cycle: the written value wins
    @(negedge clk); access = 1'b1; addr = MCYCLE; write_intent = 1'b1; we = 1'b1; wdata = 64'd1000; #1;
    dbg_sel = 5'd6; @(posedge clk); #1; check(2, "mcycle write beats that cycle's increment", dbg_val, 64'd1000);
    @(negedge clk); addr = MINSTRET; wdata = 64'd100; retire = 1'b1;
    dbg_sel = 5'd7; @(posedge clk); #1; check(2, "minstret write beats that cycle's retire", dbg_val, 64'd100);
    @(negedge clk); access = 1'b0; write_intent = 1'b0; we = 1'b0; retire = 1'b0;

    // ---------------------------------------------------------------- D: trap and mret
    wr(MSTATUS, 64'h8);             rd(MSTATUS, 0);  check(3, "set MIE", v, 64'h1808);
    rd(MINSTRET, 0); v0 = v;
    @(negedge clk); trap = 1'b1; trap_cause = 64'd2; trap_epc = 64'h8000_0010; trap_tval = 64'h0000_007B;
    @(negedge clk); trap = 1'b0;
    rd(MEPC, 0);     check(3, "trap writes mepc", v, 64'h8000_0010);
    check(3, "mepc_out after trap", mepc_out, 64'h8000_0010);
    rd(MCAUSE, 0);   check(3, "trap writes mcause", v, 64'd2);
    rd(MTVAL, 0);    check(3, "trap writes mtval", v, 64'h7B);
    rd(MSTATUS, 0);  check(3, "trap: MPIE <- MIE, MIE <- 0", v, 64'h1880);
    rd(MINSTRET, 0); check(3, "a trap is not a retirement", v - v0, 64'd0);
    @(negedge clk); mret = 1'b1; @(negedge clk); mret = 1'b0;
    rd(MSTATUS, 0);  check(3, "mret: MIE <- MPIE, MPIE <- 1", v, 64'h1888);
    rd(MEPC, 0);     check(3, "mret leaves mepc alone", v, 64'h8000_0010);
    // MPIE was already 1 above, so 'MPIE <- 1' was not visible; clear it and mret again
    wr(MSTATUS, 64'd0); @(negedge clk); mret = 1'b1; @(negedge clk); mret = 1'b0;
    rd(MSTATUS, 0);  check(3, "mret sets MPIE to 1 even when it was 0", v, 64'h1880);
    dbg_sel = 5'd2; #1; check(3, "dbg_sel 2 is mepc", dbg_val, 64'h8000_0010);
    dbg_sel = 5'd3; #1; check(3, "dbg_sel 3 is mcause", dbg_val, 64'd2);

    $display("STAGE A decode/read   %0d ok, %0d failed", pass[0], fail[0]);
    $display("STAGE B writes        %0d ok, %0d failed", pass[1], fail[1]);
    $display("STAGE C counters      %0d ok, %0d failed", pass[2], fail[2]);
    $display("STAGE D trap/mret     %0d ok, %0d failed", pass[3], fail[3]);
    $display("tb_csr: %0d checks, %0d failed", pass[0]+pass[1]+pass[2]+pass[3]+fail[0]+fail[1]+fail[2]+fail[3],
             fail[0]+fail[1]+fail[2]+fail[3]);
    if (fail[0]+fail[1]+fail[2]+fail[3] == 0) $display("RESULT PASS"); else $display("RESULT FAIL");
    $finish;
  end
endmodule
