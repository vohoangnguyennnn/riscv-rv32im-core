// Blocking restoring divider for the four RV32M divide/remainder operations.
//
// Normal operations produce one quotient bit per cycle for 32 cycles. Divide
// by zero and signed overflow complete locally with the results required by
// the RISC-V ISA. One response may be outstanding and remains stable until the
// downstream stage accepts it.
module div_unit (
  input  logic                    clk_i,
  input  logic                    rst_i,
  input  logic                    kill_i,

  input  logic                    req_valid_i,
  output logic                    req_ready_o,
  input  rv32_pkg::mdu_op_e       op_i,
  input  logic [31:0]             lhs_i,
  input  logic [31:0]             rhs_i,

  output logic                    rsp_valid_o,
  input  logic                    rsp_ready_i,
  output logic [31:0]             result_o
);

  import rv32_pkg::*;

  typedef enum logic [1:0] {
    DIV_IDLE,
    DIV_RUN,
    DIV_RESP
  } div_state_e;

  div_state_e state_q;
  mdu_op_e     op_q;

  logic [31:0] divisor_q;
  logic [31:0] quotient_q;
  logic [31:0] remainder_q;
  logic [5:0]  iter_q;
  logic        quotient_neg_q;
  logic        remainder_neg_q;
  logic [31:0] result_q;

  logic        input_signed;
  logic        input_is_div;
  logic        input_divide_by_zero;
  logic        input_signed_overflow;
  logic [31:0] input_lhs_magnitude;
  logic [31:0] input_rhs_magnitude;

  logic [32:0] remainder_shifted;
  logic [31:0] quotient_shifted;
  logic [31:0] remainder_next;
  logic [31:0] quotient_next;
  logic [31:0] quotient_corrected;
  logic [31:0] remainder_corrected;

  always_comb begin
    input_signed = (op_i == MDU_DIV) || (op_i == MDU_REM);
    input_is_div = (op_i == MDU_DIV) || (op_i == MDU_DIVU);

    input_divide_by_zero = (rhs_i == 32'b0);
    input_signed_overflow = input_signed && (lhs_i == 32'h8000_0000) && (rhs_i == 32'hffff_ffff);

    input_lhs_magnitude = (input_signed && lhs_i[31]) ? (~lhs_i + 32'd1) : lhs_i;
    input_rhs_magnitude = (input_signed && rhs_i[31]) ? (~rhs_i + 32'd1) : rhs_i;
  end

  // One restoring-division step. quotient_q initially holds the dividend
  // magnitude and shifts out its most-significant bit into the remainder.
  always_comb begin
    remainder_shifted = {remainder_q, quotient_q[31]};
    quotient_shifted  = {quotient_q[30:0], 1'b0};
    remainder_next    = remainder_shifted[31:0];
    quotient_next     = quotient_shifted;

    if (remainder_shifted >= {1'b0, divisor_q}) begin
      remainder_next   = remainder_shifted[31:0] - divisor_q;
      quotient_next[0] = 1'b1;
    end

    quotient_corrected = quotient_neg_q
                       ? (~quotient_next + 32'd1)
                       : quotient_next;
    remainder_corrected = remainder_neg_q
                        ? (~remainder_next + 32'd1)
                        : remainder_next;
  end

  always_comb begin
    req_ready_o = (state_q == DIV_IDLE) && !kill_i;
    rsp_valid_o = (state_q == DIV_RESP) && !kill_i;
    result_o    = result_q;
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      state_q         <= DIV_IDLE;
      op_q            <= MDU_NONE;
      divisor_q       <= 32'b0;
      quotient_q      <= 32'b0;
      remainder_q     <= 32'b0;
      iter_q          <= 6'b0;
      quotient_neg_q  <= 1'b0;
      remainder_neg_q <= 1'b0;
      result_q        <= 32'b0;
    end else if (kill_i) begin
      state_q         <= DIV_IDLE;
      op_q            <= MDU_NONE;
      divisor_q       <= 32'b0;
      quotient_q      <= 32'b0;
      remainder_q     <= 32'b0;
      iter_q          <= 6'b0;
      quotient_neg_q  <= 1'b0;
      remainder_neg_q <= 1'b0;
      result_q        <= 32'b0;
    end else begin
      unique case (state_q)
        DIV_IDLE: begin
          if (req_valid_i && req_ready_o) begin
            op_q            <= op_i;
            divisor_q       <= 32'b0;
            quotient_q      <= 32'b0;
            remainder_q     <= 32'b0;
            iter_q          <= 6'b0;
            quotient_neg_q  <= 1'b0;
            remainder_neg_q <= 1'b0;

            if (input_divide_by_zero) begin
              result_q <= input_is_div ? 32'hffff_ffff : lhs_i;
              state_q  <= DIV_RESP;
            end else if (input_signed_overflow) begin
              result_q <= input_is_div ? 32'h8000_0000 : 32'b0;
              state_q  <= DIV_RESP;
            end else begin
              divisor_q       <= input_rhs_magnitude;
              quotient_q      <= input_lhs_magnitude;
              quotient_neg_q  <= input_signed && (lhs_i[31] ^ rhs_i[31]);
              remainder_neg_q <= input_signed && lhs_i[31];
              state_q          <= DIV_RUN;
            end
          end
        end

        DIV_RUN: begin
          quotient_q  <= quotient_next;
          remainder_q <= remainder_next;

          if (iter_q == 6'd31) begin
            result_q <= ((op_q == MDU_DIV) || (op_q == MDU_DIVU)) ? quotient_corrected : remainder_corrected;
            state_q  <= DIV_RESP;
          end else begin
            iter_q <= iter_q + 6'd1;
          end
        end

        DIV_RESP: begin
          if (rsp_ready_i) begin
            state_q <= DIV_IDLE;
          end
        end

        default: begin
          state_q <= DIV_IDLE;
        end
      endcase
    end
  end

endmodule
