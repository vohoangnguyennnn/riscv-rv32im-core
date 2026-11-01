`timescale 1ns/1ps

// Exercise synchronous SoC reset at real CPU/fabric transaction boundaries.
// All stimulus changes occur on falling edges; handshakes are sampled before
// rising-edge NBA updates. A different reboot program detects stale packets.
module tb_soc_reset;

  import rv32_pkg::*;
  import rv32_tb_pkg::*;

  localparam int unsigned TCM_BYTES = 1024;
  localparam int unsigned MAX_CYCLES = 1500;
  localparam logic [31:0] STATUS_ADDR = TCM_BYTES - 4;
  localparam logic [31:0] RESULT_ADDR = 32'h0000_0200;
  localparam logic [31:0] REBOOT_PC = 32'h0000_0040;
  localparam logic [31:0] UART_ADDR = 32'h1000_0000;
  localparam int unsigned UART_CLKS_PER_BIT = 16;

  logic clk = 1'b0;
  logic rst = 1'b1;
  logic uart_tx;
  logic [31:0] gpio_out;
  logic [31:0] gpio_oe;
  logic test_done;
  logic test_pass;
  logic test_fail;
  logic trace_valid;
  logic [31:0] trace_pc;
  logic trace_trap;
  logic reboot_active = 1'b0;
  int unsigned checks = 0;
  int unsigned scenarios = 0;
  int unsigned reboot_retirements = 0;
  string scenario_name;

  soc_tcm_top #(
    .TCM_BYTES        (TCM_BYTES),
    .TEST_STATUS_ADDR (STATUS_ADDR),
    .UART_CLK_FREQ_HZ (1_600_000),
    .UART_BAUD_RATE   (100_000)
  ) dut (
    .clk_i                   (clk),
    .rst_i                   (rst),
    .uart_rx_i               (1'b1),
    .uart_tx_o               (uart_tx),
    .gpio_in_i               (32'b0),
    .gpio_out_o              (gpio_out),
    .gpio_oe_o               (gpio_oe),
    .test_done_o             (test_done),
    .test_pass_o             (test_pass),
    .test_fail_o             (test_fail),
    .test_status_o           (),
    .trace_valid_o           (trace_valid),
    .trace_pc_o              (trace_pc),
    .trace_insn_o            (),
    .trace_rd_we_o           (),
    .trace_rd_addr_o         (),
    .trace_rd_data_o         (),
    .trace_mem_addr_o        (),
    .trace_mem_wstrb_o       (),
    .trace_mem_wdata_o       (),
    .trace_trap_o            (trace_trap),
    .trace_cause_o           (),
    .trace_is_interrupt_o    (),
    .trace_control_o         (),
    .trace_taken_o           (),
    .trace_target_o          (),
    .perf_cycle_o            (),
    .perf_instret_o          (),
    .perf_load_use_stall_o    (),
    .perf_csr_stall_o         (),
    .perf_mdu_stall_o         (),
    .perf_mem_stall_o         (),
    .perf_redirect_o         (),
    .perf_squash_o           ()
  );

  always #5 clk = ~clk;

  task automatic check(input logic condition, input string description);
    if (condition !== 1'b1) begin
      $fatal(1, "%s: %s", scenario_name, description);
    end
    checks++;
  endtask

  // The UART reads BAUDDIV because TXDATA's busy bit varies with time.
  // Every other target reads back the value just stored. A second UART store
  // creates actual CPU backpressure without forcing any DUT signals.
  task automatic load_program(
    input int unsigned first_word,
    input logic [31:0] store_addr,
    input logic [31:0] load_addr,
    input logic [11:0] value,
    input logic double_store
  );
    int unsigned cursor;
    cursor = first_word;
    dut.u_tcm.mem[cursor++] = enc_lui(5'd1, store_addr[31:12]);
    dut.u_tcm.mem[cursor++] = enc_addi(5'd1, 5'd1, store_addr[11:0]);
    dut.u_tcm.mem[cursor++] = enc_addi(5'd2, 5'd0, value);
    dut.u_tcm.mem[cursor++] = enc_sw(5'd2, 5'd1, 12'b0);
    if (double_store) begin
      dut.u_tcm.mem[cursor++] = enc_sw(5'd2, 5'd1, 12'b0);
    end
    dut.u_tcm.mem[cursor++] = enc_lw(5'd3, 5'd1, load_addr[11:0] - store_addr[11:0]);
    dut.u_tcm.mem[cursor++] = enc_sw(5'd3, 5'd0, RESULT_ADDR[11:0]);
    dut.u_tcm.mem[cursor++] = enc_addi(5'd4, 5'd0, 12'd1);
    dut.u_tcm.mem[cursor++] = enc_sw(5'd4, 5'd0, STATUS_ADDR[11:0]);
    dut.u_tcm.mem[cursor]   = enc_jal(5'd0, 21'b0);
  endtask

  task automatic prepare_case(
    input string name,
    input logic [31:0] store_addr,
    input logic [31:0] load_addr,
    input logic double_store
  );
    @(negedge clk);
    rst = 1'b1;
    reboot_active = 1'b0;
    scenario_name = name;
    // Settle any preceding phase before changing its instruction memory.
    repeat (4) @(negedge clk);
    for (int unsigned index = 0; index < TCM_BYTES / 4; index++) begin
      dut.u_tcm.mem[index] = TB_NOP;
    end
    dut.u_tcm.mem[RESULT_ADDR / 4] = 32'hdead_beef;
    load_program(0, store_addr, load_addr, 12'h055, double_store);
    rst = 1'b0;
  endtask

  task automatic wait_for_request(
    input logic [31:0] address,
    input logic write_access,
    input logic backpressured
  );
    bit observed;
    observed = 1'b0;
    for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
      @(posedge clk);
      if (dut.core_dmem.req_valid
          && (dut.core_dmem.req_addr == address)
          && (dut.core_dmem.req_write == write_access)
          && (dut.core_dmem.req_ready == !backpressured)) begin
        observed = 1'b1;
        break;
      end
    end
    check(observed, "timed out waiting for requested transaction boundary");
    @(negedge clk);
  endtask

  task automatic reset_and_reboot(
    input logic [31:0] store_addr,
    input logic [31:0] load_addr,
    input logic double_store,
    input logic response_expected,
    input int unsigned hold_cycles
  );
    // The caller is on a falling edge after the selected transaction boundary.
    rst = 1'b1;
    #1ps;
    check(!dut.core_dmem.req_ready, "reset must block new data handshakes");
    check(dut.core_dmem.rsp_valid == response_expected,
          "an accepted response must remain visible for reset-time drain");
    if (response_expected) begin
      check(dut.u_core.u_lsu.request_sent_q,
            "reset stimulus must interrupt an accepted LSU transaction");
    end

    for (int unsigned cycle = 0; cycle < hold_cycles; cycle++) begin
      @(posedge clk);
      #1ps;
      check(!test_done && !test_pass && !test_fail, "reset must clear completion");
      check(!trace_valid, "reset must clear retirement packets");
      check(!dut.u_core.u_lsu.request_sent_q && !dut.u_core.u_lsu.discard_q,
            "LSU must release the drained transaction at the reset edge");
      check(!dut.u_dmem_demux.pending_q, "reset must clear demux ownership");
      check(!dut.core_dmem.rsp_valid, "drained response must not repeat");
      check(!dut.tcm_dmem.req_valid && !dut.timer_bus.req_valid
            && !dut.uart_bus.req_valid && !dut.gpio_bus.req_valid,
            "reset must suppress requests to all data targets");
      check(uart_tx && (gpio_out == 32'b0) && (gpio_oe == 32'b0),
            "reset must return peripheral outputs to idle");
    end

    @(negedge clk);
    // Old packets use PCs 0x04..0x24 and value 0x55. The new boot jumps to a
    // disjoint PC range and stores 0x2a, exposing stale retirement/load results.
    dut.u_tcm.mem[0] = enc_jal(5'd0, 21'h000040);
    load_program(REBOOT_PC / 4, store_addr, load_addr, 12'h02a, double_store);
    dut.u_tcm.mem[RESULT_ADDR / 4] = 32'hdead_beef;
    reboot_retirements = 0;
    reboot_active = 1'b1;
    rst = 1'b0;
  endtask

  task automatic wait_for_completion(input logic [31:0] expected_result);
    bit completed;
    completed = 1'b0;
    for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
      @(negedge clk);
      if (test_done) begin
        completed = 1'b1;
        break;
      end
    end
    check(completed, "CPU failed to complete within the reboot deadline");
    check(test_pass && !test_fail, "reboot program must report PASS");
    check(dut.u_tcm.mem[RESULT_ADDR / 4] == expected_result,
          "reboot load/store result must match the new program");
    if (reboot_active) begin
      check(reboot_retirements != 0, "reboot must retire its entry instruction");
    end
    scenarios++;
    $display("tb_soc_reset: %s PASS", scenario_name);
  endtask

  always @(posedge clk) begin
    if (!rst && trace_valid) begin
      check(!trace_trap, "test programs must not trap");
      if (reboot_active) begin
        if (reboot_retirements == 0) begin
          check(trace_pc == 32'b0, "first reboot retirement must be the reset vector");
        end else begin
          check((trace_pc >= REBOOT_PC) && (trace_pc < 32'h0000_0100),
                "pre-reset instruction escaped into the reboot retirement stream");
        end
        reboot_retirements++;
      end
    end
  end

  initial begin : run_scenarios
    logic [31:0] store_addr;
    logic [31:0] load_addr;
    logic [31:0] expected_result;

    // Control run establishes the same full-SoC program's normal completion.
    prepare_case("no injected reset", 32'h0000_0300, 32'h0000_0300, 1'b0);
    wait_for_completion(32'h0000_0055);

    for (int unsigned target = 0; target < 4; target++) begin
      case (target)
        0: begin store_addr = 32'h0000_0300; load_addr = store_addr; end
        1: begin store_addr = 32'h0200_4000; load_addr = store_addr; end
        2: begin store_addr = UART_ADDR; load_addr = UART_ADDR + 32'hc; end
        3: begin store_addr = 32'h1001_0004; load_addr = store_addr; end
        default: $fatal(1, "invalid reset test target");
      endcase
      expected_result = (target == 2) ? UART_CLKS_PER_BIT : 32'h0000_002a;

      for (int unsigned access_kind = 0; access_kind < 2; access_kind++) begin
        prepare_case($sformatf("target %0d accepted %s", target,
                              (access_kind == 0) ? "store" : "load"),
                     store_addr, load_addr, 1'b0);
        wait_for_request((access_kind == 0) ? store_addr : load_addr,
                         access_kind == 0, 1'b0);
        reset_and_reboot(store_addr, load_addr, 1'b0, 1'b1,
                         (access_kind == 0) ? 1 : 4);
        wait_for_completion(expected_result);
      end
    end

    prepare_case("UART unaccepted store", UART_ADDR, UART_ADDR + 32'hc, 1'b1);
    wait_for_request(UART_ADDR, 1'b1, 1'b1);
    check(!dut.u_core.u_lsu.request_sent_q,
          "backpressured store must not be marked accepted");
    check(!dut.u_dmem_demux.pending_q,
          "backpressured store must not own a demux response");
    reset_and_reboot(UART_ADDR, UART_ADDR + 32'hc, 1'b1, 1'b0, 7);
    wait_for_completion(UART_CLKS_PER_BIT);

    // Repeated idle resets prove the preceding scenarios leave no stale slot.
    repeat (2) begin
      scenario_name = "repeated idle reset";
      @(negedge clk);
      check(!dut.u_dmem_demux.pending_q, "idle reset must start without a pending response");
      reset_and_reboot(32'h0000_0300, 32'h0000_0300, 1'b0, 1'b0, 4);
      wait_for_completion(32'h0000_002a);
    end

    $display("tb_soc_reset: PASS (%0d scenarios, %0d checks)", scenarios, checks);
    $finish;
  end

  // Bound every wait, including future edits that accidentally bypass a task's
  // local timeout. A broken drain must fail CI rather than hang the job.
  initial begin
    repeat (MAX_CYCLES * 20) @(posedge clk);
    $fatal(1, "tb_soc_reset global timeout");
  end

endmodule
