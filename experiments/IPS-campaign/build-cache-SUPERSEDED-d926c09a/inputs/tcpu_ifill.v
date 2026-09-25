// The instruction cache, presenting the core's OWN memory-port interface.
//
// Same approach as tcpu_xlate took for the TLB: the core's fetch states are not changed at all. This
// sits between the core's request and the outside port, answers a cacheable instruction fetch from a
// resident line without going out, and otherwise passes everything through untouched.
//
// Why this placement satisfies "cache only validated executable RAM accesses after translation and the
// permission check": by the time the core drives a request, translation has already happened --
// S_XLATE issues at ptw_pa, and the untranslated path issues at pc only when satp is off. The address
// arriving here is physical and the architecture has already agreed the instruction stream may read
// it. Nothing here can cache something translation would have refused.
//
// A refill is exactly one line, at {addr[31:4], 4'b0}, in two 64-bit beats. It never crosses a line
// boundary, and a 16-byte line inside a 4 KiB page cannot cross into the next page -- so "no new
// transactions to adjacent inaccessible pages" follows from the geometry rather than from a check.
//
// `valid` is written on the LAST beat and only when NEITHER beat reported an error, so a failed refill
// leaves no line. The requesting access keeps its own error: the core sees resp_error exactly as it
// would have without a cache.
`timescale 1ns/1ps
module tcpu_ifill #(
  parameter BYTES      = 1024,
  parameter LINE_BYTES = 16
) (
  input             clk,
  input             rst,
  input             invalidate,        // fence.i

  // ---- the core side: the same signals tcpu_core already drives and samples
  input             c_req_valid,
  output            c_req_ready,
  input      [31:0] c_req_addr,
  input      [1:0]  c_req_size,
  input             c_req_write,
  input             c_is_fetch,        // this request is an instruction fetch
  output            c_resp_valid,
  output     [63:0] c_resp_rdata,
  output            c_resp_error,

  // ---- the outside port
  output            m_req_valid,
  input             m_req_ready,
  output     [31:0] m_req_addr,
  output     [1:0]  m_req_size,
  input             m_resp_valid,
  input      [63:0] m_resp_rdata,
  input             m_resp_error,

  // observation only
  output reg        o_hit,
  output reg        o_miss
);
  localparam PASS = 2'd0, FILL0 = 2'd1, FILL1 = 2'd2, ANSWER = 2'd3;

  wire cacheable_addr;
  tcpu_cacheable cb (.pa(c_req_addr), .cacheable(cacheable_addr));

  wire        ic_hit;
  wire [127:0] ic_line;
  reg          ic_fill;
  reg  [31:0]  fill_addr;
  reg  [127:0] fill_data;
  reg          fill_error;

  tcpu_icache #(.BYTES(BYTES), .LINE_BYTES(LINE_BYTES)) ic (
    .clk(clk), .rst(rst), .invalidate(invalidate),
    .pa(state == PASS ? c_req_addr : held_addr), .hit(ic_hit), .line_data(ic_line),
    .fill(ic_fill), .fill_pa(fill_addr), .fill_data(fill_data));

  reg [1:0]  state;
  reg [31:0] held_addr;
  reg        ans_valid, ans_error;
  reg [63:0] ans_data;

  // A cacheable instruction fetch is ours; everything else -- data, the walker's PTE reads, MMIO,
  // writes -- passes through with no change in timing at all.
  wire mine = c_req_valid && c_is_fetch && !c_req_write && cacheable_addr && (BYTES != 0);

  // `issued` drops the request after its handshake. Without it the refill held m_req_valid high for
  // the whole wait and the memory model recorded a fresh request every cycle -- which the bench caught
  // immediately, because it counts what actually went out rather than what was meant to.
  reg issued;
  assign c_req_ready  = mine ? (state == PASS) : m_req_ready;
  assign m_req_valid  = ((state == FILL0) || (state == FILL1)) ? ~issued : (mine ? 1'b0 : c_req_valid);
  assign m_req_addr   = (state == FILL0) ? {held_addr[31:4], 4'b0000} :
                        (state == FILL1) ? {held_addr[31:4], 4'b1000} : c_req_addr;
  // a refill beat is a full 64-bit read; everything else keeps the size the core asked for
  assign m_req_size   = ((state == FILL0) || (state == FILL1)) ? 2'd3 : c_req_size;
  // The pass-through of a response is gated on PASS, not on `mine`. `mine` depends on c_req_valid,
  // which the core drops the moment its request is accepted -- so during a refill `mine` is low and an
  // ungated pass-through would hand the core OUR OWN beats as if they were its response. The core
  // would then consume half a line as an instruction.
  assign c_resp_valid = ans_valid | ((state == PASS) ? m_resp_valid : 1'b0);
  assign c_resp_rdata = ans_valid ? ans_data  : m_resp_rdata;
  assign c_resp_error = ans_valid ? ans_error : ((state == PASS) ? m_resp_error : 1'b0);

  // the 64-bit word the core expects, selected out of the 16-byte line by addr[3]
  wire [63:0] hit_word = held_addr[3] ? ic_line[127:64] : ic_line[63:0];

  always @(posedge clk) begin
    ic_fill <= 1'b0; ans_valid <= 1'b0; o_hit <= 1'b0; o_miss <= 1'b0;
    if (rst) begin
      state <= PASS; held_addr <= 32'd0; fill_data <= 128'd0; fill_error <= 1'b0;
      fill_addr <= 32'd0; ans_error <= 1'b0; ans_data <= 64'd0; issued <= 1'b0;
    end else begin
      if (m_req_valid && m_req_ready) issued <= 1'b1;
      case (state)
      PASS: if (mine && c_req_ready) begin
        held_addr <= c_req_addr;
        if (ic_hit) begin
          o_hit     <= 1'b1;
          ans_valid <= 1'b1;
          ans_data  <= c_req_addr[3] ? ic_line[127:64] : ic_line[63:0];
          ans_error <= 1'b0;
        end else begin
          o_miss     <= 1'b1;
          fill_error <= 1'b0;
          issued     <= 1'b0;
          state      <= FILL0;
        end
      end
      FILL0: if (m_resp_valid) begin
        fill_data[63:0] <= m_resp_rdata;
        fill_error      <= fill_error | m_resp_error;
        issued          <= 1'b0;
        state           <= FILL1;
      end
      FILL1: if (m_resp_valid) begin
        fill_data[127:64] <= m_resp_rdata;
        state             <= ANSWER;
        // valid on the LAST beat, and only if NEITHER beat errored: there is no way to leave half a line
        if (!(fill_error | m_resp_error)) begin
          ic_fill   <= 1'b1;
          fill_addr <= held_addr;
        end
        ans_valid <= 1'b1;
        ans_error <= fill_error | m_resp_error;
        ans_data  <= held_addr[3] ? m_resp_rdata : fill_data[63:0];
      end
      ANSWER: begin state <= PASS; issued <= 1'b0; end
      default: begin state <= PASS; issued <= 1'b0; end
      endcase
    end
  end

  wire _unused = &{1'b0, hit_word};
endmodule
