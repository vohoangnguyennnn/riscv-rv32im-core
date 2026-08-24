// Minimal RV32IM SoC integration boundary.
//
// Instruction traffic uses TCM port A; data traffic is decoded across TCM port
// B, timer, UART, and GPIO. Timer MTIP feeds the core directly. External I/O is
// exposed for simulation or a board wrapper. A retired word store to
// TEST_STATUS_ADDR updates a sticky completion mailbox outside the CPU/fabric.
module soc_tcm_top #(
  parameter logic [31:0] RESET_VECTOR          = 32'h0000_0000,
  parameter logic [31:0] TRAP_VECTOR           = 32'h0000_0100,
  parameter int unsigned TCM_BYTES             = 64 * 1024,
  parameter logic [31:0] TCM_BASE_ADDR         = 32'h0000_0000,
  parameter string       TCM_INIT_FILE         = "",
  parameter logic [31:0] TIMER_BASE_ADDR       = 32'h0200_0000,
  parameter logic [31:0] TIMER_ADDR_MASK       = 32'hffff_0000,
  parameter logic [31:0] UART_BASE_ADDR        = 32'h1000_0000,
  parameter logic [31:0] UART_ADDR_MASK        = 32'hffff_0000,
  parameter int unsigned UART_CLK_FREQ_HZ      = 50_000_000,
  parameter int unsigned UART_BAUD_RATE        = 115_200,
  parameter logic [31:0] GPIO_BASE_ADDR        = 32'h1001_0000,
  parameter logic [31:0] GPIO_ADDR_MASK        = 32'hffff_0000,
  parameter int unsigned GPIO_WIDTH            = 32,
  parameter logic [31:0] GPIO_OUTPUT_RESET_VALUE = 32'b0,
  parameter logic [31:0] GPIO_OUTPUT_ENABLE_RESET_VALUE = 32'b0,
  parameter logic [63:0] MTIME_RESET_VALUE     = 64'b0,
  parameter logic [63:0] MTIMECMP_RESET_VALUE = 64'hffff_ffff_ffff_ffff,
  parameter logic [31:0] TEST_STATUS_ADDR      = TCM_BASE_ADDR + TCM_BYTES - 4,
  parameter logic [31:0] TEST_PASS_VALUE       = 32'h0000_0001
) (
  input  logic        clk_i,
  input  logic        rst_i,

  input  logic        uart_rx_i,
  output logic        uart_tx_o,

  input  logic [GPIO_WIDTH-1:0] gpio_in_i,
  output logic [GPIO_WIDTH-1:0] gpio_out_o,
  output logic [GPIO_WIDTH-1:0] gpio_oe_o,

  output logic        test_done_o,
  output logic        test_pass_o,
  output logic        test_fail_o,
  output logic [31:0] test_status_o,

  output logic        trace_valid_o,
  output logic [31:0] trace_pc_o,
  output logic [31:0] trace_insn_o,
  output logic        trace_rd_we_o,
  output logic [4:0]  trace_rd_addr_o,
  output logic [31:0] trace_rd_data_o,
  output logic [31:0] trace_mem_addr_o,
  output logic [3:0]  trace_mem_wstrb_o,
  output logic [31:0] trace_mem_wdata_o,
  output logic        trace_trap_o,
  output logic [4:0]  trace_cause_o,
  output logic        trace_is_interrupt_o,
  output logic        trace_control_o,
  output logic        trace_taken_o,
  output logic [31:0] trace_target_o,
  output logic [63:0] perf_cycle_o,
  output logic [63:0] perf_instret_o,
  output logic [63:0] perf_load_use_stall_o,
  output logic [63:0] perf_csr_stall_o,
  output logic [63:0] perf_mdu_stall_o,
  output logic [63:0] perf_mem_stall_o,
  output logic [63:0] perf_redirect_o,
  output logic [63:0] perf_squash_o
);

  rv32_mem_if imem();
  rv32_mem_if core_dmem();
  rv32_mem_if tcm_dmem();
  rv32_mem_if timer_bus();
  rv32_mem_if uart_bus();
  rv32_mem_if gpio_bus();

  logic test_status_commit;
  logic mtip;

  // Observe retirement so a faulting, squashed, or wrong-path store cannot finish.
  assign test_status_commit = trace_valid_o && !trace_trap_o && (trace_mem_wstrb_o == 4'b1111) && (trace_mem_addr_o == TEST_STATUS_ADDR);

  assign test_pass_o = test_done_o && (test_status_o == TEST_PASS_VALUE);
  assign test_fail_o = test_done_o && (test_status_o != TEST_PASS_VALUE);

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      test_done_o   <= 1'b0;
      test_status_o <= 32'b0;
    end else if (!test_done_o && test_status_commit) begin
      test_done_o   <= 1'b1;
      test_status_o <= trace_mem_wdata_o;
    end
  end

  rv32_core #(
    .RESET_VECTOR (RESET_VECTOR),
    .TRAP_VECTOR  (TRAP_VECTOR)
  ) u_core (
    .clk_i              (clk_i),
    .rst_i              (rst_i),
    .mtip_i             (mtip),
    .imem_m             (imem),
    .dmem_m             (core_dmem),
    .trace_valid_o      (trace_valid_o),
    .trace_pc_o         (trace_pc_o),
    .trace_insn_o       (trace_insn_o),
    .trace_rd_we_o      (trace_rd_we_o),
    .trace_rd_addr_o    (trace_rd_addr_o),
    .trace_rd_data_o    (trace_rd_data_o),
    .trace_mem_addr_o   (trace_mem_addr_o),
    .trace_mem_wstrb_o  (trace_mem_wstrb_o),
    .trace_mem_wdata_o  (trace_mem_wdata_o),
    .trace_trap_o       (trace_trap_o),
    .trace_cause_o      (trace_cause_o),
    .trace_is_interrupt_o (trace_is_interrupt_o),
    .trace_control_o    (trace_control_o),
    .trace_taken_o      (trace_taken_o),
    .trace_target_o     (trace_target_o),
    .perf_cycle_o          (perf_cycle_o),
    .perf_instret_o        (perf_instret_o),
    .perf_load_use_stall_o (perf_load_use_stall_o),
    .perf_csr_stall_o      (perf_csr_stall_o),
    .perf_mdu_stall_o      (perf_mdu_stall_o),
    .perf_mem_stall_o      (perf_mem_stall_o),
    .perf_redirect_o       (perf_redirect_o),
    .perf_squash_o         (perf_squash_o)
  );

  rv32_mem_demux #(
    .TIMER_BASE_ADDR (TIMER_BASE_ADDR),
    .TIMER_ADDR_MASK (TIMER_ADDR_MASK),
    .UART_BASE_ADDR  (UART_BASE_ADDR),
    .UART_ADDR_MASK  (UART_ADDR_MASK),
    .GPIO_BASE_ADDR  (GPIO_BASE_ADDR),
    .GPIO_ADDR_MASK  (GPIO_ADDR_MASK)
  ) u_dmem_demux (
    .clk_i   (clk_i),
    .rst_i   (rst_i),
    .core_s  (core_dmem),
    .tcm_m   (tcm_dmem),
    .timer_m (timer_bus),
    .uart_m  (uart_bus),
    .gpio_m  (gpio_bus)
  );

  rv32_mtimer #(
    .BASE_ADDR            (TIMER_BASE_ADDR),
    .MTIME_RESET_VALUE    (MTIME_RESET_VALUE),
    .MTIMECMP_RESET_VALUE (MTIMECMP_RESET_VALUE)
  ) u_mtimer (
    .clk_i   (clk_i),
    .rst_i   (rst_i),
    .timer_s (timer_bus),
    .mtip_o  (mtip)
  );

  rv32_uart #(
    .BASE_ADDR   (UART_BASE_ADDR),
    .CLK_FREQ_HZ (UART_CLK_FREQ_HZ),
    .BAUD_RATE   (UART_BAUD_RATE)
  ) u_uart (
    .clk_i     (clk_i),
    .rst_i     (rst_i),
    .uart_s    (uart_bus),
    .uart_rx_i (uart_rx_i),
    .uart_tx_o (uart_tx_o)
  );

  rv32_gpio #(
    .BASE_ADDR                (GPIO_BASE_ADDR),
    .GPIO_WIDTH               (GPIO_WIDTH),
    .OUTPUT_RESET_VALUE       (GPIO_OUTPUT_RESET_VALUE),
    .OUTPUT_ENABLE_RESET_VALUE(GPIO_OUTPUT_ENABLE_RESET_VALUE)
  ) u_gpio (
    .clk_i      (clk_i),
    .rst_i      (rst_i),
    .gpio_s     (gpio_bus),
    .gpio_in_i  (gpio_in_i),
    .gpio_out_o (gpio_out_o),
    .gpio_oe_o  (gpio_oe_o)
  );

  rv32_tcm #(
    .BYTES     (TCM_BYTES),
    .BASE_ADDR (TCM_BASE_ADDR),
    .INIT_FILE (TCM_INIT_FILE)
  ) u_tcm (
    .clk_i  (clk_i),
    .imem_s (imem),
    .dmem_s (tcm_dmem)
  );

endmodule
