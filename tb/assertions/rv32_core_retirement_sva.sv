
// Architectural commit invariants checked at the public retirement boundary.
module rv32_core_retirement_sva (
  input logic        clk_i,
  input logic        rst_i,
  input logic        trace_valid_i,
  input logic [31:0] trace_pc_i,
  input logic        trace_rd_we_i,
  input logic [4:0]  trace_rd_addr_i,
  input logic [3:0]  trace_mem_wstrb_i,
  input logic        trace_trap_i,
  input logic [4:0]  trace_cause_i,
  input logic        trace_is_interrupt_i,
  input logic        trace_control_i,
  input logic        trace_taken_i,
  input logic        commit_slot_enable_i,
  input logic        commit_slot_flush_i
);

  property p_commit_slot_never_retires_while_held;
    @(posedge clk_i)
    disable iff (rst_i)
    trace_valid_i |-> commit_slot_enable_i || commit_slot_flush_i;
  endproperty

  property p_trap_has_no_side_effect;
    @(posedge clk_i)
    disable iff (rst_i)
    trace_trap_i |-> trace_valid_i && !trace_rd_we_i && (trace_mem_wstrb_i == 4'b0000);
  endproperty

  property p_gpr_write_is_legal_retirement;
    @(posedge clk_i)
    disable iff (rst_i)
    trace_rd_we_i |-> trace_valid_i && !trace_trap_i && (trace_rd_addr_i != 5'd0);
  endproperty

  property p_store_is_legal_retirement;
    @(posedge clk_i)
    disable iff (rst_i)
    (trace_mem_wstrb_i != 4'b0000) |-> trace_valid_i && !trace_trap_i;
  endproperty

  property p_invalid_slot_has_no_event;
    @(posedge clk_i)
    disable iff (rst_i)
    !trace_valid_i |-> !trace_rd_we_i
                      && (trace_mem_wstrb_i == 4'b0000)
                      && !trace_trap_i
                      && !trace_control_i
                      && !trace_taken_i;
  endproperty

  property p_nontrap_cause_is_zero;
    @(posedge clk_i)
    disable iff (rst_i)
    trace_valid_i && !trace_trap_i |-> (trace_cause_i == 5'b0);
  endproperty

  property p_control_metadata_is_consistent;
    @(posedge clk_i)
    disable iff (rst_i)
    trace_taken_i |-> trace_valid_i && trace_control_i && !trace_trap_i;
  endproperty

  property p_retirement_pc_is_aligned;
    @(posedge clk_i)
    disable iff (rst_i)
    trace_valid_i |-> (trace_pc_i[1:0] == 2'b00);
  endproperty

  a_commit_slot_never_retires_while_held: assert property (
    p_commit_slot_never_retires_while_held
  ) else $error("valid MEM/WB packet was held and could retire more than once");

  a_trap_has_no_side_effect: assert property (p_trap_has_no_side_effect)
    else $error("trap retirement carried an architectural side effect");

  a_gpr_write_is_legal_retirement: assert property (p_gpr_write_is_legal_retirement)
    else $error("illegal GPR write appeared on the retirement trace");

  a_store_is_legal_retirement: assert property (p_store_is_legal_retirement)
    else $error("store side effect appeared outside a legal retirement");

  a_invalid_slot_has_no_event: assert property (p_invalid_slot_has_no_event)
    else $error("invalid retirement slot carried event metadata");

  a_nontrap_cause_is_zero: assert property (p_nontrap_cause_is_zero)
    else $error("non-trapping retirement carried a nonzero exception cause");

  a_control_metadata_is_consistent: assert property (p_control_metadata_is_consistent)
    else $error("taken-control metadata appeared outside control retirement");

  a_retirement_pc_is_aligned: assert property (p_retirement_pc_is_aligned)
    else $error("retirement PC violated RV32 IALIGN=32");

  c_retirement: cover property (
    @(posedge clk_i) disable iff (rst_i) trace_valid_i && !trace_trap_i
  );

  c_trap: cover property (
    @(posedge clk_i) disable iff (rst_i) trace_valid_i && trace_trap_i
  );

  c_store_retirement: cover property (
    @(posedge clk_i) disable iff (rst_i)
    trace_valid_i && (trace_mem_wstrb_i != 4'b0000)
  );

  c_taken_control_retirement: cover property (
    @(posedge clk_i) disable iff (rst_i) trace_valid_i && trace_taken_i
  );

endmodule
