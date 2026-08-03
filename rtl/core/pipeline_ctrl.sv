// Centralized control for the RV32IM five-stage pipeline.
//
// Pipeline-register storage remains in rv32_core. This module emits only
// enable/flush decisions and the selected fetch redirect. Priority follows
// instruction age so an older trap, exception, or wait can never be overridden
// by a younger control transfer or data hazard.
module pipeline_ctrl (
  input  logic                       clk_i,
  input  logic                       rst_i,

  input  logic                       load_use_i,
  input  logic                       csr_dep_i,
  input  logic                       ex_wait_i,
  input  logic                       mem_wait_i,
  input  logic                       id_exception_i,
  input  logic                       ex_exception_i,
  input  logic                       mem_exception_i,
  input  logic                       wb_trap_i,
  input  wire rv32_pkg::redirect_t   control_redirect_i,
  input  logic [31:0]                mtvec_i,

  output logic                       pc_enable_o,
  output logic                       if_id_enable_o,
  output logic                       id_ex_enable_o,
  output logic                       ex_mem_enable_o,
  output logic                       mem_wb_enable_o,
  output logic                       if_id_flush_o,
  output logic                       id_ex_flush_o,
  output logic                       ex_mem_flush_o,
  output logic                       mem_wb_flush_o,
  output logic                       redirect_valid_o,
  output logic [31:0]                redirect_pc_o,
  output logic                       trap_drain_o
);

  import rv32_pkg::*;

  logic trap_drain_q;
  logic trap_drain_d;
  logic id_hazard;

  assign id_hazard   = load_use_i || csr_dep_i;
  assign trap_drain_o = trap_drain_q;

  always_comb begin
    // Normal pipeline advance. Flush has priority over enable at the pipeline
    // registers, so flush events can retain these enable defaults.
    pc_enable_o     = 1'b1;
    if_id_enable_o  = 1'b1;
    id_ex_enable_o  = 1'b1;
    ex_mem_enable_o = 1'b1;
    mem_wb_enable_o = 1'b1;

    if_id_flush_o  = 1'b0;
    id_ex_flush_o  = 1'b0;
    ex_mem_flush_o = 1'b0;
    mem_wb_flush_o = 1'b0;

    redirect_valid_o = 1'b0;
    redirect_pc_o    = 32'b0;
    trap_drain_d     = trap_drain_q;

    // Synchronous reset is also handled directly by every pipeline register
    // and IF stage. Driving an all-stage flush here makes the controller output
    // benign and unambiguous during reset.
    if (rst_i) begin
      pc_enable_o     = 1'b0;
      if_id_enable_o  = 1'b0;
      id_ex_enable_o  = 1'b0;
      ex_mem_enable_o = 1'b0;
      mem_wb_enable_o = 1'b0;

      if_id_flush_o  = 1'b1;
      id_ex_flush_o  = 1'b1;
      ex_mem_flush_o = 1'b1;
      mem_wb_flush_o = 1'b1;

      trap_drain_d = 1'b0;

    // The trapping instruction is committing in WB. Squash every younger
    // packet, consume the current MEM/WB entry, and restart fetch at mtvec.
    end else if (wb_trap_i) begin
      if_id_flush_o  = 1'b1;
      id_ex_flush_o  = 1'b1;
      ex_mem_flush_o = 1'b1;
      mem_wb_flush_o = 1'b1;

      redirect_valid_o = 1'b1;
      redirect_pc_o    = {mtvec_i[31:2], 2'b00};
      trap_drain_d     = 1'b0;

    // A MEM exception is the oldest newly detected fault. Let the offending
    // instruction enter MEM/WB and squash every younger stage.
    end else if (mem_exception_i) begin
      pc_enable_o = 1'b0;

      if_id_flush_o  = 1'b1;
      id_ex_flush_o  = 1'b1;
      ex_mem_flush_o = 1'b1;

      trap_drain_d = 1'b1;

    // MEM owns EX/MEM while waiting. Older WB may commit once, then MEM/WB must
    // become a bubble to prevent repeated retirement on subsequent wait cycles.
    end else if (mem_wait_i) begin
      pc_enable_o     = 1'b0;
      if_id_enable_o  = 1'b0;
      id_ex_enable_o  = 1'b0;
      ex_mem_enable_o = 1'b0;

      mem_wb_flush_o = 1'b1;

    // An EX exception advances into EX/MEM while the two younger stages are
    // squashed and fetch is stopped for precise trap draining.
    end else if (ex_exception_i) begin
      pc_enable_o = 1'b0;

      if_id_flush_o = 1'b1;
      id_ex_flush_o = 1'b1;

      trap_drain_d = 1'b1;

    // A multi-cycle EX operation retains ID/EX. The older EX/MEM entry may
    // advance, after which EX/MEM receives a bubble until the result is ready.
    end else if (ex_wait_i) begin
      pc_enable_o    = 1'b0;
      if_id_enable_o = 1'b0;
      id_ex_enable_o = 1'b0;

      ex_mem_flush_o = 1'b1;

    // Once a precise exception is draining, no younger redirect or ID event is
    // allowed to restart the front end. Older MEM/EX waits and exceptions have
    // already been handled by the higher-priority branches above.
    end else if (trap_drain_q) begin
      pc_enable_o    = 1'b0;
      if_id_enable_o = 1'b0;

    // A control transfer redirects only after its result has been accepted by
    // the downstream stage. EX-origin redirects squash two younger packets; the
    // future ID-origin option squashes only IF/ID so the control packet itself
    // can enter ID/EX.
    end else if (control_redirect_i.valid) begin
      redirect_valid_o = 1'b1;
      redirect_pc_o    = control_redirect_i.target;
      if_id_flush_o    = 1'b1;

      unique case (control_redirect_i.origin)
        REDIRECT_FROM_ID: id_ex_flush_o = 1'b0;
        REDIRECT_FROM_EX: id_ex_flush_o = 1'b1;
        default:          id_ex_flush_o = 1'b1;
      endcase

    // The faulting ID packet advances into ID/EX; only the younger fetch packet
    // is discarded. Front-end issue remains stopped until WB takes the trap.
    end else if (id_exception_i) begin
      pc_enable_o   = 1'b0;
      if_id_flush_o = 1'b1;

      trap_drain_d = 1'b1;

    // Load-use and CSR dependencies hold the producer/consumer boundary and
    // inject exactly one bubble into ID/EX.
    end else if (id_hazard) begin
      pc_enable_o    = 1'b0;
      if_id_enable_o = 1'b0;

      id_ex_flush_o = 1'b1;
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      trap_drain_q <= 1'b0;
    end else begin
      trap_drain_q <= trap_drain_d;
    end
  end

endmodule
