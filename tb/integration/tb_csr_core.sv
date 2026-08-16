// SPDX-License-Identifier: MIT

module tb_csr_core;

  timeunit 1ns;
  timeprecision 1ps;

  import rv32_pkg::*;

  localparam int unsigned TCM_BYTES = 512;

  logic clk;
  logic rst;

  rv32_mem_if imem();
  rv32_mem_if dmem();

  logic        trace_valid;
  logic [31:0] trace_pc;
  logic [31:0] trace_insn;
  logic        trace_rd_we;
  logic [4:0]  trace_rd_addr;
  logic [31:0] trace_rd_data;
  logic [31:0] trace_mem_addr;
  logic [3:0]  trace_mem_wstrb;
  logic [31:0] trace_mem_wdata;
  logic        trace_trap;
  logic [4:0]  trace_cause;
  logic        trace_control;
  logic        trace_taken;
  logic [31:0] trace_target;

  logic [31:0] illegal_csr_insn;
  int          cycles;
  int          trap_count;
  int          csr_result_count;
  int          final_store_count;
  logic        saw_mret;

  rv32_core dut (
    .clk_i              (clk),
    .rst_i              (rst),
    .imem_m             (imem),
    .dmem_m             (dmem),
    .trace_valid_o      (trace_valid),
    .trace_pc_o         (trace_pc),
    .trace_insn_o       (trace_insn),
    .trace_rd_we_o      (trace_rd_we),
    .trace_rd_addr_o    (trace_rd_addr),
    .trace_rd_data_o    (trace_rd_data),
    .trace_mem_addr_o   (trace_mem_addr),
    .trace_mem_wstrb_o  (trace_mem_wstrb),
    .trace_mem_wdata_o  (trace_mem_wdata),
    .trace_trap_o       (trace_trap),
    .trace_cause_o      (trace_cause),
    .trace_control_o    (trace_control),
    .trace_taken_o      (trace_taken),
    .trace_target_o     (trace_target)
  );

  rv32_tcm #(
    .BYTES     (TCM_BYTES),
    .BASE_ADDR (32'h0000_0000)
  ) u_tcm (
    .clk_i  (clk),
    .imem_s (imem),
    .dmem_s (dmem)
  );

  always #5 clk = ~clk;

  function automatic logic [31:0] encode_addi(
    input logic [4:0]  rd,
    input logic [4:0]  rs1,
    input logic [11:0] imm
  );
    begin
      encode_addi = {imm, rs1, FUNCT3_ADD_SUB, rd, OPCODE_OP_IMM};
    end
  endfunction

  function automatic logic [31:0] encode_csr(
    input csr_addr_t   address,
    input logic [2:0] funct3,
    input logic [4:0] rd,
    input logic [4:0] source
  );
    begin
      encode_csr = {address, source, funct3, rd, OPCODE_SYSTEM};
    end
  endfunction

  function automatic logic [31:0] encode_sw(
    input logic [4:0]  rs2,
    input logic [11:0] offset
  );
    begin
      encode_sw = {
        offset[11:5],
        rs2,
        5'd0,
        FUNCT3_SW,
        offset[4:0],
        OPCODE_STORE
      };
    end
  endfunction

  task automatic check_word(
    input logic [31:0] actual,
    input logic [31:0] expected,
    input string       test_name
  );
    begin
      if (actual !== expected) begin
        $fatal(
          1,
          "%s mismatch: expected=%08x result=%08x",
          test_name,
          expected,
          actual
        );
      end
    end
  endtask

  task automatic check_csr_result(
    input logic [4:0]  expected_rd,
    input logic [31:0] expected_data,
    input string       test_name
  );
    begin
      if (!trace_rd_we) begin
        $fatal(1, "%s did not write its destination register", test_name);
      end
      check_word({27'b0, trace_rd_addr}, {27'b0, expected_rd}, test_name);
      check_word(trace_rd_data, expected_data, test_name);
      csr_result_count++;
    end
  endtask

  // This program validates the full architectural seam rather than just the
  // CSR leaf block: all six Zicsr forms, read-only legality, dynamic mtvec,
  // precise mepc/mcause/mtval capture, MRET, and ordered minstret observation.
  initial begin : initialize_program
    integer i;

    clk                = 1'b0;
    rst                = 1'b1;
    cycles             = 0;
    trap_count         = 0;
    csr_result_count   = 0;
    final_store_count  = 0;
    saw_mret           = 1'b0;

    for (i = 0; i < (TCM_BYTES / 4); i++) begin
      u_tcm.mem[i] = 32'h0000_0013;
    end

    illegal_csr_insn = encode_csr(CSR_MISA, FUNCT3_CSRRW, 5'd9, 5'd0);

    u_tcm.mem[0]  = encode_addi(5'd14, 5'd0, 12'h120);
    u_tcm.mem[1]  = encode_csr(CSR_MTVEC, FUNCT3_CSRRW, 5'd0, 5'd14);
    u_tcm.mem[2]  = encode_addi(5'd1, 5'd0, 12'h015);
    u_tcm.mem[3]  = encode_csr(CSR_MSCRATCH, FUNCT3_CSRRW, 5'd2, 5'd1);
    u_tcm.mem[4]  = encode_csr(CSR_MSCRATCH, FUNCT3_CSRRS, 5'd3, 5'd0);
    u_tcm.mem[5]  = encode_csr(CSR_MSCRATCH, FUNCT3_CSRRCI, 5'd4, 5'd1);
    u_tcm.mem[6]  = encode_csr(CSR_MSCRATCH, FUNCT3_CSRRSI, 5'd5, 5'd2);
    u_tcm.mem[7]  = encode_csr(CSR_MSCRATCH, FUNCT3_CSRRWI, 5'd6, 5'd3);
    u_tcm.mem[8]  = encode_csr(CSR_MSCRATCH, FUNCT3_CSRRC, 5'd7, 5'd1);
    u_tcm.mem[9]  = encode_csr(CSR_MSCRATCH, FUNCT3_CSRRS, 5'd8, 5'd0);
    u_tcm.mem[10] = illegal_csr_insn;
    u_tcm.mem[11] = encode_sw(5'd0, 12'h0c0); // Must be skipped by handler.
    u_tcm.mem[12] = encode_csr(CSR_MCAUSE, FUNCT3_CSRRS, 5'd10, 5'd0);
    u_tcm.mem[13] = encode_csr(CSR_MTVAL, FUNCT3_CSRRS, 5'd11, 5'd0);
    u_tcm.mem[14] = encode_csr(CSR_MEPC, FUNCT3_CSRRS, 5'd12, 5'd0);
    u_tcm.mem[15] = encode_csr(CSR_MINSTRET, FUNCT3_CSRRS, 5'd15, 5'd0);
    u_tcm.mem[16] = encode_addi(5'd13, 5'd0, 12'h044);
    u_tcm.mem[17] = encode_sw(5'd13, 12'h0c4);
    u_tcm.mem[18] = 32'h0000_006f; // jal x0, 0

    // Software-selected direct-mode trap vector at 0x120.
    u_tcm.mem[72] = encode_csr(CSR_MCAUSE, FUNCT3_CSRRS, 5'd20, 5'd0);
    u_tcm.mem[73] = encode_csr(CSR_MEPC, FUNCT3_CSRRS, 5'd21, 5'd0);
    u_tcm.mem[74] = encode_csr(CSR_MTVAL, FUNCT3_CSRRS, 5'd22, 5'd0);
    u_tcm.mem[75] = encode_addi(5'd21, 5'd21, 12'h008);
    u_tcm.mem[76] = encode_csr(CSR_MEPC, FUNCT3_CSRRW, 5'd0, 5'd21);
    u_tcm.mem[77] = INSN_MRET;

    u_tcm.mem[48] = 32'hdead_beef;
    u_tcm.mem[49] = 32'hdead_beef;

    repeat (3) @(posedge clk);
    #1ps;
    rst = 1'b0;
  end

  always @(posedge clk) begin
    #1ps;

    if (!rst) begin
      cycles++;

      if (trace_valid) begin
        if (trace_trap) begin
          if (
            (trace_pc != 32'h0000_0028) ||
            (trace_insn != illegal_csr_insn) ||
            (trace_cause != EXC_ILLEGAL_INSN) ||
            trace_rd_we
          ) begin
            $fatal(
              1,
              "unexpected CSR trap: pc=%08x insn=%08x cause=%0d rd_we=%0b",
              trace_pc,
              trace_insn,
              trace_cause,
              trace_rd_we
            );
          end
          trap_count++;
        end

        unique case (trace_pc)
          32'h0000_000c: check_csr_result(5'd2,  32'h0000_0000, "CSRRW old value");
          32'h0000_0010: check_csr_result(5'd3,  32'h0000_0015, "CSRRS read-only form");
          32'h0000_0014: check_csr_result(5'd4,  32'h0000_0015, "CSRRCI old value");
          32'h0000_0018: check_csr_result(5'd5,  32'h0000_0014, "CSRRSI old value");
          32'h0000_001c: check_csr_result(5'd6,  32'h0000_0016, "CSRRWI old value");
          32'h0000_0020: check_csr_result(5'd7,  32'h0000_0003, "CSRRC old value");
          32'h0000_0024: check_csr_result(5'd8,  32'h0000_0002, "CSRRS final value");
          32'h0000_0120: check_csr_result(5'd20, 32'h0000_0002, "handler mcause");
          32'h0000_0124: check_csr_result(5'd21, 32'h0000_0028, "handler mepc");
          32'h0000_0128: check_csr_result(5'd22, illegal_csr_insn, "handler mtval");
          32'h0000_0030: check_csr_result(5'd10, 32'h0000_0002, "returned mcause");
          32'h0000_0034: check_csr_result(5'd11, illegal_csr_insn, "returned mtval");
          32'h0000_0038: check_csr_result(5'd12, 32'h0000_0030, "updated mepc");
          32'h0000_003c: check_csr_result(5'd15, 32'd19, "ordered minstret");
          default: ;
        endcase

        if (trace_control && (trace_pc == 32'h0000_0134)) begin
          if (!trace_taken) begin
            $fatal(1, "MRET did not retire as a taken control transfer");
          end
          check_word(trace_target, 32'h0000_0030, "MRET target");
          saw_mret = 1'b1;
        end

        if (trace_mem_wstrb != 4'b0000) begin
          unique case (trace_mem_addr)
            32'h0000_00c0: $fatal(1, "trap-younger sentinel store retired");

            32'h0000_00c4: begin
              check_word(trace_mem_wdata, 32'h0000_0044, "post-MRET store data");
              final_store_count++;
            end

            default: $fatal(1, "unexpected store at address %08x", trace_mem_addr);
          endcase
        end
      end

      if (final_store_count == 1) begin
        check_word(u_tcm.mem[48], 32'hdead_beef, "squashed sentinel memory");
        check_word(u_tcm.mem[49], 32'h0000_0044, "post-MRET memory");

        if (
          (trap_count != 1) ||
          (csr_result_count != 14) ||
          !saw_mret
        ) begin
          $fatal(
            1,
            "missing/repeated CSR event: traps=%0d results=%0d mret=%0b",
            trap_count,
            csr_result_count,
            saw_mret
          );
        end

        $display("tb_csr_core: PASS (%0d cycles)", cycles);
        $finish;
      end

      if (cycles > 400) begin
        $fatal(1, "CSR core integration timeout after %0d cycles", cycles);
      end
    end
  end

endmodule
