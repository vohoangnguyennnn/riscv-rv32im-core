// SPDX-License-Identifier: MIT

module tb_decoder;

  import rv32_pkg::*;

  logic [31:0] insn;
  logic [4:0]  rs1;
  logic [4:0]  rs2;
  logic [4:0]  rd;
  imm_sel_e    imm_sel;
  decode_ctrl_t ctrl;
  logic         illegal;

  decode_ctrl_t expected_ctrl;
  int           checks;

  decoder dut (
    .insn_i    (insn),
    .rs1_o     (rs1),
    .rs2_o     (rs2),
    .rd_o      (rd),
    .imm_sel_o (imm_sel),
    .ctrl_o    (ctrl),
    .illegal_o (illegal)
  );

  function automatic logic [31:0] make_r(
    input logic [6:0] funct7,
    input logic [2:0] funct3,
    input logic [6:0] opcode
  );
    make_r = {funct7, 5'd4, 5'd3, funct3, 5'd5, opcode};
  endfunction

  function automatic logic [31:0] make_i(
    input logic [11:0] imm12,
    input logic [2:0]  funct3,
    input logic [6:0]  opcode
  );
    make_i = {imm12, 5'd3, funct3, 5'd5, opcode};
  endfunction

  function automatic logic [31:0] make_s(
    input logic [2:0] funct3
  );
    make_s = {7'h55, 5'd4, 5'd3, funct3, 5'h0a, OPCODE_STORE};
  endfunction

  function automatic logic [31:0] make_b(
    input logic [2:0] funct3
  );
    make_b = {7'h2a, 5'd4, 5'd3, funct3, 5'h15, OPCODE_BRANCH};
  endfunction

  function automatic logic [31:0] make_u(
    input logic [6:0] opcode
  );
    make_u = {20'habcde, 5'd5, opcode};
  endfunction

  function automatic logic [31:0] make_j;
    make_j = {20'habcde, 5'd5, OPCODE_JAL};
  endfunction

  task automatic set_safe_expected;
    begin
      expected_ctrl          = '0;
      expected_ctrl.op_a_sel = OP_A_ZERO;
      expected_ctrl.op_b_sel = OP_B_IMM;
      expected_ctrl.mem_size = MEM_WORD;
    end
  endtask

  task automatic check(
    input logic [31:0] test_insn,
    input imm_sel_e    expected_imm_sel,
    input logic        expected_illegal,
    input string       test_name
  );
    begin
      insn = test_insn;
      #1;

      if (rs1 !== test_insn[19:15]) begin
        $fatal(1, "%s rs1 mismatch: expected=%0d result=%0d", test_name,
               test_insn[19:15], rs1);
      end

      if (rs2 !== test_insn[24:20]) begin
        $fatal(1, "%s rs2 mismatch: expected=%0d result=%0d", test_name,
               test_insn[24:20], rs2);
      end

      if (rd !== test_insn[11:7]) begin
        $fatal(1, "%s rd mismatch: expected=%0d result=%0d", test_name,
               test_insn[11:7], rd);
      end

      if (imm_sel !== expected_imm_sel) begin
        $fatal(1, "%s imm_sel mismatch: expected=%0d result=%0d", test_name,
               expected_imm_sel, imm_sel);
      end

      if (illegal !== expected_illegal) begin
        $fatal(1, "%s illegal mismatch: expected=%0b result=%0b insn=%08x",
               test_name, expected_illegal, illegal, test_insn);
      end

      if (ctrl !== expected_ctrl) begin
        $fatal(1, "%s control mismatch: expected=%h result=%h insn=%08x",
               test_name, expected_ctrl, ctrl, test_insn);
      end

      checks++;
    end
  endtask

  task automatic check_branch(
    input logic [2:0] funct3,
    input branch_e    branch_kind,
    input string      test_name
  );
    begin
      set_safe_expected();
      expected_ctrl.uses_rs1    = 1'b1;
      expected_ctrl.uses_rs2    = 1'b1;
      expected_ctrl.branch_kind = branch_kind;
      check(make_b(funct3), IMM_B, 1'b0, test_name);
    end
  endtask

  task automatic check_load(
    input logic [2:0] funct3,
    input mem_size_e  mem_size,
    input logic       load_unsigned,
    input string      test_name
  );
    begin
      set_safe_expected();
      expected_ctrl.uses_rs1     = 1'b1;
      expected_ctrl.reg_write    = 1'b1;
      expected_ctrl.alu_op       = ALU_ADD;
      expected_ctrl.op_a_sel     = OP_A_RS1;
      expected_ctrl.op_b_sel     = OP_B_IMM;
      expected_ctrl.wb_sel       = WB_LOAD;
      expected_ctrl.mem_cmd      = MEM_LOAD;
      expected_ctrl.mem_size     = mem_size;
      expected_ctrl.load_unsigned = load_unsigned;
      check(make_i(12'ha55, funct3, OPCODE_LOAD), IMM_I, 1'b0, test_name);
    end
  endtask

  task automatic check_store(
    input logic [2:0] funct3,
    input mem_size_e  mem_size,
    input string      test_name
  );
    begin
      set_safe_expected();
      expected_ctrl.uses_rs1 = 1'b1;
      expected_ctrl.uses_rs2 = 1'b1;
      expected_ctrl.alu_op   = ALU_ADD;
      expected_ctrl.op_a_sel = OP_A_RS1;
      expected_ctrl.op_b_sel = OP_B_IMM;
      expected_ctrl.mem_cmd  = MEM_STORE;
      expected_ctrl.mem_size = mem_size;
      check(make_s(funct3), IMM_S, 1'b0, test_name);
    end
  endtask

  task automatic check_op_imm(
    input logic [11:0] imm12,
    input logic [2:0]  funct3,
    input alu_op_e     alu_op,
    input string       test_name
  );
    begin
      set_safe_expected();
      expected_ctrl.uses_rs1  = 1'b1;
      expected_ctrl.reg_write = 1'b1;
      expected_ctrl.alu_op    = alu_op;
      expected_ctrl.op_a_sel  = OP_A_RS1;
      expected_ctrl.op_b_sel  = OP_B_IMM;
      check(make_i(imm12, funct3, OPCODE_OP_IMM), IMM_I, 1'b0, test_name);
    end
  endtask

  task automatic check_op(
    input logic [6:0] funct7,
    input logic [2:0] funct3,
    input alu_op_e    alu_op,
    input string      test_name
  );
    begin
      set_safe_expected();
      expected_ctrl.uses_rs1  = 1'b1;
      expected_ctrl.uses_rs2  = 1'b1;
      expected_ctrl.reg_write = 1'b1;
      expected_ctrl.alu_op    = alu_op;
      expected_ctrl.op_a_sel  = OP_A_RS1;
      expected_ctrl.op_b_sel  = OP_B_RS2;
      check(make_r(funct7, funct3, OPCODE_OP), IMM_NONE, 1'b0, test_name);
    end
  endtask

  task automatic check_mdu(
    input logic [2:0] funct3,
    input mdu_op_e    mdu_op,
    input string      test_name
  );
    begin
      set_safe_expected();
      expected_ctrl.uses_rs1  = 1'b1;
      expected_ctrl.uses_rs2  = 1'b1;
      expected_ctrl.reg_write = 1'b1;
      expected_ctrl.op_a_sel  = OP_A_RS1;
      expected_ctrl.op_b_sel  = OP_B_RS2;
      expected_ctrl.mdu_op    = mdu_op;
      check(make_r(FUNCT7_M, funct3, OPCODE_OP), IMM_NONE, 1'b0, test_name);
    end
  endtask

  task automatic check_csr(
    input logic [11:0] csr_addr,
    input logic [2:0]  funct3,
    input logic        uses_rs1,
    input csr_cmd_e    csr_cmd,
    input string       test_name
  );
    begin
      set_safe_expected();
      expected_ctrl.uses_rs1  = uses_rs1;
      expected_ctrl.reg_write = 1'b1;
      expected_ctrl.wb_sel    = WB_CSR;
      expected_ctrl.csr_cmd   = csr_cmd;
      check(make_i(csr_addr, funct3, OPCODE_SYSTEM), IMM_NONE, 1'b0, test_name);
    end
  endtask

  task automatic check_illegal(
    input logic [31:0] test_insn,
    input string       test_name
  );
    begin
      set_safe_expected();
      check(test_insn, IMM_NONE, 1'b1, test_name);
    end
  endtask

  initial begin
    insn   = 32'b0;
    checks = 0;
    set_safe_expected();

    // RV32I upper-immediate and control-transfer instructions.
    expected_ctrl.reg_write = 1'b1;
    expected_ctrl.alu_op    = ALU_ADD;
    check(make_u(OPCODE_LUI), IMM_U, 1'b0, "LUI");

    set_safe_expected();
    expected_ctrl.reg_write = 1'b1;
    expected_ctrl.alu_op    = ALU_ADD;
    expected_ctrl.op_a_sel  = OP_A_PC;
    check(make_u(OPCODE_AUIPC), IMM_U, 1'b0, "AUIPC");

    set_safe_expected();
    expected_ctrl.reg_write   = 1'b1;
    expected_ctrl.wb_sel      = WB_PC4;
    expected_ctrl.branch_kind = BR_JAL;
    check(make_j(), IMM_J, 1'b0, "JAL");

    set_safe_expected();
    expected_ctrl.uses_rs1    = 1'b1;
    expected_ctrl.reg_write   = 1'b1;
    expected_ctrl.wb_sel      = WB_PC4;
    expected_ctrl.branch_kind = BR_JALR;
    check(make_i(12'h123, FUNCT3_JALR, OPCODE_JALR), IMM_I, 1'b0, "JALR");

    // Six conditional branches.
    check_branch(FUNCT3_BEQ,  BR_BEQ,  "BEQ");
    check_branch(FUNCT3_BNE,  BR_BNE,  "BNE");
    check_branch(FUNCT3_BLT,  BR_BLT,  "BLT");
    check_branch(FUNCT3_BGE,  BR_BGE,  "BGE");
    check_branch(FUNCT3_BLTU, BR_BLTU, "BLTU");
    check_branch(FUNCT3_BGEU, BR_BGEU, "BGEU");

    // Five RV32I loads and three stores.
    check_load(FUNCT3_LB,  MEM_BYTE, 1'b0, "LB");
    check_load(FUNCT3_LH,  MEM_HALF, 1'b0, "LH");
    check_load(FUNCT3_LW,  MEM_WORD, 1'b0, "LW");
    check_load(FUNCT3_LBU, MEM_BYTE, 1'b1, "LBU");
    check_load(FUNCT3_LHU, MEM_HALF, 1'b1, "LHU");

    check_store(FUNCT3_SB, MEM_BYTE, "SB");
    check_store(FUNCT3_SH, MEM_HALF, "SH");
    check_store(FUNCT3_SW, MEM_WORD, "SW");

    // Nine OP-IMM instructions. Non-shift immediates deliberately contain
    // nonzero upper bits to prove that only shift encodings constrain funct7.
    check_op_imm(12'ha55, FUNCT3_ADD_SUB, ALU_ADD,  "ADDI");
    check_op_imm(12'ha55, FUNCT3_SLT,     ALU_SLT,  "SLTI");
    check_op_imm(12'ha55, FUNCT3_SLTU,    ALU_SLTU, "SLTIU");
    check_op_imm(12'ha55, FUNCT3_XOR,     ALU_XOR,  "XORI");
    check_op_imm(12'ha55, FUNCT3_OR,      ALU_OR,   "ORI");
    check_op_imm(12'ha55, FUNCT3_AND,     ALU_AND,  "ANDI");
    check_op_imm({FUNCT7_BASE, 5'd17}, FUNCT3_SLL, ALU_SLL, "SLLI");
    check_op_imm({FUNCT7_BASE, 5'd17}, FUNCT3_SRL_SRA, ALU_SRL, "SRLI");
    check_op_imm({FUNCT7_SUB_SRA, 5'd17}, FUNCT3_SRL_SRA, ALU_SRA, "SRAI");

    // Ten base register-register ALU instructions.
    check_op(FUNCT7_BASE,    FUNCT3_ADD_SUB, ALU_ADD,  "ADD");
    check_op(FUNCT7_SUB_SRA, FUNCT3_ADD_SUB, ALU_SUB,  "SUB");
    check_op(FUNCT7_BASE,    FUNCT3_SLL,     ALU_SLL,  "SLL");
    check_op(FUNCT7_BASE,    FUNCT3_SLT,     ALU_SLT,  "SLT");
    check_op(FUNCT7_BASE,    FUNCT3_SLTU,    ALU_SLTU, "SLTU");
    check_op(FUNCT7_BASE,    FUNCT3_XOR,     ALU_XOR,  "XOR");
    check_op(FUNCT7_BASE,    FUNCT3_SRL_SRA, ALU_SRL,  "SRL");
    check_op(FUNCT7_SUB_SRA, FUNCT3_SRL_SRA, ALU_SRA,  "SRA");
    check_op(FUNCT7_BASE,    FUNCT3_OR,      ALU_OR,   "OR");
    check_op(FUNCT7_BASE,    FUNCT3_AND,     ALU_AND,  "AND");

    // Complete RV32M funct3 space.
    check_mdu(FUNCT3_MUL,    MDU_MUL,    "MUL");
    check_mdu(FUNCT3_MULH,   MDU_MULH,   "MULH");
    check_mdu(FUNCT3_MULHSU, MDU_MULHSU, "MULHSU");
    check_mdu(FUNCT3_MULHU,  MDU_MULHU,  "MULHU");
    check_mdu(FUNCT3_DIV,    MDU_DIV,    "DIV");
    check_mdu(FUNCT3_DIVU,   MDU_DIVU,   "DIVU");
    check_mdu(FUNCT3_REM,    MDU_REM,    "REM");
    check_mdu(FUNCT3_REMU,   MDU_REMU,   "REMU");

    // Privileged/system instructions handled by the ID integration.
    set_safe_expected();
    check(INSN_ECALL, IMM_NONE, 1'b0, "ECALL");

    set_safe_expected();
    check(INSN_EBREAK, IMM_NONE, 1'b0, "EBREAK");

    set_safe_expected();
    expected_ctrl.is_mret = 1'b1;
    check(INSN_MRET, IMM_NONE, 1'b0, "MRET");

    // Six Zicsr operations. CSR address support is checked later by csr_file;
    // decoder is responsible only for validating the instruction encoding.
    check_csr(CSR_MTVEC, FUNCT3_CSRRW,  1'b1, CSR_RW,  "CSRRW");
    check_csr(CSR_MEPC,  FUNCT3_CSRRS,  1'b1, CSR_RS,  "CSRRS");
    check_csr(CSR_MCAUSE,FUNCT3_CSRRC,  1'b1, CSR_RC,  "CSRRC");
    check_csr(CSR_MTVAL, FUNCT3_CSRRWI, 1'b0, CSR_RWI, "CSRRWI");
    check_csr(12'h999,   FUNCT3_CSRRSI, 1'b0, CSR_RSI, "CSRRSI syntax");
    check_csr(CSR_MISA,  FUNCT3_CSRRCI, 1'b0, CSR_RCI, "CSRRCI");

    set_safe_expected();
    expected_ctrl.is_fence = 1'b1;
    check(32'h0ff0_000f, IMM_NONE, 1'b0, "FENCE");

    // Reserved or out-of-scope encodings must keep benign controls.
    check_illegal(32'h0000_0000, "zero encoding");
    check_illegal(make_i(12'h123, 3'b001, OPCODE_JALR), "JALR reserved funct3");
    check_illegal(make_b(3'b010), "branch reserved funct3 010");
    check_illegal(make_b(3'b011), "branch reserved funct3 011");
    check_illegal(make_i(12'ha55, 3'b011, OPCODE_LOAD), "load reserved funct3 011");
    check_illegal(make_i(12'ha55, 3'b110, OPCODE_LOAD), "LWU is RV64 only");
    check_illegal(make_i(12'ha55, 3'b111, OPCODE_LOAD), "load reserved funct3 111");
    check_illegal(make_s(3'b011), "store reserved funct3");
    check_illegal(make_i({FUNCT7_SUB_SRA, 5'd1}, FUNCT3_SLL, OPCODE_OP_IMM),
                  "SLLI reserved upper bits");
    check_illegal(make_i({FUNCT7_M, 5'd1}, FUNCT3_SRL_SRA, OPCODE_OP_IMM),
                  "shift immediate reserved upper bits");
    check_illegal(make_r(FUNCT7_SUB_SRA, FUNCT3_AND, OPCODE_OP),
                  "OP reserved SUB_SRA combination");
    check_illegal(make_r(7'b000_0010, FUNCT3_ADD_SUB, OPCODE_OP),
                  "OP reserved funct7");
    check_illegal(32'h0000_100f, "FENCE.I out of scope");
    check_illegal(make_i(12'h123, 3'b100, OPCODE_SYSTEM),
                  "SYSTEM reserved funct3");
    check_illegal(32'h1050_0073, "WFI out of scope");
    check_illegal(32'h1020_0073, "SRET out of scope");
    check_illegal(32'h0000_00f3, "malformed ECALL");
    check_illegal(32'hffff_ffff, "unknown major opcode");

    $display("PASS: %0d decoder checks", checks);
    $finish;
  end

endmodule
