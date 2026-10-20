// MCU-0 RAM: block RAM on the router's slave interface. Byte-enable write, registered read, hex initialised.
`timescale 1ns/1ps
module mcu_ram #(
  parameter        MEM_BYTES = 65536,
  parameter [31:0] MEM_BASE  = 32'h8000_0000,
  parameter        INIT_HEX  = ""
) (
  input             clk,
  input             sel,
  input             we,
  input      [31:0] addr,
  input      [63:0] wdata,
  input      [7:0]  wmask,
  output reg [63:0] rdata
);
  localparam WORDS = MEM_BYTES / 8;
  localparam AW    = $clog2(WORDS);
  reg [63:0] mem [0:WORDS-1];
  integer i;
  initial begin
    for (i = 0; i < WORDS; i = i + 1) mem[i] = 64'd0;
    if (INIT_HEX != "") $readmemh(INIT_HEX, mem);
  end
  wire [31:0]   off = addr - MEM_BASE;
  wire [AW-1:0] idx = off[AW+2:3];
  always @(posedge clk) begin
    if (sel) begin
      if (we) begin
        for (i = 0; i < 8; i = i + 1)
          if (wmask[i]) mem[idx][i*8 +: 8] <= wdata[i*8 +: 8];
      end
      rdata <= mem[idx];
    end
  end
endmodule
