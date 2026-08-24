// Combinational ID-stage hazard detector.
//
// A load in ID/EX cannot forward to its immediate consumer; all other GPR RAW
// dependencies use EX forwarding. CSR readers also wait for conflicting
// writers in ID/EX or EX/MEM. A MEM/WB writer commits before the reader reaches
// EX, so it requires no additional stall.
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

  // CSRRW[I] always writes; CSRRS/RC[I] suppress writes for a zero mask.
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

  // Low/high counter CSRs alias one 64-bit state: writing either half suppresses
  // that edge's implicit update and may affect the other half across a carry.
  // Other implemented CSRs conflict only on an exact address match.
  function automatic logic csr_addresses_conflict(
    input csr_addr_t consumer,
    input csr_addr_t producer
  );
    begin
      unique case (consumer)
        CSR_MCYCLE,
        CSR_MCYCLEH: begin
          csr_addresses_conflict = (producer == CSR_MCYCLE) || (producer == CSR_MCYCLEH);
        end

        CSR_MINSTRET,
        CSR_MINSTRETH: begin
          csr_addresses_conflict = (producer == CSR_MINSTRET) || (producer == CSR_MINSTRETH);
        end

        default: csr_addresses_conflict = (consumer == producer);
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

    // Stall only for an older writer to the same CSR state, avoiding false
    // dependencies without weakening RAW ordering.
    csr_dependency = id_valid_i && (id_ctrl_i.csr_cmd != CSR_NONE) && ((id_ex_csr_writer && csr_addresses_conflict(id_csr_addr_i, id_ex_i.insn[31:20]))
                       || (ex_mem_csr_writer
                           && csr_addresses_conflict(id_csr_addr_i, ex_mem_i.csr_addr)));

    // MRET reads only mepc and waits only for an older mepc writer.
    mret_dependency = id_valid_i && id_ctrl_i.is_mret && ((id_ex_csr_writer && (id_ex_i.insn[31:20] == CSR_MEPC)) || (ex_mem_csr_writer && (ex_mem_i.csr_addr == CSR_MEPC)));

    // Drain older stages before reading minstret[h], so all preceding
    // retirements are visible in program order.
    minstret_dependency = id_valid_i && (id_ctrl_i.csr_cmd != CSR_NONE) && ((id_csr_addr_i == CSR_MINSTRET) || (id_csr_addr_i == CSR_MINSTRETH))
                        && ((id_ex_i.valid && !id_ex_i.exc.valid) || (ex_mem_i.valid && !ex_mem_i.exc.valid));

    csr_dep_o  = csr_dependency || mret_dependency || minstret_dependency;
    stall_id_o = load_use_o || csr_dep_o;
  end

  // MEM/WB is intentionally not interlocked: its CSR write becomes visible
  // before the held ID instruction reads that CSR in EX.

endmodule
