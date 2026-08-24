
// Machine-mode CSR state for the RV32IM core.
//
// Reads/legality are combinational; all state changes occur at WB commit.
// Trap entry outranks MRET and normal writes. Counters update from cycle and
// non-trapping retirement events.
module csr_file #(
  parameter logic [31:0] TRAP_VECTOR = 32'h0000_0100
) (
  input  logic                    clk_i,
  input  logic                    rst_i,

  input  logic [11:0]             raddr_i,
  input  rv32_pkg::csr_cmd_e      access_cmd_i,
  // Source-zero set/clear commands are reads and may access read-only CSRs.
  input  logic                    access_write_i,
  output logic [31:0]             rdata_o,
  output logic                    access_illegal_o,

  input  logic                    commit_write_i,
  input  logic [11:0]             commit_waddr_i,
  input  logic [31:0]             commit_wdata_i,
  input  logic                    retire_i,
  input  logic                    mret_commit_i,

  input  logic                    trap_valid_i,
  input  logic [31:0]             trap_pc_i,
  input  logic                    trap_is_interrupt_i,
  input  logic [4:0]              trap_cause_i,
  input  logic [31:0]             trap_tval_i,

  // Live, read-only mip.MTIP; software clears it through mtimecmp.
  input  logic                    mtip_i,

  output logic [31:0]             mtvec_o,
  output logic [31:0]             mepc_o,
  output logic                    mtimer_irq_eligible_o,
  output logic                    mtimer_irq_eligible_after_commit_o
);

  import rv32_pkg::*;

  word_t       mstatus_q;
  word_t       mstatus_d;
  word_t       mie_q;
  word_t       mie_d;
  word_t       mip_value;
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

  assign mtvec_o   = mtvec_q;
  assign mepc_o    = mepc_q;
  assign mip_value = mtip_i ? MIP_MTIP_MASK : 32'b0;

  // Eligibility is architectural state only; precise take/injection remains
  // owned by the core's single pipeline-control authority.
  assign mtimer_irq_eligible_o = mip_value[MINT_MTIP_BIT] && mie_q[MINT_MTIP_BIT] && mstatus_q[MSTATUS_MIE_BIT];

  // Expose prioritized next state for exact post-CSR/MRET reevaluation without
  // duplicating WARL or trap/MRET priority logic in the core.
  assign mtimer_irq_eligible_after_commit_o = mip_value[MINT_MTIP_BIT] && mie_d[MINT_MTIP_BIT] && mstatus_d[MSTATUS_MIE_BIT];

  // access_write_i carries the source-nonzero decision for set/clear commands.
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

  // One table owns read data and access attributes to keep legality coherent.
  always_comb begin
    rdata_o           = 32'b0;
    access_implemented = 1'b1;
    access_writable    = 1'b0;

    unique case (raddr_i)
      CSR_MSTATUS: begin
        rdata_o         = mstatus_q;
        access_writable = 1'b1;
      end

      CSR_MISA: begin
        rdata_o = MISA_RV32IM;
      end

      CSR_MIE: begin
        rdata_o         = mie_q;
        access_writable = 1'b1;
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

      CSR_MIP: begin
        rdata_o = mip_value;
        // mip writes are legal but all implemented bits are read-only.
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
      CSR_MHARTID,
      CSR_MCONFIGPTR: begin
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
    mstatus_d = mstatus_q;
    mie_d     = mie_q;
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

    // Architectural priority: trap entry > MRET > normal CSR write.
    if (trap_valid_i) begin
      mepc_d   = trap_pc_i & 32'hffff_fffc;
      mcause_d = (trap_is_interrupt_i ? MCAUSE_INTERRUPT_MASK : 32'b0) | {27'b0, trap_cause_i};
      mtval_d  = trap_tval_i;

      // Save/disable global interrupts; MPP remains hardwired to M.
      mstatus_d[MSTATUS_MPIE_BIT] = mstatus_q[MSTATUS_MIE_BIT];
      mstatus_d[MSTATUS_MIE_BIT]  = 1'b0;
      mstatus_d[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] = 2'b11;
    end else if (mret_commit_i) begin
      // Restore the interrupt stack only at commit; EX owns the PC redirect.
      mstatus_d[MSTATUS_MIE_BIT]  = mstatus_q[MSTATUS_MPIE_BIT];
      mstatus_d[MSTATUS_MPIE_BIT] = 1'b1;
      mstatus_d[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] = 2'b11;
    end else if (commit_write_i) begin
      // Explicit counter writes suppress that cycle's implicit update while
      // modifying only the addressed RV32 half.
      if ((commit_waddr_i == CSR_MCYCLE) || (commit_waddr_i == CSR_MCYCLEH)) begin
        mcycle_d = mcycle_q;
      end

      if ((commit_waddr_i == CSR_MINSTRET) || (commit_waddr_i == CSR_MINSTRETH)) begin
        minstret_d = minstret_q;
      end

      unique case (commit_waddr_i)
        CSR_MSTATUS: begin
          // Unsupported fields are RO0; MPP is WARL=M.
          mstatus_d = MSTATUS_MPP_M_VALUE | (commit_wdata_i & MSTATUS_WRITABLE_MASK);
        end

        CSR_MIE: begin
          // Only MTIE is implemented; MSIE/MEIE remain RO0.
          mie_d = commit_wdata_i & MIE_WRITABLE_MASK;
        end

        CSR_MTVEC: begin
          // Only Direct mode is implemented.
          mtvec_d = {commit_wdata_i[31:2], 2'b00};
        end

        CSR_MSCRATCH: mscratch_d = commit_wdata_i;
        CSR_MEPC:     mepc_d     = {commit_wdata_i[31:2], 2'b00};
        CSR_MCAUSE: mcause_d = commit_wdata_i & (MCAUSE_INTERRUPT_MASK | MCAUSE_CODE_MASK);
        CSR_MTVAL:    mtval_d    = commit_wdata_i;
        CSR_MIP:      ; // MTIP is live and read-only; writes have no effect.
        CSR_MCYCLE:   mcycle_d[31:0]   = commit_wdata_i;
        CSR_MCYCLEH:  mcycle_d[63:32]  = commit_wdata_i;
        CSR_MINSTRET: minstret_d[31:0] = commit_wdata_i;
        CSR_MINSTRETH: minstret_d[63:32] = commit_wdata_i;
        default: ; // Read-only or unimplemented writes are ignored defensively.
      endcase
    end

    // Normalize all unsupported/WARL fields after every update path.
    mstatus_d = MSTATUS_MPP_M_VALUE | (mstatus_d & MSTATUS_WRITABLE_MASK);
    mie_d     = mie_d & MIE_WRITABLE_MASK;
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      mstatus_q  <= MSTATUS_RESET_VALUE;
      mie_q      <= MIE_RESET_VALUE;
      mtvec_q    <= {TRAP_VECTOR[31:2], 2'b00};
      mscratch_q <= 32'b0;
      mepc_q     <= 32'b0;
      mcause_q   <= 32'b0;
      mtval_q    <= 32'b0;
      mcycle_q   <= 64'b0;
      minstret_q <= 64'b0;
    end else begin
      mstatus_q  <= mstatus_d;
      mie_q      <= mie_d;
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
