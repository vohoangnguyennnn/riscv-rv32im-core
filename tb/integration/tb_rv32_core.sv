// SPDX-License-Identifier: MIT

module tb_rv32_core;

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

  int cycles;
  int retire_count;
  int store_80_count;
  int store_84_count;
  int store_8c_count;
  int store_94_count;
  int trap_count;
  int mdu_result_count;
  logic saw_jal;

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

  function automatic logic [31:0] encode_m(
    input logic [2:0] funct3,
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input logic [4:0] rs2
  );
    begin
      encode_m = {rv32_pkg::FUNCT7_M, rs2, rs1, funct3, rd, rv32_pkg::OPCODE_OP};
    end
  endfunction

  // Mixed RV32I/RV32M program with no software-scheduled dependency NOPs. It
  // covers MDU operand/result forwarding, load-use, store-data forwarding,
  // control flush, divide corner cases, and precise illegal-instruction drain.
  initial begin
    clk            = 1'b0;
    rst            = 1'b1;
    cycles         = 0;
    retire_count   = 0;
    store_80_count = 0;
    store_84_count = 0;
    store_8c_count = 0;
    store_94_count = 0;
    trap_count     = 0;
    mdu_result_count = 0;
    saw_jal        = 1'b0;

    u_tcm.mem[0]  = 32'h0050_0093; // addi x1,  x0, 5
    u_tcm.mem[1]  = 32'h0070_0113; // addi x2,  x0, 7
    u_tcm.mem[2]  = encode_m(FUNCT3_MUL,    5'd9,  5'd1,  5'd2);  // x9  = 35
    u_tcm.mem[3]  = 32'h0014_8513; // addi x10, x9, 1 = 36
    u_tcm.mem[4]  = encode_m(FUNCT3_DIV,    5'd11, 5'd10, 5'd1);  // x11 = 7
    u_tcm.mem[5]  = encode_m(FUNCT3_REM,    5'd12, 5'd10, 5'd1);  // x12 = 1
    u_tcm.mem[6]  = 32'h0020_81b3; // add x3, x1, x2 = 12
    u_tcm.mem[7]  = 32'h0830_2023; // sw x3, 128(x0)
    u_tcm.mem[8]  = 32'h0800_2203; // lw x4, 128(x0)
    u_tcm.mem[9]  = 32'h0012_0293; // addi x5, x4, 1 = 13 (load-use)
    u_tcm.mem[10] = 32'h0850_2223; // sw x5, 132(x0)
    u_tcm.mem[11] = 32'hfff0_0813; // addi x16, x0, -1
    u_tcm.mem[12] = encode_m(FUNCT3_MULH,   5'd13, 5'd16, 5'd2);
    u_tcm.mem[13] = encode_m(FUNCT3_MULHSU, 5'd14, 5'd16, 5'd2);
    u_tcm.mem[14] = encode_m(FUNCT3_MULHU,  5'd15, 5'd16, 5'd2);
    u_tcm.mem[15] = encode_m(FUNCT3_DIVU,   5'd17, 5'd16, 5'd2);
    u_tcm.mem[16] = encode_m(FUNCT3_REMU,   5'd18, 5'd16, 5'd2);
    u_tcm.mem[17] = encode_m(FUNCT3_DIV,    5'd19, 5'd16, 5'd0);  // divide by zero
    u_tcm.mem[18] = encode_m(FUNCT3_REM,    5'd20, 5'd16, 5'd0);  // remainder by zero
    u_tcm.mem[19] = 32'h0080_036f; // jal x6, +8
    u_tcm.mem[20] = 32'h0800_2423; // wrong path: sw x0, 136(x0)
    u_tcm.mem[21] = 32'h0090_0393; // addi x7, x0, 9
    u_tcm.mem[22] = 32'h0870_2623; // sw x7, 140(x0)
    u_tcm.mem[23] = 32'hffff_ffff; // illegal instruction
    u_tcm.mem[24] = 32'h0800_2823; // wrong path: sw x0, 144(x0)

    u_tcm.mem[64] = 32'h00a0_0413; // trap vector: addi x8, x0, 10
    u_tcm.mem[65] = 32'h0000_0013; // nop
    u_tcm.mem[66] = 32'h0000_0013; // nop
    u_tcm.mem[67] = 32'h0880_2a23; // sw x8, 148(x0)
    u_tcm.mem[68] = 32'h0000_006f; // jal x0, 0

    u_tcm.mem[32] = 32'hdead_beef;
    u_tcm.mem[33] = 32'hdead_beef;
    u_tcm.mem[34] = 32'hdead_beef;
    u_tcm.mem[35] = 32'hdead_beef;
    u_tcm.mem[36] = 32'hdead_beef;
    u_tcm.mem[37] = 32'hdead_beef;

    repeat (3) @(posedge clk);
    #1ps;
    rst = 1'b0;
  end

  always @(posedge clk) begin
    #1ps;

    if (!rst) begin
      cycles++;

      if (trace_valid) begin
        retire_count++;

        if (trace_trap) begin
          if (
            (trace_pc != 32'h0000_005c) ||
            (trace_insn != 32'hffff_ffff) ||
            (trace_cause != rv32_pkg::EXC_ILLEGAL_INSN)
          ) begin
            $fatal(
              1,
              "unexpected trap at pc=%08x insn=%08x cause=%0d",
              trace_pc,
              trace_insn,
              trace_cause
            );
          end
          trap_count++;
        end

        if (trace_rd_we) begin
          unique case (trace_pc)
            32'h0000_0008: begin
              check_word({27'b0, trace_rd_addr}, 32'd9, "MUL rd");
              check_word(trace_rd_data, 32'd35, "MUL result");
              mdu_result_count++;
            end
            32'h0000_0010: begin
              check_word({27'b0, trace_rd_addr}, 32'd11, "DIV rd");
              check_word(trace_rd_data, 32'd7, "DIV result");
              mdu_result_count++;
            end
            32'h0000_0014: begin
              check_word({27'b0, trace_rd_addr}, 32'd12, "REM rd");
              check_word(trace_rd_data, 32'd1, "REM result");
              mdu_result_count++;
            end
            32'h0000_0030: begin
              check_word(trace_rd_data, 32'hffff_ffff, "MULH result");
              mdu_result_count++;
            end
            32'h0000_0034: begin
              check_word(trace_rd_data, 32'hffff_ffff, "MULHSU result");
              mdu_result_count++;
            end
            32'h0000_0038: begin
              check_word(trace_rd_data, 32'd6, "MULHU result");
              mdu_result_count++;
            end
            32'h0000_003c: begin
              check_word(trace_rd_data, 32'h2492_4924, "DIVU result");
              mdu_result_count++;
            end
            32'h0000_0040: begin
              check_word(trace_rd_data, 32'd3, "REMU result");
              mdu_result_count++;
            end
            32'h0000_0044: begin
              check_word(trace_rd_data, 32'hffff_ffff, "DIV-by-zero result");
              mdu_result_count++;
            end
            32'h0000_0048: begin
              check_word(trace_rd_data, 32'hffff_ffff, "REM-by-zero result");
              mdu_result_count++;
            end
            default: ;
          endcase
        end

        if (trace_rd_we && (trace_pc == 32'h0000_004c)) begin
          check_word({27'b0, trace_rd_addr}, 32'd6, "JAL link rd");
          check_word(trace_rd_data, 32'h0000_0050, "JAL link value");
        end

        if (trace_control && (trace_pc == 32'h0000_004c)) begin
          if (!trace_taken) begin
            $fatal(1, "JAL did not retire as taken");
          end
          check_word(trace_target, 32'h0000_0054, "JAL target");
          saw_jal = 1'b1;
        end

        if (trace_mem_wstrb != 4'b0000) begin
          unique case (trace_mem_addr)
            32'h0000_0080: begin
              check_word(trace_mem_wdata, 32'd12, "ALU store data");
              store_80_count++;
            end

            32'h0000_0084: begin
              check_word(trace_mem_wdata, 32'd13, "load consumer store data");
              store_84_count++;
            end

            32'h0000_0088: begin
              $fatal(1, "wrong-path store retired");
            end

            32'h0000_008c: begin
              check_word(trace_mem_wdata, 32'd9, "redirect target store data");
              store_8c_count++;
            end

            32'h0000_0090: begin
              $fatal(1, "instruction younger than trap performed a store");
            end

            32'h0000_0094: begin
              check_word(trace_mem_wdata, 32'd10, "trap-vector store data");
              store_94_count++;
            end

            default: begin
              $fatal(1, "unexpected store trace address %08x", trace_mem_addr);
            end
          endcase
        end
      end

      if (store_94_count == 1) begin
        check_word(u_tcm.mem[32], 32'd12, "TCM word at 0x80");
        check_word(u_tcm.mem[33], 32'd13, "TCM word at 0x84");
        check_word(u_tcm.mem[34], 32'hdead_beef, "squashed store word at 0x88");
        check_word(u_tcm.mem[35], 32'd9, "TCM word at 0x8c");
        check_word(u_tcm.mem[36], 32'hdead_beef, "trap-squashed word at 0x90");
        check_word(u_tcm.mem[37], 32'd10, "trap-vector word at 0x94");

        if (
          (store_80_count != 1) ||
          (store_84_count != 1) ||
          (store_8c_count != 1) ||
          (trap_count != 1) ||
          (mdu_result_count != 10) ||
          !saw_jal
        ) begin
          $fatal(
            1,
            "missing/repeated event: s80=%0d s84=%0d s8c=%0d traps=%0d mdu=%0d jal=%0b",
            store_80_count,
            store_84_count,
            store_8c_count,
            trap_count,
            mdu_result_count,
            saw_jal
          );
        end

        $display(
          "tb_rv32_core: PASS (%0d cycles, %0d trace events)",
          cycles,
          retire_count
        );
        $finish;
      end

      if (cycles > 600) begin
        $fatal(1, "core integration timeout after %0d cycles", cycles);
      end
    end
  end

endmodule
