// SPDX-License-Identifier: MIT

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

  typedef enum logic [3:0] {
    ACTION_ADVANCE,
    ACTION_ID_HAZARD,
    ACTION_ID_EXCEPTION,
    ACTION_EX_REDIRECT,
    ACTION_TRAP_DRAIN,
    ACTION_EX_WAIT,
    ACTION_EX_EXCEPTION,
    ACTION_MEM_WAIT,
    ACTION_MEM_EXCEPTION,
    ACTION_WB_TRAP,
    ACTION_RESET
  } pipeline_action_e;

  logic trap_drain_q;
  logic trap_drain_d;
  logic id_hazard;
  pipeline_action_e action;

  assign id_hazard   = load_use_i || csr_dep_i;
  assign trap_drain_o = trap_drain_q;

  // Select exactly one pipeline action.  The source order is the architectural
  // age/priority order from the design specification; enum numeric values do
  // not encode priority and are used only to make waveforms self-describing.
  always_comb begin
    action = ACTION_ADVANCE;

    if (rst_i) begin
      action = ACTION_RESET;
    end else if (wb_trap_i) begin
      action = ACTION_WB_TRAP;
    end else if (mem_exception_i) begin
      action = ACTION_MEM_EXCEPTION;
    end else if (mem_wait_i) begin
      action = ACTION_MEM_WAIT;
    end else if (ex_exception_i) begin
      action = ACTION_EX_EXCEPTION;
    end else if (ex_wait_i) begin
      action = ACTION_EX_WAIT;
    end else if (trap_drain_q) begin
      action = ACTION_TRAP_DRAIN;
    end else if (control_redirect_i.valid) begin
      action = ACTION_EX_REDIRECT;
    end else if (id_exception_i) begin
      action = ACTION_ID_EXCEPTION;
    end else if (id_hazard) begin
      action = ACTION_ID_HAZARD;
    end
  end

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

    unique case (action)
      // Synchronous reset is also handled directly by every pipeline register
      // and IF stage.  An all-stage flush keeps outputs benign during reset.
      ACTION_RESET: begin
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
      end

      // The trapping instruction commits its mepc/mcause/mtval update in the
      // CSR file at this edge. Squash all younger packets, consume MEM/WB, and
      // restart fetch at the current aligned direct-mode mtvec value.
      ACTION_WB_TRAP: begin
        if_id_flush_o  = 1'b1;
        id_ex_flush_o  = 1'b1;
        ex_mem_flush_o = 1'b1;
        mem_wb_flush_o = 1'b1;

        redirect_valid_o = 1'b1;
        redirect_pc_o    = {mtvec_i[31:2], 2'b00};
        trap_drain_d     = 1'b0;
      end

      // Let the offending MEM instruction enter MEM/WB and squash all younger
      // work, including the unaccepted combinational EX result.
      ACTION_MEM_EXCEPTION: begin
        pc_enable_o = 1'b0;

        if_id_flush_o  = 1'b1;
        id_ex_flush_o  = 1'b1;
        ex_mem_flush_o = 1'b1;

        trap_drain_d = 1'b1;
      end

      // EX/MEM remains owned by the memory instruction.  MEM/WB receives one
      // bubble after an older WB entry commits, preventing repeated retirement.
      ACTION_MEM_WAIT: begin
        pc_enable_o     = 1'b0;
        if_id_enable_o  = 1'b0;
        id_ex_enable_o  = 1'b0;
        ex_mem_enable_o = 1'b0;

        mem_wb_flush_o = 1'b1;
      end

      // Advance the offending EX packet into EX/MEM and squash both younger
      // pipeline entries before entering precise trap drain.
      ACTION_EX_EXCEPTION: begin
        pc_enable_o = 1'b0;

        if_id_flush_o = 1'b1;
        id_ex_flush_o = 1'b1;

        trap_drain_d = 1'b1;
      end

      // Hold the current ID/EX operation while MUL/DIV is running or a valid EX
      // result is backpressured. The older EX/MEM entry advances and is then
      // replaced by a bubble until EX produces an accepted result.
      ACTION_EX_WAIT: begin
        pc_enable_o    = 1'b0;
        if_id_enable_o = 1'b0;
        id_ex_enable_o = 1'b0;

        ex_mem_flush_o = 1'b1;
      end

      // No younger redirect or ID event may restart the front end while the
      // oldest known exception is moving toward architectural commit.
      ACTION_TRAP_DRAIN: begin
        pc_enable_o    = 1'b0;
        if_id_enable_o = 1'b0;
      end

      // EX redirects squash the two younger packets.  REDIRECT_FROM_ID remains
      // in the stable contract for the documented post-baseline optimization.
      ACTION_EX_REDIRECT: begin
        redirect_valid_o = 1'b1;
        redirect_pc_o    = control_redirect_i.target;
        if_id_flush_o    = 1'b1;

        unique case (control_redirect_i.origin)
          REDIRECT_FROM_ID: id_ex_flush_o = 1'b0;
          REDIRECT_FROM_EX: id_ex_flush_o = 1'b1;
          default:          id_ex_flush_o = 1'b1;
        endcase
      end

      // The faulting ID packet advances into ID/EX; only the younger fetch
      // packet is discarded before precise drain begins.
      ACTION_ID_EXCEPTION: begin
        pc_enable_o   = 1'b0;
        if_id_flush_o = 1'b1;

        trap_drain_d = 1'b1;
      end

      // Hold PC and IF/ID while injecting exactly one bubble into ID/EX.
      ACTION_ID_HAZARD: begin
        pc_enable_o    = 1'b0;
        if_id_enable_o = 1'b0;
        id_ex_flush_o  = 1'b1;
      end

      ACTION_ADVANCE: ;
      default:        ;
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      trap_drain_q <= 1'b0;
    end else begin
      trap_drain_q <= trap_drain_d;
    end
  end

endmodule
