// SPDX-License-Identifier: MIT

// RV32IM five-stage pipeline integration.
//
// This module owns the IF/ID, ID/EX, EX/MEM, and MEM/WB registers and is the
// single architectural commit point for the core. EX forwarding, ID load-use
// hazard detection, blocking RV32M execution, Zicsr commit, and precise
// machine-mode trap state are integrated here.
module rv32_core #(
  parameter logic [31:0] RESET_VECTOR = 32'h0000_0000,
  parameter logic [31:0] TRAP_VECTOR  = 32'h0000_0100
) (
  input  logic clk_i,
  input  logic rst_i,

  rv32_mem_if.master imem_m,
  rv32_mem_if.master dmem_m,

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

  import rv32_pkg::*;

  // --------------------------------------------------------------------------
  // Pipeline state and stage-next packets
  // --------------------------------------------------------------------------
  if_id_t  if_id_q;
  if_id_t  if_id_d;
  id_ex_t  id_ex_q;
  id_ex_t  id_ex_d;
  ex_mem_t ex_mem_q;
  ex_mem_t ex_mem_d;
  mem_wb_t mem_wb_q;
  mem_wb_t mem_wb_d;

  logic fetch_valid;
  word_t fetch_pc;
  word_t fetch_insn;
  exc_t  fetch_exc;
  logic  fetch_consume;

  // --------------------------------------------------------------------------
  // Central pipeline control
  // --------------------------------------------------------------------------
  logic pc_enable;
  logic if_id_enable;
  logic id_ex_enable;
  logic ex_mem_enable;
  logic mem_wb_enable;
  logic if_id_flush;
  logic id_ex_flush;
  logic ex_mem_flush;
  logic mem_wb_flush;
  logic redirect_valid;
  word_t redirect_pc;

  redirect_t control_redirect;
  logic      id_exception;
  logic      ex_exception;
  logic      mem_exception;
  logic      wb_trap;
  logic      ex_wait;
  logic      mem_wait;

  fwd_sel_e ex_fwd_a_sel;
  fwd_sel_e ex_fwd_b_sel;
  word_t    ex_mem_fwd_value;
  word_t    mem_wb_fwd_value;
  logic     load_use_hazard;
  logic     csr_dependency;

  // --------------------------------------------------------------------------
  // WB/architectural commit
  // --------------------------------------------------------------------------
  logic wb_retire;
  logic wb_reg_write;
  logic wb_csr_write;

  csr_addr_t csr_raddr;
  logic      csr_access_write;
  word_t     csr_rdata;
  logic      csr_access_illegal;
  word_t     csr_mtvec;
  word_t     csr_mepc;

  assign wb_trap      = mem_wb_q.valid && mem_wb_q.exc.valid;
  assign wb_retire    = mem_wb_q.valid && !mem_wb_q.exc.valid;
  assign wb_reg_write = wb_retire && mem_wb_q.reg_write && (mem_wb_q.rd != 5'd0);
  assign wb_csr_write = wb_retire && mem_wb_q.csr_write;

  csr_file #(
    .TRAP_VECTOR (TRAP_VECTOR)
  ) u_csr_file (
    .clk_i              (clk_i),
    .rst_i              (rst_i),
    .raddr_i            (csr_raddr),
    .access_cmd_i       (id_ex_q.ctrl.csr_cmd),
    .access_write_i     (csr_access_write),
    .rdata_o            (csr_rdata),
    .access_illegal_o   (csr_access_illegal),
    .commit_write_i     (wb_csr_write),
    .commit_waddr_i     (mem_wb_q.csr_addr),
    .commit_wdata_i     (mem_wb_q.csr_wdata),
    .retire_i           (wb_retire),
    .trap_valid_i       (wb_trap),
    .trap_pc_i          (mem_wb_q.pc),
    .trap_cause_i       (mem_wb_q.exc.cause),
    .trap_tval_i        (mem_wb_q.exc.tval),
    .mtvec_o            (csr_mtvec),
    .mepc_o             (csr_mepc)
  );

  // Retirement trace is driven only from MEM/WB.  A trap is a trace event but
  // is not a retired instruction and cannot write architectural state.
  always_comb begin
    trace_valid_o      = mem_wb_q.valid;
    trace_pc_o         = mem_wb_q.pc;
    trace_insn_o       = mem_wb_q.insn;
    trace_rd_we_o      = wb_reg_write;
    trace_rd_addr_o    = mem_wb_q.rd;
    trace_rd_data_o    = mem_wb_q.wb_data;
    trace_mem_addr_o   = mem_wb_q.mem_addr;
    trace_mem_wstrb_o  = mem_wb_q.mem_wstrb;
    trace_mem_wdata_o  = mem_wb_q.mem_wdata;
    trace_trap_o       = wb_trap;
    trace_cause_o      = wb_trap ? mem_wb_q.exc.cause : 5'b0;
    trace_control_o    = wb_retire && mem_wb_q.control;
    trace_taken_o      = wb_retire && mem_wb_q.control_taken;
    trace_target_o     = mem_wb_q.control_target;
  end

  // --------------------------------------------------------------------------
  // IF and IF/ID next packet
  // --------------------------------------------------------------------------
  assign fetch_consume = if_id_enable && !if_id_flush;

  if_stage #(
    .RESET_VECTOR (RESET_VECTOR)
  ) u_if_stage (
    .clk_i            (clk_i),
    .rst_i            (rst_i),
    .enable_i         (pc_enable),
    .consume_i        (fetch_consume),
    .flush_i          (if_id_flush),
    .redirect_valid_i (redirect_valid),
    .redirect_pc_i    (redirect_pc),
    .imem_m           (imem_m),
    .fetch_valid_o    (fetch_valid),
    .fetch_pc_o       (fetch_pc),
    .fetch_insn_o     (fetch_insn),
    .fetch_exc_o      (fetch_exc)
  );

  always_comb begin
    if_id_d       = '0;
    if_id_d.valid = fetch_valid;

    if (fetch_valid) begin
      if_id_d.pc   = fetch_pc;
      if_id_d.insn = fetch_insn;
      if_id_d.exc  = fetch_exc;
    end
  end

  // --------------------------------------------------------------------------
  // ID
  // --------------------------------------------------------------------------
  id_stage u_id_stage (
    .clk_i     (clk_i),
    .if_id_i   (if_id_q),
    .wb_we_i   (wb_reg_write),
    .wb_rd_i   (mem_wb_q.rd),
    .wb_data_i (mem_wb_q.wb_data),
    .id_ex_o   (id_ex_d)
  );

  assign id_exception = id_ex_d.valid && id_ex_d.exc.valid;

  hazard_unit u_hazard_unit (
    .id_valid_i    (id_ex_d.valid),
    .id_rs1_i      (id_ex_d.rs1),
    .id_rs2_i      (id_ex_d.rs2),
    .id_csr_addr_i (id_ex_d.insn[31:20]),
    .id_ctrl_i     (id_ex_d.ctrl),
    .id_ex_i       (id_ex_q),
    .ex_mem_i      (ex_mem_q),
    .mem_wb_i      (mem_wb_q),
    .load_use_o    (load_use_hazard),
    .csr_dep_o     (csr_dependency),
    .stall_id_o    ()
  );

  // --------------------------------------------------------------------------
  // EX
  // --------------------------------------------------------------------------
  logic        ex_result_valid;
  logic        ex_result_ready;
  logic        ex_kill;

  assign mem_wb_fwd_value = mem_wb_q.wb_data;

  forwarding_unit u_forwarding_unit (
    .id_ex_i      (id_ex_q),
    .ex_mem_i     (ex_mem_q),
    .mem_wb_i     (mem_wb_q),
    .ex_a_sel_o   (ex_fwd_a_sel),
    .ex_b_sel_o   (ex_fwd_b_sel)
  );

  always_comb begin
    unique case (ex_mem_q.wb_sel)
      WB_EX_RESULT: ex_mem_fwd_value = ex_mem_q.ex_result;
      WB_PC4:       ex_mem_fwd_value = ex_mem_q.pc + 32'd4;
      WB_CSR:       ex_mem_fwd_value = ex_mem_q.csr_old;
      default:      ex_mem_fwd_value = 32'b0;
    endcase
  end

  // An older WB trap or newly completed MEM fault wins over all EX work.  MEM
  // backpressure removes downstream readiness without killing the held ID/EX
  // packet.  This avoids a combinational loop through ex_wait/pipeline_ctrl.
  assign ex_kill         = wb_trap || mem_exception;
  assign ex_result_ready = !wb_trap && !mem_wait && !mem_exception;

  ex_stage u_ex_stage (
    .clk_i                  (clk_i),
    .rst_i                  (rst_i),
    .kill_i                 (ex_kill),
    .id_ex_i                (id_ex_q),
    .fwd_a_sel_i            (ex_fwd_a_sel),
    .fwd_b_sel_i            (ex_fwd_b_sel),
    .ex_mem_fwd_value_i     (ex_mem_fwd_value),
    .mem_wb_fwd_value_i     (mem_wb_fwd_value),
    .csr_rdata_i            (csr_rdata),
    .csr_mepc_i             (csr_mepc),
    .csr_access_illegal_i   (csr_access_illegal),
    .result_ready_i         (ex_result_ready),
    .csr_raddr_o            (csr_raddr),
    .csr_access_write_o     (csr_access_write),
    .ex_mem_o               (ex_mem_d),
    .control_redirect_o     (control_redirect),
    .result_valid_o         (ex_result_valid),
    .wait_o                 (ex_wait)
  );

  // Only faults discovered in EX are reported as new EX events.  Exceptions
  // already attached by IF/ID simply continue draining with their packet.
  assign ex_exception = ex_result_valid
                      && ex_mem_d.exc.valid
                      && !id_ex_q.exc.valid
                      && ex_result_ready;

  // --------------------------------------------------------------------------
  // MEM
  // --------------------------------------------------------------------------
  logic lsu_req_valid;
  logic lsu_rsp_valid;
  logic lsu_rsp_ready;
  word_t lsu_load_data;
  exc_t  lsu_exception;
  logic [3:0] lsu_trace_wstrb;
  word_t      lsu_trace_wdata;
  logic       mem_is_memory;

  assign mem_is_memory = ex_mem_q.valid && !ex_mem_q.exc.valid && ((ex_mem_q.mem_cmd == MEM_LOAD) || (ex_mem_q.mem_cmd == MEM_STORE));
  assign lsu_req_valid = mem_is_memory && !wb_trap;
  assign lsu_rsp_ready = mem_wb_enable && !mem_wb_flush && !wb_trap;

  lsu u_lsu (
    .clk_i             (clk_i),
    .rst_i             (rst_i),
    .kill_i            (wb_trap),
    .req_valid_i       (lsu_req_valid),
    .req_ready_o       (),
    .cmd_i             (ex_mem_q.mem_cmd),
    .size_i            (ex_mem_q.mem_size),
    .load_unsigned_i   (ex_mem_q.load_unsigned),
    .addr_i            (ex_mem_q.ex_result),
    .store_data_i      (ex_mem_q.store_data),
    .dmem_m            (dmem_m),
    .rsp_valid_o       (lsu_rsp_valid),
    .rsp_ready_i       (lsu_rsp_ready),
    .load_data_o       (lsu_load_data),
    .exception_o       (lsu_exception),
    .trace_wstrb_o     (lsu_trace_wstrb),
    .trace_wdata_o     (lsu_trace_wdata)
  );

  // A blocking memory instruction owns EX/MEM until the LSU produces a sticky
  // response.  Local misalignment faults and bus errors use the same response
  // path, so there is no special-case timing in the pipeline controller.
  assign mem_wait = mem_is_memory && !lsu_rsp_valid;

  always_comb begin
    mem_wb_d = '0;

    if (ex_mem_q.valid) begin
      // Non-memory instructions and exception packets complete combinationally
      // in MEM.  A memory packet becomes valid only with the LSU response.
      if (!mem_is_memory) begin
        mem_wb_d.valid          = 1'b1;
        mem_wb_d.pc             = ex_mem_q.pc;
        mem_wb_d.insn           = ex_mem_q.insn;
        mem_wb_d.rd             = ex_mem_q.rd;
        mem_wb_d.reg_write      = ex_mem_q.reg_write;
        mem_wb_d.csr_write      = ex_mem_q.csr_write;
        mem_wb_d.csr_addr       = ex_mem_q.csr_addr;
        mem_wb_d.csr_wdata      = ex_mem_q.csr_wdata;
        mem_wb_d.control        = ex_mem_q.control;
        mem_wb_d.control_taken  = ex_mem_q.control_taken;
        mem_wb_d.control_target = ex_mem_q.control_target;
        mem_wb_d.exc            = ex_mem_q.exc;

        unique case (ex_mem_q.wb_sel)
          WB_EX_RESULT: mem_wb_d.wb_data = ex_mem_q.ex_result;
          WB_PC4:      mem_wb_d.wb_data = ex_mem_q.pc + 32'd4;
          WB_CSR:      mem_wb_d.wb_data = ex_mem_q.csr_old;
          default:     mem_wb_d.wb_data = 32'b0;
        endcase
      end else if (lsu_rsp_valid) begin
        mem_wb_d.valid          = 1'b1;
        mem_wb_d.pc             = ex_mem_q.pc;
        mem_wb_d.insn           = ex_mem_q.insn;
        mem_wb_d.rd             = ex_mem_q.rd;
        mem_wb_d.reg_write      = ex_mem_q.reg_write;
        mem_wb_d.wb_data        = (ex_mem_q.mem_cmd == MEM_LOAD) ? lsu_load_data : 32'b0;
        mem_wb_d.mem_write      = (ex_mem_q.mem_cmd == MEM_STORE);
        mem_wb_d.mem_addr       = ex_mem_q.ex_result;
        mem_wb_d.mem_wstrb      = lsu_trace_wstrb;
        mem_wb_d.mem_wdata      = lsu_trace_wdata;
        mem_wb_d.control        = ex_mem_q.control;
        mem_wb_d.control_taken  = ex_mem_q.control_taken;
        mem_wb_d.control_target = ex_mem_q.control_target;
        mem_wb_d.exc            = lsu_exception;

        if (lsu_exception.valid) begin
          mem_wb_d.reg_write = 1'b0;
          mem_wb_d.mem_write = 1'b0;
          mem_wb_d.mem_wstrb = 4'b0000;
          mem_wb_d.mem_wdata = 32'b0;
        end
      end

      // No exception packet may carry an architectural side effect into WB.
      if (mem_wb_d.valid && mem_wb_d.exc.valid) begin
        mem_wb_d.reg_write = 1'b0;
        mem_wb_d.csr_write = 1'b0;
        mem_wb_d.mem_write = 1'b0;
      end
    end
  end

  // Only LSU-originated faults are new MEM exception events.  Older IF/ID/EX
  // faults retain their packet and advance normally during trap drain.
  assign mem_exception = mem_is_memory && lsu_rsp_valid && lsu_exception.valid;

  // --------------------------------------------------------------------------
  // Pipeline controller
  // --------------------------------------------------------------------------
  pipeline_ctrl u_pipeline_ctrl (
    .clk_i                (clk_i),
    .rst_i                (rst_i),
    .load_use_i           (load_use_hazard),
    .csr_dep_i            (csr_dependency),
    .ex_wait_i            (ex_wait),
    .mem_wait_i           (mem_wait),
    .id_exception_i       (id_exception),
    .ex_exception_i       (ex_exception),
    .mem_exception_i      (mem_exception),
    .wb_trap_i            (wb_trap),
    .control_redirect_i   (control_redirect),
    .mtvec_i              (csr_mtvec),
    .pc_enable_o          (pc_enable),
    .if_id_enable_o       (if_id_enable),
    .id_ex_enable_o       (id_ex_enable),
    .ex_mem_enable_o      (ex_mem_enable),
    .mem_wb_enable_o      (mem_wb_enable),
    .if_id_flush_o        (if_id_flush),
    .id_ex_flush_o        (id_ex_flush),
    .ex_mem_flush_o       (ex_mem_flush),
    .mem_wb_flush_o       (mem_wb_flush),
    .redirect_valid_o     (redirect_valid),
    .redirect_pc_o        (redirect_pc),
    .trap_drain_o         ()
  );

  // --------------------------------------------------------------------------
  // Pipeline registers: reset > flush > enable > hold
  // --------------------------------------------------------------------------
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      if_id_q <= '0;
    end else if (if_id_flush) begin
      if_id_q <= '0;
    end else if (if_id_enable) begin
      if_id_q <= if_id_d;
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      id_ex_q <= '0;
    end else if (id_ex_flush) begin
      id_ex_q <= '0;
    end else if (id_ex_enable) begin
      id_ex_q <= id_ex_d;
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      ex_mem_q <= '0;
    end else if (ex_mem_flush) begin
      ex_mem_q <= '0;
    end else if (ex_mem_enable) begin
      ex_mem_q <= ex_mem_d;
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      mem_wb_q <= '0;
    end else if (mem_wb_flush) begin
      mem_wb_q <= '0;
    end else if (mem_wb_enable) begin
      mem_wb_q <= mem_wb_d;
    end
  end

endmodule
