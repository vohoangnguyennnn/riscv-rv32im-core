// RV32 immediate generator. The decoder selects the instruction format and
// this module reconstructs the encoded immediate as a 32-bit value.
module imm_gen (
  input  logic [31:0]          insn_i,
  input  rv32_pkg::imm_sel_e   sel_i,
  output logic [31:0]          imm_o
);

  import rv32_pkg::*;

  always_comb begin
    // IMM_NONE and unsupported selector values produce a benign zero.
    imm_o = 32'b0;

    unique case (sel_i)
      IMM_NONE: imm_o = 32'b0;

      // I-type: arithmetic immediates, load offsets and JALR offsets.
      IMM_I: imm_o = {{20{insn_i[31]}}, insn_i[31:20]};

      // S-type: store offset split between bits [31:25] and [11:7].
      IMM_S: imm_o = {
        {20{insn_i[31]}},
        insn_i[31:25],
        insn_i[11:7]
      };

      // B-type: branch offsets are signed and always two-byte aligned.
      IMM_B: imm_o = {
        {19{insn_i[31]}},
        insn_i[31],
        insn_i[7],
        insn_i[30:25],
        insn_i[11:8],
        1'b0
      };

      // U-type: the encoded field directly forms bits [31:12].
      IMM_U: imm_o = {insn_i[31:12], 12'b0};

      // J-type: jump offsets are signed and always two-byte aligned.
      IMM_J: imm_o = {
        {11{insn_i[31]}},
        insn_i[31],
        insn_i[19:12],
        insn_i[20],
        insn_i[30:21],
        1'b0
      };

      default: imm_o = 32'b0;
    endcase
  end

endmodule
