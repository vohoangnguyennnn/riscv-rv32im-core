
// Centralized control for the RV32IM five-stage pipeline.
//
// Emits enable/flush/redirect decisions; storage remains in rv32_core. Action
// priority follows instruction age, so younger events cannot override older
// traps, faults, or waits.
module pipeline_ctrl (
  input  logic                       clk_i,
  input  logic                       rst_i,

  input  logic                       load_use_i,
  input  logic                       csr_dep_i,
  input  logic                       irq_state_wait_i,
  input  logic                       ex_wait_i,
  input  logic                       mem_wait_i,
  input  logic                       id_exception_i,
  input  logic                       id_interrupt_i,
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
    ACTION_IRQ_STATE_WAIT,
    ACTION_ID_EXCEPTION,
    ACTION_ID_INTERRUPT,
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

  // Source order, not enum value, defines architectural age priority.
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
    end else if (irq_state_wait_i) begin
      action = ACTION_IRQ_STATE_WAIT;
    end else if (id_exception_i) begin
      action = ACTION_ID_EXCEPTION;
    end else if (id_interrupt_i) begin
      action = ACTION_ID_INTERRUPT;
    end else if (id_hazard) begin
      action = ACTION_ID_HAZARD;
    end
  end

  always_comb begin
    // Flush outranks enable in the pipeline registers, so advance is the base.
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
      // All-stage flush keeps controller outputs benign during reset.
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

      // Commit trap state, squash younger packets, and restart at direct mtvec.
      ACTION_WB_TRAP: begin
        if_id_flush_o  = 1'b1;
        id_ex_flush_o  = 1'b1;
        ex_mem_flush_o = 1'b1;
        mem_wb_flush_o = 1'b1;

        redirect_valid_o = 1'b1;
        redirect_pc_o    = {mtvec_i[31:2], 2'b00};
        trap_drain_d     = 1'b0;
      end

      // Advance the MEM offender and squash all younger work.
      ACTION_MEM_EXCEPTION: begin
        pc_enable_o = 1'b0;

        if_id_flush_o  = 1'b1;
        id_ex_flush_o  = 1'b1;
        ex_mem_flush_o = 1'b1;

        trap_drain_d = 1'b1;
      end

      // Hold EX/MEM ownership; bubble MEM/WB to prevent repeated retirement.
      ACTION_MEM_WAIT: begin
        pc_enable_o     = 1'b0;
        if_id_enable_o  = 1'b0;
        id_ex_enable_o  = 1'b0;
        ex_mem_enable_o = 1'b0;

        mem_wb_flush_o = 1'b1;
      end

      // Advance the EX offender, squash younger packets, then enter drain.
      ACTION_EX_EXCEPTION: begin
        pc_enable_o = 1'b0;

        if_id_flush_o = 1'b1;
        id_ex_flush_o = 1'b1;

        trap_drain_d = 1'b1;
      end

      // Hold ID/EX while EX is busy/backpressured; bubble the vacated EX/MEM.
      ACTION_EX_WAIT: begin
        pc_enable_o    = 1'b0;
        if_id_enable_o = 1'b0;
        id_ex_enable_o = 1'b0;

        ex_mem_flush_o = 1'b1;
      end

      // Block younger front-end events until the selected trap commits.
      ACTION_TRAP_DRAIN: begin
        pc_enable_o    = 1'b0;
        if_id_enable_o = 1'b0;
      end

      // EX redirects squash the two younger packets.
      ACTION_EX_REDIRECT: begin
        redirect_valid_o = 1'b1;
        redirect_pc_o    = control_redirect_i.target;
        if_id_flush_o    = 1'b1;
        id_ex_flush_o    = 1'b1;
      end

      // ID exceptions and interrupts move identically, but distinct actions
      // preserve arbitration visibility in waveforms.
      ACTION_ID_EXCEPTION,
      ACTION_ID_INTERRUPT: begin
        pc_enable_o   = 1'b0;
        if_id_flush_o = 1'b1;

        trap_drain_d = 1'b1;
      end

      // Hold ID behind older mstatus/mie/MRET state until post-commit
      // interrupt eligibility is known.
      ACTION_IRQ_STATE_WAIT,

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
