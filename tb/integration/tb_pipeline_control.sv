// SPDX-License-Identifier: MIT

// Gate-4 directed regression for EX-resolved control transfers, two-younger
// instruction squash, precise exception ordering, and trap/MRET redirection.
module tb_pipeline_control;

  timeunit 1ns;
  timeprecision 1ps;

  import rv32_pkg::*;
  import rv32_tb_pkg::*;

  localparam int unsigned TCM_BYTES   = 4096;
  localparam int unsigned WORDS       = TCM_BYTES / 4;
  localparam logic [31:0] TRAP_VECTOR = 32'h0000_0300;
  localparam logic [31:0] SIG_BASE    = 32'h0000_0700;
  localparam logic [31:0] DONE_ADDR   = 32'h0000_07fc;

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

  int unsigned program_word;
  int unsigned cycles;
  int unsigned checks;
  int unsigned trap_count;
  int unsigned mret_count;
  int unsigned handler_read_count;
  int unsigned wb_trap_redirect_count;
  int unsigned mem_priority_count;
  int unsigned redirect_flush_count;
  int unsigned not_taken_ex_count;
  int unsigned misaligned_ex_count;

  logic forbidden_pc [0:WORDS-1];
  int unsigned retire_count [0:WORDS-1];

  logic [31:0] not_taken_pc;
  logic [31:0] not_taken_next_pc;
  logic [31:0] taken_branch_pc;
  logic [31:0] taken_branch_target;
  logic [31:0] jal_pc;
  logic [31:0] jal_target;
  logic [31:0] jalr_pc;
  logic [31:0] jalr_target;
  logic [31:0] misaligned_pc;
  logic [31:0] misaligned_target;
  logic [31:0] misaligned_resume_pc;
  logic [31:0] mem_fault_pc;
  logic [31:0] mem_fault_resume_pc;
  logic [31:0] not_taken_retire_cycle;
  logic [31:0] not_taken_next_retire_cycle;

  rv32_core #(
    .TRAP_VECTOR (TRAP_VECTOR)
  ) dut (
    .clk_i             (clk),
    .rst_i             (rst),
    .imem_m            (imem),
    .dmem_m            (dmem),
    .trace_valid_o     (trace_valid),
    .trace_pc_o        (trace_pc),
    .trace_insn_o      (trace_insn),
    .trace_rd_we_o     (trace_rd_we),
    .trace_rd_addr_o   (trace_rd_addr),
    .trace_rd_data_o   (trace_rd_data),
    .trace_mem_addr_o  (trace_mem_addr),
    .trace_mem_wstrb_o (trace_mem_wstrb),
    .trace_mem_wdata_o (trace_mem_wdata),
    .trace_trap_o      (trace_trap),
    .trace_cause_o     (trace_cause),
    .trace_control_o   (trace_control),
    .trace_taken_o     (trace_taken),
    .trace_target_o    (trace_target)
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
        $fatal(1, "%s: expected=%08x actual=%08x", test_name, expected, actual);
      end
      checks++;
    end
  endtask

  task automatic emit(input logic [31:0] insn);
    begin
      u_tcm.mem[program_word] = insn;
      program_word++;
    end
  endtask

  task automatic emit_forbidden(input logic [31:0] insn);
    begin
      forbidden_pc[program_word] = 1'b1;
      emit(insn);
    end
  endtask

  task automatic validate_final_state;
    begin
      check_word(u_tcm.mem[(SIG_BASE + 32'd0)  >> 2], 32'h0000_0011, "not-taken fall-through");
      check_word(u_tcm.mem[(SIG_BASE + 32'd4)  >> 2], 32'd7,         "taken-branch CSR squash");
      check_word(u_tcm.mem[(SIG_BASE + 32'd8)  >> 2], jal_target,    "JAL link consumer");
      check_word(u_tcm.mem[(SIG_BASE + 32'd12) >> 2], 32'd2,         "post-flush MDU recovery");
      check_word(u_tcm.mem[(SIG_BASE + 32'd16) >> 2], jalr_target,   "JALR link consumer");
      check_word(u_tcm.mem[(SIG_BASE + 32'd20) >> 2], 32'h0000_0033, "post-misaligned-trap execution");
      check_word(u_tcm.mem[(SIG_BASE + 32'd24) >> 2], 32'd7,         "misaligned younger CSR squash");

      check_word(u_tcm.mem[32'h0000_0760 >> 2], 32'hdead_beef, "branch wrong-path store");
      check_word(u_tcm.mem[32'h0000_0764 >> 2], 32'hdead_beef, "JAL wrong-path store");
      check_word(u_tcm.mem[32'h0000_0768 >> 2], 32'hdead_beef, "JALR wrong-path store");
      check_word(u_tcm.mem[32'h0000_076c >> 2], 32'hdead_beef, "misaligned younger store");
      check_word(u_tcm.mem[32'h0000_0770 >> 2], 32'hdead_beef, "MRET wrong-path store");
      check_word(u_tcm.mem[32'h0000_0774 >> 2], 32'hdead_beef, "MEM-fault younger store");
      check_word(u_tcm.mem[32'h0000_0778 >> 2], 32'hdead_beef, "younger JAL target store");

      if (
        (trap_count != 2) ||
        (mret_count != 2) ||
        (handler_read_count != 6) ||
        (wb_trap_redirect_count != 2) ||
        (mem_priority_count != 1) ||
        (redirect_flush_count != 5) ||
        (not_taken_ex_count != 1) ||
        (misaligned_ex_count != 1)
      ) begin
        $fatal(
          1,
          "control coverage mismatch traps=%0d mret=%0d handler=%0d wb_redirect=%0d mem_priority=%0d ex_redirect=%0d not_taken=%0d misaligned=%0d",
          trap_count,
          mret_count,
          handler_read_count,
          wb_trap_redirect_count,
          mem_priority_count,
          redirect_flush_count,
          not_taken_ex_count,
          misaligned_ex_count
        );
      end
      checks++;

      if (not_taken_next_retire_cycle != (not_taken_retire_cycle + 1)) begin
        $fatal(
          1,
          "not-taken branch inserted a bubble: branch_cycle=%0d next_cycle=%0d",
          not_taken_retire_cycle,
          not_taken_next_retire_cycle
        );
      end
      checks++;
    end
  endtask

  initial begin : initialize_program
    logic [31:0] jalr_setup_pc;

    clk                         = 1'b0;
    rst                         = 1'b1;
    program_word                = 0;
    cycles                      = 0;
    checks                      = 0;
    trap_count                  = 0;
    mret_count                  = 0;
    handler_read_count          = 0;
    wb_trap_redirect_count      = 0;
    mem_priority_count          = 0;
    redirect_flush_count        = 0;
    not_taken_ex_count          = 0;
    misaligned_ex_count         = 0;
    not_taken_retire_cycle      = 0;
    not_taken_next_retire_cycle = 0;

    for (int unsigned word_index = 0; word_index < WORDS; word_index++) begin
      u_tcm.mem[word_index] = TB_NOP;
      forbidden_pc[word_index] = 1'b0;
      retire_count[word_index] = 0;
    end

    for (int unsigned address = 32'h760; address <= 32'h778; address += 4) begin
      u_tcm.mem[address >> 2] = 32'hdead_beef;
    end
    u_tcm.mem[DONE_ADDR >> 2] = 32'b0;

    emit(enc_addi(5'd31, 5'd0, SIG_BASE[11:0]));
    emit(enc_addi(5'd1, 5'd0, 12'd1));
    emit(enc_addi(5'd2, 5'd0, 12'd2));
    emit(enc_addi(5'd3, 5'd0, 12'd7));
    emit(enc_csr(CSR_MSCRATCH, FUNCT3_CSRRW, 5'd0, 5'd3));

    // Not-taken conditional control must neither flush nor insert a bubble.
    not_taken_pc = program_word << 2;
    emit(enc_branch(FUNCT3_BEQ, 5'd1, 5'd2, 13'd12));
    not_taken_next_pc = program_word << 2;
    emit(enc_addi(5'd4, 5'd0, 12'h011));
    emit(enc_sw(5'd4, 5'd31, 12'd0));

    // Taken branch has two younger side-effecting instructions in ID/IF.
    taken_branch_pc     = program_word << 2;
    taken_branch_target = taken_branch_pc + 32'd12;
    emit(enc_branch(FUNCT3_BEQ, 5'd1, 5'd1, 13'd12));
    emit_forbidden(enc_sw(5'd1, 5'd31, 12'h060));
    emit_forbidden(enc_csr(CSR_MSCRATCH, FUNCT3_CSRRWI, 5'd0, 5'd31));
    emit(enc_csr(CSR_MSCRATCH, FUNCT3_CSRRS, 5'd5, 5'd0));
    emit(enc_sw(5'd5, 5'd31, 12'd4));

    // JAL squashes a wrong-path MDU and store. A subsequent MUL proves the
    // flushed request did not occupy or poison the multiplier.
    jal_pc     = program_word << 2;
    jal_target = jal_pc + 32'd12;
    emit(enc_jal(5'd6, 21'd12));
    emit_forbidden(enc_mdu(FUNCT3_MUL, 5'd7, 5'd1, 5'd2));
    emit_forbidden(enc_sw(5'd1, 5'd31, 12'h064));
    emit(enc_addi(5'd8, 5'd6, 12'd8));
    emit(enc_sw(5'd8, 5'd31, 12'd8));
    emit(enc_mdu(FUNCT3_MUL, 5'd9, 5'd1, 5'd2));
    emit(enc_sw(5'd9, 5'd31, 12'd12));

    // ALU -> JALR dependency is adjacent. Two younger instructions are
    // flushed and the target consumes the link value.
    jalr_setup_pc = program_word << 2;
    jalr_pc       = jalr_setup_pc + 32'd4;
    jalr_target   = jalr_setup_pc + 32'd16;
    emit(enc_addi(5'd10, 5'd0, jalr_target[11:0]));
    emit(enc_jalr(5'd11, 5'd10, 12'd0));
    emit_forbidden(enc_mdu(FUNCT3_DIV, 5'd12, 5'd2, 5'd1));
    emit_forbidden(enc_sw(5'd1, 5'd31, 12'h068));
    emit(enc_addi(5'd13, 5'd11, 12'd8));
    emit(enc_sw(5'd13, 5'd31, 12'd16));

    // IALIGN=32: JAL +2 traps with cause 0 and must not redirect. The handler
    // advances mepc by 20 bytes, deliberately skipping four younger sentinels.
    misaligned_pc        = program_word << 2;
    misaligned_target    = misaligned_pc + 32'd2;
    misaligned_resume_pc = misaligned_pc + 32'd20;
    emit(enc_jal(5'd14, 21'd2));
    emit_forbidden(enc_sw(5'd1, 5'd31, 12'h06c));
    emit_forbidden(enc_csr(CSR_MSCRATCH, FUNCT3_CSRRWI, 5'd0, 5'd30));
    emit_forbidden(enc_mdu(FUNCT3_MUL, 5'd15, 5'd1, 5'd2));
    emit_forbidden(enc_addi(5'd15, 5'd0, 12'h7ff));
    emit(enc_addi(5'd15, 5'd0, 12'h033));
    emit(enc_sw(5'd15, 5'd31, 12'd20));
    emit(enc_csr(CSR_MSCRATCH, FUNCT3_CSRRS, 5'd16, 5'd0));
    emit(enc_sw(5'd16, 5'd31, 12'd24));

    // Bad TCM load reaches MEM while the younger JAL is held in EX. The MEM
    // exception must kill that redirect and the target-side store as well.
    emit(enc_lui(5'd30, 20'h00001)); // x30 = first address outside the 4 KiB TCM.
    mem_fault_pc        = program_word << 2;
    mem_fault_resume_pc = mem_fault_pc + 32'd20;
    emit(enc_lw(5'd17, 5'd30, 12'd0));
    emit(enc_jal(5'd18, 21'd12));
    emit_forbidden(enc_sw(5'd1, 5'd31, 12'h074));
    emit_forbidden(enc_mdu(FUNCT3_DIV, 5'd19, 5'd2, 5'd1));
    emit_forbidden(enc_sw(5'd2, 5'd31, 12'h078));
    emit(enc_addi(5'd19, 5'd0, 12'h05a));
    emit(enc_sw(5'd19, 5'd0, DONE_ADDR[11:0]));
    emit(enc_jal(5'd0, 21'd0));

    // Common direct-mode handler. CSR reads are checked on both invocations.
    u_tcm.mem[(TRAP_VECTOR + 32'd0)  >> 2] = enc_csr(CSR_MCAUSE, FUNCT3_CSRRS, 5'd20, 5'd0);
    u_tcm.mem[(TRAP_VECTOR + 32'd4)  >> 2] = enc_csr(CSR_MTVAL,  FUNCT3_CSRRS, 5'd21, 5'd0);
    u_tcm.mem[(TRAP_VECTOR + 32'd8)  >> 2] = enc_csr(CSR_MEPC,   FUNCT3_CSRRS, 5'd22, 5'd0);
    u_tcm.mem[(TRAP_VECTOR + 32'd12) >> 2] = enc_addi(5'd22, 5'd22, 12'd20);
    u_tcm.mem[(TRAP_VECTOR + 32'd16) >> 2] = enc_csr(CSR_MEPC, FUNCT3_CSRRW, 5'd0, 5'd22);
    u_tcm.mem[(TRAP_VECTOR + 32'd20) >> 2] = INSN_MRET;
    forbidden_pc[(TRAP_VECTOR + 32'd24) >> 2] = 1'b1;
    u_tcm.mem[(TRAP_VECTOR + 32'd24) >> 2] = enc_sw(5'd1, 5'd31, 12'h070);
    forbidden_pc[(TRAP_VECTOR + 32'd28) >> 2] = 1'b1;
    u_tcm.mem[(TRAP_VECTOR + 32'd28) >> 2] = enc_mdu(FUNCT3_MUL, 5'd23, 5'd1, 5'd2);

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
  end

  always @(negedge clk) begin : check_control_priority
    if (!rst) begin
      // WB trap owns the externally visible redirect and always selects mtvec.
      if (dut.wb_trap) begin
        if (!dut.redirect_valid || (dut.redirect_pc != TRAP_VECTOR)) begin
          $fatal(
            1,
            "WB trap redirect mismatch valid=%0b pc=%08x",
            dut.redirect_valid,
            dut.redirect_pc
          );
        end
        wb_trap_redirect_count++;
        checks++;
      end

      // A newly completed older load fault and the younger JAL coexist here.
      // The EX result must be killed before it can generate a redirect.
      if (dut.mem_exception) begin
        if (
          !dut.id_ex_q.valid ||
          (dut.id_ex_q.pc != (mem_fault_pc + 32'd4)) ||
          !dut.ex_kill ||
          dut.control_redirect.valid
        ) begin
          $fatal(
            1,
            "MEM exception lost priority: id_ex_pc=%08x kill=%0b ex_redirect=%0b",
            dut.id_ex_q.pc,
            dut.ex_kill,
            dut.control_redirect.valid
          );
        end
        mem_priority_count++;
        checks++;
      end

      if (dut.id_ex_q.valid && (dut.id_ex_q.pc == not_taken_pc)) begin
        if (dut.control_redirect.valid || dut.id_ex_flush) begin
          $fatal(1, "not-taken branch flushed or redirected the pipeline");
        end
        not_taken_ex_count++;
        checks++;
      end

      if (
        dut.id_ex_q.valid &&
        (dut.id_ex_q.pc == misaligned_pc) &&
        dut.ex_exception &&
        (misaligned_ex_count == 0)
      ) begin
        if (
          dut.control_redirect.valid ||
          !dut.ex_mem_d.exc.valid ||
          (dut.ex_mem_d.exc.cause != EXC_INST_ADDR_MISALIGNED)
        ) begin
          $fatal(1, "misaligned control target redirected or failed to raise cause 0");
        end
        misaligned_ex_count++;
        checks++;
      end

      // Every accepted taken control transfer resolved in EX flushes both
      // younger pipeline registers. This includes both MRET invocations.
      if (
        dut.control_redirect.valid &&
        (
          (dut.id_ex_q.pc == taken_branch_pc) ||
          (dut.id_ex_q.pc == jal_pc) ||
          (dut.id_ex_q.pc == jalr_pc) ||
          (dut.id_ex_q.pc == (TRAP_VECTOR + 32'd20))
        )
      ) begin
        if (!dut.if_id_flush || !dut.id_ex_flush) begin
          $fatal(1, "EX redirect did not flush IF/ID and ID/EX");
        end
        redirect_flush_count++;
        checks++;
      end
    end
  end

  always @(posedge clk) begin : monitor_retirement
    int unsigned pc_word;
    logic [4:0] expected_handler_cause;
    logic [31:0] expected_handler_tval;
    logic [31:0] expected_handler_mepc;

    #1ps;
    if (!rst) begin
      cycles++;

      if (trace_valid) begin
        pc_word = trace_pc >> 2;
        if ((pc_word < WORDS) && forbidden_pc[pc_word]) begin
          $fatal(1, "wrong-path instruction retired at pc=%08x", trace_pc);
        end

        retire_count[pc_word]++;
        if (retire_count[pc_word] > 1) begin
          // The common trap handler is intentionally executed twice.
          if ((trace_pc < TRAP_VECTOR) || (trace_pc > (TRAP_VECTOR + 32'd20))) begin
            $fatal(1, "instruction retired more than once at pc=%08x", trace_pc);
          end
        end

        if (trace_trap) begin
          if (trace_rd_we || (trace_mem_wstrb != 4'b0000)) begin
            $fatal(1, "trapping instruction carried an architectural side effect");
          end

          unique case (trap_count)
            0: begin
              check_word(trace_pc, misaligned_pc, "misaligned trap PC");
              check_word({27'b0, trace_cause}, {27'b0, EXC_INST_ADDR_MISALIGNED}, "misaligned trap cause");
              check_word(trace_target, misaligned_target, "misaligned trap target metadata");
            end

            1: begin
              check_word(trace_pc, mem_fault_pc, "load access-fault PC");
              check_word({27'b0, trace_cause}, {27'b0, EXC_LOAD_ACCESS_FAULT}, "load access-fault cause");
            end

            default: $fatal(1, "unexpected extra trap at pc=%08x", trace_pc);
          endcase
          trap_count++;
        end else begin
          if (trace_pc == not_taken_pc) begin
            if (!trace_control || trace_taken) begin
              $fatal(1, "not-taken branch retirement metadata is wrong");
            end
            not_taken_retire_cycle = cycles;
            checks++;
          end
          if (trace_pc == not_taken_next_pc) begin
            not_taken_next_retire_cycle = cycles;
          end

          if (trace_pc == taken_branch_pc) begin
            if (!trace_control || !trace_taken || (trace_target != taken_branch_target)) begin
              $fatal(1, "taken branch retirement metadata is wrong");
            end
            checks++;
          end
          if (trace_pc == jal_pc) begin
            if (!trace_control || !trace_taken || (trace_target != jal_target)) begin
              $fatal(1, "JAL retirement metadata is wrong");
            end
            check_word(trace_rd_data, jal_pc + 32'd4, "JAL link value");
          end
          if (trace_pc == jalr_pc) begin
            if (!trace_control || !trace_taken || (trace_target != jalr_target)) begin
              $fatal(1, "JALR retirement metadata is wrong");
            end
            check_word(trace_rd_data, jalr_pc + 32'd4, "JALR link value");
          end

          if (trace_pc == (TRAP_VECTOR + 32'd20)) begin
            if (!trace_control || !trace_taken) begin
              $fatal(1, "MRET did not retire as a taken control transfer");
            end
            if (mret_count == 0) begin
              check_word(trace_target, misaligned_resume_pc, "first MRET target");
            end else if (mret_count == 1) begin
              check_word(trace_target, mem_fault_resume_pc, "second MRET target");
            end else begin
              $fatal(1, "unexpected extra MRET retirement");
            end
            mret_count++;
          end

          expected_handler_cause = (trap_count == 1)
                                 ? EXC_INST_ADDR_MISALIGNED
                                 : EXC_LOAD_ACCESS_FAULT;
          expected_handler_tval  = (trap_count == 1)
                                 ? misaligned_target
                                 : 32'h0000_1000;
          expected_handler_mepc  = (trap_count == 1)
                                 ? misaligned_pc
                                 : mem_fault_pc;

          if (trace_pc == (TRAP_VECTOR + 32'd0)) begin
            check_word(trace_rd_data, {27'b0, expected_handler_cause}, "handler mcause");
            handler_read_count++;
          end
          if (trace_pc == (TRAP_VECTOR + 32'd4)) begin
            check_word(trace_rd_data, expected_handler_tval, "handler mtval");
            handler_read_count++;
          end
          if (trace_pc == (TRAP_VECTOR + 32'd8)) begin
            check_word(trace_rd_data, expected_handler_mepc, "handler mepc");
            handler_read_count++;
          end
        end

        if ((trace_mem_wstrb != 4'b0000) && (trace_mem_addr == DONE_ADDR)) begin
          check_word(trace_mem_wdata, 32'h0000_005a, "completion store data");
          validate_final_state();
          $display(
            "tb_pipeline_control: PASS (%0d cycles, %0d checks, %0d precise traps)",
            cycles,
            checks,
            trap_count
          );
          $finish;
        end
      end

      if (cycles > 1500) begin
        $fatal(1, "pipeline control integration timeout after %0d cycles", cycles);
      end
    end
  end

endmodule
