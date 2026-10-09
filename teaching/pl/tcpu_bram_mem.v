// A synthesizable memory behind PHYSICAL_PORT: what a core needs on pure PL when the capacity fits in BRAM.
//
// It is the harness memory model with the test machinery removed. The contract it keeps, which the harness
// monitors check in simulation:
//   * req_ready is registered: a request is accepted the cycle after it is first seen, never combinationally
//   * the response comes one cycle after acceptance, never in the handshake cycle; one request in flight
//   * a read returns the whole aligned 8-byte word -- the core picks its lanes -- and a write applies exactly
//     the wmask lanes; req_size is not needed for either, so it is ignored
//   * an address outside [MEM_BASE, MEM_BASE + MEM_BYTES) answers resp_error = 1 and touches nothing
//   * an atomic request (req_amo or req_lrsc non-zero) answers resp_error = 1 until a later step adds the
//     reservation and the read-modify-write; nothing is silently done as a plain access
// The array is written with byte enables and read into a register, the pattern Vivado infers as block RAM
// with an output register. 64 KiB is 16 RAMB36; PYNQ-Z1 has 140, so up to about 512 KiB is realistic.
`timescale 1ns/1ps
module tcpu_bram_mem #(
  parameter        MEM_BYTES = 65536,              // power of two, >= 64
  parameter [31:0] MEM_BASE  = 32'h8000_0000,
  parameter        INIT_HEX  = ""                  // $readmemh image: 64-bit words, one per line, from the base
) (
  input             clk,
  input             rst,
  input             req_valid,
  output reg        req_ready,
  input      [31:0] req_addr,
  input             req_write,
  input      [1:0]  req_size,
  input      [63:0] req_wdata,
  input      [7:0]  req_wmask,
  input      [3:0]  req_amo,
  input      [1:0]  req_lrsc,
  output reg        resp_valid,
  input             resp_ready,                    // the core holds it at 1; kept for the bundle's shape
  output reg [63:0] resp_rdata,
  output reg        resp_error,
  output reg        resp_scfail
);
  localparam WORDS = MEM_BYTES / 8;
  localparam AW    = $clog2(WORDS);

  reg [63:0] mem [0:WORDS-1];
  integer i;
  initial begin
    for (i = 0; i < WORDS; i = i + 1) mem[i] = 64'd0;
    if (INIT_HEX != "") $readmemh(INIT_HEX, mem);
  end

  wire [31:0] off      = req_addr - MEM_BASE;
  wire        in_range = (req_addr >= MEM_BASE) && (off < MEM_BYTES);
  wire        atomic   = (req_amo != 4'd0) || (req_lrsc != 2'd0);
  wire [AW-1:0] idx    = off[AW+2:3];

  reg busy;                                        // accepted, response pending
  always @(posedge clk) begin
    if (rst) begin
      req_ready <= 1'b0; busy <= 1'b0; resp_valid <= 1'b0; resp_error <= 1'b0; resp_scfail <= 1'b0; resp_rdata <= 64'd0;
    end else begin
      resp_valid <= 1'b0;
      // offer seen this cycle -> ready next cycle; the handshake is the cycle ready is high
      req_ready <= req_valid && !busy && !req_ready;
      if (req_valid && req_ready) begin
        busy <= 1'b1;
        resp_error <= !in_range || atomic;
        if (in_range && !atomic) begin
          if (req_write) begin
            for (i = 0; i < 8; i = i + 1)
              if (req_wmask[i]) mem[idx][i*8 +: 8] <= req_wdata[i*8 +: 8];
            resp_rdata <= 64'd0;
          end else
            resp_rdata <= mem[idx];
        end else
          resp_rdata <= 64'd0;
      end
      if (busy) begin                              // the cycle after acceptance: answer
        resp_valid <= 1'b1; busy <= 1'b0;
      end
    end
  end
endmodule
