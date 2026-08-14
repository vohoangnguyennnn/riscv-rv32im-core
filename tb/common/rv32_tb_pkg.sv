// SPDX-License-Identifier: MIT

// Reusable instruction encoders for directed pipeline integration tests.
// Keeping encoders in a test-only package makes programs readable while the
// expected results remain independent of the RTL decoder implementation.
package rv32_tb_pkg;

  import rv32_pkg::*;

  localparam logic [31:0] TB_NOP = 32'h0000_0013;

  function automatic logic [31:0] enc_addi(
    input logic [4:0]  rd,
    input logic [4:0]  rs1,
    input logic [11:0] immediate
  );
    return {immediate, rs1, FUNCT3_ADD_SUB, rd, OPCODE_OP_IMM};
  endfunction

  function automatic logic [31:0] enc_add(
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input logic [4:0] rs2
  );
    return {FUNCT7_BASE, rs2, rs1, FUNCT3_ADD_SUB, rd, OPCODE_OP};
  endfunction

  function automatic logic [31:0] enc_lui(
    input logic [4:0]  rd,
    input logic [19:0] immediate
  );
    return {immediate, rd, OPCODE_LUI};
  endfunction

  function automatic logic [31:0] enc_auipc(
    input logic [4:0]  rd,
    input logic [19:0] immediate
  );
    return {immediate, rd, OPCODE_AUIPC};
  endfunction

  function automatic logic [31:0] enc_lw(
    input logic [4:0]  rd,
    input logic [4:0]  rs1,
    input logic [11:0] offset
  );
    return {offset, rs1, FUNCT3_LW, rd, OPCODE_LOAD};
  endfunction

  function automatic logic [31:0] enc_sw(
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [11:0] offset
  );
    return {
      offset[11:5],
      rs2,
      rs1,
      FUNCT3_SW,
      offset[4:0],
      OPCODE_STORE
    };
  endfunction

  function automatic logic [31:0] enc_branch(
    input logic [2:0]  funct3,
    input logic [4:0]  rs1,
    input logic [4:0]  rs2,
    input logic [12:0] offset
  );
    return {
      offset[12],
      offset[10:5],
      rs2,
      rs1,
      funct3,
      offset[4:1],
      offset[11],
      OPCODE_BRANCH
    };
  endfunction

  function automatic logic [31:0] enc_jal(
    input logic [4:0]  rd,
    input logic [20:0] offset
  );
    return {
      offset[20],
      offset[10:1],
      offset[11],
      offset[19:12],
      rd,
      OPCODE_JAL
    };
  endfunction

  function automatic logic [31:0] enc_jalr(
    input logic [4:0]  rd,
    input logic [4:0]  rs1,
    input logic [11:0] offset
  );
    return {offset, rs1, FUNCT3_JALR, rd, OPCODE_JALR};
  endfunction

  function automatic logic [31:0] enc_mdu(
    input logic [2:0] funct3,
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input logic [4:0] rs2
  );
    return {FUNCT7_M, rs2, rs1, funct3, rd, OPCODE_OP};
  endfunction

  function automatic logic [31:0] enc_csr(
    input csr_addr_t   address,
    input logic [2:0] funct3,
    input logic [4:0] rd,
    input logic [4:0] source
  );
    return {address, source, funct3, rd, OPCODE_SYSTEM};
  endfunction

endpackage
