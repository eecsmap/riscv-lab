// MCU-0 VGA text mode (teaching/vga/README.md): 800 x 600 at 60 Hz for a Digilent Pmod VGA on JA + JB.
//
// VESA 800 x 600 @ 60 Hz has a 40.000 MHz pixel clock -- exactly MCU-0's clock -- so the video side runs on the CPU's
// clock: one pixel per cycle, no clock generator and no clock-domain crossing. A line is 1056 clocks (800 visible,
// 40 front porch, 128 sync, 88 back porch), a frame 628 lines (600, 1, 4, 23); both syncs are active high.
//
// The screen is 100 x 75 character cells of 8 x 8 pixels. A cell is a halfword in the text RAM:
//   bits 7:0 character (teaching/mcu0/mcu_vga_font.v: 0x20..0x7F ASCII, 0x80..0x8F quarter blocks), 11:8 foreground
//   colour, 15:12 background colour -- indexes into the fixed 16-colour palette below.
// The CPU writes the cells; the beam reads them on its own, 60 times a second. Nothing else is needed to keep a
// picture up, so drawing is just storing.
//
// Address map (base 0x1003_0000, a 64 KiB window):
//   +0x0000 .. +0x3A97  text RAM, row by row: cell (x, y) is the halfword at 2 * (y * 100 + x). Read/write, any width.
//   +0x4000 FRAME   R   frames started since reset (counts as each vertical blank begins)
//   +0x4008 STATUS  R   bit 0 VBLANK (the beam is between frames: lines 600..627), bits 25:16 the line the beam is on
//   +0x4010 SCROLL  RW  bits 6:0: the text row shown at the top of the screen (0..74); the rows below it follow, and
//                       wrap round. Scrolling a console by one line is one store instead of moving 7,400 cells.
// A store into a cell the beam is drawing shows from the next line of pixels on: change the screen during VBLANK (or
// just after FRAME changes) and no frame ever shows half an update.
//
// The beam side is a 3-stage pipeline: counters -> text RAM -> font ROM -> colour. The syncs and the visible flag go
// through the same three stages, so they stay lined up with the pixels.
`timescale 1ns/1ps
module mcu_vga (
  input             clk,
  input             rst,
  input             sel,
  input             we,
  input      [31:0] addr,
  input      [63:0] wdata,
  input      [7:0]  wmask,
  output     [63:0] rdata,
  output reg [3:0]  r,
  output reg [3:0]  g,
  output reg [3:0]  b,
  output reg        hs,
  output reg        vs
);
  localparam H_VIS = 800, H_SYNC0 = 840, H_SYNC1 = 968, H_TOTAL = 1056;
  localparam V_VIS = 600, V_SYNC0 = 601, V_SYNC1 = 605, V_TOTAL = 628;
  localparam ROWS = 75;

  // ---- the text RAM: 2048 x 64 bits (four cells a word, 7500 cells used), byte writes from the CPU
  reg  [63:0] tmem [0:2047];
  integer i;
  initial for (i = 0; i < 2048; i = i + 1) tmem[i] = 64'd0;

  // ---- the CPU side (the router's one-cycle slave contract)
  wire        is_reg = addr[14];
  reg  [63:0] ram_q, reg_q;
  reg         reg_q_sel;
  reg  [31:0] frame;
  reg  [6:0]  top;
  reg  [10:0] hc;                        // 0 .. 1055
  reg  [9:0]  vc;                        // 0 .. 627
  assign rdata = reg_q_sel ? reg_q : ram_q;

  always @(posedge clk) begin
    if (sel && !is_reg) begin
      for (i = 0; i < 8; i = i + 1)
        if (we && wmask[i]) tmem[addr[13:3]][i*8 +: 8] <= wdata[i*8 +: 8];
      ram_q <= tmem[addr[13:3]];
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      reg_q <= 64'd0; reg_q_sel <= 1'b0; top <= 7'd0;
    end else if (sel) begin
      reg_q_sel <= is_reg;
      reg_q <= (addr[4:3] == 2'd0) ? {32'd0, frame} :
               (addr[4:3] == 2'd1) ? {38'd0, vc, 15'd0, vc >= V_VIS} :
               (addr[4:3] == 2'd2) ? {57'd0, top} : 64'd0;
      if (we && is_reg && addr[4:3] == 2'd2 && wmask[0]) top <= wdata[6:0];
    end
  end

  // ---- the beam: stage 0, counters and the cell under the beam
  always @(posedge clk) begin
    if (rst) begin
      hc <= 11'd0; vc <= 10'd0; frame <= 32'd0;
    end else begin
      if (hc == H_TOTAL - 1) begin
        hc <= 11'd0;
        vc <= (vc == V_TOTAL - 1) ? 10'd0 : vc + 10'd1;
      end else hc <= hc + 11'd1;
      if (hc == 11'd0 && vc == V_VIS) frame <= frame + 32'd1;
    end
  end

  wire [6:0]  row   = vc[9:3];                                 // 0..74 on visible lines
  wire [7:0]  srow  = {1'b0, row} + {1'b0, top};               // scrolled
  wire [6:0]  drow  = (srow >= ROWS) ? srow - ROWS : srow[6:0];
  wire [12:0] cell_i  = {drow, 6'd0} + {1'b0, drow, 5'd0} + {4'd0, drow, 2'd0} + {6'd0, hc[9:3]};   // drow * 100 + col
  wire        vis0  = (hc < H_VIS) && (vc < V_VIS);
  wire        hs0   = (hc >= H_SYNC0) && (hc < H_SYNC1);
  wire        vs0   = (vc >= V_SYNC0) && (vc < V_SYNC1);

  // stage 1: the text RAM word holding the cell
  reg  [63:0] tq;
  reg  [1:0]  lane1;
  reg  [2:0]  y1, x1, x2;
  reg         vis1, hs1, vs1, vis2, hs2, vs2;
  always @(posedge clk) begin
    tq <= tmem[cell_i[12:2]];
    lane1 <= cell_i[1:0]; y1 <= vc[2:0]; x1 <= hc[2:0]; vis1 <= vis0; hs1 <= hs0; vs1 <= vs0;
  end
  wire [15:0] c1 = (lane1 == 2'd0) ? tq[15:0] : (lane1 == 2'd1) ? tq[31:16] : (lane1 == 2'd2) ? tq[47:32] : tq[63:48];

  // stage 2: the glyph's row of 8 pixels
  wire [7:0] glyph;
  reg  [3:0] fg2, bg2;
  mcu_vga_font font (.clk(clk), .addr({c1[7:0], y1}), .q(glyph));
  always @(posedge clk) begin
    fg2 <= c1[11:8]; bg2 <= c1[15:12]; x2 <= x1; vis2 <= vis1; hs2 <= hs1; vs2 <= vs1;
  end
  wire [3:0] idx = glyph[3'd7 - x2] ? fg2 : bg2;

  // stage 3: the palette, black outside the visible area (monitors measure black level during blanking)
  reg [11:0] rgb;
  always @(*)
    case (idx)
      4'd0:  rgb = 12'h000;   // black
      4'd1:  rgb = 12'h00A;   // blue
      4'd2:  rgb = 12'h0A0;   // green
      4'd3:  rgb = 12'h0AA;   // cyan
      4'd4:  rgb = 12'hA00;   // red
      4'd5:  rgb = 12'hA0A;   // magenta
      4'd6:  rgb = 12'hA50;   // brown
      4'd7:  rgb = 12'hAAA;   // light grey
      4'd8:  rgb = 12'h555;   // dark grey
      4'd9:  rgb = 12'h55F;   // light blue
      4'd10: rgb = 12'h5F5;   // light green
      4'd11: rgb = 12'h5FF;   // light cyan
      4'd12: rgb = 12'hF55;   // light red
      4'd13: rgb = 12'hF5F;   // light magenta
      4'd14: rgb = 12'hFF5;   // yellow
      default: rgb = 12'hFFF; // white
    endcase
  always @(posedge clk) begin
    if (rst) begin r <= 4'd0; g <= 4'd0; b <= 4'd0; hs <= 1'b0; vs <= 1'b0; end
    else begin
      r <= vis2 ? rgb[11:8] : 4'd0; g <= vis2 ? rgb[7:4] : 4'd0; b <= vis2 ? rgb[3:0] : 4'd0;
      hs <= hs2; vs <= vs2;
    end
  end
endmodule
