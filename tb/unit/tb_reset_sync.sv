// SPDX-License-Identifier: MIT

module tb_reset_sync;

  timeunit 1ns;
  timeprecision 1ps;

  localparam int unsigned STAGES = 3;

  logic clk;
  logic arst_n;
  logic rst;
  int unsigned checks;

  reset_sync #(
    .STAGES (STAGES)
  ) dut (
    .clk_i   (clk),
    .arst_ni (arst_n),
    .rst_o   (rst)
  );

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

  initial begin
    clk     = 1'b0;
    arst_n  = 1'b1;
    checks  = 0;

    // FPGA initialization holds the functional reset active. Assertion is
    // independent of the clock for the private synchronizer stages, but the
    // reset exported to the SoC remains a synchronous signal.
    #2ns;
    arst_n = 1'b0;
    #1ps;
    check_bit(rst, 1'b1, "power-up functional reset active");
    check_bit(|dut.reset_pipe_q, 1'b0, "all synchronizer stages cleared");

    // Release between clock edges. Reset must remain active until exactly the
    // configured number of rising edges has shifted through the chain and the
    // dedicated functional-reset register has sampled the released state.
    #2ns;
    arst_n = 1'b1;
    #1ps;
    check_bit(rst, 1'b1, "no asynchronous deassertion");

    for (int unsigned stage = 0; stage < STAGES; stage++) begin
      @(posedge clk);
      #1ps;
      check_bit(rst, 1'b1, $sformatf("deassertion stage %0d holds reset", stage));
    end

    @(posedge clk);
    #1ps;
    check_bit(rst, 1'b0, "functional reset releases synchronously");
    check_bit(&dut.reset_pipe_q, 1'b1, "all synchronizer stages released");

    // Reassert after normal operation and repeat the release to prove the
    // chain is reusable rather than relying on power-up initialization.
    @(negedge clk);
    #2ns;
    arst_n = 1'b0;
    #1ps;
    check_bit(rst, 1'b0, "functional reset does not assert asynchronously");
    check_bit(|dut.reset_pipe_q, 1'b0, "runtime assertion clears synchronizer");

    @(posedge clk);
    #1ps;
    check_bit(rst, 1'b1, "runtime functional reset asserts synchronously");

    @(negedge clk);
    arst_n = 1'b1;
    repeat (STAGES) begin
      @(posedge clk);
      #1ps;
      check_bit(rst, 1'b1, "runtime release remains synchronized");
    end
    @(posedge clk);
    #1ps;
    check_bit(rst, 1'b0, "runtime release completes synchronously");

    $display("tb_reset_sync: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
