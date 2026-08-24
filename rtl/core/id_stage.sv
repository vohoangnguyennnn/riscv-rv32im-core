// RV32IM + Zicsr instruction-decode stage.
//
// Pipeline storage remains in rv32_core. This stage combines decode, immediate
// generation, register access, WB-to-ID bypass, and exception construction.
module id_stage (
  input  logic                   clk_i,
  input  wire rv32_pkg::if_id_t  if_id_i,

  input  logic                   wb_we_i,
  input  logic [4:0]             wb_rd_i,
  input  logic [31:0]            wb_data_i,

  output wire rv32_pkg::id_ex_t  id_ex_o
);

  import rv32_pkg::*;

  logic [4:0]   dec_rs1;
  logic [4:0]   dec_rs2;
  logic [4:0]   dec_rd;
  imm_sel_e     dec_imm_sel;
  decode_ctrl_t dec_ctrl;
  logic         dec_illegal;

  word_t dec_imm;
  word_t rf_rs1_data;
  word_t rf_rs2_data;
  word_t id_rs1_value;
  word_t id_rs2_value;

  id_ex_t id_ex_d;

  decoder u_decoder (
    .insn_i    (if_id_i.insn),
    .rs1_o     (dec_rs1),
    .rs2_o     (dec_rs2),
    .rd_o      (dec_rd),
    .imm_sel_o (dec_imm_sel),
    .ctrl_o    (dec_ctrl),
    .illegal_o (dec_illegal)
  );

  imm_gen u_imm_gen (
    .insn_i (if_id_i.insn),
    .sel_i  (dec_imm_sel),
    .imm_o  (dec_imm)
  );

  regfile u_regfile (
    .clk_i    (clk_i),
    .we_i     (wb_we_i),
    .waddr_i  (wb_rd_i),
    .wdata_i  (wb_data_i),
    .raddr1_i (dec_rs1),
    .raddr2_i (dec_rs2),
    .rdata1_o (rf_rs1_data),
    .rdata2_o (rf_rs2_data)
  );

  // Explicit WB-to-ID bypass avoids technology-specific read-during-write
  // behavior; unused operands are zeroed to prevent X propagation.
  always_comb begin
    id_rs1_value = 32'b0;
    id_rs2_value = 32'b0;

    if (dec_ctrl.uses_rs1) begin
      if (wb_we_i && (wb_rd_i != 5'd0) && (wb_rd_i == dec_rs1)) begin
        id_rs1_value = wb_data_i;
      end else begin
        id_rs1_value = rf_rs1_data;
      end
    end

    if (dec_ctrl.uses_rs2) begin
      if (wb_we_i && (wb_rd_i != 5'd0) && (wb_rd_i == dec_rs2)) begin
        id_rs2_value = wb_data_i;
      end else begin
        id_rs2_value = rf_rs2_data;
      end
    end
  end

  always_comb begin
    id_ex_d = '0;

    if (if_id_i.valid) begin
      id_ex_d.valid     = 1'b1;
      id_ex_d.pc        = if_id_i.pc;
      id_ex_d.insn      = if_id_i.insn;
      id_ex_d.rs1       = dec_rs1;
      id_ex_d.rs2       = dec_rs2;
      id_ex_d.rd        = dec_rd;
      id_ex_d.rs1_value = id_rs1_value;
      id_ex_d.rs2_value = id_rs2_value;
      id_ex_d.imm       = dec_imm;
      id_ex_d.ctrl      = dec_ctrl;
      id_ex_d.exc       = if_id_i.exc;

      // A fetch exception precedes errors from decoding its placeholder bits.
      if (!if_id_i.exc.valid) begin
        if (dec_illegal) begin
          id_ex_d.exc.valid = 1'b1;
          id_ex_d.exc.cause = EXC_ILLEGAL_INSN;
          id_ex_d.exc.tval  = if_id_i.insn;
        end else if (if_id_i.insn == INSN_ECALL) begin
          id_ex_d.exc.valid = 1'b1;
          id_ex_d.exc.cause = EXC_ECALL_M;
          id_ex_d.exc.tval  = 32'b0;
        end else if (if_id_i.insn == INSN_EBREAK) begin
          id_ex_d.exc.valid = 1'b1;
          id_ex_d.exc.cause = EXC_BREAKPOINT;
          id_ex_d.exc.tval  = if_id_i.pc;
        end
      end

      // Exception packets retain metadata but carry no side effects into EX.
      if (id_ex_d.exc.valid) begin
        id_ex_d.rs1_value = 32'b0;
        id_ex_d.rs2_value = 32'b0;
        id_ex_d.ctrl      = '0;
      end
    end
  end

  assign id_ex_o = id_ex_d;

endmodule
