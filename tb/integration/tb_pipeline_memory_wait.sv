// SPDX-License-Identifier: MIT

// Gate-4 integration test for request backpressure, delayed responses, load-use
// ordering, and MDU launch suppression behind an older unresolved memory op.
module tb_pipeline_memory_wait;

  timeunit 1ns;
  timeprecision 1ps;

  import rv32_pkg::*;
  import rv32_tb_pkg::*;

  localparam int unsigned MEM_BYTES = 2048;
  localparam logic [31:0] SIG_BASE  = 32'h0000_0400;
  localparam logic [31:0] DATA_BASE = 32'h0000_0500;
  localparam logic [31:0] DONE_ADDR = 32'h0000_07fc;

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

  int unsigned cycles;
  int unsigned checks;
  int unsigned mem_wait_cycles;
  int unsigned ex_wait_cycles;
  int unsigned request_backpressure_cycles;
  int unsigned dmem_request_count;
  int unsigned load_bubble_count;
  int unsigned retire_count [0:(MEM_BYTES/4)-1];

  rv32_core dut (
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

  rv32_delayed_mem #(
    .BYTES          (MEM_BYTES),
    .DMEM_REQ_DELAY (3),
    .DMEM_RSP_DELAY (6)
  ) u_mem (
    .clk_i  (clk),
    .rst_i  (rst),
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

  initial begin : initialize_program
    clk                         = 1'b0;
    rst                         = 1'b1;
    cycles                      = 0;
    checks                      = 0;
    mem_wait_cycles             = 0;
    ex_wait_cycles              = 0;
    request_backpressure_cycles = 0;
    dmem_request_count          = 0;
    load_bubble_count           = 0;

    for (int unsigned word_index = 0; word_index < (MEM_BYTES / 4); word_index++) begin
      u_mem.mem[word_index] = TB_NOP;
      retire_count[word_index] = 0;
    end

    u_mem.mem[0] = enc_addi(5'd31, 5'd0, SIG_BASE[11:0]);
    u_mem.mem[1] = enc_addi(5'd30, 5'd0, DATA_BASE[11:0]);
    u_mem.mem[2] = enc_addi(5'd3, 5'd0, 12'd9);
    u_mem.mem[3] = enc_lw(5'd1, 5'd30, 12'd0);
    u_mem.mem[4] = enc_mdu(FUNCT3_MUL, 5'd2, 5'd1, 5'd3);
    u_mem.mem[5] = enc_addi(5'd4, 5'd2, 12'd1);
    u_mem.mem[6] = enc_sw(5'd4, 5'd31, 12'd0);
    u_mem.mem[7] = enc_lw(5'd5, 5'd30, 12'd4);
    u_mem.mem[8] = enc_sw(5'd5, 5'd31, 12'd4);
    u_mem.mem[9] = enc_addi(5'd6, 5'd5, 12'd2);
    u_mem.mem[10] = enc_sw(5'd6, 5'd31, 12'd8);
    // The branch enters ID/EX with a stale x8 snapshot, then waits behind the
    // store while x8 commits in WB. The held packet must absorb that WB value
    // after MEM/WB forwarding disappears.
    u_mem.mem[11] = enc_addi(5'd9, 5'd0, 12'd16);
    u_mem.mem[12] = enc_addi(5'd8, 5'd0, 12'd16);
    u_mem.mem[13] = enc_sw(5'd8, 5'd31, 12'd12);
    u_mem.mem[14] = enc_branch(FUNCT3_BEQ, 5'd8, 5'd9, 13'd12);
    u_mem.mem[15] = enc_sw(5'd0, 5'd31, 12'd20);
    u_mem.mem[16] = enc_addi(5'd10, 5'd0, 12'h7ff);
    u_mem.mem[17] = enc_addi(5'd10, 5'd0, 12'h033);
    u_mem.mem[18] = enc_sw(5'd10, 5'd31, 12'd16);
    u_mem.mem[19] = enc_addi(5'd7, 5'd0, 12'h05a);
    u_mem.mem[20] = enc_sw(5'd7, 5'd0, DONE_ADDR[11:0]);
    u_mem.mem[21] = enc_jal(5'd0, 21'd0);

    u_mem.mem[DATA_BASE >> 2]           = 32'd7;
    u_mem.mem[(DATA_BASE + 32'd4) >> 2] = 32'h1234_5678;
    u_mem.mem[SIG_BASE >> 2]            = 32'hdead_beef;
    u_mem.mem[(SIG_BASE + 32'd4) >> 2]  = 32'hdead_beef;
    u_mem.mem[(SIG_BASE + 32'd8) >> 2]  = 32'hdead_beef;
    u_mem.mem[(SIG_BASE + 32'd12) >> 2] = 32'hdead_beef;
    u_mem.mem[(SIG_BASE + 32'd16) >> 2] = 32'hdead_beef;
    u_mem.mem[(SIG_BASE + 32'd20) >> 2] = 32'hdead_beef;
    u_mem.mem[DONE_ADDR >> 2]           = 32'b0;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
  end

  always @(negedge clk) begin
    if (!rst) begin
      if (dut.mem_wait) mem_wait_cycles++;
      if (dut.ex_wait)  ex_wait_cycles++;
      if (dmem.req_valid && !dmem.req_ready) request_backpressure_cycles++;
      if (dmem.req_valid && dmem.req_ready) dmem_request_count++;

      // An MDU request must not launch while an older memory operation owns
      // EX/MEM. This is the key ordering invariant behind result_ready_i.
      if (
        dut.mem_wait &&
        (dut.u_ex_stage.mul_req_valid || dut.u_ex_stage.div_req_valid)
      ) begin
        $fatal(1, "MDU request launched behind an unresolved memory operation");
      end

      if (
        dut.load_use_hazard &&
        dut.id_ex_flush &&
        !dut.if_id_enable &&
        dut.ex_mem_enable
      ) begin
        load_bubble_count++;
      end
    end
  end

  always @(posedge clk) begin : monitor_retirement
    int unsigned pc_word;

    #1ps;
    if (!rst) begin
      cycles++;

      if (trace_valid) begin
        if (trace_trap) begin
          $fatal(
            1,
            "unexpected trap pc=%08x insn=%08x cause=%0d",
            trace_pc,
            trace_insn,
            trace_cause
          );
        end

        pc_word = trace_pc >> 2;
        retire_count[pc_word]++;
        if (retire_count[pc_word] > 1) begin
          $fatal(1, "instruction retired more than once during memory wait pc=%08x", trace_pc);
        end

        if (trace_rd_we && (trace_pc == 32'h0000_0010)) begin
          check_word({27'b0, trace_rd_addr}, 32'd2, "load-dependent MUL destination");
          check_word(trace_rd_data, 32'd63, "load-dependent MUL result");
        end
        if (trace_rd_we && (trace_pc == 32'h0000_0014)) begin
          check_word(trace_rd_data, 32'd64, "MDU-dependent ALU result");
        end

        if ((trace_mem_wstrb != 4'b0000) && (trace_mem_addr == DONE_ADDR)) begin
          check_word(trace_mem_wdata, 32'h0000_005a, "completion store data");
          check_word(u_mem.mem[SIG_BASE >> 2], 32'd64, "delayed load/MDU/store signature");
          check_word(
            u_mem.mem[(SIG_BASE + 32'd4) >> 2],
            32'h1234_5678,
            "delayed load to store-data signature"
          );
          check_word(
            u_mem.mem[(SIG_BASE + 32'd8) >> 2],
            32'h1234_567a,
            "post-wait dependent ALU signature"
          );
          check_word(
            u_mem.mem[(SIG_BASE + 32'd12) >> 2],
            32'd16,
            "producer value stored before delayed hold"
          );
          check_word(
            u_mem.mem[(SIG_BASE + 32'd16) >> 2],
            32'h0000_0033,
            "held ID/EX operand refreshed from WB"
          );
          check_word(
            u_mem.mem[(SIG_BASE + 32'd20) >> 2],
            32'hdead_beef,
            "stale held operand did not select wrong path"
          );

          if (dmem_request_count != 8) begin
            $fatal(1, "expected 8 accepted data requests, observed %0d", dmem_request_count);
          end
          if (load_bubble_count != 2) begin
            $fatal(1, "expected 2 load-use bubbles, observed %0d", load_bubble_count);
          end
          if ((mem_wait_cycles < 40) || (request_backpressure_cycles < 15)) begin
            $fatal(
              1,
              "insufficient wait coverage: mem_wait=%0d request_backpressure=%0d",
              mem_wait_cycles,
              request_backpressure_cycles
            );
          end
          if (ex_wait_cycles < 2) begin
            $fatal(1, "MDU wait was not observed");
          end
          checks += 7;

          $display(
            "tb_pipeline_memory_wait: PASS (%0d cycles, mem_wait=%0d, req_backpressure=%0d)",
            cycles,
            mem_wait_cycles,
            request_backpressure_cycles
          );
          $finish;
        end
      end

      if (cycles > 1200) begin
        $fatal(1, "pipeline memory-wait integration timeout after %0d cycles", cycles);
      end
    end
  end

endmodule
