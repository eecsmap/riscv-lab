// CPU-C: the compressed-instruction decompressor. Combinational, one 16-bit parcel in, one 32-bit
// instruction out, plus "illegal" and "hint". RV64 integer subset only (cpu-c/ENCODINGS.md is the table
// this implements, row for row). No F/D here, so every compressed floating-point encoding is illegal.
//
// A HINT expands to `addi x0, x0, 0`: it retires with no architectural effect. Reserved encodings, the
// all-zero parcel, custom space and the FP rows raise `illegal`; the core reports the original parcel.
`timescale 1ns/1ps
module tcpu_cdecode #(
  parameter FAULT_C_IMM = 0,   // fault injection: c.addi4spn's immediate assembled in the wrong order
  parameter FAULT_C_REG = 0    // fault injection: the compact register field mapped to x0..x7 instead of x8..x15
) (
  input      [15:0] c,
  output reg [31:0] insn,
  output reg        illegal,
  output reg        hint
);
  wire [1:0] op = c[1:0];
  wire [2:0] f3 = c[15:13];
  wire [4:0] rd_full  = c[11:7];       // full register fields (CI / CR / CSS formats)
  wire [4:0] rs2_full = c[6:2];
  wire [4:0] rdp  = FAULT_C_REG != 0 ? {2'b00, c[4:2]} : {2'b01, c[4:2]};   // rd'  / rs2' (x8..x15)
  wire [4:0] rs1p = FAULT_C_REG != 0 ? {2'b00, c[9:7]} : {2'b01, c[9:7]};   // rs1' / rd'  (x8..x15)
  // ---- immediates, each assembled from the field positions the spec gives for that format
  // nzuimm[5:4|9:6|2|3] = c[12:11|10:7|6|5] -> value bits [9:6]=c[10:7], [5:4]=c[12:11], [3]=c[5], [2]=c[6]
  wire [9:0]  imm_addi4spn = FAULT_C_IMM != 0 ? {c[10:7], c[12:11], c[6], c[5], 2'b00}   // fault: bits 3 and 2 swapped
                                              : {c[10:7], c[12:11], c[5], c[6], 2'b00};
  wire [6:0]  imm_lw    = {c[5], c[12:10], c[6], 2'b00};                 // uimm[5:3] from 12:10, [2|6] from 6,5
  wire [7:0]  imm_ld    = {c[6:5], c[12:10], 3'b000};                    // uimm[5:3] from 12:10, [7:6] from 6:5
  wire [11:0] imm_ci    = {{7{c[12]}}, c[6:2]};                          // sign-extended 6-bit
  wire [11:0] imm_16sp  = {{3{c[12]}}, c[4:3], c[5], c[2], c[6], 4'b0000}; // nzimm[9|4|6|8:7|5]
  wire [19:0] imm_lui   = {{15{c[12]}}, c[6:2]};                         // nzimm[17:12] sign-extended
  wire [5:0]  shamt     = {c[12], c[6:2]};
  wire [11:0] imm_j     = {c[12], c[8], c[10:9], c[6], c[7], c[2], c[11], c[5:3], 1'b0}; // [11|4|9:8|10|6|7|3:1|5]
  wire [8:0]  imm_b     = {c[12], c[6:5], c[2], c[11:10], c[4:3], 1'b0};  // [8|4:3|7:6|2:1|5]
  wire [7:0]  imm_lwsp  = {c[3:2], c[12], c[6:4], 2'b00};                 // [5] 12, [4:2] 6:4, [7:6] 3:2
  wire [8:0]  imm_ldsp  = {c[4:2], c[12], c[6:5], 3'b000};                // [5] 12, [4:3] 6:5, [8:6] 4:2
  wire [7:0]  imm_swsp  = {c[8:7], c[12:9], 2'b00};                       // [5:2] 12:9, [7:6] 8:7
  wire [8:0]  imm_sdsp  = {c[9:7], c[12:10], 3'b000};                     // [5:3] 12:10, [8:6] 9:7
  // helpers to build 32-bit instructions (I-type, S-type, B-type, J-type, R-type, U-type)
  function [31:0] I; input [11:0] imm; input [4:0] rs1; input [2:0] f; input [4:0] rd; input [6:0] opc;
    I = {imm, rs1, f, rd, opc}; endfunction
  function [31:0] S; input [11:0] imm; input [4:0] rs2; input [4:0] rs1; input [2:0] f;
    S = {imm[11:5], rs2, rs1, f, imm[4:0], 7'b0100011}; endfunction
  function [31:0] R; input [6:0] f7; input [4:0] rs2; input [4:0] rs1; input [2:0] f; input [4:0] rd; input [6:0] opc;
    R = {f7, rs2, rs1, f, rd, opc}; endfunction
  localparam [31:0] NOP = 32'h00000013;
  always @(*) begin
    insn = NOP; illegal = 1'b0; hint = 1'b0;
    case (op)
      2'b00: case (f3)
        3'b000: begin  // c.addi4spn
          if (c == 16'h0000)            illegal = 1'b1;
          else if (imm_addi4spn == 0)   illegal = 1'b1;               // reserved
          else insn = I({2'b00, imm_addi4spn}, 5'd2, 3'b000, rdp, 7'b0010011);
        end
        3'b010: insn = I({5'd0, imm_lw}, rs1p, 3'b010, rdp, 7'b0000011);      // c.lw
        3'b011: insn = I({4'd0, imm_ld}, rs1p, 3'b011, rdp, 7'b0000011);      // c.ld (RV64)
        3'b110: insn = S({5'd0, imm_lw}, rdp, rs1p, 3'b010);                  // c.sw
        3'b111: insn = S({4'd0, imm_ld}, rdp, rs1p, 3'b011);                  // c.sd (RV64)
        default: illegal = 1'b1;                                              // c.fld / reserved / c.fsd
      endcase
      2'b01: case (f3)
        3'b000: begin  // c.nop / c.addi
          if (rd_full == 5'd0) begin insn = NOP; hint = (imm_ci != 0); end
          else if (imm_ci == 0) begin insn = NOP; hint = 1'b1; end
          else insn = I(imm_ci, rd_full, 3'b000, rd_full, 7'b0010011);
        end
        3'b001: begin  // c.addiw (RV64)
          if (rd_full == 5'd0) illegal = 1'b1;
          else insn = I(imm_ci, rd_full, 3'b000, rd_full, 7'b0011011);
        end
        3'b010: begin  // c.li
          if (rd_full == 5'd0) begin insn = NOP; hint = 1'b1; end
          else insn = I(imm_ci, 5'd0, 3'b000, rd_full, 7'b0010011);
        end
        3'b011: begin  // c.addi16sp / c.lui
          if (rd_full == 5'd2) begin
            if (imm_16sp == 0) illegal = 1'b1;
            else insn = I(imm_16sp, 5'd2, 3'b000, 5'd2, 7'b0010011);
          end else if (rd_full == 5'd0) begin
            if (imm_lui == 0) illegal = 1'b1; else begin insn = NOP; hint = 1'b1; end
          end else begin
            if (imm_lui == 0) illegal = 1'b1;
            else insn = {imm_lui, rd_full, 7'b0110111};
          end
        end
        3'b100: case (c[11:10])
          2'b00: begin if (shamt == 0) begin insn = NOP; hint = 1'b1; end           // c.srli (shamt 0: HINT)
                       else insn = I({6'b000000, shamt}, rs1p, 3'b101, rs1p, 7'b0010011); end
          2'b01: begin if (shamt == 0) begin insn = NOP; hint = 1'b1; end           // c.srai
                       else insn = I({6'b010000, shamt}, rs1p, 3'b101, rs1p, 7'b0010011); end
          2'b10: insn = I(imm_ci, rs1p, 3'b111, rs1p, 7'b0010011);                  // c.andi
          2'b11: case ({c[12], c[6:5]})
            3'b000: insn = R(7'b0100000, rdp, rs1p, 3'b000, rs1p, 7'b0110011);      // c.sub
            3'b001: insn = R(7'b0000000, rdp, rs1p, 3'b100, rs1p, 7'b0110011);      // c.xor
            3'b010: insn = R(7'b0000000, rdp, rs1p, 3'b110, rs1p, 7'b0110011);      // c.or
            3'b011: insn = R(7'b0000000, rdp, rs1p, 3'b111, rs1p, 7'b0110011);      // c.and
            3'b100: insn = R(7'b0100000, rdp, rs1p, 3'b000, rs1p, 7'b0111011);      // c.subw
            3'b101: insn = R(7'b0000000, rdp, rs1p, 3'b000, rs1p, 7'b0111011);      // c.addw
            default: illegal = 1'b1;                                                // reserved
          endcase
        endcase
        3'b101: insn = {imm_j[11], imm_j[10:1], imm_j[11], {8{imm_j[11]}}, 5'd0, 7'b1101111};  // c.j
        3'b110: insn = {{4{imm_b[8]}}, imm_b[7:5], 5'd0, rs1p, 3'b000, imm_b[4:1], imm_b[8], 7'b1100011}; // c.beqz
        3'b111: insn = {{4{imm_b[8]}}, imm_b[7:5], 5'd0, rs1p, 3'b001, imm_b[4:1], imm_b[8], 7'b1100011}; // c.bnez
      endcase
      2'b10: case (f3)
        3'b000: begin  // c.slli
          if (rd_full == 5'd0 || shamt == 0) begin insn = NOP; hint = 1'b1; end
          else insn = I({6'b000000, shamt}, rd_full, 3'b001, rd_full, 7'b0010011);
        end
        3'b010: begin if (rd_full == 5'd0) illegal = 1'b1;                       // c.lwsp
                      else insn = I({4'd0, imm_lwsp}, 5'd2, 3'b010, rd_full, 7'b0000011); end
        3'b011: begin if (rd_full == 5'd0) illegal = 1'b1;                       // c.ldsp (RV64)
                      else insn = I({3'd0, imm_ldsp}, 5'd2, 3'b011, rd_full, 7'b0000011); end
        3'b100: begin
          if (c[12] == 1'b0) begin
            if (rs2_full == 5'd0) begin                                          // c.jr
              if (rd_full == 5'd0) illegal = 1'b1;
              else insn = I(12'd0, rd_full, 3'b000, 5'd0, 7'b1100111);
            end else begin                                                       // c.mv
              if (rd_full == 5'd0) begin insn = NOP; hint = 1'b1; end
              else insn = R(7'b0000000, rs2_full, 5'd0, 3'b000, rd_full, 7'b0110011);
            end
          end else begin
            if (rs2_full == 5'd0) begin
              if (rd_full == 5'd0) insn = 32'h00100073;                          // c.ebreak
              else insn = I(12'd0, rd_full, 3'b000, 5'd1, 7'b1100111);           // c.jalr
            end else begin                                                       // c.add
              if (rd_full == 5'd0) begin insn = NOP; hint = 1'b1; end
              else insn = R(7'b0000000, rs2_full, rd_full, 3'b000, rd_full, 7'b0110011);
            end
          end
        end
        3'b110: insn = S({4'd0, imm_swsp}, rs2_full, 5'd2, 3'b010);              // c.swsp
        3'b111: insn = S({3'd0, imm_sdsp}, rs2_full, 5'd2, 3'b011);              // c.sdsp
        default: illegal = 1'b1;                                                 // c.fldsp / c.fsdsp
      endcase
      default: illegal = 1'b1;   // op == 11 is not a compressed instruction; the core never asks
    endcase
  end
endmodule
