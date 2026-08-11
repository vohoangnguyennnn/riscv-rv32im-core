// SPDX-License-Identifier: MIT

module tb_imm_gen;

  import rv32_pkg::*;

  logic [31:0] insn;
  imm_sel_e   sel;
  logic [31:0] imm;
  int          checks;

  imm_gen dut (
    .insn_i (insn),
    .sel_i  (sel),
    .imm_o  (imm)
  );

  function automatic logic [31:0] encode_i(input logic [31:0] value);
    logic [31:0] encoded;
    begin
      encoded        = 32'b0;
      encoded[31:20] = value[11:0];
      encode_i       = encoded;
    end
  endfunction

  function automatic logic [31:0] encode_s(input logic [31:0] value);
    logic [31:0] encoded;
    begin
      encoded        = 32'b0;
      encoded[31:25] = value[11:5];
      encoded[11:7]  = value[4:0];
      encode_s       = encoded;
    end
  endfunction

  function automatic logic [31:0] encode_b(input logic [31:0] value);
    logic [31:0] encoded;
    begin
      encoded        = 32'b0;
      encoded[31]    = value[12];
      encoded[7]     = value[11];
      encoded[30:25] = value[10:5];
      encoded[11:8]  = value[4:1];
      encode_b       = encoded;
    end
  endfunction

  function automatic logic [31:0] encode_u(input logic [31:0] value);
    logic [31:0] encoded;
    begin
      encoded        = 32'b0;
      encoded[31:12] = value[31:12];
      encode_u       = encoded;
    end
  endfunction

  function automatic logic [31:0] encode_j(input logic [31:0] value);
    logic [31:0] encoded;
    begin
      encoded        = 32'b0;
      encoded[31]    = value[20];
      encoded[19:12] = value[19:12];
      encoded[20]    = value[11];
      encoded[30:21] = value[10:1];
      encode_j       = encoded;
    end
  endfunction

  task automatic check(
    input imm_sel_e    test_sel,
    input logic [31:0] test_insn,
    input logic [31:0] expected,
    input string       test_name
  );
    begin
      sel  = test_sel;
      insn = test_insn;
      #1;

      if (imm !== expected) begin
        $fatal(
          1,
          "%s failed: sel=%0d insn=%08x expected=%08x result=%08x",
          test_name,
          test_sel,
          test_insn,
          expected,
          imm
        );
      end

      checks++;
    end
  endtask

  initial begin
    insn   = 32'b0;
    sel    = IMM_NONE;
    checks = 0;

    check(IMM_NONE, 32'hffff_ffff, 32'h0000_0000, "none");

    check(IMM_I, encode_i(32'h0000_0000), 32'h0000_0000, "I zero");
    check(IMM_I, encode_i(32'h0000_07ff), 32'h0000_07ff, "I max positive");
    check(IMM_I, encode_i(32'hffff_f800), 32'hffff_f800, "I min negative");
    check(IMM_I, encode_i(32'hffff_ffff), 32'hffff_ffff, "I negative one");

    check(IMM_S, encode_s(32'h0000_0000), 32'h0000_0000, "S zero");
    check(IMM_S, encode_s(32'h0000_07ff), 32'h0000_07ff, "S max positive");
    check(IMM_S, encode_s(32'hffff_f800), 32'hffff_f800, "S min negative");
    check(IMM_S, encode_s(32'hffff_ffff), 32'hffff_ffff, "S negative one");

    check(IMM_B, encode_b(32'h0000_0002), 32'h0000_0002, "B smallest positive");
    check(IMM_B, encode_b(32'h0000_0ffe), 32'h0000_0ffe, "B max positive");
    check(IMM_B, encode_b(32'hffff_f000), 32'hffff_f000, "B min negative");
    check(IMM_B, encode_b(32'hffff_fffe), 32'hffff_fffe, "B negative two");

    check(IMM_U, encode_u(32'h0000_0000), 32'h0000_0000, "U zero");
    check(IMM_U, encode_u(32'h1234_5000), 32'h1234_5000, "U normal");
    check(IMM_U, encode_u(32'h8000_0000), 32'h8000_0000, "U sign bit");
    check(IMM_U, encode_u(32'hffff_f000), 32'hffff_f000, "U all upper bits");

    check(IMM_J, encode_j(32'h0000_0002), 32'h0000_0002, "J smallest positive");
    check(IMM_J, encode_j(32'h000f_fffe), 32'h000f_fffe, "J max positive");
    check(IMM_J, encode_j(32'hfff0_0000), 32'hfff0_0000, "J min negative");
    check(IMM_J, encode_j(32'hffff_fffe), 32'hffff_fffe, "J negative two");

    $display("PASS: %0d immediate-generator checks", checks);
    $finish;
  end

endmodule
