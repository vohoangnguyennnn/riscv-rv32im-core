
// MicroPhase A7-Lite R1.1 top for the TCM-based RV32IM SoC.
//
// A Clocking Wizard converts the board's 50 MHz clock to 75 MHz. On-board green
// LEDs are active-low; FAIL/DONE remain active-high on JP2.
module fpga_top #(
  parameter logic [31:0] RESET_VECTOR      = 32'h0000_0000,
  parameter logic [31:0] TRAP_VECTOR       = 32'h0000_0100,
  parameter int unsigned TCM_BYTES         = 64 * 1024,
  parameter logic [31:0] TCM_BASE_ADDR     = 32'h0000_0000,
  parameter string       TCM_INIT_FILE     = "",
  parameter logic [31:0] TEST_STATUS_ADDR  = TCM_BASE_ADDR + TCM_BYTES - 4,
  parameter logic [31:0] TEST_PASS_VALUE   = 32'h0000_0001,
  parameter int unsigned SOC_CLK_FREQ_HZ   = 75_000_000,
  parameter int unsigned RESET_SYNC_STAGES = 2,
  parameter int unsigned HEARTBEAT_WIDTH    = 24
) (
  input  logic clk_50m_i,
  input  logic reset_ni,
  input  logic user_reset_ni,
  input  logic uart_rx_i,
  output logic uart_tx_o,
  output logic gpio_led_o,
  output logic led1_n_o,
  output logic led2_n_o,
  output logic fail_o,
  output logic done_o
);

  logic clk_75m;
  logic clk_locked;
  logic clock_reset_ni;
  logic soc_rst;
  logic test_done;
  logic test_pass;
  logic test_fail;
  logic [HEARTBEAT_WIDTH-1:0] heartbeat_q;
  logic heartbeat;
  logic uart_tx;
  logic [31:0] gpio_out;
  logic [31:0] gpio_oe;

  clk_wiz_0 u_clk_wiz (
    .clk_in1  (clk_50m_i),
    .reset    (~reset_ni),
    .clk_out1 (clk_75m),
    .locked   (clk_locked)
  );

  // K3 resets the clocking boundary; K1 resets only the synchronous SoC so the
  // status outputs remain observably reset while the user button is held.
  assign clock_reset_ni = reset_ni && user_reset_ni && clk_locked;

  reset_sync #(
    .STAGES (RESET_SYNC_STAGES)
  ) u_reset_sync (
    .clk_i   (clk_75m),
    .arst_ni (clock_reset_ni),
    .rst_o   (soc_rst)
  );

  // Stop the heartbeat at completion so the visible result is stable.
  always_ff @(posedge clk_75m) begin
    if (soc_rst || test_done) begin
      heartbeat_q <= '0;
    end else begin
      heartbeat_q <= heartbeat_q + 1'b1;
    end
  end

  // D6/D5 illuminate low; JP2 FAIL/DONE retain active-high polarity.
  always_comb begin
    heartbeat = 1'b0;
    led1_n_o  = 1'b1;
    led2_n_o  = 1'b1;
    fail_o    = 1'b0;
    done_o    = 1'b0;

    if (reset_ni && user_reset_ni && clk_locked && !soc_rst) begin
      heartbeat = heartbeat_q[HEARTBEAT_WIDTH-1] && !test_done;
      led1_n_o  = ~heartbeat;
      led2_n_o  = ~test_pass;
      fail_o    =  test_fail;
      done_o    =  test_done;
    end
  end

  // Hold external peripherals benign throughout either reset source or loss of
  // clock lock, even while the generated SoC clock is not toggling.
  assign uart_tx_o  = (reset_ni && user_reset_ni && clk_locked) ? uart_tx : 1'b1;
  assign gpio_led_o = reset_ni && user_reset_ni && clk_locked && !soc_rst
                    && gpio_oe[0] && gpio_out[0];

  soc_tcm_top #(
    .RESET_VECTOR      (RESET_VECTOR),
    .TRAP_VECTOR       (TRAP_VECTOR),
    .TCM_BYTES         (TCM_BYTES),
    .TCM_BASE_ADDR     (TCM_BASE_ADDR),
    .TCM_INIT_FILE     (TCM_INIT_FILE),
    .UART_CLK_FREQ_HZ  (SOC_CLK_FREQ_HZ),
    .TEST_STATUS_ADDR  (TEST_STATUS_ADDR),
    .TEST_PASS_VALUE   (TEST_PASS_VALUE)
  ) u_soc (
    .clk_i              (clk_75m),
    .rst_i              (soc_rst),
    .uart_rx_i          (uart_rx_i),
    .uart_tx_o          (uart_tx),
    .gpio_in_i          (32'b0),
    .gpio_out_o         (gpio_out),
    .gpio_oe_o          (gpio_oe),
    .test_done_o        (test_done),
    .test_pass_o        (test_pass),
    .test_fail_o        (test_fail),
    .test_status_o      (),
    .trace_valid_o      (),
    .trace_pc_o         (),
    .trace_insn_o       (),
    .trace_rd_we_o      (),
    .trace_rd_addr_o    (),
    .trace_rd_data_o    (),
    .trace_mem_addr_o   (),
    .trace_mem_wstrb_o  (),
    .trace_mem_wdata_o  (),
    .trace_trap_o       (),
    .trace_cause_o      (),
    .trace_is_interrupt_o (),
    .trace_control_o    (),
    .trace_taken_o      (),
    .trace_target_o     (),
    .perf_cycle_o          (),
    .perf_instret_o        (),
    .perf_load_use_stall_o (),
    .perf_csr_stall_o      (),
    .perf_mdu_stall_o      (),
    .perf_mem_stall_o      (),
    .perf_redirect_o       (),
    .perf_squash_o         ()
  );

endmodule
