// SPDX-License-Identifier: MIT

module tb_mul_unit;

  timeunit 1ns;
  timeprecision 1ps;

  import rv32_pkg::*;

  logic        clk;
  logic        rst;
  logic        kill;
  logic        req_valid;
  logic        req_ready;
  mdu_op_e     op;
  logic [31:0] lhs;
  logic [31:0] rhs;
  logic        rsp_valid;
  logic        rsp_ready;
  logic [31:0] result;
  int          checks;

  mul_unit dut (
    .clk_i       (clk),
    .rst_i       (rst),
    .kill_i      (kill),
    .req_valid_i (req_valid),
    .req_ready_o (req_ready),
    .op_i        (op),
    .lhs_i       (lhs),
    .rhs_i       (rhs),
    .rsp_valid_o (rsp_valid),
    .rsp_ready_i (rsp_ready),
    .result_o    (result)
  );

  always #5 clk = ~clk;

  function automatic logic [31:0] multiply_reference(
    input mdu_op_e     test_op,
    input logic [31:0] test_lhs,
    input logic [31:0] test_rhs
  );
    logic signed [63:0] lhs_ext;
    logic signed [63:0] rhs_ext;
    logic signed [63:0] full_product;
    begin
      lhs_ext = $signed({32'b0, test_lhs});
      rhs_ext = $signed({32'b0, test_rhs});

      unique case (test_op)
        MDU_MULH: begin
          lhs_ext = $signed({{32{test_lhs[31]}}, test_lhs});
          rhs_ext = $signed({{32{test_rhs[31]}}, test_rhs});
        end

        MDU_MULHSU: begin
          lhs_ext = $signed({{32{test_lhs[31]}}, test_lhs});
          rhs_ext = $signed({32'b0, test_rhs});
        end

        default: begin
          lhs_ext = $signed({32'b0, test_lhs});
          rhs_ext = $signed({32'b0, test_rhs});
        end
      endcase

      full_product = lhs_ext * rhs_ext;
      multiply_reference = (test_op == MDU_MUL)
                         ? full_product[31:0]
                         : full_product[63:32];
    end
  endfunction

  function automatic logic [31:0] xorshift32(input logic [31:0] value);
    logic [31:0] next_value;
    begin
      next_value = value;
      next_value ^= next_value << 13;
      next_value ^= next_value >> 17;
      next_value ^= next_value << 5;
      return next_value;
    end
  endfunction

  task automatic check_bit(
    input logic  actual,
    input logic  expected,
    input string test_name
  );
    begin
      if (actual !== expected) begin
        $fatal(1, "%s: expected=%0b actual=%0b", test_name, expected, actual);
      end
      checks++;
    end
  endtask

  task automatic run_case(
    input mdu_op_e     test_op,
    input logic [31:0] test_lhs,
    input logic [31:0] test_rhs,
    input int unsigned backpressure_cycles,
    input string       test_name
  );
    logic [31:0] expected;
    logic [31:0] held_result;
    begin
      expected = multiply_reference(test_op, test_lhs, test_rhs);

      @(negedge clk);
      check_bit(req_ready, 1'b1, {test_name, " request ready"});
      req_valid = 1'b1;
      op        = test_op;
      lhs       = test_lhs;
      rhs       = test_rhs;
      rsp_ready = 1'b0;

      @(posedge clk);
      #1ps;
      check_bit(rsp_valid, 1'b0, {test_name, " no same-edge response"});
      check_bit(req_ready, 1'b0, {test_name, " one outstanding operation"});

      // Change the request bus immediately after acceptance. The result must
      // still use the operands and operation captured at the launch edge.
      @(negedge clk);
      req_valid = 1'b0;
      op        = MDU_NONE;
      lhs       = ~test_lhs;
      rhs       = ~test_rhs;

      @(posedge clk);
      #1ps;
      check_bit(rsp_valid, 1'b1, {test_name, " two-stage response valid"});
      if (result !== expected) begin
        $fatal(
          1,
          "%s: op=%0d lhs=%08x rhs=%08x expected=%08x actual=%08x",
          test_name,
          test_op,
          test_lhs,
          test_rhs,
          expected,
          result
        );
      end
      checks++;
      held_result = result;

      repeat (backpressure_cycles) begin
        @(posedge clk);
        #1ps;
        check_bit(rsp_valid, 1'b1, {test_name, " sticky response valid"});
        check_bit(req_ready, 1'b0, {test_name, " blocked request while response pending"});
        if (result !== held_result) begin
          $fatal(1, "%s: result changed under response backpressure", test_name);
        end
        checks++;
      end

      @(negedge clk);
      rsp_ready = 1'b1;
      @(posedge clk);
      #1ps;
      check_bit(rsp_valid, 1'b0, {test_name, " response consumed"});
      check_bit(req_ready, 1'b1, {test_name, " ready after response"});
      @(negedge clk);
      rsp_ready = 1'b0;
    end
  endtask

  task automatic check_kill;
    begin
      @(negedge clk);
      req_valid = 1'b1;
      op        = MDU_MULHU;
      lhs       = 32'hffff_ffff;
      rhs       = 32'hffff_ffff;

      @(posedge clk);
      #1ps;
      @(negedge clk);
      req_valid = 1'b0;
      kill      = 1'b1;

      @(posedge clk);
      #1ps;
      check_bit(rsp_valid, 1'b0, "kill suppresses in-flight response");
      check_bit(req_ready, 1'b0, "request blocked while kill asserted");

      @(negedge clk);
      kill = 1'b0;
      #1ps;
      check_bit(req_ready, 1'b1, "ready after kill release");
    end
  endtask

  initial begin
    logic [31:0] random_state;
    logic [31:0] random_lhs;
    logic [31:0] random_rhs;
    mdu_op_e     random_op;

    clk       = 1'b0;
    rst       = 1'b1;
    kill      = 1'b0;
    req_valid = 1'b0;
    op        = MDU_NONE;
    lhs       = 32'b0;
    rhs       = 32'b0;
    rsp_ready = 1'b0;
    checks    = 0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    #1ps;
    check_bit(req_ready, 1'b1, "ready after reset");

    // Architectural boundaries required by Gate 2 of the design plan.
    run_case(MDU_MUL,    32'b0,          32'hffff_ffff, 0, "MUL zero");
    run_case(MDU_MUL,    32'b1,          32'h8000_0000, 0, "MUL one");
    run_case(MDU_MUL,    32'hffff_ffff,  32'h8000_0000, 0, "MUL minus one");
    run_case(MDU_MUL,    32'h7fff_ffff,  32'h7fff_ffff, 0, "MUL INT_MAX square");
    run_case(MDU_MULH,   32'h8000_0000,  32'hffff_ffff, 3, "MULH signed boundary/backpressure");
    run_case(MDU_MULH,   32'h8000_0000,  32'h8000_0000, 0, "MULH INT_MIN square");
    run_case(MDU_MULHSU, 32'hffff_ffff,  32'hffff_ffff, 0, "MULHSU negative by unsigned max");
    run_case(MDU_MULHSU, 32'h8000_0000,  32'hffff_ffff, 0, "MULHSU INT_MIN by unsigned max");
    run_case(MDU_MULHU,  32'hffff_ffff,  32'hffff_ffff, 0, "MULHU unsigned max square");

    // Reproducible pseudo-random vectors cover all four signedness modes.
    random_state = 32'h6d2b_79f5;
    for (int unsigned i = 0; i < 96; i++) begin
      random_state = xorshift32(random_state);
      random_lhs   = random_state;
      random_state = xorshift32(random_state);
      random_rhs   = random_state;
      unique case (i % 4)
        0: random_op = MDU_MUL;
        1: random_op = MDU_MULH;
        2: random_op = MDU_MULHSU;
        default: random_op = MDU_MULHU;
      endcase
      run_case(
        random_op,
        random_lhs,
        random_rhs,
        0,
        $sformatf("random multiply vector %0d", i)
      );
    end

    check_kill();

    // Prove that an aborted request cannot corrupt the following operation.
    run_case(MDU_MULHU, 32'h1234_5678, 32'h89ab_cdef, 0, "post-kill recovery");

    $display("tb_mul_unit: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
