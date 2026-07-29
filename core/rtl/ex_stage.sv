// RV32IM + Zicsr execute-stage datapath and control-transfer resolver.
//
// Pipeline storage remains in rv32_core. This module applies EX forwarding,
// selects ALU operands, builds the next EX/MEM packet, performs CSR
// read-modify-write, and resolves branch/JAL/JALR/MRET. A redirect is emitted
// only when the EX result is accepted, preventing repeated redirects while the
// downstream stage is held.
//
// MUL/DIV are deliberately fail-safe until the dedicated handshake units are
// integrated: an M-extension packet asserts wait_o and cannot advance with an
// incorrect placeholder result.
module ex_stage (
  input  logic                    clk_i,
  input  logic                    rst_i,
  input  logic                    kill_i,

  input  wire rv32_pkg::id_ex_t   id_ex_i,
  input  rv32_pkg::fwd_sel_e      fwd_a_sel_i,
  input  rv32_pkg::fwd_sel_e      fwd_b_sel_i,
  input  logic [31:0]             ex_mem_fwd_value_i,
  input  logic [31:0]             mem_wb_fwd_value_i,

  input  logic [31:0]             csr_rdata_i,
  input  logic                    csr_access_illegal_i,
  input  logic                    result_ready_i,

  output logic [11:0]             csr_raddr_o,
  output wire rv32_pkg::ex_mem_t  ex_mem_o,
  output wire rv32_pkg::redirect_t control_redirect_o,
  output logic                    result_valid_o,
  output logic                    wait_o
);

  import rv32_pkg::*;

  word_t     forwarded_rs1;
  word_t     forwarded_rs2;
  word_t     alu_operand_a;
  word_t     alu_operand_b;
  word_t     alu_result;

  logic      branch_taken;
  word_t     branch_target;
  logic      branch_target_misaligned;

  logic      active;
  logic      is_csr;
  logic      is_mdu;
  logic      is_control;
  logic      control_taken;
  word_t     control_target;
  logic      control_target_misaligned;
  logic      ex_fire;

  word_t     csr_wdata;
  logic      csr_write;

  ex_mem_t   ex_mem_d;
  redirect_t control_redirect_d;

  // clk_i becomes stateful when mul_unit/div_unit are integrated. Keeping it
  // in the final interface now avoids an integration-only port-contract change.

  assign active     = id_ex_i.valid && !rst_i && !kill_i;
  assign is_csr     = (id_ex_i.ctrl.csr_cmd != CSR_NONE);
  // An exception already attached to the packet must drain to WB instead of
  // being trapped behind an MDU command that will never be launched.
  assign is_mdu =
    (id_ex_i.ctrl.mdu_op != MDU_NONE) && !id_ex_i.exc.valid;
  assign is_control =
    (id_ex_i.ctrl.branch_kind != BR_NONE) || id_ex_i.ctrl.is_mret;

  always_comb begin
    forwarded_rs1 = id_ex_i.rs1_value;
    forwarded_rs2 = id_ex_i.rs2_value;

    unique case (fwd_a_sel_i)
      FWD_REGFILE: forwarded_rs1 = id_ex_i.rs1_value;
      FWD_EX_MEM:  forwarded_rs1 = ex_mem_fwd_value_i;
      FWD_MEM_WB:  forwarded_rs1 = mem_wb_fwd_value_i;
      default:     forwarded_rs1 = id_ex_i.rs1_value;
    endcase

    unique case (fwd_b_sel_i)
      FWD_REGFILE: forwarded_rs2 = id_ex_i.rs2_value;
      FWD_EX_MEM:  forwarded_rs2 = ex_mem_fwd_value_i;
      FWD_MEM_WB:  forwarded_rs2 = mem_wb_fwd_value_i;
      default:     forwarded_rs2 = id_ex_i.rs2_value;
    endcase
  end

  always_comb begin
    alu_operand_a = 32'b0;
    alu_operand_b = 32'b0;

    unique case (id_ex_i.ctrl.op_a_sel)
      OP_A_RS1:  alu_operand_a = forwarded_rs1;
      OP_A_PC:   alu_operand_a = id_ex_i.pc;
      OP_A_ZERO: alu_operand_a = 32'b0;
      default:   alu_operand_a = 32'b0;
    endcase

    unique case (id_ex_i.ctrl.op_b_sel)
      OP_B_RS2: alu_operand_b = forwarded_rs2;
      OP_B_IMM: alu_operand_b = id_ex_i.imm;
      default:  alu_operand_b = 32'b0;
    endcase
  end

  alu u_alu (
    .op_i     (id_ex_i.ctrl.alu_op),
    .a_i      (alu_operand_a),
    .b_i      (alu_operand_b),
    .result_o (alu_result)
  );

  branch_unit u_branch_unit (
    .kind_i       (id_ex_i.ctrl.branch_kind),
    .pc_i         (id_ex_i.pc),
    .imm_i        (id_ex_i.imm),
    .rs1_i        (forwarded_rs1),
    .rs2_i        (forwarded_rs2),
    .taken_o      (branch_taken),
    .target_o     (branch_target),
    .misaligned_o (branch_target_misaligned)
  );

  // CSR immediate forms use the zero-extended zimm field, while register forms
  // consume the forwarded rs1 value. CSRRS/CSRRC suppress the architectural
  // write when rs1=x0; their immediate forms do the same when zimm=0.
  always_comb begin
    csr_raddr_o = 12'b0;
    csr_wdata   = 32'b0;
    csr_write   = 1'b0;

    if (active && id_ex_i.ctrl.is_mret) begin
      csr_raddr_o = CSR_MEPC;
    end else if (active && is_csr) begin
      csr_raddr_o = id_ex_i.insn[31:20];
    end

    unique case (id_ex_i.ctrl.csr_cmd)
      CSR_RW: begin
        csr_wdata   = forwarded_rs1;
        csr_write   = 1'b1;
      end

      CSR_RS: begin
        csr_wdata   = csr_rdata_i | forwarded_rs1;
        csr_write   = (id_ex_i.rs1 != 5'd0);
      end

      CSR_RC: begin
        csr_wdata   = csr_rdata_i & ~forwarded_rs1;
        csr_write   = (id_ex_i.rs1 != 5'd0);
      end

      CSR_RWI: begin
        csr_wdata   = {27'b0, id_ex_i.rs1};
        csr_write   = 1'b1;
      end

      CSR_RSI: begin
        csr_wdata   = csr_rdata_i | {27'b0, id_ex_i.rs1};
        csr_write   = (id_ex_i.rs1 != 5'd0);
      end

      CSR_RCI: begin
        csr_wdata   = csr_rdata_i & ~{27'b0, id_ex_i.rs1};
        csr_write   = (id_ex_i.rs1 != 5'd0);
      end

      default: begin
        csr_wdata   = 32'b0;
        csr_write   = 1'b0;
      end
    endcase
  end

  always_comb begin
    control_taken  = branch_taken;
    control_target = branch_target;

    if (id_ex_i.ctrl.is_mret) begin
      control_taken  = 1'b1;
      control_target = csr_rdata_i;
    end

    // branch_unit already checks this for branch/JAL/JALR. Re-checking the
    // selected target also covers MRET without creating a separate comparator.
    control_target_misaligned = id_ex_i.ctrl.is_mret
      ? (control_taken && (control_target[1:0] != 2'b00))
      : branch_target_misaligned;

    // Non-MDU operations are combinationally available. Valid never depends on
    // ready; this preserves ordinary ready/valid semantics under backpressure.
    result_valid_o = active && !is_mdu;
    ex_fire        = result_valid_o && result_ready_i;
    wait_o         = active && (is_mdu || !result_ready_i);

    ex_mem_d = '0;

    if (result_valid_o) begin
      ex_mem_d.valid          = 1'b1;
      ex_mem_d.pc             = id_ex_i.pc;
      ex_mem_d.insn           = id_ex_i.insn;
      ex_mem_d.rd             = id_ex_i.rd;
      ex_mem_d.reg_write      = id_ex_i.ctrl.reg_write;
      ex_mem_d.wb_sel         = id_ex_i.ctrl.wb_sel;
      ex_mem_d.ex_result      = alu_result;
      ex_mem_d.store_data     = forwarded_rs2;
      ex_mem_d.mem_cmd        = id_ex_i.ctrl.mem_cmd;
      ex_mem_d.mem_size       = id_ex_i.ctrl.mem_size;
      ex_mem_d.load_unsigned  = id_ex_i.ctrl.load_unsigned;
      ex_mem_d.csr_addr       = is_csr ? id_ex_i.insn[31:20] : 12'b0;
      ex_mem_d.csr_write      = is_csr && csr_write;
      ex_mem_d.csr_wdata      = is_csr ? csr_wdata : 32'b0;
      ex_mem_d.csr_old        = is_csr ? csr_rdata_i : 32'b0;
      ex_mem_d.control        = is_control;
      ex_mem_d.control_taken  = control_taken;
      ex_mem_d.control_target = control_target;
      ex_mem_d.exc            = id_ex_i.exc;

      // An older IF/ID exception attached to this packet has priority over
      // faults discovered by EX.
      if (!ex_mem_d.exc.valid) begin
        if (is_csr && csr_access_illegal_i) begin
          ex_mem_d.exc.valid = 1'b1;
          ex_mem_d.exc.cause = EXC_ILLEGAL_INSN;
          ex_mem_d.exc.tval  = id_ex_i.insn;
        end else if (is_control && control_target_misaligned) begin
          ex_mem_d.exc.valid = 1'b1;
          ex_mem_d.exc.cause = EXC_INST_ADDR_MISALIGNED;
          ex_mem_d.exc.tval  = control_target;
        end
      end

      // Exception packets keep debug/retirement metadata but cannot create an
      // architectural or memory side effect.
      if (ex_mem_d.exc.valid) begin
        ex_mem_d.reg_write = 1'b0;
        ex_mem_d.mem_cmd   = MEM_NONE;
        ex_mem_d.csr_write = 1'b0;
      end
    end

    control_redirect_d = '0;

    if (
      ex_fire &&
      is_control &&
      control_taken &&
      !ex_mem_d.exc.valid
    ) begin
      control_redirect_d.valid  = 1'b1;
      control_redirect_d.target = control_target;
      control_redirect_d.origin = REDIRECT_FROM_EX;
    end
  end

  assign ex_mem_o           = ex_mem_d;
  assign control_redirect_o = control_redirect_d;

endmodule
