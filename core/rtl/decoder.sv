// Combinational RV32IM + Zicsr instruction decoder.
//
// The decoder is intentionally strict: outputs default to a side-effect-free
// illegal instruction and are enabled only after all relevant opcode, funct3
// and funct7 fields have been validated.
module decoder (
  input  logic [31:0]               insn_i,
  output logic [4:0]                rs1_o,
  output logic [4:0]                rs2_o,
  output logic [4:0]                rd_o,
  output rv32_pkg::imm_sel_e        imm_sel_o,
  output rv32_pkg::decode_ctrl_t    ctrl_o,
  output logic                      illegal_o
);

  import rv32_pkg::*;

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  always_comb begin
    opcode = insn_i[6:0];
    funct3 = insn_i[14:12];
    funct7 = insn_i[31:25];

    // Register indices are always exposed. uses_rs1/uses_rs2 determine whether
    // the corresponding instruction fields are architectural dependencies.
    rs1_o = insn_i[19:15];
    rs2_o = insn_i[24:20];
    rd_o  = insn_i[11:7];

    // Benign defaults prevent latches and suppress side effects for illegal
    // instructions. Enum zero values provide the NONE/EX_RESULT defaults.
    imm_sel_o          = IMM_NONE;
    ctrl_o             = '0;
    ctrl_o.op_a_sel    = OP_A_ZERO;
    ctrl_o.op_b_sel    = OP_B_IMM;
    ctrl_o.mem_size    = MEM_WORD;
    illegal_o          = 1'b1;

    unique case (opcode)
      OPCODE_LUI: begin
        imm_sel_o       = IMM_U;
        ctrl_o.reg_write = 1'b1;
        ctrl_o.alu_op    = ALU_ADD;
        ctrl_o.op_a_sel  = OP_A_ZERO;
        ctrl_o.op_b_sel  = OP_B_IMM;
        illegal_o        = 1'b0;
      end

      OPCODE_AUIPC: begin
        imm_sel_o        = IMM_U;
        ctrl_o.reg_write = 1'b1;
        ctrl_o.alu_op    = ALU_ADD;
        ctrl_o.op_a_sel  = OP_A_PC;
        ctrl_o.op_b_sel  = OP_B_IMM;
        illegal_o        = 1'b0;
      end

      OPCODE_JAL: begin
        imm_sel_o          = IMM_J;
        ctrl_o.reg_write   = 1'b1;
        ctrl_o.wb_sel      = WB_PC4;
        ctrl_o.branch_kind = BR_JAL;
        illegal_o          = 1'b0;
      end

      OPCODE_JALR: begin
        if (funct3 == FUNCT3_JALR) begin
          imm_sel_o          = IMM_I;
          ctrl_o.uses_rs1    = 1'b1;
          ctrl_o.reg_write   = 1'b1;
          ctrl_o.wb_sel      = WB_PC4;
          ctrl_o.branch_kind = BR_JALR;
          illegal_o          = 1'b0;
        end
      end

      OPCODE_BRANCH: begin
        unique case (funct3)
          FUNCT3_BEQ:  begin ctrl_o.branch_kind = BR_BEQ;  illegal_o = 1'b0; end
          FUNCT3_BNE:  begin ctrl_o.branch_kind = BR_BNE;  illegal_o = 1'b0; end
          FUNCT3_BLT:  begin ctrl_o.branch_kind = BR_BLT;  illegal_o = 1'b0; end
          FUNCT3_BGE:  begin ctrl_o.branch_kind = BR_BGE;  illegal_o = 1'b0; end
          FUNCT3_BLTU: begin ctrl_o.branch_kind = BR_BLTU; illegal_o = 1'b0; end
          FUNCT3_BGEU: begin ctrl_o.branch_kind = BR_BGEU; illegal_o = 1'b0; end
          default: ;
        endcase

        if (!illegal_o) begin
          imm_sel_o       = IMM_B;
          ctrl_o.uses_rs1 = 1'b1;
          ctrl_o.uses_rs2 = 1'b1;
        end
      end

      OPCODE_LOAD: begin
        unique case (funct3)
          FUNCT3_LB: begin
            ctrl_o.mem_size      = MEM_BYTE;
            ctrl_o.load_unsigned = 1'b0;
            illegal_o            = 1'b0;
          end
          FUNCT3_LH: begin
            ctrl_o.mem_size      = MEM_HALF;
            ctrl_o.load_unsigned = 1'b0;
            illegal_o            = 1'b0;
          end
          FUNCT3_LW: begin
            ctrl_o.mem_size      = MEM_WORD;
            ctrl_o.load_unsigned = 1'b0;
            illegal_o            = 1'b0;
          end
          FUNCT3_LBU: begin
            ctrl_o.mem_size      = MEM_BYTE;
            ctrl_o.load_unsigned = 1'b1;
            illegal_o            = 1'b0;
          end
          FUNCT3_LHU: begin
            ctrl_o.mem_size      = MEM_HALF;
            ctrl_o.load_unsigned = 1'b1;
            illegal_o            = 1'b0;
          end
          default: ;
        endcase

        if (!illegal_o) begin
          imm_sel_o          = IMM_I;
          ctrl_o.uses_rs1    = 1'b1;
          ctrl_o.reg_write   = 1'b1;
          ctrl_o.alu_op      = ALU_ADD;
          ctrl_o.op_a_sel    = OP_A_RS1;
          ctrl_o.op_b_sel    = OP_B_IMM;
          ctrl_o.wb_sel      = WB_LOAD;
          ctrl_o.mem_cmd     = MEM_LOAD;
        end
      end

      OPCODE_STORE: begin
        unique case (funct3)
          FUNCT3_SB: begin ctrl_o.mem_size = MEM_BYTE; illegal_o = 1'b0; end
          FUNCT3_SH: begin ctrl_o.mem_size = MEM_HALF; illegal_o = 1'b0; end
          FUNCT3_SW: begin ctrl_o.mem_size = MEM_WORD; illegal_o = 1'b0; end
          default: ;
        endcase

        if (!illegal_o) begin
          imm_sel_o        = IMM_S;
          ctrl_o.uses_rs1  = 1'b1;
          ctrl_o.uses_rs2  = 1'b1;
          ctrl_o.alu_op    = ALU_ADD;
          ctrl_o.op_a_sel  = OP_A_RS1;
          ctrl_o.op_b_sel  = OP_B_IMM;
          ctrl_o.mem_cmd   = MEM_STORE;
        end
      end

      OPCODE_OP_IMM: begin
        unique case (funct3)
          FUNCT3_ADD_SUB: begin ctrl_o.alu_op = ALU_ADD;  illegal_o = 1'b0; end
          FUNCT3_SLT:     begin ctrl_o.alu_op = ALU_SLT;  illegal_o = 1'b0; end
          FUNCT3_SLTU:    begin ctrl_o.alu_op = ALU_SLTU; illegal_o = 1'b0; end
          FUNCT3_XOR:     begin ctrl_o.alu_op = ALU_XOR;  illegal_o = 1'b0; end
          FUNCT3_OR:      begin ctrl_o.alu_op = ALU_OR;   illegal_o = 1'b0; end
          FUNCT3_AND:     begin ctrl_o.alu_op = ALU_AND;  illegal_o = 1'b0; end

          FUNCT3_SLL: begin
            if (funct7 == FUNCT7_BASE) begin
              ctrl_o.alu_op = ALU_SLL;
              illegal_o     = 1'b0;
            end
          end

          FUNCT3_SRL_SRA: begin
            unique case (funct7)
              FUNCT7_BASE: begin
                ctrl_o.alu_op = ALU_SRL;
                illegal_o     = 1'b0;
              end
              FUNCT7_SUB_SRA: begin
                ctrl_o.alu_op = ALU_SRA;
                illegal_o     = 1'b0;
              end
              default: ;
            endcase
          end

          default: ;
        endcase

        if (!illegal_o) begin
          imm_sel_o        = IMM_I;
          ctrl_o.uses_rs1  = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.op_a_sel  = OP_A_RS1;
          ctrl_o.op_b_sel  = OP_B_IMM;
        end
      end

      OPCODE_OP: begin
        unique case (funct7)
          FUNCT7_BASE: begin
            unique case (funct3)
              FUNCT3_ADD_SUB: begin ctrl_o.alu_op = ALU_ADD;  illegal_o = 1'b0; end
              FUNCT3_SLL:     begin ctrl_o.alu_op = ALU_SLL;  illegal_o = 1'b0; end
              FUNCT3_SLT:     begin ctrl_o.alu_op = ALU_SLT;  illegal_o = 1'b0; end
              FUNCT3_SLTU:    begin ctrl_o.alu_op = ALU_SLTU; illegal_o = 1'b0; end
              FUNCT3_XOR:     begin ctrl_o.alu_op = ALU_XOR;  illegal_o = 1'b0; end
              FUNCT3_SRL_SRA: begin ctrl_o.alu_op = ALU_SRL;  illegal_o = 1'b0; end
              FUNCT3_OR:      begin ctrl_o.alu_op = ALU_OR;   illegal_o = 1'b0; end
              FUNCT3_AND:     begin ctrl_o.alu_op = ALU_AND;  illegal_o = 1'b0; end
              default: ;
            endcase
          end

          FUNCT7_SUB_SRA: begin
            unique case (funct3)
              FUNCT3_ADD_SUB: begin ctrl_o.alu_op = ALU_SUB; illegal_o = 1'b0; end
              FUNCT3_SRL_SRA: begin ctrl_o.alu_op = ALU_SRA; illegal_o = 1'b0; end
              default: ;
            endcase
          end

          FUNCT7_M: begin
            unique case (funct3)
              FUNCT3_MUL:    begin ctrl_o.mdu_op = MDU_MUL;    illegal_o = 1'b0; end
              FUNCT3_MULH:   begin ctrl_o.mdu_op = MDU_MULH;   illegal_o = 1'b0; end
              FUNCT3_MULHSU: begin ctrl_o.mdu_op = MDU_MULHSU; illegal_o = 1'b0; end
              FUNCT3_MULHU:  begin ctrl_o.mdu_op = MDU_MULHU;  illegal_o = 1'b0; end
              FUNCT3_DIV:    begin ctrl_o.mdu_op = MDU_DIV;    illegal_o = 1'b0; end
              FUNCT3_DIVU:   begin ctrl_o.mdu_op = MDU_DIVU;   illegal_o = 1'b0; end
              FUNCT3_REM:    begin ctrl_o.mdu_op = MDU_REM;    illegal_o = 1'b0; end
              FUNCT3_REMU:   begin ctrl_o.mdu_op = MDU_REMU;   illegal_o = 1'b0; end
              default: ;
            endcase
          end

          default: ;
        endcase

        if (!illegal_o) begin
          ctrl_o.uses_rs1  = 1'b1;
          ctrl_o.uses_rs2  = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.op_a_sel  = OP_A_RS1;
          ctrl_o.op_b_sel  = OP_B_RS2;
        end
      end

      OPCODE_MISC_MEM: begin
        // FENCE is a legal NOP for this single-hart blocking memory system.
        // FENCE.I (funct3 001) remains illegal because Zifencei is out of scope.
        if (funct3 == FUNCT3_FENCE) begin
          ctrl_o.is_fence = 1'b1;
          illegal_o       = 1'b0;
        end
      end

      OPCODE_SYSTEM: begin
        unique case (funct3)
          FUNCT3_PRIV: begin
            unique case (insn_i)
              INSN_ECALL,
              INSN_EBREAK: illegal_o = 1'b0;

              INSN_MRET: begin
                ctrl_o.is_mret = 1'b1;
                illegal_o      = 1'b0;
              end

              default: ;
            endcase
          end

          FUNCT3_CSRRW: begin
            ctrl_o.uses_rs1 = 1'b1;
            ctrl_o.csr_cmd  = CSR_RW;
            illegal_o       = 1'b0;
          end

          FUNCT3_CSRRS: begin
            ctrl_o.uses_rs1 = 1'b1;
            ctrl_o.csr_cmd  = CSR_RS;
            illegal_o       = 1'b0;
          end

          FUNCT3_CSRRC: begin
            ctrl_o.uses_rs1 = 1'b1;
            ctrl_o.csr_cmd  = CSR_RC;
            illegal_o       = 1'b0;
          end

          FUNCT3_CSRRWI: begin
            ctrl_o.csr_cmd = CSR_RWI;
            illegal_o      = 1'b0;
          end

          FUNCT3_CSRRSI: begin
            ctrl_o.csr_cmd = CSR_RSI;
            illegal_o      = 1'b0;
          end

          FUNCT3_CSRRCI: begin
            ctrl_o.csr_cmd = CSR_RCI;
            illegal_o      = 1'b0;
          end

          default: ;
        endcase

        if (!illegal_o && (ctrl_o.csr_cmd != CSR_NONE)) begin
          ctrl_o.reg_write = 1'b1;
          ctrl_o.wb_sel    = WB_CSR;
        end
      end

      default: ;
    endcase
  end

endmodule
