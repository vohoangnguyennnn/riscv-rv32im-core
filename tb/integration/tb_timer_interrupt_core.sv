module tb_timer_interrupt_core;

  timeunit 1ns;
  timeprecision 1ps;

  import rv32_pkg::*;

  localparam int unsigned TCM_BYTES   = 4 * 1024;
  localparam int unsigned WORDS       = TCM_BYTES / 4;
  localparam logic [31:0] TRAP_VECTOR = 32'h0000_0100;
  localparam logic [31:0] DONE_ADDR   = 32'h0000_0300;
  localparam logic [31:0] BAD_ADDR    = 32'h0000_0304;
  localparam int unsigned MAX_CYCLES  = 1500;

  logic clk;
  logic rst;
  logic mtip;

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
  logic        trace_is_interrupt;
  logic        trace_control;
  logic        trace_taken;
  logic [31:0] trace_target;

  int unsigned checks;

  rv32_core #(
    .RESET_VECTOR (32'h0000_0000),
    .TRAP_VECTOR  (TRAP_VECTOR)
  ) dut (
    .clk_i                   (clk),
    .rst_i                   (rst),
    .mtip_i                  (mtip),
    .imem_m                  (imem),
    .dmem_m                  (dmem),
    .trace_valid_o           (trace_valid),
    .trace_pc_o              (trace_pc),
    .trace_insn_o            (trace_insn),
    .trace_rd_we_o           (trace_rd_we),
    .trace_rd_addr_o         (trace_rd_addr),
    .trace_rd_data_o         (trace_rd_data),
    .trace_mem_addr_o        (trace_mem_addr),
    .trace_mem_wstrb_o       (trace_mem_wstrb),
    .trace_mem_wdata_o       (trace_mem_wdata),
    .trace_trap_o            (trace_trap),
    .trace_cause_o           (trace_cause),
    .trace_is_interrupt_o    (trace_is_interrupt),
    .trace_control_o         (trace_control),
    .trace_taken_o           (trace_taken),
    .trace_target_o          (trace_target),
    .perf_cycle_o            (),
    .perf_instret_o          (),
    .perf_load_use_stall_o   (),
    .perf_csr_stall_o        (),
    .perf_mdu_stall_o        (),
    .perf_mem_stall_o        (),
    .perf_redirect_o         (),
    .perf_squash_o           ()
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

  function automatic logic [31:0] enc_addi(
    input logic [4:0]  rd,
    input logic [4:0]  rs1,
    input logic [11:0] imm
  );
    enc_addi = {imm, rs1, FUNCT3_ADD_SUB, rd, OPCODE_OP_IMM};
  endfunction

  function automatic logic [31:0] enc_csr(
    input csr_addr_t   address,
    input logic [2:0] funct3,
    input logic [4:0] rd,
    input logic [4:0] source
  );
    enc_csr = {address, source, funct3, rd, OPCODE_SYSTEM};
  endfunction

  function automatic logic [31:0] enc_sw(
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [11:0] offset
  );
    enc_sw = {
      offset[11:5],
      rs2,
      rs1,
      FUNCT3_SW,
      offset[4:0],
      OPCODE_STORE
    };
  endfunction

  function automatic logic [31:0] enc_mdu(
    input logic [2:0] funct3,
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input logic [4:0] rs2
  );
    enc_mdu = {FUNCT7_M, rs2, rs1, funct3, rd, OPCODE_OP};
  endfunction

  function automatic logic [31:0] enc_jal(
    input logic [4:0]  rd,
    input logic [20:0] offset
  );
    enc_jal = {
      offset[20],
      offset[10:1],
      offset[11],
      offset[19:12],
      rd,
      OPCODE_JAL
    };
  endfunction

  task automatic check_bit(
    input logic actual,
    input logic expected,
    input string test_name
  );
    begin
      if (actual !== expected) begin
        $fatal(1, "%s mismatch: expected=%0b actual=%0b", test_name, expected, actual);
      end
      checks++;
    end
  endtask

  task automatic check_word(
    input logic [31:0] actual,
    input logic [31:0] expected,
    input string test_name
  );
    begin
      if (actual !== expected) begin
        $fatal(1, "%s mismatch: expected=%08x actual=%08x", test_name, expected, actual);
      end
      checks++;
    end
  endtask

  task automatic start_phase(input logic pending_at_reset);
    begin
      @(negedge clk);
      rst  = 1'b1;
      mtip = pending_at_reset;
      repeat (3) @(posedge clk);
      #1ps;

      for (int unsigned word_index = 0; word_index < WORDS; word_index++) begin
        u_tcm.mem[word_index] = 32'h0000_0013;
      end
    end
  endtask

  task automatic release_reset;
    begin
      @(negedge clk);
      rst = 1'b0;
    end
  endtask

  task automatic install_enable_sequence;
    begin
      // x1 = MTIE, then set mie.MTIE and mstatus.MIE in program order.
      u_tcm.mem[0] = enc_addi(5'd1, 5'd0, 12'd128);
      u_tcm.mem[1] = enc_csr(CSR_MIE, FUNCT3_CSRRS, 5'd0, 5'd1);
      u_tcm.mem[2] = enc_csr(CSR_MSTATUS, FUNCT3_CSRRSI, 5'd0, 5'd8);
    end
  endtask

  task automatic install_mret_handler;
    begin
      u_tcm.mem[TRAP_VECTOR >> 2] = INSN_MRET;
    end
  endtask

  task automatic run_enable_and_mret_retrigger;
    int unsigned timer_traps;
    int unsigned mret_retirements;
    logic        completed;
    logic [31:0] first_irq_pc;
    logic [31:0] second_irq_pc;
    begin
      start_phase(1'b1);
      install_enable_sequence();
      install_mret_handler();

      u_tcm.mem[3] = enc_addi(5'd2, 5'd0, 12'h041);
      u_tcm.mem[4] = enc_addi(5'd3, 5'd0, 12'h042);
      u_tcm.mem[5] = enc_sw(5'd3, 5'd0, DONE_ADDR[11:0]);
      u_tcm.mem[6] = 32'h0000_006f;

      timer_traps     = 0;
      mret_retirements = 0;
      completed       = 1'b0;
      first_irq_pc    = 32'b0;
      second_irq_pc   = 32'b0;
      release_reset();

      for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
        @(posedge clk);
        #1ps;

        if (trace_valid) begin
          if (trace_trap) begin
            check_word({27'b0, trace_cause}, {27'b0, IRQ_M_TIMER_CAUSE},
                       "pending-enable timer cause");
            check_bit(trace_is_interrupt, 1'b1,
                      "pending-enable interrupt qualifier");
            check_word(trace_insn, 32'b0, "synthetic interrupt instruction metadata");
            check_bit(trace_rd_we, 1'b0, "timer trap has no GPR side effect");
            check_word({28'b0, trace_mem_wstrb}, 32'b0,
                       "timer trap has no memory side effect");

            if (timer_traps == 0) begin
              first_irq_pc = trace_pc;
            end else begin
              second_irq_pc = trace_pc;
              check_bit(mret_retirements != 0, 1'b1,
                        "pending timer waits for first MRET");
              // Stop the level only after proving that MRET can re-enable a
              // still-pending interrupt and cause a second precise trap.
              mtip = 1'b0;
            end
            timer_traps++;
          end else if (trace_pc == TRAP_VECTOR) begin
            check_bit(trace_control, 1'b1, "MRET retirement control metadata");
            check_bit(trace_taken, 1'b1, "MRET retirement taken metadata");
            mret_retirements++;
          end else if ((timer_traps == 1)
                       && (mret_retirements != 0)
                       && (trace_pc == first_irq_pc)) begin
            $fatal(
              1,
              "instruction at mepc retired before pending interrupt retrigger"
            );
          end

          if ((trace_mem_wstrb == 4'b1111) && (trace_mem_addr == DONE_ADDR)) begin
            check_word(trace_mem_wdata, 32'h0000_0042,
                       "pending-enable completion data");
            completed = 1'b1;
          end
        end

        if (completed && (timer_traps == 2) && (mret_retirements == 2)) begin
          break;
        end
      end

      check_bit(completed, 1'b1, "pending-enable phase completed");
      check_word(timer_traps, 32'd2, "one initial and one post-MRET timer trap");
      check_word(mret_retirements, 32'd2, "one MRET per timer trap");
      check_word(first_irq_pc, 32'h0000_000c,
                 "interrupt taken immediately after enable commit");
      check_word(second_irq_pc, first_irq_pc,
                 "pending interrupt retaken immediately after MRET");
    end
  endtask

  task automatic run_disable_shadow;
    logic armed;
    logic completed;
    begin
      start_phase(1'b0);
      install_enable_sequence();
      install_mret_handler();

      u_tcm.mem[3] = enc_csr(CSR_MSTATUS, FUNCT3_CSRRCI, 5'd0, 5'd8);
      u_tcm.mem[4] = enc_addi(5'd2, 5'd0, 12'h066);
      u_tcm.mem[5] = enc_sw(5'd2, 5'd0, DONE_ADDR[11:0]);
      u_tcm.mem[6] = 32'h0000_006f;

      armed     = 1'b0;
      completed = 1'b0;
      release_reset();

      for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
        @(negedge clk);
        #1ps;
        if (dut.id_ex_q.valid && (dut.id_ex_q.pc == 32'h0000_000c)) begin
          mtip = 1'b1;
          #1ps;
          check_bit(dut.mtimer_irq_eligible, 1'b1,
                    "disable-shadow sees pre-commit enable state");
          check_bit(dut.irq_state_ambiguous, 1'b1,
                    "disable-shadow detects in-flight mstatus writer");
          check_bit(dut.id_interrupt_candidate, 1'b0,
                    "disable-shadow blocks interrupt injection");
          armed = 1'b1;
          break;
        end
      end
      check_bit(armed, 1'b1, "disable-shadow stimulus armed");

      for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
        @(posedge clk);
        #1ps;
        if (trace_valid && trace_trap) begin
          $fatal(1, "interrupt escaped disable-shadow at pc=%08x", trace_pc);
        end

        if (trace_valid && (trace_mem_wstrb == 4'b1111)
            && (trace_mem_addr == DONE_ADDR)) begin
          check_word(trace_mem_wdata, 32'h0000_0066,
                     "disable-shadow completion data");
          completed = 1'b1;
          break;
        end
      end

      check_bit(completed, 1'b1, "disable-shadow phase completed");
      check_bit(dut.u_csr_file.mstatus_q[MSTATUS_MIE_BIT], 1'b0,
                "CSRRC committed MIE clear");
      check_bit(dut.id_interrupt_candidate, 1'b0,
                "pending MTIP remains masked after MIE clear");
      mtip = 1'b0;
    end
  endtask

  task automatic run_div_blocking_interrupt;
    logic armed;
    logic div_retired;
    logic timer_trapped;
    logic mret_retired;
    logic completed;
    begin
      start_phase(1'b0);
      install_enable_sequence();
      install_mret_handler();

      u_tcm.mem[3] = enc_addi(5'd4, 5'd0, 12'd100);
      u_tcm.mem[4] = enc_addi(5'd5, 5'd0, 12'd3);
      u_tcm.mem[5] = enc_mdu(FUNCT3_DIV, 5'd6, 5'd4, 5'd5);
      u_tcm.mem[6] = enc_addi(5'd7, 5'd0, 12'h055);
      u_tcm.mem[7] = enc_sw(5'd7, 5'd0, DONE_ADDR[11:0]);
      u_tcm.mem[8] = 32'h0000_006f;

      armed         = 1'b0;
      div_retired   = 1'b0;
      timer_trapped = 1'b0;
      mret_retired  = 1'b0;
      completed     = 1'b0;
      release_reset();

      for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
        @(negedge clk);
        #1ps;
        if (dut.id_ex_q.valid && (dut.id_ex_q.pc == 32'h0000_0014)
            && dut.ex_wait) begin
          mtip = 1'b1;
          #1ps;
          check_bit(dut.id_interrupt_candidate, 1'b1,
                    "DIV wait holds a younger timer candidate");
          check_word(dut.id_ex_decoded.pc, 32'h0000_0018,
                     "DIV wait interrupted-next PC");
          armed = 1'b1;
          break;
        end
      end
      check_bit(armed, 1'b1, "DIV interrupt stimulus armed");

      for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
        @(posedge clk);
        #1ps;
        if (trace_valid) begin
          if (!trace_trap && (trace_pc == 32'h0000_0014)) begin
            check_word(trace_rd_data, 32'd33, "DIV result before interrupt");
            div_retired = 1'b1;
          end

          if (trace_trap) begin
            check_bit(div_retired, 1'b1, "DIV retires before younger interrupt");
            check_bit(trace_is_interrupt, 1'b1,
                      "DIV race interrupt qualifier");
            check_word({27'b0, trace_cause}, {27'b0, IRQ_M_TIMER_CAUSE},
                       "DIV race timer cause");
            check_word(trace_pc, 32'h0000_0018, "DIV race mepc");
            timer_trapped = 1'b1;
            mtip = 1'b0;
          end else if (trace_pc == TRAP_VECTOR) begin
            mret_retired = 1'b1;
          end

          if ((trace_mem_wstrb == 4'b1111) && (trace_mem_addr == DONE_ADDR)) begin
            check_word(trace_mem_wdata, 32'h0000_0055,
                       "DIV interrupt completion data");
            completed = 1'b1;
            break;
          end
        end
      end

      check_bit(timer_trapped, 1'b1, "DIV timer trap observed");
      check_bit(mret_retired, 1'b1, "DIV timer handler returned");
      check_bit(completed, 1'b1, "DIV interrupt phase completed");
    end
  endtask

  task automatic run_redirect_interrupt_priority;
    logic armed;
    logic timer_trapped;
    logic mret_retired;
    logic completed;
    begin
      start_phase(1'b0);
      install_enable_sequence();
      install_mret_handler();

      // Two NOPs let both enable writers commit before JAL reaches EX. MTIP is
      // asserted exactly while the taken JAL redirects and a wrong-path store
      // is at the ID boundary. The redirect must reject that interrupt packet;
      // the still-pending level is then retaken at the target PC.
      u_tcm.mem[3] = 32'h0000_0013;
      u_tcm.mem[4] = 32'h0000_0013;
      u_tcm.mem[5] = enc_jal(5'd0, 21'd8);
      u_tcm.mem[6] = enc_sw(5'd0, 5'd0, BAD_ADDR[11:0]);
      u_tcm.mem[7] = enc_addi(5'd7, 5'd0, 12'h077);
      u_tcm.mem[8] = enc_sw(5'd7, 5'd0, DONE_ADDR[11:0]);
      u_tcm.mem[9] = 32'h0000_006f;

      armed         = 1'b0;
      timer_trapped = 1'b0;
      mret_retired  = 1'b0;
      completed     = 1'b0;
      release_reset();

      for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
        @(negedge clk);
        #1ps;
        if (dut.id_ex_q.valid
            && (dut.id_ex_q.pc == 32'h0000_0014)
            && dut.control_redirect.valid) begin
          mtip = 1'b1;
          #1ps;
          check_word(dut.control_redirect.target, 32'h0000_001c,
                     "redirect race target");
          check_word(dut.id_ex_decoded.pc, 32'h0000_0018,
                     "redirect race wrong-path candidate PC");
          check_bit(dut.mtimer_irq_eligible, 1'b1,
                    "redirect race timer eligible");
          check_bit(dut.id_interrupt_candidate, 1'b1,
                    "redirect race builds interrupt candidate");
          check_bit(dut.id_interrupt, 1'b1,
                    "redirect race presents interrupt event");
          check_bit(dut.redirect_valid, 1'b1,
                    "older EX redirect selected");
          check_bit(dut.id_ex_flush, 1'b1,
                    "redirect rejects wrong-path interrupt packet");
          armed = 1'b1;
          break;
        end
      end
      check_bit(armed, 1'b1, "redirect interrupt stimulus armed");

      for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
        @(posedge clk);
        #1ps;
        if (trace_valid) begin
          if (trace_trap) begin
            check_bit(trace_is_interrupt, 1'b1,
                      "redirect race interrupt qualifier");
            check_word({27'b0, trace_cause}, {27'b0, IRQ_M_TIMER_CAUSE},
                       "redirect race timer cause");
            check_word(trace_pc, 32'h0000_001c,
                       "redirect race retaken target PC");
            timer_trapped = 1'b1;
            mtip = 1'b0;
          end else if (trace_pc == TRAP_VECTOR) begin
            mret_retired = 1'b1;
          end

          if ((trace_mem_wstrb == 4'b1111) && (trace_mem_addr == BAD_ADDR)) begin
            $fatal(1, "wrong-path store retired during redirect/interrupt race");
          end

          if ((trace_mem_wstrb == 4'b1111) && (trace_mem_addr == DONE_ADDR)) begin
            check_word(trace_mem_wdata, 32'h0000_0077,
                       "redirect interrupt completion data");
            completed = 1'b1;
            break;
          end
        end
      end

      check_bit(timer_trapped, 1'b1, "redirect timer trap observed");
      check_bit(mret_retired, 1'b1, "redirect timer handler returned");
      check_bit(completed, 1'b1, "redirect interrupt phase completed");
      check_word(u_tcm.mem[BAD_ADDR >> 2], 32'h0000_0013,
                 "redirect wrong-path memory unchanged");
    end
  endtask

  task automatic install_delayed_illegal_program;
    begin
      install_enable_sequence();
      u_tcm.mem[3] = 32'h0000_0013;
      u_tcm.mem[4] = 32'h0000_0013;
      u_tcm.mem[5] = 32'h0000_0013;
      u_tcm.mem[6] = 32'hffff_ffff;
    end
  endtask

  task automatic run_simultaneous_exception;
    logic armed;
    logic trapped;
    begin
      start_phase(1'b0);
      install_delayed_illegal_program();
      armed   = 1'b0;
      trapped = 1'b0;
      release_reset();

      for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
        @(negedge clk);
        #1ps;
        if (dut.id_ex_decoded.valid
            && (dut.id_ex_decoded.pc == 32'h0000_0018)
            && dut.id_ex_decoded.exc.valid) begin
          mtip = 1'b1;
          #1ps;
          check_bit(dut.mtimer_irq_eligible, 1'b1,
                    "simultaneous exception timer eligible");
          check_bit(dut.id_interrupt_candidate, 1'b0,
                    "synchronous ID exception beats timer");
          armed = 1'b1;
          break;
        end
      end
      check_bit(armed, 1'b1, "simultaneous exception stimulus armed");

      for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
        @(posedge clk);
        #1ps;
        if (trace_valid && trace_trap) begin
          check_bit(trace_is_interrupt, 1'b0,
                    "simultaneous trap remains synchronous");
          check_word({27'b0, trace_cause}, {27'b0, EXC_ILLEGAL_INSN},
                     "simultaneous illegal cause");
          check_word(trace_pc, 32'h0000_0018, "simultaneous illegal mepc");
          check_word(trace_insn, 32'hffff_ffff,
                     "simultaneous illegal instruction metadata");
          trapped = 1'b1;
          mtip = 1'b0;
          break;
        end
      end
      check_bit(trapped, 1'b1, "simultaneous synchronous trap observed");

      @(posedge clk);
      #1ps;
      check_word(dut.u_csr_file.mcause_q, 32'd2,
                 "simultaneous committed mcause");
      check_word(dut.u_csr_file.mepc_q, 32'h0000_0018,
                 "simultaneous committed mepc");
    end
  endtask

  task automatic run_trap_drain_pending;
    logic armed;
    logic trapped;
    begin
      start_phase(1'b0);
      install_delayed_illegal_program();
      armed   = 1'b0;
      trapped = 1'b0;
      release_reset();

      for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
        @(negedge clk);
        #1ps;
        if (dut.trap_drain
            && dut.u_csr_file.mstatus_q[MSTATUS_MIE_BIT]
            && dut.u_csr_file.mie_q[MINT_MTIP_BIT]) begin
          mtip = 1'b1;
          #1ps;
          check_bit(dut.mtimer_irq_eligible, 1'b1,
                    "trap-drain timer becomes eligible");
          check_bit(dut.id_interrupt_candidate, 1'b0,
                    "trap-drain blocks new interrupt packet");
          armed = 1'b1;
          break;
        end
      end
      check_bit(armed, 1'b1, "trap-drain stimulus armed");

      for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
        @(posedge clk);
        #1ps;
        if (trace_valid && trace_trap) begin
          check_bit(trace_is_interrupt, 1'b0,
                    "trap-drain preserves older synchronous trap");
          check_word({27'b0, trace_cause}, {27'b0, EXC_ILLEGAL_INSN},
                     "trap-drain older cause");
          check_word(trace_pc, 32'h0000_0018, "trap-drain older mepc");
          trapped = 1'b1;
          mtip = 1'b0;
          break;
        end
      end
      check_bit(trapped, 1'b1, "trap-drain synchronous trap observed");
    end
  endtask

  initial begin
    clk    = 1'b0;
    rst    = 1'b1;
    mtip   = 1'b0;
    checks = 0;

    run_enable_and_mret_retrigger();
    run_disable_shadow();
    run_div_blocking_interrupt();
    run_redirect_interrupt_priority();
    run_simultaneous_exception();
    run_trap_drain_pending();

    $display("tb_timer_interrupt_core: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
