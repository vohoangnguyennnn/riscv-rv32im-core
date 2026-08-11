// SPDX-License-Identifier: MIT

module tb_fpga_top;

  timeunit 1ns;
  timeprecision 1ps;

  localparam int unsigned TCM_BYTES = 512;
  localparam logic [31:0] STATUS_ADDR = TCM_BYTES - 4;
  localparam int unsigned RESET_STAGES = 3;
  localparam int unsigned MAX_CYCLES = 500;

  logic clk;
  logic reset_n;
  logic led1_n;
  logic led2_n;
  logic fail;
  logic done;
  logic [3:0] physical_status;
  int unsigned checks;

  fpga_top #(
    .TCM_BYTES         (TCM_BYTES),
    .TCM_INIT_FILE     ("tb/data/fpga_smoke.mem"),
    .TEST_STATUS_ADDR  (STATUS_ADDR),
    .RESET_SYNC_STAGES (RESET_STAGES),
    .HEARTBEAT_WIDTH   (3)
  ) dut (
    .clk_50m_i (clk),
    .reset_ni  (reset_n),
    .led1_n_o  (led1_n),
    .led2_n_o  (led2_n),
    .fail_o    (fail),
    .done_o    (done)
  );

  assign physical_status = {done, fail, led2_n, led1_n};

  always #5 clk = ~clk;

  task automatic check_bit(
    input logic actual,
    input logic expected,
    input string test_name
  );
    begin
      if (actual !== expected) begin
        $fatal(1, "%s mismatch: expected=%0b result=%0b", test_name, expected, actual);
      end
      checks++;
    end
  endtask

  task automatic check_nibble(
    input logic [3:0] actual,
    input logic [3:0] expected,
    input string test_name
  );
    begin
      if (actual !== expected) begin
        $fatal(1, "%s mismatch: expected=%x result=%x", test_name, expected, actual);
      end
      checks++;
    end
  endtask

  task automatic release_reset;
    begin
      @(negedge clk);
      reset_n = 1'b1;

      repeat (RESET_STAGES) begin
        @(posedge clk);
        #1ps;
        check_bit(dut.soc_rst, 1'b1, "FPGA reset release pipeline holds");
        check_nibble(physical_status, 4'b0011,
                     "physical outputs remain inactive during reset release");
      end

      @(posedge clk);
      #1ps;
      check_bit(dut.soc_rst, 1'b0, "FPGA reset releases synchronously");
    end
  endtask

  task automatic wait_for_done(input logic [3:0] expected_leds, input string test_name);
    bit completed;
    begin
      completed = 1'b0;
      for (int unsigned cycle = 0; cycle < MAX_CYCLES; cycle++) begin
        @(posedge clk);
        #1ps;
        if (done) begin
          completed = 1'b1;
          break;
        end
      end
      if (!completed) begin
        $fatal(1, "%s timed out", test_name);
      end
      check_nibble(physical_status, expected_leds, test_name);
    end
  endtask

  initial begin
    clk     = 1'b0;
    reset_n = 1'b1;
    checks  = 0;

    // Drive an explicit inactive-to-active transition; this models the board
    // reset pin and avoids relying on simulator-specific X-to-0 initialization.
    #1ps;
    reset_n = 1'b0;
    #1ps;
    check_bit(dut.soc_rst, 1'b1, "power-on reset asserted asynchronously");
    check_nibble(physical_status, 4'b0011, "power-on outputs inactive");
    check_nibble(dut.u_soc.u_tcm.mem[0][3:0], 4'h3, "FPGA image initialized");

    // DONE is high, FAIL is low, the active-low PASS LED is illuminated, and
    // the active-low heartbeat LED is off after completion.
    release_reset();
    wait_for_done(4'b1001, "A7-Lite PASS pin mapping");

    // The private synchronizer accepts reset asynchronously, while the SoC
    // functional reset and LED blanking change only on a clock edge. This
    // prevents an async-reset register from feeding inferred BRAM controls.
    @(negedge clk);
    #2ns;
    reset_n = 1'b0;
    #1ps;
    check_bit(dut.soc_rst, 1'b0, "SoC reset waits for a clock edge");
    @(posedge clk);
    #1ps;
    check_bit(dut.soc_rst, 1'b1, "runtime FPGA reset asserts synchronously");
    check_nibble(physical_status, 4'b0011, "runtime reset deactivates outputs");

    // Replace the image while reset is asserted and prove a non-pass mailbox
    // value maps to stable done+fail LEDs.
    dut.u_soc.u_tcm.mem[0] = 32'h0070_0093; // addi x1, x0, 7
    dut.u_soc.u_tcm.mem[1] = 32'h1e10_2e23; // sw x1, 508(x0)
    dut.u_soc.u_tcm.mem[2] = 32'h0000_006f; // jal x0, 0
    release_reset();
    wait_for_done(4'b1111, "A7-Lite FAIL pin mapping");

    // A program that never writes the mailbox leaves done/pass/fail low while
    // the small test heartbeat counter demonstrates observable liveness.
    @(negedge clk);
    reset_n = 1'b0;
    #1ps;
    dut.u_soc.u_tcm.mem[0] = 32'h0000_006f;
    release_reset();
    repeat (4) @(posedge clk);
    #1ps;
    check_bit(done,   1'b0, "running program has not completed");
    check_bit(fail,   1'b0, "running program has not failed");
    check_bit(led2_n, 1'b1, "active-low PASS LED remains off");
    check_bit(led1_n, 1'b0, "active-low heartbeat LED is illuminated");

    $display("tb_fpga_top: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
