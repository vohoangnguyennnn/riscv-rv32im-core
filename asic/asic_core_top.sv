// ASIC top for the bare rv32_core: flattens the two rv32_mem_if ports into
// plain pins, because a physical block boundary cannot carry an interface.
// Memory (TCM) is outside this block; trace_*/perf_* are left open on purpose
// so synthesis removes the observability-only logic from the area numbers.
module asic_core_top (
  input  logic        clk_i,
  input  logic        rst_i,
  input  logic        mtip_i,

  output logic        imem_req_valid_o,
  input  logic        imem_req_ready_i,
  output logic [31:0] imem_req_addr_o,
  input  logic        imem_rsp_valid_i,
  input  logic [31:0] imem_rsp_rdata_i,
  input  logic        imem_rsp_err_i,

  output logic        dmem_req_valid_o,
  input  logic        dmem_req_ready_i,
  output logic [31:0] dmem_req_addr_o,
  output logic        dmem_req_write_o,
  output logic [31:0] dmem_req_wdata_o,
  output logic [3:0]  dmem_req_wstrb_o,
  input  logic        dmem_rsp_valid_i,
  input  logic [31:0] dmem_rsp_rdata_i,
  input  logic        dmem_rsp_err_i
);

  rv32_mem_if imem ();
  rv32_mem_if dmem ();

  assign imem_req_valid_o = imem.req_valid;
  assign imem_req_addr_o  = imem.req_addr;
  assign imem.req_ready   = imem_req_ready_i;
  assign imem.rsp_valid   = imem_rsp_valid_i;
  assign imem.rsp_rdata   = imem_rsp_rdata_i;
  assign imem.rsp_err     = imem_rsp_err_i;

  assign dmem_req_valid_o = dmem.req_valid;
  assign dmem_req_addr_o  = dmem.req_addr;
  assign dmem_req_write_o = dmem.req_write;
  assign dmem_req_wdata_o = dmem.req_wdata;
  assign dmem_req_wstrb_o = dmem.req_wstrb;
  assign dmem.req_ready   = dmem_req_ready_i;
  assign dmem.rsp_valid   = dmem_rsp_valid_i;
  assign dmem.rsp_rdata   = dmem_rsp_rdata_i;
  assign dmem.rsp_err     = dmem_rsp_err_i;

  rv32_core u_core (
    .clk_i                (clk_i),
    .rst_i                (rst_i),
    .mtip_i               (mtip_i),
    .imem_m               (imem),
    .dmem_m               (dmem),
    .trace_valid_o        (),
    .trace_pc_o           (),
    .trace_insn_o         (),
    .trace_rd_we_o        (),
    .trace_rd_addr_o      (),
    .trace_rd_data_o      (),
    .trace_mem_addr_o     (),
    .trace_mem_wstrb_o    (),
    .trace_mem_wdata_o    (),
    .trace_trap_o         (),
    .trace_cause_o        (),
    .trace_is_interrupt_o (),
    .trace_control_o      (),
    .trace_taken_o        (),
    .trace_target_o       (),
    .perf_cycle_o         (),
    .perf_instret_o       (),
    .perf_load_use_stall_o(),
    .perf_csr_stall_o     (),
    .perf_mdu_stall_o     (),
    .perf_mem_stall_o     (),
    .perf_redirect_o      (),
    .perf_squash_o        ()
  );

endmodule
