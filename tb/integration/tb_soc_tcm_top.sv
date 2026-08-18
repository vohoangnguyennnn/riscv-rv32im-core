module tb_soc_tcm_top;

  timeunit 1ns;
  timeprecision 1ps;

  import rv32_pkg::*;

  localparam int unsigned TCM_BYTES = 512;
  localparam logic [31:0] STATUS_ADDR = TCM_BYTES - 4;
  localparam int unsigned MAX_CYCLES = 500;

  logic clk;
  logic rst;

  logic        test_done;
  logic        test_pass;
  logic        test_fail;
  logic [31:0] test_status;
  logic        trace_valid;
  logic [31:0] trace_pc;
  logic [31:0] trace_insn;
  logic        trace_rd_we;
  logic [4:0]  trace_rd_addr;
  logic [31:0] trace_rd_data;
  logic [31:0] trace_mem_addr;
  logic [3:0]  trace_mem_wstrb;
  logic [31:0] trace_mem_wdata;
  logic        trace_trap;
  logic [4:0]  trace_cause;
  logic        trace_control;
  logic        trace_taken;
  logic [31:0] trace_target;

  int unsigned checks;
  int unsigned phase;
  int unsigned completion_stores;
  logic saw_expected_trap;

  soc_tcm_top #(
    .RESET_VECTOR     (32'h0000_0000),
    .TRAP_VECTOR      (32'h0000_0100),
    .TCM_BYTES        (TCM_BYTES),
    .TCM_BASE_ADDR    (32'h0000_0000),
    .TCM_INIT_FILE    ("tb/data/soc_tcm_init.mem"),
    .TEST_STATUS_ADDR (STATUS_ADDR),
    .TEST_PASS_VALUE  (32'h0000_0001)
  ) dut (
    .clk_i              (clk),
    .rst_i              (rst),
    .test_done_o        (test_done),
    .test_pass_o        (test_pass),
    .test_fail_o        (test_fail),
    .test_status_o      (test_status),
    .trace_valid_o      (trace_valid),
    .trace_pc_o         (trace_pc),
    .trace_insn_o       (trace_insn),
    .trace_rd_we_o      (trace_rd_we),
    .trace_rd_addr_o    (trace_rd_addr),
    .trace_rd_data_o    (trace_rd_data),
    .trace_mem_addr_o   (trace_mem_addr),
    .trace_mem_wstrb_o  (trace_mem_wstrb),
    .trace_mem_wdata_o  (trace_mem_wdata),
    .trace_trap_o       (trace_trap),
    .trace_cause_o      (trace_cause),
    .trace_control_o    (trace_control),
    .trace_taken_o      (trace_taken),
    .trace_target_o     (trace_target)
  );

  always #5 clk = ~clk;

  function automatic logic [31:0] encode_i(
    input logic [11:0] imm,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3,
    input logic [4:0]  rd,
    input logic [6:0]  opcode
  );
    encode_i = {imm, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] encode_s(
    input logic [11:0] imm,
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3
  );
    encode_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], OPCODE_STORE};
  endfunction

  task automatic check_bit(
    input logic actual,
    input logic expected,
    input string test_name
  );
    begin
      if (actual !== expected) begin
        $fatal(1, "%s mismatch: expected=%0b result=%0b", test_name, expected, actual);
      end
      checks++;
    end
  endtask

  task automatic check_word(
    input logic [31:0] actual,
    input logic [31:0] expected,
    input string test_name
  );
    begin
      if (actual !== expected) begin
        $fatal(1, "%s mismatch: expected=%08x result=%08x", test_name, expected, actual);
      end
      checks++;
    end
  endtask

  task automatic clear_tcm;
    begin
      for (int unsigned word_index = 0; word_index < TCM_BYTES / 4; word_index++) begin
        dut.u_tcm.mem[word_index] = 32'b0;
      end
    end
  endtask

  task automatic apply_reset;
    begin
      rst = 1'b1;
      repeat (4) @(posedge clk);
      #1ps;
      check_bit(test_done, 1'b0, "reset clears completion");
      check_bit(test_pass, 1'b0, "reset clears pass");
      check_bit(test_fail, 1'b0, "reset clears fail");
      check_word(test_status, 32'b0, "reset clears status");
      @(negedge clk);
      rst = 1'b0;
    end
  endtask

  task automatic wait_for_completion(input string test_name);
    bit completed;
    begin
      completed = 1'b0;
      for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
        @(posedge clk);
        #1ps;
        if (test_done) begin
          completed = 1'b1;
          break;
        end
      end
      if (!completed) begin
        $fatal(1, "%s timed out waiting for test_done", test_name);
      end
    end
  endtask

  always @(posedge clk) begin
    #1ps;
    if (!rst && trace_valid) begin
      // Prove the top trace is the same architectural observation point used
      // by the completion monitor, not a speculative memory transaction.
      if ((trace_mem_wstrb == 4'b1111) && (trace_mem_addr == STATUS_ADDR)) begin
        completion_stores++;
        if (phase == 1) begin
          check_word(trace_mem_wdata, 32'h0000_0001, "pass completion trace data");
        end else if (phase == 2) begin
          check_word(trace_mem_wdata, 32'h0000_0007, "fail completion trace data");
        end else begin
          $fatal(1, "unexpected completion store in phase %0d", phase);
        end
      end

      if (trace_trap) begin
        if (phase != 3) begin
          $fatal(1, "unexpected trap in phase %0d", phase);
        end
      end
    end
  end

  initial begin
    clk               = 1'b0;
    rst               = 1'b1;
    checks            = 0;
    phase             = 0;
    completion_stores = 0;
    saw_expected_trap = 1'b0;

    // Check the optional BRAM initialization path before the directed phases
    // overwrite memory through the testbench hierarchy.
    #1ps;
    check_word(dut.u_tcm.mem[0], 32'h0000_0013, "TCM init-file first word");

    // Phase 1: full-SoC program with an ALU dependency, a store/load round
    // trip, and a pass mailbox write.
    clear_tcm();
    dut.u_tcm.mem[0] = encode_i(12'd41, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);
    dut.u_tcm.mem[1] = encode_i(12'd1,  5'd1, 3'b000, 5'd1, OPCODE_OP_IMM);
    dut.u_tcm.mem[2] = encode_s(12'd128, 5'd1, 5'd0, 3'b010);
    dut.u_tcm.mem[3] = encode_i(12'd128, 5'd0, 3'b010, 5'd2, OPCODE_LOAD);
    dut.u_tcm.mem[4] = encode_i(12'hfd7, 5'd2, 3'b000, 5'd3, OPCODE_OP_IMM);
    dut.u_tcm.mem[5] = encode_s(STATUS_ADDR[11:0], 5'd3, 5'd0, 3'b010);
    dut.u_tcm.mem[6] = 32'h0000_006f;
    phase = 1;
    apply_reset();
    wait_for_completion("pass program");
    check_bit(test_pass, 1'b1, "pass program pass output");
    check_bit(test_fail, 1'b0, "pass program fail output");
    check_word(test_status, 32'h0000_0001, "pass program status");
    check_word(dut.u_tcm.mem[32], 32'd42, "unified TCM data result");

    // Completion and its first value remain sticky until reset.
    repeat (4) @(posedge clk);
    #1ps;
    check_bit(test_done, 1'b1, "pass completion remains sticky");
    check_word(test_status, 32'h0000_0001, "pass status remains sticky");

    // Phase 2: reset and prove a non-pass status is classified as failure.
    clear_tcm();
    dut.u_tcm.mem[0] = encode_i(12'd7, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM);
    dut.u_tcm.mem[1] = encode_s(STATUS_ADDR[11:0], 5'd1, 5'd0, 3'b010);
    dut.u_tcm.mem[2] = 32'h0000_006f;
    phase = 2;
    apply_reset();
    wait_for_completion("failure program");
    check_bit(test_pass, 1'b0, "failure program pass output");
    check_bit(test_fail, 1'b1, "failure program fail output");
    check_word(test_status, 32'h0000_0007, "failure program status");

    // Phase 3: an illegal instruction must reach the top trace but must not be
    // mistaken for a completion event.
    clear_tcm();
    dut.u_tcm.mem[0]  = 32'hffff_ffff;
    dut.u_tcm.mem[64] = 32'h0000_006f;
    phase = 3;
    apply_reset();
    for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
      @(posedge clk);
      #1ps;
      if (trace_valid && trace_trap) begin
        check_word(trace_pc, 32'h0000_0000, "illegal trap PC");
        check_word(trace_insn, 32'hffff_ffff, "illegal trap instruction");
        check_word({27'b0, trace_cause}, {27'b0, EXC_ILLEGAL_INSN}, "illegal trap cause");
        saw_expected_trap = 1'b1;
        break;
      end
    end
    check_bit(saw_expected_trap, 1'b1, "top-level illegal trap observed");
    check_bit(test_done, 1'b0, "trap does not complete test");
    check_bit(test_pass, 1'b0, "trap does not assert pass");
    check_bit(test_fail, 1'b0, "trap does not assert fail");
    check_word(completion_stores, 32'd2, "one completion store per software phase");

    $display("tb_soc_tcm_top: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
