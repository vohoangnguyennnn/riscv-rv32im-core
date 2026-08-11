// SPDX-License-Identifier: MIT

module tb_regfile;

  logic        clk;
  logic        we;
  logic [4:0]  waddr;
  logic [31:0] wdata;
  logic [4:0]  raddr1;
  logic [4:0]  raddr2;
  logic [31:0] rdata1;
  logic [31:0] rdata2;
  int          checks;

  regfile dut (
    .clk_i    (clk),
    .we_i     (we),
    .waddr_i  (waddr),
    .wdata_i  (wdata),
    .raddr1_i (raddr1),
    .raddr2_i (raddr2),
    .rdata1_o (rdata1),
    .rdata2_o (rdata2)
  );

  always #5 clk = ~clk;

  task automatic check_reads(
    input logic [4:0]  test_raddr1,
    input logic [4:0]  test_raddr2,
    input logic [31:0] expected_rdata1,
    input logic [31:0] expected_rdata2,
    input string       test_name
  );
    begin
      raddr1 = test_raddr1;
      raddr2 = test_raddr2;
      #1;

      if (rdata1 !== expected_rdata1) begin
        $fatal(
          1,
          "%s port 1 mismatch: x%0d expected=%08x result=%08x",
          test_name,
          test_raddr1,
          expected_rdata1,
          rdata1
        );
      end

      if (rdata2 !== expected_rdata2) begin
        $fatal(
          1,
          "%s port 2 mismatch: x%0d expected=%08x result=%08x",
          test_name,
          test_raddr2,
          expected_rdata2,
          rdata2
        );
      end

      checks += 2;
    end
  endtask

  task automatic write_reg(
    input logic [4:0]  test_waddr,
    input logic [31:0] test_wdata
  );
    begin
      @(negedge clk);
      we    = 1'b1;
      waddr = test_waddr;
      wdata = test_wdata;
      @(posedge clk);
      #1;
      we    = 1'b0;
      waddr = 5'd0;
      wdata = 32'b0;
    end
  endtask

  initial begin
    clk     = 1'b0;
    we      = 1'b0;
    waddr   = 5'd0;
    wdata   = 32'b0;
    raddr1  = 5'd0;
    raddr2  = 5'd0;
    checks  = 0;

    // x0 must read as zero through both independent read ports.
    check_reads(5'd0, 5'd0, 32'b0, 32'b0, "x0 initial read");

    // A write targeting x0 must be ignored.
    write_reg(5'd0, 32'hffff_ffff);
    check_reads(5'd0, 5'd0, 32'b0, 32'b0, "x0 write ignored");

    // Give all writable architectural registers a known, unique value.
    for (int i = 1; i < 32; i++) begin
      write_reg(i[4:0], 32'h1000_0000 + i);
    end

    // Exercise every address and both asynchronous read ports.
    for (int i = 1; i < 32; i++) begin
      check_reads(
        i[4:0],
        5'(32 - i),
        32'h1000_0000 + i,
        32'h1000_0000 + (32 - i),
        $sformatf("dual read x%0d/x%0d", i, 32 - i)
      );
    end

    // Read data must not change until the active write clock edge.
    @(negedge clk);
    raddr1 = 5'd7;
    raddr2 = 5'd0;
    we     = 1'b1;
    waddr  = 5'd7;
    wdata  = 32'hdead_beef;
    #1;
    check_reads(
      5'd7,
      5'd0,
      32'h1000_0007,
      32'b0,
      "write is not visible before rising edge"
    );

    @(posedge clk);
    #1;
    we = 1'b0;
    check_reads(
      5'd7,
      5'd0,
      32'hdead_beef,
      32'b0,
      "write is visible after rising edge"
    );

    // With write enable low, a clock edge must preserve the stored value.
    @(negedge clk);
    we    = 1'b0;
    waddr = 5'd7;
    wdata = 32'hbad0_bad0;
    @(posedge clk);
    #1;
    check_reads(
      5'd7,
      5'd31,
      32'hdead_beef,
      32'h1000_001f,
      "write enable low"
    );

    $display("tb_regfile: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
