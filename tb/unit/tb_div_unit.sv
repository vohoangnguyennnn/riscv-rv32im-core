// SPDX-License-Identifier: MIT

module tb_div_unit;

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

  div_unit dut (
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

  function automatic logic [31:0] divide_reference(
    input mdu_op_e     test_op,
    input logic [31:0] test_lhs,
    input logic [31:0] test_rhs
  );
    logic signed [31:0] signed_lhs;
    logic signed [31:0] signed_rhs;
    begin
      signed_lhs = $signed(test_lhs);
      signed_rhs = $signed(test_rhs);

      unique case (test_op)
        MDU_DIV: begin
          if (test_rhs == 32'b0) begin
            divide_reference = 32'hffff_ffff;
          end else if ((test_lhs == 32'h8000_0000) && (test_rhs == 32'hffff_ffff)) begin
            divide_reference = 32'h8000_0000;
          end else begin
            divide_reference = signed_lhs / signed_rhs;
          end
        end

        MDU_DIVU: begin
          if (test_rhs == 32'b0) begin
            divide_reference = 32'hffff_ffff;
          end else begin
            divide_reference = test_lhs / test_rhs;
          end
        end

        MDU_REM: begin
          if (test_rhs == 32'b0) begin
            divide_reference = test_lhs;
          end else if ((test_lhs == 32'h8000_0000) && (test_rhs == 32'hffff_ffff)) begin
            divide_reference = 32'b0;
          end else begin
            divide_reference = signed_lhs % signed_rhs;
          end
        end

        default: begin // MDU_REMU
          if (test_rhs == 32'b0) begin
            divide_reference = test_lhs;
          end else begin
            divide_reference = test_lhs % test_rhs;
          end
        end
      endcase
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

  function automatic logic is_special_case(
    input mdu_op_e     test_op,
    input logic [31:0] test_lhs,
    input logic [31:0] test_rhs
  );
    logic signed_op;
    begin
      signed_op = (test_op == MDU_DIV) || (test_op == MDU_REM);
      return (test_rhs == 32'b0)
          || (signed_op && (test_lhs == 32'h8000_0000) && (test_rhs == 32'hffff_ffff));
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
    input  mdu_op_e     test_op,
    input  logic [31:0] test_lhs,
    input  logic [31:0] test_rhs,
    input  int unsigned backpressure_cycles,
    input  string       test_name,
    output logic [31:0] actual_result
  );
    logic [31:0] expected;
    logic [31:0] held_result;
    logic        special_case;
    begin
      expected     = divide_reference(test_op, test_lhs, test_rhs);
      special_case = is_special_case(test_op, test_lhs, test_rhs);

      @(negedge clk);
      check_bit(req_ready, 1'b1, {test_name, " request ready"});
      req_valid = 1'b1;
      op        = test_op;
      lhs       = test_lhs;
      rhs       = test_rhs;
      rsp_ready = 1'b0;

      @(posedge clk);
      #1ps;
      check_bit(rsp_valid, special_case, {test_name, " special-case latency"});
      check_bit(req_ready, 1'b0, {test_name, " one outstanding operation"});

      // Mutating the request signals verifies launch-edge operand capture.
      @(negedge clk);
      req_valid = 1'b0;
      op        = MDU_NONE;
      lhs       = ~test_lhs;
      rhs       = ~test_rhs;

      if (!special_case) begin
        // Normal restoring division performs exactly 32 iterations after the
        // request acceptance edge. A response before iteration 32 is illegal.
        for (int unsigned iteration = 1; iteration < 32; iteration++) begin
          @(posedge clk);
          #1ps;
          check_bit(
            rsp_valid,
            1'b0,
            $sformatf("%s no early response at iteration %0d", test_name, iteration)
          );
          check_bit(req_ready, 1'b0, {test_name, " busy during iteration"});
        end

        @(posedge clk);
        #1ps;
        check_bit(rsp_valid, 1'b1, {test_name, " response after iteration 32"});
      end

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
      actual_result = result;
      held_result   = result;

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

  task automatic check_signed_identity(
    input logic [31:0] test_lhs,
    input logic [31:0] test_rhs,
    input string       test_name
  );
    logic [31:0] quotient;
    logic [31:0] remainder;
    logic signed [63:0] dividend_wide;
    logic signed [63:0] divisor_wide;
    logic signed [63:0] quotient_wide;
    logic signed [63:0] remainder_wide;
    begin
      run_case(MDU_DIV, test_lhs, test_rhs, 0, {test_name, " DIV"}, quotient);
      run_case(MDU_REM, test_lhs, test_rhs, 0, {test_name, " REM"}, remainder);

      dividend_wide  = $signed({{32{test_lhs[31]}}, test_lhs});
      divisor_wide   = $signed({{32{test_rhs[31]}}, test_rhs});
      quotient_wide  = $signed({{32{quotient[31]}}, quotient});
      remainder_wide = $signed({{32{remainder[31]}}, remainder});

      if (dividend_wide != (divisor_wide * quotient_wide) + remainder_wide) begin
        $fatal(1, "%s: signed dividend != divisor * quotient + remainder", test_name);
      end
      if ((remainder != 32'b0) && (remainder[31] != test_lhs[31])) begin
        $fatal(1, "%s: REM sign differs from dividend sign", test_name);
      end
      checks += 2;
    end
  endtask

  task automatic check_unsigned_identity(
    input logic [31:0] test_lhs,
    input logic [31:0] test_rhs,
    input string       test_name
  );
    logic [31:0] quotient;
    logic [31:0] remainder;
    logic [63:0] dividend_wide;
    logic [63:0] divisor_wide;
    logic [63:0] quotient_wide;
    logic [63:0] remainder_wide;
    begin
      run_case(MDU_DIVU, test_lhs, test_rhs, 0, {test_name, " DIVU"}, quotient);
      run_case(MDU_REMU, test_lhs, test_rhs, 0, {test_name, " REMU"}, remainder);

      dividend_wide  = {32'b0, test_lhs};
      divisor_wide   = {32'b0, test_rhs};
      quotient_wide  = {32'b0, quotient};
      remainder_wide = {32'b0, remainder};

      if (dividend_wide != (divisor_wide * quotient_wide) + remainder_wide) begin
        $fatal(1, "%s: unsigned dividend != divisor * quotient + remainder", test_name);
      end
      if (remainder_wide >= divisor_wide) begin
        $fatal(1, "%s: unsigned remainder is not smaller than divisor", test_name);
      end
      checks += 2;
    end
  endtask

  task automatic check_kill_and_reset;
    begin
      // Kill a normal operation after several restoring iterations.
      @(negedge clk);
      req_valid = 1'b1;
      op        = MDU_DIVU;
      lhs       = 32'hffff_ffff;
      rhs       = 32'd7;
      @(posedge clk);
      #1ps;
      @(negedge clk);
      req_valid = 1'b0;

      repeat (7) @(posedge clk);
      @(negedge clk);
      kill = 1'b1;
      @(posedge clk);
      #1ps;
      check_bit(rsp_valid, 1'b0, "kill suppresses divider response");
      check_bit(req_ready, 1'b0, "request blocked while kill asserted");
      @(negedge clk);
      kill = 1'b0;
      #1ps;
      check_bit(req_ready, 1'b1, "ready after divider kill release");

      // Reset must also discard all partial quotient/remainder state.
      @(negedge clk);
      req_valid = 1'b1;
      op        = MDU_REM;
      lhs       = 32'h8000_0001;
      rhs       = 32'd13;
      @(posedge clk);
      #1ps;
      @(negedge clk);
      req_valid = 1'b0;
      repeat (5) @(posedge clk);
      @(negedge clk);
      rst = 1'b1;
      @(posedge clk);
      #1ps;
      check_bit(rsp_valid, 1'b0, "reset suppresses divider response");
      @(negedge clk);
      rst = 1'b0;
      #1ps;
      check_bit(req_ready, 1'b1, "ready after divider reset release");
    end
  endtask

  initial begin
    logic [31:0] unused_result;
    logic [31:0] random_state;
    logic [31:0] random_lhs;
    logic [31:0] random_rhs;

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

    // Complete RISC-V divide-by-zero and signed-overflow table.
    run_case(MDU_DIV,  32'h1234_5678, 32'b0,          3, "DIV by zero", unused_result);
    run_case(MDU_DIVU, 32'h89ab_cdef, 32'b0,          0, "DIVU by zero", unused_result);
    run_case(MDU_REM,  32'h8000_0001, 32'b0,          0, "REM by zero", unused_result);
    run_case(MDU_REMU, 32'hffff_ffff, 32'b0,          0, "REMU by zero", unused_result);
    run_case(MDU_DIV,  32'h8000_0000, 32'hffff_ffff, 0, "DIV signed overflow", unused_result);
    run_case(MDU_REM,  32'h8000_0000, 32'hffff_ffff, 0, "REM signed overflow", unused_result);
    run_case(MDU_DIVU, 32'd100,       32'd7,         4, "normal DIVU backpressure", unused_result);

    // Directed sign and rounding-toward-zero vectors.
    check_signed_identity(32'd7,         32'd3,         "positive by positive");
    check_signed_identity(32'hffff_fff9, 32'd3,         "negative by positive");
    check_signed_identity(32'd7,         32'hffff_fffd, "positive by negative");
    check_signed_identity(32'hffff_fff9, 32'hffff_fffd, "negative by negative");
    check_signed_identity(32'h8000_0000, 32'd1,         "INT_MIN by one");
    check_signed_identity(32'h7fff_ffff, 32'h8000_0000, "INT_MAX by INT_MIN");
    check_unsigned_identity(32'hffff_ffff, 32'd1,        "UINT_MAX by one");
    check_unsigned_identity(32'hffff_ffff, 32'h8000_0000,"UINT_MAX by high divisor");

    // Deterministic randomized identity checks. Divisors are forced nonzero;
    // the one signed-overflow pair is already covered explicitly above.
    random_state = 32'h9e37_79b9;
    for (int unsigned i = 0; i < 24; i++) begin
      random_state = xorshift32(random_state);
      random_lhs   = random_state;
      random_state = xorshift32(random_state);
      random_rhs   = (random_state == 32'b0) ? 32'd1 : random_state;
      if ((random_lhs == 32'h8000_0000) && (random_rhs == 32'hffff_ffff)) begin
        random_rhs = 32'd1;
      end

      check_signed_identity(
        random_lhs,
        random_rhs,
        $sformatf("random signed identity %0d", i)
      );
      check_unsigned_identity(
        random_lhs,
        random_rhs,
        $sformatf("random unsigned identity %0d", i)
      );
    end

    check_kill_and_reset();
    run_case(MDU_DIVU, 32'hdead_beef, 32'd17, 0, "post-abort recovery", unused_result);

    $display("tb_div_unit: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
