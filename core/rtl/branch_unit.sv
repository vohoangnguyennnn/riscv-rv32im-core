// Combinational control-transfer comparator and target generator.
//
// Conditional branches and JAL are PC-relative. JALR uses rs1 + immediate
// and clears target bit 0 as required by RISC-V. This core has IALIGN=32, so
// any taken target with either low address bit set is misaligned.
module branch_unit (
  input  rv32_pkg::branch_e kind_i,
  input  logic [31:0]       pc_i,
  input  logic [31:0]       imm_i,
  input  logic [31:0]       rs1_i,
  input  logic [31:0]       rs2_i,
  output logic              taken_o,
  output logic [31:0]       target_o,
  output logic              misaligned_o
);

  import rv32_pkg::*;

  always_comb begin
    taken_o      = 1'b0;
    target_o     = 32'b0;
    misaligned_o = 1'b0;

    unique case (kind_i)
      BR_NONE: begin
        taken_o  = 1'b0;
        target_o = 32'b0;
      end

      BR_BEQ: begin
        taken_o  = (rs1_i == rs2_i);
        target_o = pc_i + imm_i;
      end

      BR_BNE: begin
        taken_o  = (rs1_i != rs2_i);
        target_o = pc_i + imm_i;
      end

      BR_BLT: begin
        taken_o  = ($signed(rs1_i) < $signed(rs2_i));
        target_o = pc_i + imm_i;
      end

      BR_BGE: begin
        taken_o  = ($signed(rs1_i) >= $signed(rs2_i));
        target_o = pc_i + imm_i;
      end

      BR_BLTU: begin
        taken_o  = (rs1_i < rs2_i);
        target_o = pc_i + imm_i;
      end

      BR_BGEU: begin
        taken_o  = (rs1_i >= rs2_i);
        target_o = pc_i + imm_i;
      end

      BR_JAL: begin
        taken_o  = 1'b1;
        target_o = pc_i + imm_i;
      end

      BR_JALR: begin
        taken_o  = 1'b1;
        target_o = (rs1_i + imm_i) & 32'hffff_fffe;
      end

      default: begin
        taken_o  = 1'b0;
        target_o = 32'b0;
      end
    endcase

    // A not-taken conditional branch never raises an alignment exception.
    misaligned_o = taken_o && (target_o[1:0] != 2'b00);
  end

endmodule
