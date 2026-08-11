// SPDX-License-Identifier: MIT

module tb_alu;

  import rv32_pkg::*;

  alu_op_e    op;
  logic [31:0] a;
  logic [31:0] b;
  logic [31:0] result;
  int          checks;

  alu dut (
    .op_i     (op),
    .a_i      (a),
    .b_i      (b),
    .result_o (result)
  );

  task automatic check(
    input alu_op_e    test_op,
    input logic [31:0] test_a,
    input logic [31:0] test_b,
    input logic [31:0] expected,
    input string       test_name
  );
    begin
      op = test_op;
      a  = test_a;
      b  = test_b;
      #1;

      if (result !== expected) begin
        $fatal(
          1,
          "%s failed: op=%0d a=%08x b=%08x expected=%08x result=%08x",
          test_name,
          test_op,
          test_a,
          test_b,
          expected,
          result
        );
      end

      checks++;
    end
  endtask

  initial begin
    op     = ALU_NONE;
    a      = 32'b0;
    b      = 32'b0;
    checks = 0;

    check(ALU_NONE, 32'hdead_beef, 32'h1234_5678, 32'h0000_0000, "none");

    check(ALU_ADD, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, "add zero");
    check(ALU_ADD, 32'h1234_5678, 32'h1111_1111, 32'h2345_6789, "add normal");
    check(ALU_ADD, 32'hffff_ffff, 32'h0000_0001, 32'h0000_0000, "add wrap");
    check(ALU_ADD, 32'h7fff_ffff, 32'h0000_0001, 32'h8000_0000, "add sign boundary");

    check(ALU_SUB, 32'h1234_5678, 32'h1111_1111, 32'h0123_4567, "sub normal");
    check(ALU_SUB, 32'h0000_0000, 32'h0000_0001, 32'hffff_ffff, "sub wrap");
    check(ALU_SUB, 32'h8000_0000, 32'h0000_0001, 32'h7fff_ffff, "sub sign boundary");

    check(ALU_SLL, 32'h8000_0001, 32'd0,  32'h8000_0001, "sll zero");
    check(ALU_SLL, 32'h0000_0001, 32'd1,  32'h0000_0002, "sll one");
    check(ALU_SLL, 32'h0000_0001, 32'd31, 32'h8000_0000, "sll thirty-one");
    check(ALU_SLL, 32'h89ab_cdef, 32'd32, 32'h89ab_cdef, "sll masks shamt");

    check(ALU_SRL, 32'h8000_0001, 32'd0,  32'h8000_0001, "srl zero");
    check(ALU_SRL, 32'h8000_0001, 32'd1,  32'h4000_0000, "srl one");
    check(ALU_SRL, 32'h8000_0000, 32'd31, 32'h0000_0001, "srl thirty-one");
    check(ALU_SRL, 32'h8000_0000, 32'd63, 32'h0000_0001, "srl masks shamt");

    check(ALU_SRA, 32'h8000_0001, 32'd0,  32'h8000_0001, "sra zero");
    check(ALU_SRA, 32'h8000_0001, 32'd1,  32'hc000_0000, "sra negative");
    check(ALU_SRA, 32'h8000_0000, 32'd31, 32'hffff_ffff, "sra negative thirty-one");
    check(ALU_SRA, 32'h7fff_ffff, 32'd31, 32'h0000_0000, "sra positive thirty-one");

    check(ALU_SLT, 32'hffff_ffff, 32'h0000_0000, 32'h0000_0001, "slt negative");
    check(ALU_SLT, 32'h0000_0000, 32'hffff_ffff, 32'h0000_0000, "slt positive");
    check(ALU_SLT, 32'h8000_0000, 32'h7fff_ffff, 32'h0000_0001, "slt sign boundary");
    check(ALU_SLT, 32'h1234_5678, 32'h1234_5678, 32'h0000_0000, "slt equal");

    check(ALU_SLTU, 32'h0000_0000, 32'hffff_ffff, 32'h0000_0001, "sltu low");
    check(ALU_SLTU, 32'hffff_ffff, 32'h0000_0000, 32'h0000_0000, "sltu high");
    check(ALU_SLTU, 32'h8000_0000, 32'h7fff_ffff, 32'h0000_0000, "sltu boundary");
    check(ALU_SLTU, 32'h1234_5678, 32'h1234_5678, 32'h0000_0000, "sltu equal");

    check(ALU_XOR, 32'ha5a5_5a5a, 32'hffff_0000, 32'h5a5a_5a5a, "xor");
    check(ALU_OR,  32'ha5a5_0000, 32'h0000_5a5a, 32'ha5a5_5a5a, "or");
    check(ALU_AND, 32'ha5a5_5a5a, 32'hffff_0000, 32'ha5a5_0000, "and");
    check(ALU_AND, 32'hffff_ffff, 32'h0000_0000, 32'h0000_0000, "and zero");

    $display("PASS: %0d ALU checks", checks);
    $finish;
  end

endmodule
