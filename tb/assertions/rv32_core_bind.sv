
// Keep assertion binding in verification space. Any simulation that compiles
// this file checks both core memory ports and the architectural commit point.
bind rv32_core rv32_mem_protocol_sva #(
  .PORT_ID (0)
) u_imem_protocol_sva (
  .clk_i        (clk_i),
  .rst_i        (rst_i),
  .req_valid_i  (imem_m.req_valid),
  .req_ready_i  (imem_m.req_ready),
  .req_addr_i   (imem_m.req_addr),
  .req_write_i  (imem_m.req_write),
  .req_wdata_i  (imem_m.req_wdata),
  .req_wstrb_i  (imem_m.req_wstrb),
  .rsp_valid_i  (imem_m.rsp_valid)
);

bind rv32_core rv32_mem_protocol_sva #(
  .PORT_ID (1)
) u_dmem_protocol_sva (
  .clk_i        (clk_i),
  .rst_i        (rst_i),
  .req_valid_i  (dmem_m.req_valid),
  .req_ready_i  (dmem_m.req_ready),
  .req_addr_i   (dmem_m.req_addr),
  .req_write_i  (dmem_m.req_write),
  .req_wdata_i  (dmem_m.req_wdata),
  .req_wstrb_i  (dmem_m.req_wstrb),
  .rsp_valid_i  (dmem_m.rsp_valid)
);

bind rv32_core rv32_core_retirement_sva u_retirement_sva (
  .clk_i                 (clk_i),
  .rst_i                 (rst_i),
  .trace_valid_i         (trace_valid_o),
  .trace_pc_i            (trace_pc_o),
  .trace_rd_we_i         (trace_rd_we_o),
  .trace_rd_addr_i       (trace_rd_addr_o),
  .trace_mem_wstrb_i     (trace_mem_wstrb_o),
  .trace_trap_i          (trace_trap_o),
  .trace_cause_i         (trace_cause_o),
  .trace_is_interrupt_i  (trace_is_interrupt_o),
  .trace_control_i       (trace_control_o),
  .trace_taken_i         (trace_taken_o),
  .commit_slot_enable_i  (mem_wb_enable),
  .commit_slot_flush_i   (mem_wb_flush)
);

bind rv32_core rv32_core_interrupt_sva u_interrupt_sva (
  .clk_i                    (clk_i),
  .rst_i                    (rst_i),
  .interrupt_candidate_i    (id_interrupt_candidate),
  .interrupt_event_i        (id_interrupt),
  .interrupt_accept_i       (id_interrupt && id_ex_enable && !id_ex_flush),
  .irq_eligible_i           (mtimer_irq_eligible),
  .irq_eligible_before_commit_i(csr_mtimer_irq_eligible),
  .irq_eligible_after_commit_i(csr_mtimer_irq_eligible_after_commit),
  .mem_wb_irq_state_writer_i(mem_wb_irq_state_writer),
  .irq_state_ambiguous_i    (irq_state_ambiguous),
  .trap_drain_i             (trap_drain),
  .candidate_valid_i        (id_ex_decoded.valid),
  .candidate_exc_valid_i    (id_ex_decoded.exc.valid),
  .candidate_pc_i           (id_ex_decoded.pc),
  .id_ex_valid_i            (id_ex_q.valid),
  .id_ex_pc_i               (id_ex_q.pc),
  .id_ex_insn_i             (id_ex_q.insn),
  .id_ex_exc_valid_i        (id_ex_q.exc.valid),
  .id_ex_exc_interrupt_i    (id_ex_q.exc.is_interrupt),
  .id_ex_exc_cause_i        (id_ex_q.exc.cause),
  .id_ex_exc_tval_i         (id_ex_q.exc.tval),
  .id_ex_ctrl_zero_i        (id_ex_q.ctrl == '0)
);
