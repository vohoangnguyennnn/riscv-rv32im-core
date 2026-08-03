// SPDX-License-Identifier: MIT

// Minimal machine-mode CSR state for the RV32IM core.
//
// CSR reads and legality checks are combinational so EX can either build the
// read-modify-write result or raise an illegal-instruction exception. State is
// changed only at architectural commit in WB. Synchronous traps have priority
// over normal CSR writes, while mcycle advances on every non-reset clock and
// minstret advances exactly once for each non-trapping retired instruction.
module csr_file #(
  parameter logic [31:0] TRAP_VECTOR = 32'h0000_0100
) (
  input  logic                    clk_i,
  input  logic                    rst_i,

  input  logic [11:0]             raddr_i,
  input  rv32_pkg::csr_cmd_e      access_cmd_i,
  // Required for CSRRS/CSRRC and their immediate forms: source zero turns the
  // operation into a read and therefore permits access to a read-only CSR.
  input  logic                    access_write_i,
  output logic [31:0]             rdata_o,
  output logic                    access_illegal_o,

  input  logic                    commit_write_i,
  input  logic [11:0]             commit_waddr_i,
  input  logic [31:0]             commit_wdata_i,
  input  logic                    retire_i,

  input  logic                    trap_valid_i,
  input  logic [31:0]             trap_pc_i,
  input  logic [4:0]              trap_cause_i,
  input  logic [31:0]             trap_tval_i,

  output logic [31:0]             mtvec_o,
  output logic [31:0]             mepc_o
);

  import rv32_pkg::*;

  word_t       mtvec_q;
  word_t       mtvec_d;
  word_t       mscratch_q;
  word_t       mscratch_d;
  word_t       mepc_q;
  word_t       mepc_d;
  word_t       mcause_q;
  word_t       mcause_d;
  word_t       mtval_q;
  word_t       mtval_d;
  logic [63:0] mcycle_q;
  logic [63:0] mcycle_d;
  logic [63:0] minstret_q;
  logic [63:0] minstret_d;

  logic access_implemented;
  logic access_writable;
  logic access_cmd_legal;
  logic access_writes;

  assign mtvec_o = mtvec_q;
  assign mepc_o  = mepc_q;

  // The command identifies mandatory writes (CSRRW/CSRRWI). For set/clear
  // forms, access_write_i carries the source-nonzero decision made by decode.
  always_comb begin
    access_cmd_legal = 1'b1;
    access_writes    = 1'b0;

    unique case (access_cmd_i)
      CSR_NONE: ;
      CSR_RW,
      CSR_RWI: access_writes = 1'b1;
      CSR_RS,
      CSR_RC,
      CSR_RSI,
      CSR_RCI: access_writes = access_write_i;
      default: begin
        access_cmd_legal = 1'b0;
        access_writes    = 1'b0;
      end
    endcase
  end

  // Read data and access attributes share one decode table so an implemented
  // CSR cannot accidentally be readable through one path but illegal through
  // the other. All identification CSRs intentionally read as zero.
  always_comb begin
    rdata_o           = 32'b0;
    access_implemented = 1'b1;
    access_writable    = 1'b0;

    unique case (raddr_i)
      CSR_MISA: begin
        rdata_o = MISA_RV32IM;
      end

      CSR_MTVEC: begin
        rdata_o        = mtvec_q;
        access_writable = 1'b1;
      end

      CSR_MSCRATCH: begin
        rdata_o        = mscratch_q;
        access_writable = 1'b1;
      end

      CSR_MEPC: begin
        rdata_o        = mepc_q;
        access_writable = 1'b1;
      end

      CSR_MCAUSE: begin
        rdata_o        = mcause_q;
        access_writable = 1'b1;
      end

      CSR_MTVAL: begin
        rdata_o        = mtval_q;
        access_writable = 1'b1;
      end

      CSR_MCYCLE: begin
        rdata_o        = mcycle_q[31:0];
        access_writable = 1'b1;
      end

      CSR_MCYCLEH: begin
        rdata_o        = mcycle_q[63:32];
        access_writable = 1'b1;
      end

      CSR_MINSTRET: begin
        rdata_o        = minstret_q[31:0];
        access_writable = 1'b1;
      end

      CSR_MINSTRETH: begin
        rdata_o        = minstret_q[63:32];
        access_writable = 1'b1;
      end

      CSR_MVENDORID,
      CSR_MARCHID,
      CSR_MIMPID,
      CSR_MHARTID: begin
        rdata_o = 32'b0;
      end

      default: begin
        rdata_o            = 32'b0;
        access_implemented = 1'b0;
        access_writable    = 1'b0;
      end
    endcase

    access_illegal_o = 1'b0;

    if (access_cmd_i != CSR_NONE) begin
      access_illegal_o = !access_cmd_legal || !access_implemented || (access_writes && !access_writable);
    end
  end

  always_comb begin
    mtvec_d    = mtvec_q;
    mscratch_d = mscratch_q;
    mepc_d     = mepc_q;
    mcause_d   = mcause_q;
    mtval_d    = mtval_q;

    // Counter updates are expressed as 64-bit operations so low/high carry is
    // natural. An explicit write to either RV32 half suppresses the implicit
    // update of that underlying 64-bit counter at the same edge.
    mcycle_d   = mcycle_q + 64'd1;
    minstret_d = minstret_q;

    if (retire_i && !trap_valid_i) begin
      minstret_d = minstret_q + 64'd1;
    end

    // A trapping packet cannot simultaneously perform a normal CSR commit.
    // Giving trap entry explicit priority also makes that invariant fail-safe.
    if (trap_valid_i) begin
      mepc_d   = trap_pc_i & 32'hffff_fffc;
      mcause_d = {27'b0, trap_cause_i};
      mtval_d  = trap_tval_i;
    end else if (commit_write_i) begin
      // An explicit counter write replaces the implicit update caused by the
      // same instruction/cycle. RV32 writes still modify only the addressed
      // low or high half of the underlying 64-bit counter.
      if ((commit_waddr_i == CSR_MCYCLE) || (commit_waddr_i == CSR_MCYCLEH)) begin
        mcycle_d = mcycle_q;
      end

      if ((commit_waddr_i == CSR_MINSTRET) || (commit_waddr_i == CSR_MINSTRETH)) begin
        minstret_d = minstret_q;
      end

      unique case (commit_waddr_i)
        CSR_MTVEC: begin
          // Only Direct mode is implemented in this milestone.
          mtvec_d = {commit_wdata_i[31:2], 2'b00};
        end

        CSR_MSCRATCH: mscratch_d = commit_wdata_i;
        CSR_MEPC:     mepc_d     = {commit_wdata_i[31:2], 2'b00};
        CSR_MCAUSE:   mcause_d   = {27'b0, commit_wdata_i[4:0]};
        CSR_MTVAL:    mtval_d    = commit_wdata_i;
        CSR_MCYCLE:   mcycle_d[31:0]   = commit_wdata_i;
        CSR_MCYCLEH:  mcycle_d[63:32]  = commit_wdata_i;
        CSR_MINSTRET: minstret_d[31:0] = commit_wdata_i;
        CSR_MINSTRETH: minstret_d[63:32] = commit_wdata_i;
        default: ; // Read-only or unimplemented writes are ignored defensively.
      endcase
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      mtvec_q    <= {TRAP_VECTOR[31:2], 2'b00};
      mscratch_q <= 32'b0;
      mepc_q     <= 32'b0;
      mcause_q   <= 32'b0;
      mtval_q    <= 32'b0;
      mcycle_q   <= 64'b0;
      minstret_q <= 64'b0;
    end else begin
      mtvec_q    <= mtvec_d;
      mscratch_q <= mscratch_d;
      mepc_q     <= mepc_d;
      mcause_q   <= mcause_d;
      mtval_q    <= mtval_d;
      mcycle_q   <= mcycle_d;
      minstret_q <= minstret_d;
    end
  end

endmodule
