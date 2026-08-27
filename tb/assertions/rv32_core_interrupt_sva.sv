// Precise machine-timer interrupt invariants at the ID/EX acceptance boundary.
// This checker deliberately distinguishes a combinational interrupt candidate
// from a packet accepted by the pipeline controller: an older wait, exception,
// or redirect is allowed to reject the candidate and retry the level later.
module rv32_core_interrupt_sva (
  input logic        clk_i,
  input logic        rst_i,
  input logic        interrupt_candidate_i,
  input logic        interrupt_event_i,
  input logic        interrupt_accept_i,
  input logic        irq_eligible_i,
  input logic        irq_eligible_before_commit_i,
  input logic        irq_eligible_after_commit_i,
  input logic        mem_wb_irq_state_writer_i,
  input logic        irq_state_ambiguous_i,
  input logic        trap_drain_i,
  input logic        candidate_valid_i,
  input logic        candidate_exc_valid_i,
  input logic [31:0] candidate_pc_i,
  input logic        id_ex_valid_i,
  input logic [31:0] id_ex_pc_i,
  input logic [31:0] id_ex_insn_i,
  input logic        id_ex_exc_valid_i,
  input logic        id_ex_exc_interrupt_i,
  input logic [4:0]  id_ex_exc_cause_i,
  input logic [31:0] id_ex_exc_tval_i,
  input logic        id_ex_ctrl_zero_i
);

  default clocking cb @(posedge clk_i);
  endclocking

  property p_candidate_requires_effective_eligibility;
    disable iff (rst_i)
    interrupt_candidate_i |-> irq_eligible_i
                              && !irq_state_ambiguous_i
                              && !trap_drain_i;
  endproperty

  property p_enable_commit_builds_immediate_candidate;
    disable iff (rst_i)
    mem_wb_irq_state_writer_i
      && !irq_eligible_before_commit_i
      && irq_eligible_after_commit_i
      && candidate_valid_i
      && !candidate_exc_valid_i
      && !irq_state_ambiguous_i
      && !trap_drain_i
        |-> interrupt_candidate_i;
  endproperty

  property p_interrupt_event_originates_from_candidate;
    disable iff (rst_i)
    interrupt_event_i |-> interrupt_candidate_i;
  endproperty

  property p_accepted_interrupt_builds_precise_packet;
    disable iff (rst_i)
    interrupt_accept_i |=> id_ex_valid_i
                          && id_ex_exc_valid_i
                          && id_ex_exc_interrupt_i
                          && (id_ex_exc_cause_i == 5'd7)
                          && (id_ex_exc_tval_i == 32'b0)
                          && (id_ex_pc_i == $past(candidate_pc_i))
                          && (id_ex_insn_i == 32'b0)
                          && id_ex_ctrl_zero_i;
  endproperty

  a_candidate_requires_effective_eligibility: assert property (
    p_candidate_requires_effective_eligibility
  ) else $error("timer interrupt candidate bypassed effective eligibility");

  a_enable_commit_builds_immediate_candidate: assert property (
    p_enable_commit_builds_immediate_candidate
  ) else $error("pending timer interrupt was delayed past an enabling commit");

  a_interrupt_event_originates_from_candidate: assert property (
    p_interrupt_event_originates_from_candidate
  ) else $error("ID interrupt event was not created by timer arbitration");

  a_accepted_interrupt_builds_precise_packet: assert property (
    p_accepted_interrupt_builds_precise_packet
  ) else $error("accepted timer interrupt did not create a side-effect-free precise packet");

  c_interrupt_candidate: cover property (
    disable iff (rst_i) interrupt_candidate_i
  );

  c_interrupt_accepted: cover property (
    disable iff (rst_i) interrupt_accept_i
  );

  c_interrupt_candidate_rejected: cover property (
    disable iff (rst_i) interrupt_candidate_i && !interrupt_accept_i
  );

  c_enable_commit_interrupt: cover property (
    disable iff (rst_i)
    mem_wb_irq_state_writer_i
      && !irq_eligible_before_commit_i
      && irq_eligible_after_commit_i
      && interrupt_candidate_i
  );

endmodule
