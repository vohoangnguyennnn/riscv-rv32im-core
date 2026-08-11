// SPDX-License-Identifier: MIT

module tb_csr;

  timeunit 1ns;
  timeprecision 1ps;

  import rv32_pkg::*;

  logic       clk;
  logic       rst;
  csr_addr_t  raddr;
  csr_cmd_e   access_cmd;
  logic       access_write;
  word_t      rdata;
  logic       access_illegal;
  logic       commit_write;
  csr_addr_t  commit_waddr;
  word_t      commit_wdata;
  logic       retire;
  logic       trap_valid;
  word_t      trap_pc;
  logic [4:0] trap_cause;
  word_t      trap_tval;
  word_t      mtvec;
  word_t      mepc;
  int         checks;

  csr_file #(
    .TRAP_VECTOR (32'h0000_0103)
  ) dut (
    .clk_i              (clk),
    .rst_i              (rst),
    .raddr_i            (raddr),
    .access_cmd_i       (access_cmd),
    .access_write_i     (access_write),
    .rdata_o            (rdata),
    .access_illegal_o   (access_illegal),
    .commit_write_i     (commit_write),
    .commit_waddr_i     (commit_waddr),
    .commit_wdata_i     (commit_wdata),
    .retire_i           (retire),
    .trap_valid_i       (trap_valid),
    .trap_pc_i          (trap_pc),
    .trap_cause_i       (trap_cause),
    .trap_tval_i        (trap_tval),
    .mtvec_o            (mtvec),
    .mepc_o             (mepc)
  );

  always #5 clk = ~clk;

  task automatic drive_idle;
    begin
      raddr         = 12'b0;
      access_cmd    = CSR_NONE;
      access_write  = 1'b0;
      commit_write  = 1'b0;
      commit_waddr  = 12'b0;
      commit_wdata  = 32'b0;
      retire        = 1'b0;
      trap_valid    = 1'b0;
      trap_pc       = 32'b0;
      trap_cause    = 5'b0;
      trap_tval     = 32'b0;
    end
  endtask

  task automatic check_access(
    input csr_addr_t address,
    input csr_cmd_e  command,
    input logic      writes,
    input word_t     expected_data,
    input logic      expected_illegal,
    input string     test_name
  );
    begin
      raddr        = address;
      access_cmd   = command;
      access_write = writes;
      #1ps;

      if ((rdata !== expected_data) || (access_illegal !== expected_illegal)) begin
        $fatal(
          1,
          "%s mismatch: data=%08x/%08x illegal=%0b/%0b",
          test_name,
          rdata,
          expected_data,
          access_illegal,
          expected_illegal
        );
      end

      checks++;
    end
  endtask

  task automatic commit_csr(
    input csr_addr_t address,
    input word_t     value,
    input logic      retire_with_write
  );
    begin
      @(negedge clk);
      commit_write = 1'b1;
      commit_waddr = address;
      commit_wdata = value;
      retire       = retire_with_write;

      @(posedge clk);
      #1ps;
      commit_write = 1'b0;
      commit_waddr = 12'b0;
      commit_wdata = 32'b0;
      retire       = 1'b0;
    end
  endtask

  task automatic advance_cycle(input logic retire_instruction);
    begin
      @(negedge clk);
      retire = retire_instruction;
      @(posedge clk);
      #1ps;
      retire = 1'b0;
    end
  endtask

  initial begin
    word_t minstret_before_trap;

    clk    = 1'b0;
    rst    = 1'b1;
    checks = 0;
    drive_idle();

    repeat (2) @(posedge clk);
    #1ps;
    rst = 1'b0;

    // Reset values and read-only identification CSRs.
    check_access(CSR_MTVEC,    CSR_RS, 1'b0, 32'h0000_0100, 1'b0, "mtvec reset/alignment");
    check_access(CSR_MEPC,     CSR_RS, 1'b0, 32'b0,          1'b0, "mepc reset");
    check_access(CSR_MCYCLE,   CSR_RS, 1'b0, 32'b0,          1'b0, "mcycle reset");
    check_access(CSR_MINSTRET, CSR_RS, 1'b0, 32'b0,          1'b0, "minstret reset");
    check_access(CSR_MISA,     CSR_RS, 1'b0, MISA_RV32IM,    1'b0, "misa value");
    check_access(CSR_MVENDORID,CSR_RS, 1'b0, 32'b0,          1'b0, "mvendorid zero");
    check_access(CSR_MARCHID,  CSR_RS, 1'b0, 32'b0,          1'b0, "marchid zero");
    check_access(CSR_MIMPID,   CSR_RS, 1'b0, 32'b0,          1'b0, "mimpid zero");
    check_access(CSR_MHARTID,  CSR_RS, 1'b0, 32'b0,          1'b0, "mhartid zero");

    // All six Zicsr command classes receive correct read-only legality. The
    // set/clear forms become pure reads when their register/zimm source is 0.
    check_access(CSR_MISA, CSR_RW,  1'b0, MISA_RV32IM, 1'b1, "CSRRW read-only illegal");
    check_access(CSR_MISA, CSR_RWI, 1'b0, MISA_RV32IM, 1'b1, "CSRRWI read-only illegal");
    check_access(CSR_MISA, CSR_RS,  1'b0, MISA_RV32IM, 1'b0, "CSRRS zero source read");
    check_access(CSR_MISA, CSR_RS,  1'b1, MISA_RV32IM, 1'b1, "CSRRS write read-only illegal");
    check_access(CSR_MISA, CSR_RC,  1'b0, MISA_RV32IM, 1'b0, "CSRRC zero source read");
    check_access(CSR_MISA, CSR_RC,  1'b1, MISA_RV32IM, 1'b1, "CSRRC write read-only illegal");
    check_access(CSR_MISA, CSR_RSI, 1'b0, MISA_RV32IM, 1'b0, "CSRRSI zero source read");
    check_access(CSR_MISA, CSR_RSI, 1'b1, MISA_RV32IM, 1'b1, "CSRRSI write read-only illegal");
    check_access(CSR_MISA, CSR_RCI, 1'b0, MISA_RV32IM, 1'b0, "CSRRCI zero source read");
    check_access(CSR_MISA, CSR_RCI, 1'b1, MISA_RV32IM, 1'b1, "CSRRCI write read-only illegal");
    check_access(12'h999,  CSR_RS,  1'b0, 32'b0,       1'b1, "unimplemented CSR illegal");
    check_access(12'h999,  CSR_NONE,1'b0, 32'b0,       1'b0, "inactive CSR access benign");

    // Writable machine CSRs commit only at the clock edge. WARL alignment and
    // mcause narrowing are enforced by the state-holding block.
    commit_csr(CSR_MTVEC, 32'h1234_5003, 1'b0);
    check_access(CSR_MTVEC, CSR_RS, 1'b0, 32'h1234_5000, 1'b0, "mtvec direct mode mask");
    if (mtvec !== 32'h1234_5000) $fatal(1, "mtvec output mismatch");
    checks++;

    commit_csr(CSR_MSCRATCH, 32'hdead_beef, 1'b0);
    check_access(CSR_MSCRATCH, CSR_RS, 1'b0, 32'hdead_beef, 1'b0, "mscratch write/read");

    commit_csr(CSR_MEPC, 32'h8000_0123, 1'b0);
    check_access(CSR_MEPC, CSR_RS, 1'b0, 32'h8000_0120, 1'b0, "mepc IALIGN mask");
    if (mepc !== 32'h8000_0120) $fatal(1, "mepc output mismatch");
    checks++;

    commit_csr(CSR_MCAUSE, 32'hffff_ffff, 1'b0);
    check_access(CSR_MCAUSE, CSR_RS, 1'b0, 32'h0000_001f, 1'b0, "mcause WLRL width");

    commit_csr(CSR_MTVAL, 32'hfeed_c0de, 1'b0);
    check_access(CSR_MTVAL, CSR_RS, 1'b0, 32'hfeed_c0de, 1'b0, "mtval write/read");

    // mcycle increments during stalls and carries from the low to high half.
    commit_csr(CSR_MCYCLEH, 32'h1234_5678, 1'b0);
    commit_csr(CSR_MCYCLE,  32'hffff_fffe, 1'b0);
    check_access(CSR_MCYCLEH, CSR_RS, 1'b0, 32'h1234_5678, 1'b0, "mcycle high write");
    check_access(CSR_MCYCLE,  CSR_RS, 1'b0, 32'hffff_fffe, 1'b0, "mcycle low write priority");
    advance_cycle(1'b0);
    check_access(CSR_MCYCLE, CSR_RS, 1'b0, 32'hffff_ffff, 1'b0, "mcycle advances on stall");
    advance_cycle(1'b0);
    check_access(CSR_MCYCLE,  CSR_RS, 1'b0, 32'h0000_0000, 1'b0, "mcycle low carry");
    check_access(CSR_MCYCLEH, CSR_RS, 1'b0, 32'h1234_5679, 1'b0, "mcycle high carry");

    // minstret advances only on retire, supports 64-bit carry, and an explicit
    // write suppresses the automatic counter update on that same edge.
    commit_csr(CSR_MINSTRETH, 32'h89ab_cdef, 1'b0);
    commit_csr(CSR_MINSTRET,  32'hffff_fffe, 1'b0);
    advance_cycle(1'b1);
    check_access(CSR_MINSTRET, CSR_RS, 1'b0, 32'hffff_ffff, 1'b0, "minstret retire increment");
    advance_cycle(1'b1);
    check_access(CSR_MINSTRET,  CSR_RS, 1'b0, 32'h0000_0000, 1'b0, "minstret low carry");
    check_access(CSR_MINSTRETH, CSR_RS, 1'b0, 32'h89ab_cdf0, 1'b0, "minstret high carry");
    advance_cycle(1'b0);
    check_access(CSR_MINSTRET, CSR_RS, 1'b0, 32'h0000_0000, 1'b0, "minstret holds on stall");
    commit_csr(CSR_MINSTRET, 32'd10, 1'b1);
    check_access(CSR_MINSTRET, CSR_RS, 1'b0, 32'd10, 1'b0, "minstret write beats increment");

    // Trap entry beats a simultaneous defensive commit and suppresses retire.
    // It captures aligned mepc, synchronous mcause, and unmodified mtval.
    minstret_before_trap = rdata;
    @(negedge clk);
    commit_write = 1'b1;
    commit_waddr = CSR_MTVEC;
    commit_wdata = 32'hffff_f000;
    retire       = 1'b1;
    trap_valid   = 1'b1;
    trap_pc      = 32'h0000_2083;
    trap_cause   = EXC_STORE_ACCESS_FAULT;
    trap_tval    = 32'h8000_0004;
    @(posedge clk);
    #1ps;
    drive_idle();

    check_access(CSR_MTVEC, CSR_RS, 1'b0, 32'h1234_5000, 1'b0, "trap suppresses CSR commit");
    check_access(CSR_MEPC, CSR_RS, 1'b0, 32'h0000_2080, 1'b0, "trap mepc capture");
    check_access(CSR_MCAUSE, CSR_RS, 1'b0, 32'd7, 1'b0, "trap mcause capture");
    check_access(CSR_MTVAL, CSR_RS, 1'b0, 32'h8000_0004, 1'b0, "trap mtval capture");
    check_access(CSR_MINSTRET, CSR_RS, 1'b0, minstret_before_trap, 1'b0, "trap does not retire");

    advance_cycle(1'b1);
    check_access(CSR_MINSTRET, CSR_RS, 1'b0, minstret_before_trap + 32'd1, 1'b0, "post-trap retire");

    // Synchronous reset also resets both 64-bit counters and restores mtvec.
    @(negedge clk);
    rst = 1'b1;
    @(posedge clk);
    #1ps;
    check_access(CSR_MTVEC, CSR_RS, 1'b0, 32'h0000_0100, 1'b0, "synchronous reset mtvec");
    check_access(CSR_MCYCLE, CSR_RS, 1'b0, 32'b0, 1'b0, "synchronous reset mcycle");
    check_access(CSR_MINSTRET, CSR_RS, 1'b0, 32'b0, 1'b0, "synchronous reset minstret");

    $display("tb_csr: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
