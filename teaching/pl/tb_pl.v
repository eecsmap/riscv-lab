// Simulates tcpu_pl_top as it would sit on the board: clock, reset, LEDs. No harness, no monitors -- the
// contract was checked by `make stepN`; this run checks the integration with the BRAM memory.
//   +hex=<file> +tohost=<addr> [+maxcycles=<n>] [+vcd=<file>]
`timescale 1ns/1ps
module tb_pl;
  reg clk = 1'b0, rst = 1'b1;
  always #5 clk = ~clk;
  reg [1023:0] hexfile, vcdfile;
  reg [31:0] tohost_addr;
  integer maxcycles = 200000, cycles = 0, commits = 0;
  wire tohost_valid, tohost_pass, commit_valid;
  wire [62:0] tohost_code;

  // INIT_HEX is a parameter, so the image is loaded by hierarchical reference below instead; the top's own
  // tohost snoop keeps its default address, this bench watches the port for the +tohost address itself
  tcpu_pl_top top (.clk(clk), .rst(rst), .tohost_valid(tohost_valid), .tohost_code(tohost_code),
                   .tohost_pass(tohost_pass), .commit_valid(commit_valid));

  initial begin
    if (!$value$plusargs("hex=%s", hexfile)) begin $display("tb_pl: +hex=<file> is required"); $finish; end
    if (!$value$plusargs("tohost=%h", tohost_addr)) begin $display("tb_pl: +tohost=<addr> is required"); $finish; end
    if ($value$plusargs("maxcycles=%d", maxcycles)) ;
    $readmemh(hexfile, top.mem.mem);
    if ($value$plusargs("vcd=%s", vcdfile)) begin $dumpfile(vcdfile); $dumpvars(0, tb_pl); end
    repeat (3) @(posedge clk);
    #1 rst = 1'b0;
  end

  // the snoop in the top compares against its parameter; here we watch the port for the +tohost address
  reg seen = 1'b0; reg [63:0] val;
  always @(posedge clk) if (!rst) begin
    cycles = cycles + 1;
    if (commit_valid) commits = commits + 1;
    if (top.req_valid && top.req_ready && top.req_write && top.req_addr == tohost_addr) begin
      seen <= 1'b1; val <= top.req_wdata;
    end
    if (seen) begin
      repeat (4) @(posedge clk);
      $display("SUMMARY cycles=%0d commits=%0d", cycles, commits);
      if (val[0] && val[63:1] == 63'd0) $display("TOHOST code=0\nRESULT PASS");
      else begin $display("TOHOST value=%h", val); $display("RESULT FAIL"); end
      $finish;
    end
    if (cycles >= maxcycles) begin
      $display("TIMEOUT after %0d cycles (pc=%h state=%0d)", cycles, top.cpu.dbg_pc[31:0], top.cpu.dbg_state);
      $display("SUMMARY cycles=%0d commits=%0d\nRESULT FAIL", cycles, commits); $finish;
    end
  end
endmodule
