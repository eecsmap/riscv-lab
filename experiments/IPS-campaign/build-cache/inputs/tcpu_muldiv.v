// CPU-M: the integer multiply/divide unit. Iterative, one shared datapath, readable first (DECISIONS D2).
//
// Contract (the core relies on every line of this):
//   * `start` is accepted only while `busy` is low; on that edge op/a/b are latched once and never re-read.
//     A `start` while busy is ignored -- an operation can neither be restarted nor duplicated.
//   * `busy` is high from the cycle after acceptance until the cycle `done` pulses.
//   * `done` is high for exactly one cycle, with `result` valid on that same cycle and held afterwards
//     until the next acceptance. There is never a stale `done`: reset clears it, and so does acceptance.
//   * reset (synchronous) abandons the operation: busy/done fall, nothing is written back by the core
//     because the core's own state machine restarts at fetch.
//   * the unit issues no memory traffic and has no other side effect.
//
// Datapath: 64 iterations for every operation. Multiplication is shift-and-add on magnitudes with the sign
// restored afterwards (MULH / MULHSU / MUL take the high or low half of the 128-bit signed product; MULHU
// the high half of the unsigned one). Division is restoring division on magnitudes with the RISC-V sign
// rules applied afterwards: quotient sign = sign(a) xor sign(b), remainder sign = sign(a); division by zero
// gives quotient all ones and remainder = dividend; the one overflow (most negative / -1) gives the most
// negative quotient and remainder 0. The W forms operate on the low 32 bits as 32-bit values and sign-extend
// their 32-bit result. No combinational `*`, `/` or `%` anywhere.
`timescale 1ns/1ps
module tcpu_muldiv #(
  parameter FAULT_W_SEXT    = 0,   // fault injection: W results zero-extended instead of sign-extended
  parameter FAULT_MULH_SIGN = 0    // fault injection: high half of a signed product not sign-corrected
) (
  input             clk,
  input             rst,
  input             start,
  input      [3:0]  op,       // 0 MUL 1 MULH 2 MULHSU 3 MULHU 4 DIV 5 DIVU 6 REM 7 REMU
                              // 8 MULW 9 DIVW 10 DIVUW 11 REMW 12 REMUW
  input      [63:0] a,
  input      [63:0] b,
  output reg        busy,
  output reg        done,
  output reg [63:0] result
);
  localparam OP_MUL = 4'd0, OP_MULH = 4'd1, OP_MULHSU = 4'd2, OP_MULHU = 4'd3,
             OP_DIV = 4'd4, OP_DIVU = 4'd5, OP_REM = 4'd6, OP_REMU = 4'd7,
             OP_MULW = 4'd8, OP_DIVW = 4'd9, OP_DIVUW = 4'd10, OP_REMW = 4'd11, OP_REMUW = 4'd12;

  reg [3:0]  op_r;
  reg        is_w, is_div, a_neg, b_neg;   // latched at acceptance
  reg [63:0] a_mag, b_mag;                 // magnitudes (or the raw unsigned values)
  reg [6:0]  count;
  // multiply: {hi, lo} shifts right one place per step; lo starts as the multiplier
  reg [64:0] mhi;
  reg [63:0] mlo;
  // divide: remainder / quotient registers
  reg [64:0] rem;
  reg [63:0] quo;

  // ---- what "signed" means for each operation, decided once at acceptance
  wire w_op   = (op == OP_MULW) || (op == OP_DIVW) || (op == OP_DIVUW) || (op == OP_REMW) || (op == OP_REMUW);
  wire div_op = (op == OP_DIV) || (op == OP_DIVU) || (op == OP_REM) || (op == OP_REMU) ||
                (op == OP_DIVW) || (op == OP_DIVUW) || (op == OP_REMW) || (op == OP_REMUW);
  wire a_signed = (op == OP_MUL) || (op == OP_MULH) || (op == OP_MULHSU) || (op == OP_DIV) || (op == OP_REM) ||
                  (op == OP_MULW) || (op == OP_DIVW) || (op == OP_REMW);
  wire b_signed = (op == OP_MUL) || (op == OP_MULH) || (op == OP_DIV) || (op == OP_REM) ||
                  (op == OP_MULW) || (op == OP_DIVW) || (op == OP_REMW);
  // the W forms see 32-bit operands: sign- or zero-extended to 64 so one datapath serves both widths
  wire [63:0] a_in = w_op ? (a_signed ? {{32{a[31]}}, a[31:0]} : {32'd0, a[31:0]}) : a;
  wire [63:0] b_in = w_op ? (b_signed ? {{32{b[31]}}, b[31:0]} : {32'd0, b[31:0]}) : b;
  wire a_neg_in = a_signed & a_in[63];
  wire b_neg_in = b_signed & b_in[63];
  wire [63:0] a_mag_in = a_neg_in ? (~a_in + 64'd1) : a_in;
  wire [63:0] b_mag_in = b_neg_in ? (~b_in + 64'd1) : b_in;

  // ---- one step of each algorithm
  wire [64:0] msum = mhi + (mlo[0] ? {1'b0, a_mag} : 65'd0);
  wire [64:0] rem_shift = {rem[63:0], quo[63]};
  wire        rem_ge    = rem_shift >= {1'b0, b_mag};
  wire [64:0] rem_next  = rem_ge ? (rem_shift - {1'b0, b_mag}) : rem_shift;

  // ---- the final result, assembled from the magnitude result when the last step has landed
  wire [127:0] prod_mag = {mhi[63:0], mlo};
  wire         prod_neg = a_neg ^ b_neg;                    // sign of a signed product
  wire [127:0] prod_signed = prod_neg ? (~prod_mag + 128'd1) : prod_mag;
  wire [63:0]  quo_mag = quo;
  wire [63:0]  rem_mag = rem[63:0];
  wire         div_by_zero = (b_mag == 64'd0);
  // the overflow case exists only for the signed forms: most negative dividend, divisor -1
  wire         div_ovf = (op_r == OP_DIV) || (op_r == OP_REM) || (op_r == OP_DIVW) || (op_r == OP_REMW);
  wire         ovf = div_ovf && a_neg && !b_neg && (b_mag == 64'd1) &&
                     (is_w ? (a_mag == 64'h0000_0000_8000_0000) : (a_mag == 64'h8000_0000_0000_0000));
  wire [63:0]  quo_signed = (a_neg ^ b_neg) ? (~quo_mag + 64'd1) : quo_mag;
  wire [63:0]  rem_signed = a_neg ? (~rem_mag + 64'd1) : rem_mag;
  wire [63:0]  a_raw = is_w ? ((op_r == OP_DIVUW || op_r == OP_REMUW) ? {32'd0, a_mag[31:0]} :
                               (a_neg ? (~a_mag + 64'd1) : a_mag)) : (a_neg ? (~a_mag + 64'd1) : a_mag);
  reg [63:0] full;     // the 64-bit result before W narrowing
  always @(*) begin
    case (op_r)
      OP_MUL, OP_MULW: full = prod_signed[63:0];
      OP_MULH:         full = (FAULT_MULH_SIGN != 0) ? prod_mag[127:64] : prod_signed[127:64];
      OP_MULHSU:       full = (FAULT_MULH_SIGN != 0) ? prod_mag[127:64] : prod_signed[127:64];
      OP_MULHU:        full = prod_mag[127:64];
      OP_DIV, OP_DIVW: full = div_by_zero ? 64'hFFFF_FFFF_FFFF_FFFF : ovf ? (is_w ? 64'hFFFF_FFFF_8000_0000 : 64'h8000_0000_0000_0000) : quo_signed;
      OP_DIVU, OP_DIVUW: full = div_by_zero ? 64'hFFFF_FFFF_FFFF_FFFF : quo_mag;
      OP_REM, OP_REMW: full = div_by_zero ? a_raw : ovf ? 64'd0 : rem_signed;
      OP_REMU, OP_REMUW: full = div_by_zero ? a_raw : rem_mag;
      default:         full = 64'd0;
    endcase
  end
  wire [63:0] narrowed = is_w ? ((FAULT_W_SEXT != 0) ? {32'd0, full[31:0]} : {{32{full[31]}}, full[31:0]}) : full;

  always @(posedge clk) begin
    done <= 1'b0;
    if (rst) begin
      busy <= 1'b0; done <= 1'b0; count <= 7'd0; result <= 64'd0;
      op_r <= 4'd0; is_w <= 1'b0; is_div <= 1'b0; a_neg <= 1'b0; b_neg <= 1'b0;
      a_mag <= 64'd0; b_mag <= 64'd0; mhi <= 65'd0; mlo <= 64'd0; rem <= 65'd0; quo <= 64'd0;
    end else if (!busy) begin
      if (start) begin
        busy  <= 1'b1; count <= 7'd0;
        op_r  <= op; is_w <= w_op; is_div <= div_op; a_neg <= a_neg_in; b_neg <= b_neg_in;
        a_mag <= a_mag_in; b_mag <= b_mag_in;
        mhi   <= 65'd0; mlo <= b_mag_in;        // multiplier in lo, multiplicand held in a_mag
        rem   <= 65'd0; quo <= a_mag_in;        // dividend in quo, divisor held in b_mag
      end
    end else begin
      // one step per cycle, 64 steps, then one cycle to assemble the result
      if (count < 7'd64) begin
        if (is_div) begin rem <= rem_next; quo <= {quo[62:0], rem_ge}; end
        else        begin mhi <= {1'b0, msum[64:1]}; mlo <= {msum[0], mlo[63:1]}; end
        count <= count + 7'd1;
      end else begin
        result <= narrowed; done <= 1'b1; busy <= 1'b0;
      end
    end
  end
endmodule
