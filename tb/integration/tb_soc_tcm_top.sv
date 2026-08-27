module tb_soc_tcm_top;

  timeunit 1ns;
  timeprecision 1ps;

  import rv32_pkg::*;

  localparam int unsigned TCM_BYTES = 512;
  localparam logic [31:0] STATUS_ADDR = TCM_BYTES - 4;
  localparam int unsigned MAX_CYCLES = 500;
  localparam int unsigned UART_CLK_FREQ_HZ = 1_000_000;
  localparam int unsigned UART_BAUD_RATE = 100_000;
  localparam int unsigned UART_CLKS_PER_BIT = UART_CLK_FREQ_HZ / UART_BAUD_RATE;
  localparam int unsigned GPIO_WIDTH = 16;

  logic clk;
  logic rst;
  logic uart_rx;
  logic uart_tx;
  logic [GPIO_WIDTH-1:0] gpio_in;
  logic [GPIO_WIDTH-1:0] gpio_out;
  logic [GPIO_WIDTH-1:0] gpio_oe;

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
  logic        trace_is_interrupt;
  logic        trace_control;
  logic        trace_taken;
  logic [31:0] trace_target;

  int unsigned checks;
  int unsigned phase;
  int unsigned completion_stores;
  logic saw_expected_trap;
  logic saw_timer_trap;
  logic saw_timer_mret;

  soc_tcm_top #(
    .RESET_VECTOR     (32'h0000_0000),
    .TRAP_VECTOR      (32'h0000_0100),
    .TCM_BYTES        (TCM_BYTES),
    .TCM_BASE_ADDR    (32'h0000_0000),
    .TCM_INIT_FILE    ("tb/data/soc_tcm_init.mem"),
    .UART_CLK_FREQ_HZ (UART_CLK_FREQ_HZ),
    .UART_BAUD_RATE   (UART_BAUD_RATE),
    .GPIO_WIDTH       (GPIO_WIDTH),
    .TEST_STATUS_ADDR (STATUS_ADDR),
    .TEST_PASS_VALUE  (32'h0000_0001)
  ) dut (
    .clk_i              (clk),
    .rst_i              (rst),
    .uart_rx_i          (uart_rx),
    .uart_tx_o          (uart_tx),
    .gpio_in_i          (gpio_in),
    .gpio_out_o         (gpio_out),
    .gpio_oe_o          (gpio_oe),
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
    .trace_is_interrupt_o (trace_is_interrupt),
    .trace_control_o    (trace_control),
    .trace_taken_o      (trace_taken),
    .trace_target_o     (trace_target),
    .perf_cycle_o          (),
    .perf_instret_o        (),
    .perf_load_use_stall_o (),
    .perf_csr_stall_o      (),
    .perf_mdu_stall_o      (),
    .perf_mem_stall_o      (),
    .perf_redirect_o       (),
    .perf_squash_o         ()
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

  function automatic logic [31:0] encode_b(
    input logic [12:0] imm,
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3
  );
    encode_b = {
      imm[12],
      imm[10:5],
      rs2,
      rs1,
      funct3,
      imm[4:1],
      imm[11],
      OPCODE_BRANCH
    };
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

  task automatic drive_uart_rx_frame(input logic [7:0] data);
    begin
      // Let software enter its STATUS polling loop before presenting a frame.
      repeat (4) @(negedge clk);
      uart_rx = 1'b0;
      repeat (UART_CLKS_PER_BIT) @(negedge clk);

      for (int unsigned bit_index = 0; bit_index < 8; bit_index++) begin
        uart_rx = data[bit_index];
        repeat (UART_CLKS_PER_BIT) @(negedge clk);
      end

      uart_rx = 1'b1;
      repeat (UART_CLKS_PER_BIT) @(negedge clk);
    end
  endtask

  task automatic capture_uart_tx_frame(
    input logic [7:0] expected_data,
    input string      test_name
  );
    begin
      @(negedge uart_tx);
      #1ps;
      check_bit(uart_tx, 1'b0, {test_name, " start edge"});
      repeat (UART_CLKS_PER_BIT / 2) @(posedge clk);
      #1ps;
      check_bit(uart_tx, 1'b0, {test_name, " start center"});

      for (int unsigned bit_index = 0; bit_index < 8; bit_index++) begin
        repeat (UART_CLKS_PER_BIT) @(posedge clk);
        #1ps;
        check_bit(
          uart_tx,
          expected_data[bit_index],
          $sformatf("%s data bit %0d", test_name, bit_index)
        );
      end

      repeat (UART_CLKS_PER_BIT) @(posedge clk);
      #1ps;
      check_bit(uart_tx, 1'b1, {test_name, " stop center"});
      repeat (UART_CLKS_PER_BIT / 2) @(posedge clk);
      #1ps;
      check_bit(uart_tx, 1'b1, {test_name, " idle"});
    end
  endtask

  task automatic exercise_uart_echo(input logic [7:0] expected_data);
    bit rx_drive_done;
    bit tx_capture_done;
    begin
      rx_drive_done   = 1'b0;
      tx_capture_done = 1'b0;

      fork
        begin
          drive_uart_rx_frame(expected_data);
          rx_drive_done = 1'b1;
        end
        begin
          capture_uart_tx_frame(expected_data, "CPU UART echo");
          tx_capture_done = 1'b1;
        end
        begin
          for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
            @(posedge clk);
            if (rx_drive_done && tx_capture_done) begin
              break;
            end
          end
          if (!rx_drive_done || !tx_capture_done) begin
            $fatal(1, "UART echo timed out");
          end
        end
      join
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
      check_bit(uart_tx, 1'b1, "reset keeps UART TX idle");
      check_word({16'b0, gpio_out}, 32'b0, "reset clears GPIO output");
      check_word({16'b0, gpio_oe}, 32'b0, "reset clears GPIO output-enable");
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
        end else if ((phase >= 4) && (phase <= 7)) begin
          check_word(trace_mem_wdata, 32'h0000_0001, "SoC peripheral completion trace data");
        end else begin
          $fatal(1, "unexpected completion store in phase %0d", phase);
        end
      end

      if (trace_trap) begin
        if (phase == 5) begin
          check_bit(trace_is_interrupt, 1'b1,
                    "timer trap interrupt qualifier");
          check_word({27'b0, trace_cause}, {27'b0, IRQ_M_TIMER_CAUSE},
                     "timer trap cause");
          saw_timer_trap = 1'b1;
        end else if (phase != 3) begin
          $fatal(1, "unexpected trap in phase %0d", phase);
        end
      end else if ((phase == 5) && (trace_insn == INSN_MRET)) begin
        check_bit(trace_control, 1'b1, "timer MRET control metadata");
        check_bit(trace_taken, 1'b1, "timer MRET taken metadata");
        saw_timer_mret = 1'b1;
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
    saw_timer_trap    = 1'b0;
    saw_timer_mret    = 1'b0;
    uart_rx           = 1'b1;
    gpio_in           = 16'ha55a;

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

    // Phase 4: exercise the complete CPU -> demux -> timer path. Software
    // programs mtimecmp through MMIO, reads it back, observes the resulting
    // live timer-pending level through mip.MTIP, and then returns to TCM for
    // result/mailbox stores. Global interrupt enable remains clear here so the
    // MMIO/readback behavior can be checked independently of trap delivery.
    clear_tcm();
    dut.u_tcm.mem[0]  = {20'h02004, 5'd1, OPCODE_LUI};
    dut.u_tcm.mem[1]  = encode_s(12'd4, 5'd0, 5'd1, FUNCT3_SW);
    dut.u_tcm.mem[2]  = encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd2, OPCODE_OP_IMM);
    dut.u_tcm.mem[3]  = encode_s(12'd0, 5'd2, 5'd1, FUNCT3_SW);
    dut.u_tcm.mem[4]  = encode_i(12'd0, 5'd1, FUNCT3_LW, 5'd3, OPCODE_LOAD);
    dut.u_tcm.mem[5]  = encode_i(CSR_MIP, 5'd0, FUNCT3_CSRRS, 5'd4, OPCODE_SYSTEM);
    dut.u_tcm.mem[6]  = encode_s(12'd128, 5'd3, 5'd0, FUNCT3_SW);
    dut.u_tcm.mem[7]  = encode_s(12'd132, 5'd4, 5'd0, FUNCT3_SW);
    dut.u_tcm.mem[8]  = encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd5, OPCODE_OP_IMM);
    dut.u_tcm.mem[9]  = encode_s(STATUS_ADDR[11:0], 5'd5, 5'd0, FUNCT3_SW);
    dut.u_tcm.mem[10] = 32'h0000_006f;
    phase = 4;
    apply_reset();
    wait_for_completion("timer MMIO program");
    check_bit(test_pass, 1'b1, "timer program pass output");
    check_bit(test_fail, 1'b0, "timer program fail output");
    check_word(test_status, 32'h0000_0001, "timer program status");
    check_word(dut.u_tcm.mem[32], 32'h0000_0001, "mtimecmp low MMIO readback");
    check_word(dut.u_tcm.mem[33], MIP_MTIP_MASK, "timer drives live mip.MTIP");
    check_word(completion_stores, 32'd3, "one completion store per completing phase");

    // Phase 5: end-to-end timer delivery. Software first creates a pending
    // compare level through the real demux/timer path, enables MTIE and MIE,
    // takes the interrupt, clears the level in the handler, executes MRET, and
    // only then reaches the normal completion store in the interrupted code.
    clear_tcm();
    dut.u_tcm.mem[0]  = {20'h02004, 5'd1, OPCODE_LUI};
    dut.u_tcm.mem[1]  = encode_i(12'd0, 5'd0, FUNCT3_ADD_SUB, 5'd2, OPCODE_OP_IMM);
    dut.u_tcm.mem[2]  = encode_s(12'd4, 5'd2, 5'd1, FUNCT3_SW);
    dut.u_tcm.mem[3]  = encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd2, OPCODE_OP_IMM);
    dut.u_tcm.mem[4]  = encode_s(12'd0, 5'd2, 5'd1, FUNCT3_SW);
    dut.u_tcm.mem[5]  = encode_i(12'd128, 5'd0, FUNCT3_ADD_SUB, 5'd3, OPCODE_OP_IMM);
    dut.u_tcm.mem[6]  = encode_i(CSR_MIE, 5'd3, FUNCT3_CSRRS, 5'd0, OPCODE_SYSTEM);
    dut.u_tcm.mem[7]  = encode_i(CSR_MSTATUS, 5'd8, FUNCT3_CSRRSI, 5'd0, OPCODE_SYSTEM);
    dut.u_tcm.mem[8]  = 32'h0000_0013;
    dut.u_tcm.mem[9]  = 32'h0000_0013;
    dut.u_tcm.mem[10] = encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd5, OPCODE_OP_IMM);
    dut.u_tcm.mem[11] = encode_s(STATUS_ADDR[11:0], 5'd5, 5'd0, FUNCT3_SW);
    dut.u_tcm.mem[12] = 32'h0000_006f;

    dut.u_tcm.mem[64] = encode_i(12'hfff, 5'd0, FUNCT3_ADD_SUB, 5'd2, OPCODE_OP_IMM);
    dut.u_tcm.mem[65] = encode_s(12'd4, 5'd2, 5'd1, FUNCT3_SW);
    dut.u_tcm.mem[66] = encode_s(12'd0, 5'd2, 5'd1, FUNCT3_SW);
    dut.u_tcm.mem[67] = INSN_MRET;

    saw_timer_trap = 1'b0;
    saw_timer_mret = 1'b0;
    phase = 5;
    apply_reset();
    wait_for_completion("timer interrupt program");
    check_bit(saw_timer_trap, 1'b1, "end-to-end timer trap observed");
    check_bit(saw_timer_mret, 1'b1, "end-to-end timer MRET observed");
    check_bit(dut.mtip, 1'b0, "timer handler clears MTIP level");
    check_word(dut.u_core.u_csr_file.mcause_q, 32'h8000_0007,
               "timer interrupt committed mcause");
    check_bit(test_pass, 1'b1, "timer interrupt program pass output");
    check_word(completion_stores, 32'd4, "one completion store per completing phase");

    // Phase 6: CPU-visible GPIO path. Exercise ordinary OUTPUT/OE writes plus
    // the atomic SET/CLEAR/TOGGLE aliases, then read both output state and the
    // synchronized external input back through the complete data fabric.
    clear_tcm();
    dut.u_tcm.mem[0]  = {20'h10010, 5'd1, OPCODE_LUI};
    dut.u_tcm.mem[1]  = encode_i(12'h5a5, 5'd0, FUNCT3_ADD_SUB, 5'd2, OPCODE_OP_IMM);
    dut.u_tcm.mem[2]  = encode_s(12'd4, 5'd2, 5'd1, FUNCT3_SW);
    dut.u_tcm.mem[3]  = encode_i(12'h00f, 5'd0, FUNCT3_ADD_SUB, 5'd3, OPCODE_OP_IMM);
    dut.u_tcm.mem[4]  = encode_s(12'h00c, 5'd3, 5'd1, FUNCT3_SW);
    dut.u_tcm.mem[5]  = encode_i(12'h005, 5'd0, FUNCT3_ADD_SUB, 5'd3, OPCODE_OP_IMM);
    dut.u_tcm.mem[6]  = encode_s(12'h010, 5'd3, 5'd1, FUNCT3_SW);
    dut.u_tcm.mem[7]  = encode_i(12'h0f0, 5'd0, FUNCT3_ADD_SUB, 5'd3, OPCODE_OP_IMM);
    dut.u_tcm.mem[8]  = encode_s(12'h014, 5'd3, 5'd1, FUNCT3_SW);
    dut.u_tcm.mem[9]  = encode_i(12'h0ff, 5'd0, FUNCT3_ADD_SUB, 5'd3, OPCODE_OP_IMM);
    dut.u_tcm.mem[10] = encode_s(12'h008, 5'd3, 5'd1, FUNCT3_SW);
    dut.u_tcm.mem[11] = encode_i(12'h004, 5'd1, FUNCT3_LW, 5'd4, OPCODE_LOAD);
    dut.u_tcm.mem[12] = encode_i(12'h000, 5'd1, FUNCT3_LW, 5'd5, OPCODE_LOAD);
    dut.u_tcm.mem[13] = encode_s(12'd128, 5'd4, 5'd0, FUNCT3_SW);
    dut.u_tcm.mem[14] = encode_s(12'd132, 5'd5, 5'd0, FUNCT3_SW);
    dut.u_tcm.mem[15] = encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd6, OPCODE_OP_IMM);
    dut.u_tcm.mem[16] = encode_s(STATUS_ADDR[11:0], 5'd6, 5'd0, FUNCT3_SW);
    dut.u_tcm.mem[17] = 32'h0000_006f;
    phase = 6;
    apply_reset();
    wait_for_completion("GPIO MMIO program");
    check_bit(test_pass, 1'b1, "GPIO program pass output");
    check_bit(test_fail, 1'b0, "GPIO program fail output");
    check_word({16'b0, gpio_out}, 32'h0000_055a, "GPIO external output sequence");
    check_word({16'b0, gpio_oe}, 32'h0000_00ff, "GPIO external output-enable");
    check_word(dut.u_tcm.mem[32], 32'h0000_055a, "GPIO OUTPUT MMIO readback");
    check_word(dut.u_tcm.mem[33], 32'h0000_a55a, "GPIO synchronized INPUT readback");
    check_word(completion_stores, 32'd5, "GPIO completion store counted");

    // Phase 7: true UART RX -> software -> TX echo. Software polls STATUS until
    // RX is valid, reads/pops RXDATA, writes the byte to TXDATA, and stores the
    // received value into TCM. The testbench drives and samples only top pins.
    clear_tcm();
    dut.u_tcm.mem[0] = {20'h10000, 5'd1, OPCODE_LUI};
    dut.u_tcm.mem[1] = encode_i(12'h008, 5'd1, FUNCT3_LW, 5'd3, OPCODE_LOAD);
    dut.u_tcm.mem[2] = encode_i(12'h004, 5'd3, FUNCT3_AND, 5'd3, OPCODE_OP_IMM);
    dut.u_tcm.mem[3] = encode_b(13'h1ff8, 5'd0, 5'd3, FUNCT3_BEQ);
    dut.u_tcm.mem[4] = encode_i(12'h004, 5'd1, FUNCT3_LW, 5'd4, OPCODE_LOAD);
    dut.u_tcm.mem[5] = encode_s(12'h000, 5'd4, 5'd1, FUNCT3_SB);
    dut.u_tcm.mem[6] = encode_s(12'd136, 5'd4, 5'd0, FUNCT3_SW);
    dut.u_tcm.mem[7] = encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd5, OPCODE_OP_IMM);
    dut.u_tcm.mem[8] = encode_s(STATUS_ADDR[11:0], 5'd5, 5'd0, FUNCT3_SW);
    dut.u_tcm.mem[9] = 32'h0000_006f;
    phase = 7;
    apply_reset();
    exercise_uart_echo(8'h45);
    wait_for_completion("UART echo program");
    check_bit(test_pass, 1'b1, "UART echo program pass output");
    check_bit(test_fail, 1'b0, "UART echo program fail output");
    check_word(dut.u_tcm.mem[34], 32'h0000_0045, "UART RX byte stored by software");
    check_word(completion_stores, 32'd6, "UART completion store counted");

    $display("tb_soc_tcm_top: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
