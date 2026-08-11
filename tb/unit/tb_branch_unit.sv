// SPDX-License-Identifier: MIT

module tb_branch_unit;

  import rv32_pkg::*;

  branch_e    kind;
  logic [31:0] pc;
  logic [31:0] imm;
  logic [31:0] rs1;
  logic [31:0] rs2;
  logic        taken;
  logic [31:0] target;
  logic        misaligned;
  int          checks;

  branch_unit dut (
    .kind_i       (kind),
    .pc_i         (pc),
    .imm_i        (imm),
    .rs1_i        (rs1),
    .rs2_i        (rs2),
    .taken_o      (taken),
    .target_o     (target),
    .misaligned_o (misaligned)
  );

  task automatic check(
    input branch_e    test_kind,
    input logic [31:0] test_pc,
    input logic [31:0] test_imm,
    input logic [31:0] test_rs1,
    input logic [31:0] test_rs2,
    input logic        expected_taken,
    input logic [31:0] expected_target,
    input logic        expected_misaligned,
    input string       test_name
  );
    begin
      kind = test_kind;
      pc   = test_pc;
      imm  = test_imm;
      rs1  = test_rs1;
      rs2  = test_rs2;
      #1;

      if (taken !== expected_taken) begin
        $fatal(
          1,
          "%s taken mismatch: expected=%0b result=%0b",
          test_name,
          expected_taken,
          taken
        );
      end

      if (target !== expected_target) begin
        $fatal(
          1,
          "%s target mismatch: expected=%08x result=%08x",
          test_name,
          expected_target,
          target
        );
      end

      if (misaligned !== expected_misaligned) begin
        $fatal(
          1,
          "%s misaligned mismatch: expected=%0b result=%0b target=%08x",
          test_name,
          expected_misaligned,
          misaligned,
          target
        );
      end

      checks++;
    end
  endtask

  initial begin
    kind   = BR_NONE;
    pc     = 32'b0;
    imm    = 32'b0;
    rs1    = 32'b0;
    rs2    = 32'b0;
    checks = 0;

    check(BR_NONE, 32'h1000, 32'h0010, 32'h1111, 32'h2222,
          1'b0, 32'h0000_0000, 1'b0, "none");

    // Equality branches and the rule that only taken targets can fault.
    check(BR_BEQ, 32'h1000, 32'h0010, 32'h1234, 32'h1234,
          1'b1, 32'h0000_1010, 1'b0, "BEQ taken");
    check(BR_BEQ, 32'h1000, 32'h0010, 32'h1234, 32'h5678,
          1'b0, 32'h0000_1010, 1'b0, "BEQ not taken");
    check(BR_BEQ, 32'h1000, 32'h0002, 32'h1234, 32'h5678,
          1'b0, 32'h0000_1002, 1'b0, "BEQ not taken misaligned target");
    check(BR_BEQ, 32'h1000, 32'h0002, 32'h1234, 32'h1234,
          1'b1, 32'h0000_1002, 1'b1, "BEQ taken misaligned target");

    check(BR_BNE, 32'h2000, 32'h0020, 32'h1234, 32'h5678,
          1'b1, 32'h0000_2020, 1'b0, "BNE taken");
    check(BR_BNE, 32'h2000, 32'h0020, 32'h1234, 32'h1234,
          1'b0, 32'h0000_2020, 1'b0, "BNE not taken");

    // Signed comparisons.
    check(BR_BLT, 32'h3000, 32'h0010, 32'hffff_ffff, 32'h0000_0000,
          1'b1, 32'h0000_3010, 1'b0, "BLT negative less than zero");
    check(BR_BLT, 32'h3000, 32'h0010, 32'h0000_0000, 32'hffff_ffff,
          1'b0, 32'h0000_3010, 1'b0, "BLT zero not less than negative");
    check(BR_BLT, 32'h3000, 32'h0010, 32'h8000_0000, 32'h7fff_ffff,
          1'b1, 32'h0000_3010, 1'b0, "BLT signed boundary");

    check(BR_BGE, 32'h4000, 32'h0010, 32'hffff_ffff, 32'h0000_0000,
          1'b0, 32'h0000_4010, 1'b0, "BGE negative not greater");
    check(BR_BGE, 32'h4000, 32'h0010, 32'h0000_0000, 32'hffff_ffff,
          1'b1, 32'h0000_4010, 1'b0, "BGE zero greater than negative");
    check(BR_BGE, 32'h4000, 32'h0010, 32'h8000_0000, 32'h8000_0000,
          1'b1, 32'h0000_4010, 1'b0, "BGE equal");

    // Unsigned comparisons use the same bit patterns with different results.
    check(BR_BLTU, 32'h5000, 32'h0010, 32'h0000_0000, 32'hffff_ffff,
          1'b1, 32'h0000_5010, 1'b0, "BLTU low less than high");
    check(BR_BLTU, 32'h5000, 32'h0010, 32'hffff_ffff, 32'h0000_0000,
          1'b0, 32'h0000_5010, 1'b0, "BLTU high not less than low");

    check(BR_BGEU, 32'h6000, 32'h0010, 32'hffff_ffff, 32'h0000_0000,
          1'b1, 32'h0000_6010, 1'b0, "BGEU high greater than low");
    check(BR_BGEU, 32'h6000, 32'h0010, 32'h0000_0000, 32'hffff_ffff,
          1'b0, 32'h0000_6010, 1'b0, "BGEU low not greater than high");
    check(BR_BGEU, 32'h6000, 32'h0010, 32'h89ab_cdef, 32'h89ab_cdef,
          1'b1, 32'h0000_6010, 1'b0, "BGEU equal");

    // PC-relative target generation, including negative offset and wraparound.
    check(BR_JAL, 32'h0000_1000, 32'h0000_0080, 32'b0, 32'b0,
          1'b1, 32'h0000_1080, 1'b0, "JAL positive offset");
    check(BR_JAL, 32'h0000_1000, 32'hffff_fff0, 32'b0, 32'b0,
          1'b1, 32'h0000_0ff0, 1'b0, "JAL negative offset");
    check(BR_JAL, 32'h0000_1000, 32'h0000_0002, 32'b0, 32'b0,
          1'b1, 32'h0000_1002, 1'b1, "JAL misaligned target");
    check(BR_JAL, 32'hffff_fffc, 32'h0000_0008, 32'b0, 32'b0,
          1'b1, 32'h0000_0004, 1'b0, "JAL target wraparound");

    // JALR uses rs1 rather than PC and always clears target bit 0.
    check(BR_JALR, 32'hdead_beef, 32'h0000_0004, 32'h0000_1001, 32'b0,
          1'b1, 32'h0000_1004, 1'b0, "JALR clears bit zero");
    check(BR_JALR, 32'hdead_beef, 32'h0000_0003, 32'h0000_1000, 32'b0,
          1'b1, 32'h0000_1002, 1'b1, "JALR bit one misalignment");
    check(BR_JALR, 32'hdead_beef, 32'hffff_fff8, 32'h0000_1008, 32'b0,
          1'b1, 32'h0000_1000, 1'b0, "JALR negative offset");
    check(BR_JALR, 32'hdead_beef, 32'h0000_0005, 32'hffff_fffd, 32'b0,
          1'b1, 32'h0000_0002, 1'b1, "JALR target wraparound");

    $display("PASS: %0d branch-unit checks", checks);
    $finish;
  end

endmodule
