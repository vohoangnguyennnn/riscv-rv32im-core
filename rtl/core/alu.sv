module alu (
  input  rv32_pkg::alu_op_e op_i,
  input  logic [31:0]       a_i,
  input  logic [31:0]       b_i,
  output logic [31:0]       result_o
);

  import rv32_pkg::*;

  always_comb begin
    // ALU_NONE and invalid enum values produce a benign result
    result_o = 32'b0;

    unique case (op_i)
      ALU_NONE: result_o = 32'b0;
      ALU_ADD:  result_o = a_i + b_i;
      ALU_SUB:  result_o = a_i - b_i;
      ALU_SLL:  result_o = a_i << b_i[4:0];
      ALU_SRL:  result_o = a_i >> b_i[4:0];
      ALU_SRA:  result_o = $signed(a_i) >>> b_i[4:0];
      ALU_SLT:  result_o = {31'b0, $signed(a_i) < $signed(b_i)};
      ALU_SLTU: result_o = {31'b0, a_i < b_i};
      ALU_XOR:  result_o = a_i ^ b_i;
      ALU_OR:   result_o = a_i | b_i;
      ALU_AND:  result_o = a_i & b_i;
      default:  result_o = 32'b0;
    endcase
  end

endmodule
