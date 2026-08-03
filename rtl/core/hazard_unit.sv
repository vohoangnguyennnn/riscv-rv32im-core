// Combinational ID-stage hazard detector.
//
// The baseline pipeline needs one data interlock: a load in ID/EX cannot
// provide its value to the immediately following consumer.  All other GPR RAW
// dependencies are handled by EX forwarding.  CSR writes commit in WB, so a
// CSR reader in ID is serialized behind writers in ID/EX and EX/MEM.  A writer
// already in MEM/WB commits on the same edge that advances the reader to EX and
// therefore does not require another stall.
module hazard_unit (
  input  logic                         id_valid_i,
  input  logic [4:0]                   id_rs1_i,
  input  logic [4:0]                   id_rs2_i,
  input  logic [11:0]                  id_csr_addr_i,
  input  wire rv32_pkg::decode_ctrl_t  id_ctrl_i,

  input  wire rv32_pkg::id_ex_t        id_ex_i,
  input  wire rv32_pkg::ex_mem_t       ex_mem_i,
  input  wire rv32_pkg::mem_wb_t       mem_wb_i,

  output logic                         load_use_o,
  output logic                         csr_dep_o,
  output logic                         stall_id_o
);

  import rv32_pkg::*;

  logic id_ex_is_load;
  logic id_ex_csr_writer;
  logic ex_mem_csr_writer;
  logic csr_dependency;
  logic mret_dependency;
  logic minstret_dependency;

  function automatic logic raw_match(
    input logic      producer_valid,
    input logic      producer_writes,
    input reg_addr_t producer_rd,
    input logic      consumer_uses,
    input reg_addr_t consumer_rs
  );
    begin
      raw_match = producer_valid && producer_writes && (producer_rd != 5'd0) && consumer_uses && (producer_rd == consumer_rs);
    end
  endfunction

  // CSRRW and CSRRWI always write, including an x0/zimm=0 source.  Set/clear
  // forms suppress the CSR write when their register or immediate mask is 0.
  function automatic logic csr_command_writes(
    input csr_cmd_e  command,
    input reg_addr_t source
  );
    begin
      unique case (command)
        CSR_RW,
        CSR_RWI: csr_command_writes = 1'b1;

        CSR_RS,
        CSR_RC,
        CSR_RSI,
        CSR_RCI: csr_command_writes = (source != 5'd0);

        default: csr_command_writes = 1'b0;
      endcase
    end
  endfunction

  always_comb begin
    id_ex_is_load = id_ex_i.valid && !id_ex_i.exc.valid && id_ex_i.ctrl.reg_write && (id_ex_i.ctrl.mem_cmd == MEM_LOAD);

    load_use_o = 1'b0;
    if (id_valid_i) begin
      load_use_o = raw_match(
        id_ex_is_load,
        id_ex_i.ctrl.reg_write,
        id_ex_i.rd,
        id_ctrl_i.uses_rs1,
        id_rs1_i
      ) || raw_match(
        id_ex_is_load,
        id_ex_i.ctrl.reg_write,
        id_ex_i.rd,
        id_ctrl_i.uses_rs2,
        id_rs2_i
      );
    end

    id_ex_csr_writer = id_ex_i.valid && !id_ex_i.exc.valid && csr_command_writes(id_ex_i.ctrl.csr_cmd, id_ex_i.rs1);

    ex_mem_csr_writer = ex_mem_i.valid && !ex_mem_i.exc.valid && ex_mem_i.csr_write;

    // Baseline CSR serialization is intentionally conservative: any older
    // uncommitted CSR write stalls a CSR instruction in ID, regardless of CSR
    // address.  This avoids a second address-compare path in decode.
    csr_dependency = id_valid_i && (id_ctrl_i.csr_cmd != CSR_NONE) && (id_ex_csr_writer || ex_mem_csr_writer);

    // MRET reads only mepc.  Unlike a general CSR instruction, it needs to
    // wait only for an older writer targeting that exact CSR.
    mret_dependency = id_valid_i && id_ctrl_i.is_mret && ((id_ex_csr_writer && (id_ex_i.insn[31:20] == CSR_MEPC)) || (ex_mem_csr_writer && (ex_mem_i.csr_addr == CSR_MEPC)));

    // minstret changes implicitly when every older non-trapping instruction
    // commits. Drain ID/EX and EX/MEM before reading either RV32 half so the
    // explicit CSR read observes all preceding retirements in program order.
    minstret_dependency = id_valid_i
                        && (id_ctrl_i.csr_cmd != CSR_NONE)
                        && ((id_csr_addr_i == CSR_MINSTRET) || (id_csr_addr_i == CSR_MINSTRETH))
                        && ((id_ex_i.valid && !id_ex_i.exc.valid) || (ex_mem_i.valid && !ex_mem_i.exc.valid));

    csr_dep_o  = csr_dependency || mret_dependency || minstret_dependency;
    stall_id_o = load_use_o || csr_dep_o;
  end

  // mem_wb_i is part of the stable hazard-unit contract so the commit-stage
  // timing is explicit at this boundary.  It is intentionally not interlocked:
  // MEM/WB CSR writes become visible before the held ID instruction reads the
  // CSR file in its following EX cycle.

endmodule
