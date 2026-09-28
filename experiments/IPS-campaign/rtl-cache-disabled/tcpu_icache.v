// A small blocking, physically tagged instruction cache.
//
// Design fixed before implementation in experiments/IPS-campaign/STAGE3-DESIGN.md. Geometry frozen:
// 1 KiB, direct mapped, 16-byte lines -- 64 lines, tag = pa[31:10], index = pa[9:4].
//
// The property that matters most is structural rather than checked: **a line cannot be half filled.**
// `fill` takes the WHOLE 128-bit line in one cycle, so a refill that errored on its second beat simply
// never asserts it. There is no interface through which a partial line could be marked valid.
//
// BYTES = 0 removes it: `hit` is constant 0 and every fetch goes to memory, which must be
// architecturally identical to the predecessor stage.
`timescale 1ns/1ps
module tcpu_icache #(
  parameter BYTES      = 1024,
  parameter LINE_BYTES = 16
) (
  input             clk,
  input             rst,
  input             invalidate,        // fence.i, and anything else that must not leave a stale line

  input      [31:0] pa,
  output            hit,
  output    [127:0] line_data,

  // one cycle, the whole line, ONLY from a complete refill in which no beat reported an error
  input             fill,
  input      [31:0] fill_pa,
  input     [127:0] fill_data
);
  localparam LINES = BYTES / LINE_BYTES;

  generate
  if (BYTES == 0) begin : g_disabled
    assign hit = 1'b0;
    assign line_data = 128'd0;
    wire _unused = &{1'b0, clk, rst, invalidate, pa, fill, fill_pa, fill_data};
  end else begin : g_cache
    // 1 KiB / 16 B = 64 lines -> index is pa[9:4], tag is pa[31:10]
    localparam IDX_LO  = 4;                                  // log2(LINE_BYTES)
    localparam IDX_BITS = (LINES <= 1)   ? 1 :
                          (LINES <= 2)   ? 1 :
                          (LINES <= 4)   ? 2 :
                          (LINES <= 8)   ? 3 :
                          (LINES <= 16)  ? 4 :
                          (LINES <= 32)  ? 5 :
                          (LINES <= 64)  ? 6 :
                          (LINES <= 128) ? 7 : 8;
    localparam TAG_LO  = IDX_LO + IDX_BITS;

    reg              v    [0:LINES-1];
    reg  [31:TAG_LO] tag  [0:LINES-1];
    reg  [127:0]     data [0:LINES-1];

    wire [IDX_BITS-1:0] idx      = pa[IDX_LO +: IDX_BITS];
    wire [IDX_BITS-1:0] fill_idx = fill_pa[IDX_LO +: IDX_BITS];

    assign hit       = v[idx] && (tag[idx] == pa[31:TAG_LO]);
    assign line_data = data[idx];

    integer i;
    always @(posedge clk) begin
      if (rst || invalidate) begin
        // every line, in one cycle. Reset and fence.i are the same action here: nothing survives.
        for (i = 0; i < LINES; i = i + 1) v[i] <= 1'b0;
      end else if (fill) begin
        v   [fill_idx] <= 1'b1;
        tag [fill_idx] <= fill_pa[31:TAG_LO];
        data[fill_idx] <= fill_data;
      end
    end
  end
  endgenerate
endmodule
