module tb_freertos_soc;

  timeunit 1ns;
  timeprecision 1ps;

  localparam int unsigned TCM_BYTES = 64 * 1024;
  localparam int unsigned WORDS = TCM_BYTES / 4;
  localparam int unsigned REPORT_WORD = 32'h0000_e000 / 4;
  localparam int unsigned UART_CLK_FREQ_HZ = 75_000_000;
  localparam int unsigned UART_BAUD_RATE = 115_200;
  localparam int unsigned UART_CLKS_PER_BIT =
    UART_CLK_FREQ_HZ / UART_BAUD_RATE;
  localparam int unsigned GPIO_WIDTH = 16;
  localparam int unsigned DEFAULT_MAX_CYCLES = 1_500_000;

  localparam logic [31:0] PASS_STATUS = 32'h0000_0001;
  localparam logic [31:0] REPORT_MAGIC = 32'h4652_544f;
  localparam logic [31:0] KERNEL_VERSION = 32'h000b_0300;
  localparam logic [7:0] ECHO_BYTE = 8'ha5;
  localparam logic [31:0] INSN_MRET = 32'h3020_0073;

  logic clk;
  logic rst;
  logic uart_rx;
  logic uart_tx;
  logic [GPIO_WIDTH-1:0] gpio_in;
  logic [GPIO_WIDTH-1:0] gpio_out;
  logic [GPIO_WIDTH-1:0] gpio_oe;

  logic test_done;
  logic test_pass;
  logic test_fail;
  logic [31:0] test_status;
  logic trace_valid;
  logic [31:0] trace_pc;
  logic [31:0] trace_insn;
  logic trace_rd_we;
  logic [4:0] trace_rd_addr;
  logic [31:0] trace_rd_data;
  logic [31:0] trace_mem_addr;
  logic [3:0] trace_mem_wstrb;
  logic [31:0] trace_mem_wdata;
  logic trace_trap;
  logic [4:0] trace_cause;
  logic trace_is_interrupt;
  logic trace_control;
  logic trace_taken;
  logic [31:0] trace_target;

  string mem_file;
  int unsigned max_cycles;
  int unsigned cycles;
  int unsigned checks;
  int unsigned timer_traps;
  int unsigned yield_traps;
  int unsigned mret_retirements;
  int unsigned gpio_transitions;
  logic previous_gpio;

  soc_tcm_top #(
    .TCM_BYTES        (TCM_BYTES),
    .UART_CLK_FREQ_HZ (UART_CLK_FREQ_HZ),
    .UART_BAUD_RATE   (UART_BAUD_RATE),
    .GPIO_WIDTH       (GPIO_WIDTH)
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

  task automatic check_equal(
    input logic [31:0] actual,
    input logic [31:0] expected,
    input string name
  );
    begin
      if (actual !== expected) begin
        $fatal(1, "%s mismatch: expected=%08x actual=%08x", name,
               expected, actual);
      end
      checks++;
    end
  endtask

  task automatic check_at_least(
    input logic [31:0] actual,
    input logic [31:0] minimum,
    input string name
  );
    begin
      if ((^actual === 1'bx) || (actual < minimum)) begin
        $fatal(1, "%s below minimum: minimum=%0d actual=%0d", name,
               minimum, actual);
      end
      checks++;
    end
  endtask

  task automatic capture_uart_byte(
    input logic [7:0] expected,
    input string name
  );
    logic [7:0] received;
    begin
      @(negedge uart_tx);
      repeat (UART_CLKS_PER_BIT / 2) @(posedge clk);
      #1ps;
      if (uart_tx !== 1'b0) begin
        $fatal(1, "%s invalid start bit", name);
      end

      for (int unsigned bit_index = 0; bit_index < 8; bit_index++) begin
        repeat (UART_CLKS_PER_BIT) @(posedge clk);
        #1ps;
        received[bit_index] = uart_tx;
      end

      repeat (UART_CLKS_PER_BIT) @(posedge clk);
      #1ps;
      if (uart_tx !== 1'b1) begin
        $fatal(1, "%s invalid stop bit", name);
      end

      repeat (UART_CLKS_PER_BIT / 2) @(posedge clk);
      check_equal({24'b0, received}, {24'b0, expected}, name);
    end
  endtask

  task automatic drive_uart_byte(input logic [7:0] value);
    begin
      uart_rx = 1'b0;
      repeat (UART_CLKS_PER_BIT) @(negedge clk);

      for (int unsigned bit_index = 0; bit_index < 8; bit_index++) begin
        uart_rx = value[bit_index];
        repeat (UART_CLKS_PER_BIT) @(negedge clk);
      end

      uart_rx = 1'b1;
      repeat (UART_CLKS_PER_BIT) @(negedge clk);
    end
  endtask

  task automatic check_report;
    logic [31:0] blink_count;
    logic [31:0] gpio_value;
    begin
      check_equal(dut.u_tcm.mem[REPORT_WORD + 0], REPORT_MAGIC,
                  "report magic");
      check_equal(dut.u_tcm.mem[REPORT_WORD + 1], KERNEL_VERSION,
                  "FreeRTOS version");
      check_at_least(dut.u_tcm.mem[REPORT_WORD + 2], 32'd4,
                     "scheduler tick count");
      check_at_least(dut.u_tcm.mem[REPORT_WORD + 3], 32'd4,
                     "tick-hook count");
      check_at_least(dut.u_tcm.mem[REPORT_WORD + 4], 32'd8,
                     "context-switch count");
      check_at_least(dut.u_tcm.mem[REPORT_WORD + 5], 32'd3,
                     "blink-task count");
      check_equal(dut.u_tcm.mem[REPORT_WORD + 6], 32'd1,
                  "UART echo count");
      check_equal(dut.u_tcm.mem[REPORT_WORD + 7], {24'b0, ECHO_BYTE},
                  "UART echoed byte");
      check_equal(dut.u_tcm.mem[REPORT_WORD + 12], 32'b0,
                  "no unexpected exception mepc");
      check_equal(dut.u_tcm.mem[REPORT_WORD + 14], 32'b0,
                  "no platform failure");

      blink_count = dut.u_tcm.mem[REPORT_WORD + 5];
      gpio_value = dut.u_tcm.mem[REPORT_WORD + 8];
      check_equal(gpio_value & 32'd1, blink_count & 32'd1,
                  "GPIO output matches blink parity");

      if ((dut.u_tcm.mem[REPORT_WORD + 9] & 32'h0000_0008) == 0) begin
        $fatal(1, "report mstatus.MIE is not enabled in task context");
      end
      checks++;
      if ((dut.u_tcm.mem[REPORT_WORD + 10] & 32'h0000_0080) == 0) begin
        $fatal(1, "report mie.MTIE is not enabled");
      end
      checks++;
    end
  endtask

  initial begin : run_freertos_demo
    clk = 1'b0;
    rst = 1'b1;
    uart_rx = 1'b1;
    gpio_in = '0;
    max_cycles = DEFAULT_MAX_CYCLES;
    cycles = 0;
    checks = 0;
    timer_traps = 0;
    yield_traps = 0;
    mret_retirements = 0;
    gpio_transitions = 0;
    previous_gpio = 1'b0;

    if (!$value$plusargs("mem=%s", mem_file)) begin
      $fatal(1, "missing required +mem=<FreeRTOS memory image>");
    end
    void'($value$plusargs("max_cycles=%d", max_cycles));

    for (int unsigned word_index = 0; word_index < WORDS; word_index++) begin
      dut.u_tcm.mem[word_index] = 32'b0;
    end
    $readmemh(mem_file, dut.u_tcm.mem);

    repeat (5) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    capture_uart_byte("R", "UART ready[0]");
    capture_uart_byte("E", "UART ready[1]");
    capture_uart_byte("A", "UART ready[2]");
    capture_uart_byte("D", "UART ready[3]");
    capture_uart_byte("Y", "UART ready[4]");
    capture_uart_byte(8'h0a, "UART ready[5]");

    fork
      drive_uart_byte(ECHO_BYTE);
      capture_uart_byte(ECHO_BYTE, "UART task echo");
    join

    while (!test_done) begin
      @(posedge clk);
    end
    #1ps;

    check_equal(test_status, PASS_STATUS, "completion status");
    check_equal({31'b0, test_pass}, 32'd1, "completion pass flag");
    check_equal({31'b0, test_fail}, 32'd0, "completion fail flag");
    check_at_least(timer_traps, 32'd4, "machine timer traps");
    check_at_least(mret_retirements, 32'd4, "MRET retirements");
    check_at_least(gpio_transitions, 32'd3, "GPIO output transitions");
    check_equal({31'b0, gpio_oe[0]}, 32'd1, "GPIO output enable");
    check_report();

    $display(
      "tb_freertos_soc: PASS (%0d checks, %0d cycles, %0d MTIP traps, %0d yield traps, %0d MRET, %0d GPIO transitions)",
      checks, cycles, timer_traps, yield_traps, mret_retirements,
      gpio_transitions
    );
    $finish;
  end

  always @(posedge clk) begin : monitor_execution
    #1ps;
    if (!rst) begin
      cycles++;

      if (trace_valid && trace_trap) begin
        unique case (trace_cause)
          5'd7: timer_traps++;
          // FreeRTOS uses an M-mode ECALL as its synchronous yield request.
          5'd11: yield_traps++;
          default: begin
            $fatal(1,
                   "unexpected trap cause=%0d pc=%08x insn=%08x at cycle %0d",
                   trace_cause, trace_pc, trace_insn, cycles);
          end
        endcase
      end

      if (trace_valid && !trace_trap && (trace_insn == INSN_MRET)) begin
        if (!trace_control || !trace_taken) begin
          $fatal(1, "MRET retirement lacks control-flow metadata");
        end
        mret_retirements++;
      end

      if (gpio_out[0] != previous_gpio) begin
        gpio_transitions++;
        previous_gpio = gpio_out[0];
      end

      if (test_done && test_fail) begin
        $fatal(1,
               "FreeRTOS software failure status=%08x report_code=%08x mcause=%08x mepc=%08x mtval=%08x",
               test_status,
               dut.u_tcm.mem[REPORT_WORD + 14],
               dut.u_tcm.mem[REPORT_WORD + 11],
               dut.u_tcm.mem[REPORT_WORD + 12],
               dut.u_tcm.mem[REPORT_WORD + 13]);
      end

      if (cycles >= max_cycles) begin
        $fatal(1,
               "FreeRTOS demo timed out after %0d cycles (MTIP=%0d yield=%0d MRET=%0d GPIO=%0d pc=%08x insn=%08x)",
               cycles, timer_traps, yield_traps, mret_retirements,
               gpio_transitions,
               trace_pc, trace_insn);
      end
    end
  end

endmodule
