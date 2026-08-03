// Blocking, two-stage multiplier for the RV32M multiply instructions.
//
// One operation may be outstanding. Operands and signedness are captured when
// the request is accepted; the following stage registers the architectural
// low/high result. A completed response remains stable until it is consumed.
module mul_unit (
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
    MUL_IDLE,
    MUL_EXEC,
    MUL_RESP
  } mul_state_e;

  mul_state_e          state_q;
  logic signed [32:0]  lhs_ext_d;
  logic signed [32:0]  rhs_ext_d;
  logic signed [32:0]  lhs_q;
  logic signed [32:0]  rhs_q;
  mdu_op_e              op_q;
  logic signed [63:0]  product;
  logic [31:0]         result_q;

  // A leading sign bit is used only where required by the selected high-half
  // operation. MUL may use unsigned operands because its low 32 bits are
  // independent of operand signedness.
  always_comb begin
    lhs_ext_d = $signed({1'b0, lhs_i});
    rhs_ext_d = $signed({1'b0, rhs_i});

    unique case (op_i)
      MDU_MULH: begin
        lhs_ext_d = $signed({lhs_i[31], lhs_i});
        rhs_ext_d = $signed({rhs_i[31], rhs_i});
      end

      MDU_MULHSU: begin
        lhs_ext_d = $signed({lhs_i[31], lhs_i});
        rhs_ext_d = $signed({1'b0, rhs_i});
      end

      default: begin // MDU_MUL and MDU_MULHU
        lhs_ext_d = $signed({1'b0, lhs_i});
        rhs_ext_d = $signed({1'b0, rhs_i});
      end
    endcase
  end

  // Keeping the multiply between explicit input and output registers gives
  // synthesis a clean DSP inference boundary without binding this RTL to a
  // device-specific primitive.
  assign product = lhs_q * rhs_q;

  always_comb begin
    req_ready_o = (state_q == MUL_IDLE) && !kill_i;
    rsp_valid_o = (state_q == MUL_RESP) && !kill_i;
    result_o    = result_q;
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      state_q  <= MUL_IDLE;
      lhs_q    <= '0;
      rhs_q    <= '0;
      op_q     <= MDU_NONE;
      result_q <= '0;
    end else if (kill_i) begin
      state_q  <= MUL_IDLE;
      lhs_q    <= '0;
      rhs_q    <= '0;
      op_q     <= MDU_NONE;
      result_q <= '0;
    end else begin
      unique case (state_q)
        MUL_IDLE: begin
          if (req_valid_i && req_ready_o) begin
            lhs_q   <= lhs_ext_d;
            rhs_q   <= rhs_ext_d;
            op_q    <= op_i;
            state_q <= MUL_EXEC;
          end
        end

        MUL_EXEC: begin
          result_q <= (op_q == MDU_MUL) ? product[31:0] : product[63:32];
          state_q  <= MUL_RESP;
        end

        MUL_RESP: begin
          if (rsp_ready_i) begin
            state_q <= MUL_IDLE;
          end
        end

        default: begin
          state_q <= MUL_IDLE;
        end
      endcase
    end
  end

endmodule
