// Combinational EX-stage forwarding selector.
//
// The youngest available producer wins independently for each source operand:
// EX/MEM has priority over MEM/WB.  EX/MEM loads are deliberately excluded
// because their data is not available until the MEM response reaches MEM/WB.
// Pipeline packets carrying exceptions never participate in forwarding.
module forwarding_unit (
  input  wire rv32_pkg::id_ex_t   id_ex_i,
  input  wire rv32_pkg::ex_mem_t  ex_mem_i,
  input  wire rv32_pkg::mem_wb_t  mem_wb_i,

  output rv32_pkg::fwd_sel_e      ex_a_sel_o,
  output rv32_pkg::fwd_sel_e      ex_b_sel_o
);

  import rv32_pkg::*;

  logic consumer_valid;
  logic ex_mem_value_ready;
  logic mem_wb_value_ready;

  function automatic logic source_matches(
    input logic      producer_ready,
    input reg_addr_t producer_rd,
    input logic      consumer_uses,
    input reg_addr_t consumer_rs
  );
    begin
      source_matches = producer_ready && consumer_uses && (producer_rd == consumer_rs);
    end
  endfunction

  always_comb begin
    consumer_valid = id_ex_i.valid && !id_ex_i.exc.valid;

    // ALU/MDU results, PC+4, and the old CSR value are available from EX/MEM.
    // A load result is available only after memory completes in MEM/WB.
    ex_mem_value_ready = ex_mem_i.valid && ex_mem_i.reg_write && !ex_mem_i.exc.valid && (ex_mem_i.rd != 5'd0) && (ex_mem_i.wb_sel != WB_LOAD);

    // MEM/WB wb_data is already the final architectural writeback value, including completed loads.
    mem_wb_value_ready = mem_wb_i.valid && mem_wb_i.reg_write && !mem_wb_i.exc.valid && (mem_wb_i.rd != 5'd0);

    ex_a_sel_o = FWD_REGFILE;
    ex_b_sel_o = FWD_REGFILE;

    if (consumer_valid) begin
      if (source_matches(ex_mem_value_ready, ex_mem_i.rd, id_ex_i.ctrl.uses_rs1, id_ex_i.rs1)) begin
        ex_a_sel_o = FWD_EX_MEM;
      end else if (source_matches(mem_wb_value_ready, mem_wb_i.rd, id_ex_i.ctrl.uses_rs1, id_ex_i.rs1)) begin
        ex_a_sel_o = FWD_MEM_WB;
      end

      if (source_matches(ex_mem_value_ready, ex_mem_i.rd, id_ex_i.ctrl.uses_rs2, id_ex_i.rs2)) begin
        ex_b_sel_o = FWD_EX_MEM;
      end else if (source_matches( mem_wb_value_ready, mem_wb_i.rd, id_ex_i.ctrl.uses_rs2, id_ex_i.rs2)) begin
        ex_b_sel_o = FWD_MEM_WB;
      end
    end
  end

endmodule
