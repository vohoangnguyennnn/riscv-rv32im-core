// SPDX-License-Identifier: MIT

module tb_rv32_tcm;

  localparam int unsigned TEST_BYTES = 64;
  localparam logic [31:0] TEST_BASE  = 32'h0000_1000;

  logic clk;
  int   checks;

  rv32_mem_if imem();
  rv32_mem_if dmem();

  rv32_tcm #(
    .BYTES     (TEST_BYTES),
    .BASE_ADDR (TEST_BASE)
  ) dut (
    .clk_i  (clk),
    .imem_s (imem),
    .dmem_s (dmem)
  );

  always #5 clk = ~clk;

  task automatic check_bit(
    input logic  actual,
    input logic  expected,
    input string test_name
  );
    begin
      if (actual !== expected) begin
        $fatal(
          1,
          "%s mismatch: expected=%0b result=%0b",
          test_name,
          expected,
          actual
        );
      end
      checks++;
    end
  endtask

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
      checks++;
    end
  endtask

  task automatic dmem_access(
    input logic        write,
    input logic [31:0] addr,
    input logic [31:0] wdata,
    input logic [3:0]  wstrb,
    input logic        expected_err,
    input logic        check_rdata,
    input logic [31:0] expected_rdata,
    input string       test_name
  );
    begin
      @(negedge clk);
      dmem.req_valid = 1'b1;
      dmem.req_addr  = addr;
      dmem.req_write = write;
      dmem.req_wdata = wdata;
      dmem.req_wstrb = wstrb;
      #1;

      check_bit(dmem.req_ready, 1'b1, {test_name, " ready"});
      check_bit(dmem.rsp_valid, 1'b0, {test_name, " no early response"});

      @(posedge clk);
      #1;
      check_bit(dmem.rsp_valid, 1'b1, {test_name, " response valid"});
      check_bit(dmem.rsp_err, expected_err, {test_name, " response error"});
      if (check_rdata) begin
        check_word(
          dmem.rsp_rdata,
          expected_rdata,
          {test_name, " response data"}
        );
      end

      dmem.req_valid = 1'b0;
      dmem.req_addr  = 32'b0;
      dmem.req_write = 1'b0;
      dmem.req_wdata = 32'b0;
      dmem.req_wstrb = 4'b0000;

      @(posedge clk);
      #1;
      check_bit(dmem.rsp_valid, 1'b0, {test_name, " response retires"});
    end
  endtask

  task automatic imem_access(
    input logic        write,
    input logic [31:0] addr,
    input logic [3:0]  wstrb,
    input logic        expected_err,
    input logic [31:0] expected_rdata,
    input string       test_name
  );
    begin
      @(negedge clk);
      imem.req_valid = 1'b1;
      imem.req_addr  = addr;
      imem.req_write = write;
      imem.req_wdata = 32'hffff_ffff;
      imem.req_wstrb = wstrb;
      #1;

      check_bit(imem.req_ready, 1'b1, {test_name, " ready"});
      check_bit(imem.rsp_valid, 1'b0, {test_name, " no early response"});

      @(posedge clk);
      #1;
      check_bit(imem.rsp_valid, 1'b1, {test_name, " response valid"});
      check_bit(imem.rsp_err, expected_err, {test_name, " response error"});
      check_word(
        imem.rsp_rdata,
        expected_rdata,
        {test_name, " response data"}
      );

      imem.req_valid = 1'b0;
      imem.req_addr  = 32'b0;
      imem.req_write = 1'b0;
      imem.req_wdata = 32'b0;
      imem.req_wstrb = 4'b0000;

      @(posedge clk);
      #1;
      check_bit(imem.rsp_valid, 1'b0, {test_name, " response retires"});
    end
  endtask

  initial begin
    clk              = 1'b0;
    checks           = 0;

    imem.req_valid   = 1'b0;
    imem.req_addr    = 32'b0;
    imem.req_write   = 1'b0;
    imem.req_wdata   = 32'b0;
    imem.req_wstrb   = 4'b0000;

    dmem.req_valid   = 1'b0;
    dmem.req_addr    = 32'b0;
    dmem.req_write   = 1'b0;
    dmem.req_wdata   = 32'b0;
    dmem.req_wstrb   = 4'b0000;

    // One idle edge establishes known response-register values without
    // resetting the memory array.
    @(posedge clk);
    #1;
    check_bit(imem.req_ready, 1'b1, "instruction port always ready");
    check_bit(dmem.req_ready, 1'b1, "data port always ready");
    check_bit(imem.rsp_valid, 1'b0, "instruction response idle");
    check_bit(dmem.rsp_valid, 1'b0, "data response idle");

    // A data-port store must be visible through both ports because the TCM is
    // one unified memory rather than separate instruction/data arrays.
    dmem_access(
      1'b1,
      TEST_BASE,
      32'h1234_5678,
      4'b1111,
      1'b0,
      1'b0,
      32'b0,
      "full-word store"
    );
    dmem_access(
      1'b0,
      TEST_BASE,
      32'b0,
      4'b0000,
      1'b0,
      1'b1,
      32'h1234_5678,
      "full-word data read"
    );
    imem_access(
      1'b0,
      TEST_BASE,
      4'b0000,
      1'b0,
      32'h1234_5678,
      "unified instruction read"
    );

    // Exercise every byte write-enable lane independently.
    dmem_access(
      1'b1, TEST_BASE + 32'd4, 32'h0000_00aa, 4'b0001,
      1'b0, 1'b0, 32'b0, "byte lane 0"
    );
    dmem_access(
      1'b1, TEST_BASE + 32'd4, 32'h0000_bb00, 4'b0010,
      1'b0, 1'b0, 32'b0, "byte lane 1"
    );
    dmem_access(
      1'b1, TEST_BASE + 32'd4, 32'h00cc_0000, 4'b0100,
      1'b0, 1'b0, 32'b0, "byte lane 2"
    );
    dmem_access(
      1'b1, TEST_BASE + 32'd4, 32'hdd00_0000, 4'b1000,
      1'b0, 1'b0, 32'b0, "byte lane 3"
    );
    dmem_access(
      1'b0, TEST_BASE + 32'd4, 32'b0, 4'b0000,
      1'b0, 1'b1, 32'hddcc_bbaa, "combined byte-lane read"
    );

    // Both BRAM ports must complete independent reads in the same cycle.
    @(negedge clk);
    imem.req_valid = 1'b1;
    imem.req_addr  = TEST_BASE;
    dmem.req_valid = 1'b1;
    dmem.req_addr  = TEST_BASE + 32'd4;
    #1;
    check_bit(imem.req_ready, 1'b1, "simultaneous imem ready");
    check_bit(dmem.req_ready, 1'b1, "simultaneous dmem ready");

    @(posedge clk);
    #1;
    check_bit(imem.rsp_valid, 1'b1, "simultaneous imem response");
    check_bit(dmem.rsp_valid, 1'b1, "simultaneous dmem response");
    check_word(imem.rsp_rdata, 32'h1234_5678, "simultaneous imem data");
    check_word(dmem.rsp_rdata, 32'hddcc_bbaa, "simultaneous dmem data");
    check_bit(imem.rsp_err, 1'b0, "simultaneous imem error");
    check_bit(dmem.rsp_err, 1'b0, "simultaneous dmem error");
    imem.req_valid = 1'b0;
    dmem.req_valid = 1'b0;

    @(posedge clk);
    #1;
    check_bit(imem.rsp_valid, 1'b0, "simultaneous imem retires");
    check_bit(dmem.rsp_valid, 1'b0, "simultaneous dmem retires");

    // Back-to-back requests demonstrate accepting a new request while the
    // previous response is valid.
    @(negedge clk);
    dmem.req_valid = 1'b1;
    dmem.req_addr  = TEST_BASE;
    @(posedge clk);
    #1;
    check_bit(dmem.rsp_valid, 1'b1, "back-to-back first valid");
    check_word(dmem.rsp_rdata, 32'h1234_5678, "back-to-back first data");
    dmem.req_addr = TEST_BASE + 32'd4;

    @(posedge clk);
    #1;
    check_bit(dmem.rsp_valid, 1'b1, "back-to-back second valid");
    check_word(dmem.rsp_rdata, 32'hddcc_bbaa, "back-to-back second data");
    dmem.req_valid = 1'b0;

    @(posedge clk);
    #1;
    check_bit(dmem.rsp_valid, 1'b0, "back-to-back responses retire");

    // The instruction port rejects writes, and both ports report bounds
    // errors without indexing outside the BRAM array.
    imem_access(
      1'b1,
      TEST_BASE,
      4'b1111,
      1'b1,
      32'b0,
      "instruction write rejected"
    );
    imem_access(
      1'b0,
      TEST_BASE - 32'd4,
      4'b0000,
      1'b1,
      32'b0,
      "instruction address below range"
    );
    dmem_access(
      1'b1,
      TEST_BASE + TEST_BYTES,
      32'hffff_ffff,
      4'b1111,
      1'b1,
      1'b1,
      32'b0,
      "data address above range"
    );

    // Verify that the failed store did not alias a valid memory word.
    dmem_access(
      1'b0,
      TEST_BASE,
      32'b0,
      4'b0000,
      1'b0,
      1'b1,
      32'h1234_5678,
      "out-of-range store has no side effect"
    );

    $display("tb_rv32_tcm: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
