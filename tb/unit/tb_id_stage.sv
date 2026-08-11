// SPDX-License-Identifier: MIT

module tb_id_stage;

  import rv32_pkg::*;

  logic   clk;
  if_id_t if_id;

  logic        wb_we;
  logic [4:0]  wb_rd;
  logic [31:0] wb_data;

  id_ex_t id_ex;
  int     checks;

  id_stage dut (
    .clk_i    (clk),
    .if_id_i  (if_id),
    .wb_we_i  (wb_we),
    .wb_rd_i  (wb_rd),
    .wb_data_i (wb_data),
    .id_ex_o  (id_ex)
  );

  always #5 clk = ~clk;

  function automatic decode_ctrl_t safe_ctrl;
    decode_ctrl_t ctrl;
    begin
      ctrl          = '0;
      ctrl.op_a_sel = OP_A_ZERO;
      ctrl.op_b_sel = OP_B_IMM;
      ctrl.mem_size = MEM_WORD;
      safe_ctrl     = ctrl;
    end
  endfunction

  function automatic logic [31:0] encode_r(
    input logic [6:0] funct7,
    input logic [4:0] rs2,
    input logic [4:0] rs1,
    input logic [2:0] funct3,
    input logic [4:0] rd,
    input logic [6:0] opcode
  );
    encode_r = {funct7, rs2, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] encode_i(
    input logic [11:0] imm12,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3,
    input logic [4:0]  rd,
    input logic [6:0]  opcode
  );
    encode_i = {imm12, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] encode_s(
    input logic [11:0] imm12,
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3
  );
    encode_s = {
      imm12[11:5],
      rs2,
      rs1,
      funct3,
      imm12[4:0],
      OPCODE_STORE
    };
  endfunction

  task automatic drive_packet(
    input logic        valid,
    input logic [31:0] pc,
    input logic [31:0] insn
  );
    begin
      if_id           = '0;
      if_id.valid     = valid;
      if_id.pc        = pc;
      if_id.insn      = insn;
      #1;
    end
  endtask

  task automatic write_register(
    input logic [4:0]  rd,
    input logic [31:0] data
  );
    begin
      @(negedge clk);
      wb_we   = 1'b1;
      wb_rd   = rd;
      wb_data = data;
      @(posedge clk);
      #1;
      wb_we   = 1'b0;
      wb_rd   = 5'd0;
      wb_data = 32'b0;
    end
  endtask

  task automatic check_bundle(
    input id_ex_t expected,
    input string  test_name
  );
    begin
      if (id_ex !== expected) begin
        $fatal(
          1,
          "%s bundle mismatch:\n  expected=%h\n  result  =%h",
          test_name,
          expected,
          id_ex
        );
      end
      checks++;
    end
  endtask

  initial begin
    id_ex_t      expected;
    decode_ctrl_t expected_ctrl;
    logic [31:0] test_insn;

    clk         = 1'b0;
    if_id       = '0;
    wb_we       = 1'b0;
    wb_rd       = 5'd0;
    wb_data     = 32'b0;
    checks      = 0;

    // An invalid IF/ID entry produces a fully benign ID/EX bubble.
    #1;
    expected = '0;
    check_bundle(expected, "invalid bubble");

    // Give the source registers deterministic architectural values.
    write_register(5'd3, 32'h1111_1111);
    write_register(5'd4, 32'h2222_2222);
    write_register(5'd7, 32'h7777_7777);

    // Register-register decode carries both source values and side-effect
    // controls into the ID/EX next bundle.
    test_insn = encode_r(
      FUNCT7_BASE,
      5'd4,
      5'd3,
      FUNCT3_ADD_SUB,
      5'd5,
      OPCODE_OP
    );
    drive_packet(1'b1, 32'h0000_1000, test_insn);

    expected_ctrl              = safe_ctrl();
    expected_ctrl.uses_rs1     = 1'b1;
    expected_ctrl.uses_rs2     = 1'b1;
    expected_ctrl.reg_write    = 1'b1;
    expected_ctrl.alu_op       = ALU_ADD;
    expected_ctrl.op_a_sel     = OP_A_RS1;
    expected_ctrl.op_b_sel     = OP_B_RS2;

    expected           = '0;
    expected.valid     = 1'b1;
    expected.pc        = 32'h0000_1000;
    expected.insn      = test_insn;
    expected.rs1       = 5'd3;
    expected.rs2       = 5'd4;
    expected.rd        = 5'd5;
    expected.rs1_value = 32'h1111_1111;
    expected.rs2_value = 32'h2222_2222;
    expected.ctrl      = expected_ctrl;
    check_bundle(expected, "ADD decode");

    // Immediate decode sign-extends the operand and zeros the unused rs2 value.
    test_insn = encode_i(
      12'hfff,
      5'd3,
      FUNCT3_ADD_SUB,
      5'd6,
      OPCODE_OP_IMM
    );
    drive_packet(1'b1, 32'h0000_1004, test_insn);

    expected_ctrl              = safe_ctrl();
    expected_ctrl.uses_rs1     = 1'b1;
    expected_ctrl.reg_write    = 1'b1;
    expected_ctrl.alu_op       = ALU_ADD;
    expected_ctrl.op_a_sel     = OP_A_RS1;

    expected           = '0;
    expected.valid     = 1'b1;
    expected.pc        = 32'h0000_1004;
    expected.insn      = test_insn;
    expected.rs1       = 5'd3;
    expected.rs2       = 5'd31;
    expected.rd        = 5'd6;
    expected.rs1_value = 32'h1111_1111;
    expected.imm       = 32'hffff_ffff;
    expected.ctrl      = expected_ctrl;
    check_bundle(expected, "ADDI negative immediate");

    // Store decode preserves both operands and reconstructs the split S
    // immediate.
    test_insn = encode_s(
      12'hffc,
      5'd4,
      5'd3,
      FUNCT3_SW
    );
    drive_packet(1'b1, 32'h0000_1008, test_insn);

    expected_ctrl              = safe_ctrl();
    expected_ctrl.uses_rs1     = 1'b1;
    expected_ctrl.uses_rs2     = 1'b1;
    expected_ctrl.alu_op       = ALU_ADD;
    expected_ctrl.op_a_sel     = OP_A_RS1;
    expected_ctrl.mem_cmd      = MEM_STORE;

    expected           = '0;
    expected.valid     = 1'b1;
    expected.pc        = 32'h0000_1008;
    expected.insn      = test_insn;
    expected.rs1       = 5'd3;
    expected.rs2       = 5'd4;
    expected.rd        = 5'd28;
    expected.rs1_value = 32'h1111_1111;
    expected.rs2_value = 32'h2222_2222;
    expected.imm       = 32'hffff_fffc;
    expected.ctrl      = expected_ctrl;
    check_bundle(expected, "SW decode");

    // WB data must be visible to ID in the commit cycle, before relying on the
    // register-file write edge.
    test_insn = encode_r(
      FUNCT7_BASE,
      5'd4,
      5'd3,
      FUNCT3_ADD_SUB,
      5'd5,
      OPCODE_OP
    );
    drive_packet(1'b1, 32'h0000_100c, test_insn);

    expected_ctrl              = safe_ctrl();
    expected_ctrl.uses_rs1     = 1'b1;
    expected_ctrl.uses_rs2     = 1'b1;
    expected_ctrl.reg_write    = 1'b1;
    expected_ctrl.alu_op       = ALU_ADD;
    expected_ctrl.op_a_sel     = OP_A_RS1;
    expected_ctrl.op_b_sel     = OP_B_RS2;
    expected                   = '0;
    expected.valid             = 1'b1;
    expected.pc                = 32'h0000_100c;
    expected.insn              = test_insn;
    expected.rs1               = 5'd3;
    expected.rs2               = 5'd4;
    expected.rd                = 5'd5;
    expected.rs1_value         = 32'h1111_1111;
    expected.rs2_value         = 32'h2222_2222;
    expected.ctrl              = expected_ctrl;

    @(negedge clk);
    wb_we   = 1'b1;
    wb_rd   = 5'd3;
    wb_data = 32'hdead_beef;
    #1;

    expected.pc        = 32'h0000_100c;
    expected.insn      = test_insn;
    expected.rs1_value = 32'hdead_beef;
    expected.rs2_value = 32'h2222_2222;
    expected.imm       = 32'b0;
    expected.ctrl      = expected_ctrl;
    check_bundle(expected, "WB to ID bypass");

    @(posedge clk);
    #1;
    wb_we   = 1'b0;
    wb_rd   = 5'd0;
    wb_data = 32'b0;
    expected.rs1_value = 32'hdead_beef;
    check_bundle(expected, "WB value committed");

    // A write targeting x0 must not bypass nonzero data into an x0 operand.
    test_insn = encode_r(
      FUNCT7_BASE,
      5'd4,
      5'd0,
      FUNCT3_ADD_SUB,
      5'd5,
      OPCODE_OP
    );
    drive_packet(1'b1, 32'h0000_1010, test_insn);
    wb_we   = 1'b1;
    wb_rd   = 5'd0;
    wb_data = 32'hffff_ffff;
    #1;

    expected.pc        = 32'h0000_1010;
    expected.insn      = test_insn;
    expected.rs1       = 5'd0;
    expected.rs1_value = 32'b0;
    expected.rs2_value = 32'h2222_2222;
    check_bundle(expected, "x0 bypass suppressed");

    wb_we   = 1'b0;
    wb_data = 32'b0;

    // Both read ports independently select the WB bypass when they name the
    // same committing destination.
    test_insn = encode_r(
      FUNCT7_BASE,
      5'd7,
      5'd7,
      FUNCT3_ADD_SUB,
      5'd9,
      OPCODE_OP
    );
    drive_packet(1'b1, 32'h0000_1014, test_insn);
    @(negedge clk);
    wb_we   = 1'b1;
    wb_rd   = 5'd7;
    wb_data = 32'hcafe_babe;
    #1;

    expected           = '0;
    expected.valid     = 1'b1;
    expected.pc        = 32'h0000_1014;
    expected.insn      = test_insn;
    expected.rs1       = 5'd7;
    expected.rs2       = 5'd7;
    expected.rd        = 5'd9;
    expected.rs1_value = 32'hcafe_babe;
    expected.rs2_value = 32'hcafe_babe;
    expected.ctrl      = expected_ctrl;
    check_bundle(expected, "dual-source WB bypass");

    @(posedge clk);
    #1;
    wb_we   = 1'b0;
    wb_rd   = 5'd0;
    wb_data = 32'b0;

    // A fetch access fault has priority over decoding the placeholder
    // instruction and must suppress all controls.
    if_id           = '0;
    if_id.valid     = 1'b1;
    if_id.pc        = 32'h0001_0000;
    if_id.insn      = 32'b0;
    if_id.exc.valid = 1'b1;
    if_id.exc.cause = EXC_INST_ACCESS_FAULT;
    if_id.exc.tval  = 32'h0001_0000;
    #1;

    expected           = '0;
    expected.valid     = 1'b1;
    expected.pc        = 32'h0001_0000;
    expected.exc       = if_id.exc;
    check_bundle(expected, "fetch exception priority");

    // Reserved encodings become illegal-instruction exceptions with the
    // original instruction bits in tval.
    test_insn = 32'hffff_ffff;
    drive_packet(1'b1, 32'h0000_1018, test_insn);

    expected           = '0;
    expected.valid     = 1'b1;
    expected.pc        = 32'h0000_1018;
    expected.insn      = test_insn;
    expected.rs1       = 5'd31;
    expected.rs2       = 5'd31;
    expected.rd        = 5'd31;
    expected.exc.valid = 1'b1;
    expected.exc.cause = EXC_ILLEGAL_INSN;
    expected.exc.tval  = test_insn;
    check_bundle(expected, "illegal instruction exception");

    // ECALL and EBREAK are legal encodings that deliberately create precise
    // synchronous exceptions in ID.
    drive_packet(1'b1, 32'h0000_101c, INSN_ECALL);
    expected           = '0;
    expected.valid     = 1'b1;
    expected.pc        = 32'h0000_101c;
    expected.insn      = INSN_ECALL;
    expected.exc.valid = 1'b1;
    expected.exc.cause = EXC_ECALL_M;
    expected.exc.tval  = 32'b0;
    check_bundle(expected, "ECALL exception");

    drive_packet(1'b1, 32'h0000_1020, INSN_EBREAK);
    expected           = '0;
    expected.valid     = 1'b1;
    expected.pc        = 32'h0000_1020;
    expected.insn      = INSN_EBREAK;
    expected.rs2       = INSN_EBREAK[24:20];
    expected.exc.valid = 1'b1;
    expected.exc.cause = EXC_BREAKPOINT;
    expected.exc.tval  = 32'h0000_1020;
    check_bundle(expected, "EBREAK exception");

    // MRET remains a legal control operation; its target is resolved in EX.
    drive_packet(1'b1, 32'h0000_1024, INSN_MRET);
    expected_ctrl         = safe_ctrl();
    expected_ctrl.is_mret = 1'b1;
    expected              = '0;
    expected.valid        = 1'b1;
    expected.pc           = 32'h0000_1024;
    expected.insn         = INSN_MRET;
    expected.rs1          = INSN_MRET[19:15];
    expected.rs2          = INSN_MRET[24:20];
    expected.rd           = INSN_MRET[11:7];
    expected.ctrl         = expected_ctrl;
    check_bundle(expected, "MRET decode");

    // CSR-immediate instructions retain zimm in the rs1 field but do not read
    // the integer register file.
    test_insn = encode_i(
      CSR_MTVEC,
      5'd7,
      FUNCT3_CSRRWI,
      5'd8,
      OPCODE_SYSTEM
    );
    drive_packet(1'b1, 32'h0000_1028, test_insn);

    expected_ctrl              = safe_ctrl();
    expected_ctrl.reg_write    = 1'b1;
    expected_ctrl.wb_sel       = WB_CSR;
    expected_ctrl.csr_cmd      = CSR_RWI;
    expected                  = '0;
    expected.valid            = 1'b1;
    expected.pc               = 32'h0000_1028;
    expected.insn             = test_insn;
    expected.rs1              = 5'd7;
    expected.rs2              = CSR_MTVEC[4:0];
    expected.rd               = 5'd8;
    expected.ctrl             = expected_ctrl;
    check_bundle(expected, "CSRRWI zimm");

    // FENCE is a legal no-op in the current single-hart blocking-TCM system.
    test_insn = 32'h0ff0_000f;
    drive_packet(1'b1, 32'h0000_102c, test_insn);
    expected_ctrl          = safe_ctrl();
    expected_ctrl.is_fence = 1'b1;
    expected               = '0;
    expected.valid         = 1'b1;
    expected.pc            = 32'h0000_102c;
    expected.insn          = test_insn;
    expected.rs1           = test_insn[19:15];
    expected.rs2           = test_insn[24:20];
    expected.rd            = test_insn[11:7];
    expected.ctrl          = expected_ctrl;
    check_bundle(expected, "FENCE legal no-op");

    $display("tb_id_stage: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
