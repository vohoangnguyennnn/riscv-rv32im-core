// Minimal RV32IM SoC integration boundary.
//
// The core sees independent instruction and data ports while both are backed
// by one true-dual-port TCM. A retired full-word store to TEST_STATUS_ADDR is
// captured as a sticky completion mailbox for simulation, FPGA LEDs, or a
// future debug bridge. No test-only behavior is inserted into the CPU or TCM.
module soc_tcm_top #(
  parameter logic [31:0] RESET_VECTOR     = 32'h0000_0000,
  parameter logic [31:0] TRAP_VECTOR      = 32'h0000_0100,
  parameter int unsigned TCM_BYTES        = 64 * 1024,
  parameter logic [31:0] TCM_BASE_ADDR    = 32'h0000_0000,
  parameter string       TCM_INIT_FILE    = "",
  parameter logic [31:0] TEST_STATUS_ADDR = TCM_BASE_ADDR + TCM_BYTES - 4,
  parameter logic [31:0] TEST_PASS_VALUE  = 32'h0000_0001
) (
  input  logic        clk_i,
  input  logic        rst_i,

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
  output logic        trace_control_o,
  output logic        trace_taken_o,
  output logic [31:0] trace_target_o
);

  rv32_mem_if imem();
  rv32_mem_if dmem();

  logic test_status_commit;

  // Observe architectural retirement rather than the raw data bus. Therefore
  // a faulting, squashed, or wrong-path store can never mark the SoC complete.
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
    .imem_m             (imem),
    .dmem_m             (dmem),
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
    .trace_control_o    (trace_control_o),
    .trace_taken_o      (trace_taken_o),
    .trace_target_o     (trace_target_o)
  );

  rv32_tcm #(
    .BYTES     (TCM_BYTES),
    .BASE_ADDR (TCM_BASE_ADDR),
    .INIT_FILE (TCM_INIT_FILE)
  ) u_tcm (
    .clk_i  (clk_i),
    .imem_s (imem),
    .dmem_s (dmem)
  );

endmodule
