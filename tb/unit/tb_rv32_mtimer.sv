module tb_rv32_mtimer;

  localparam logic [31:0] TEST_BASE        = 32'h0200_0000;
  localparam logic [31:0] MTIMECMP_LO_ADDR = TEST_BASE + 32'h0000_4000;
  localparam logic [31:0] MTIMECMP_HI_ADDR = TEST_BASE + 32'h0000_4004;
  localparam logic [31:0] MTIME_LO_ADDR    = TEST_BASE + 32'h0000_bff8;
  localparam logic [31:0] MTIME_HI_ADDR    = TEST_BASE + 32'h0000_bffc;

  logic clk;
  logic rst;
  logic mtip;
  int   checks;

  logic [63:0] timer_before;
  logic [63:0] compare_before;
  logic [31:0] first_read_value;

  rv32_mem_if timer();

  rv32_mtimer #(
    .BASE_ADDR (TEST_BASE)
  ) dut (
    .clk_i   (clk),
    .rst_i   (rst),
    .timer_s (timer),
    .mtip_o  (mtip)
  );

  always #5 clk = ~clk;

  task automatic drive_idle;
    begin
      timer.req_valid = 1'b0;
      timer.req_addr  = 32'b0;
      timer.req_write = 1'b0;
      timer.req_wdata = 32'b0;
      timer.req_wstrb = 4'b0000;
    end
  endtask

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

  task automatic check_dword(
    input logic [63:0] actual,
    input logic [63:0] expected,
    input string       test_name
  );
    begin
      if (actual !== expected) begin
        $fatal(
          1,
          "%s mismatch: expected=%016x result=%016x",
          test_name,
          expected,
          actual
        );
      end
      checks++;
    end
  endtask

  task automatic timer_access(
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
      timer.req_valid = 1'b1;
      timer.req_addr  = addr;
      timer.req_write = write;
      timer.req_wdata = wdata;
      timer.req_wstrb = wstrb;
      #1;

      check_bit(timer.req_ready, 1'b1, {test_name, " request ready"});

      @(posedge clk);
      #1;
      check_bit(timer.rsp_valid, 1'b1, {test_name, " response valid"});
      check_bit(timer.rsp_err, expected_err, {test_name, " response error"});

      if (check_rdata) begin
        check_word(timer.rsp_rdata, expected_rdata, {test_name, " response data"});
      end

      drive_idle();
    end
  endtask

  task automatic write_word(
    input logic [31:0] addr,
    input logic [31:0] value,
    input string       test_name
  );
    begin
      timer_access(
        1'b1,
        addr,
        value,
        4'b1111,
        1'b0,
        1'b0,
        32'b0,
        test_name
      );
    end
  endtask

  task automatic set_mtime(
    input logic [63:0] value,
    input string       test_name
  );
    begin
      write_word(MTIME_HI_ADDR, value[63:32], {test_name, " high"});
      write_word(MTIME_LO_ADDR, value[31:0],  {test_name, " low"});
      check_dword(dut.mtime_q, value, test_name);
    end
  endtask

  task automatic set_mtimecmp(
    input logic [63:0] value,
    input string       test_name
  );
    begin
      write_word(MTIMECMP_HI_ADDR, value[63:32], {test_name, " high"});
      write_word(MTIMECMP_LO_ADDR, value[31:0],  {test_name, " low"});
      check_dword(dut.mtimecmp_q, value, test_name);
    end
  endtask

  initial begin
    clk    = 1'b0;
    rst    = 1'b1;
    checks = 0;
    drive_idle();

    #1;
    check_bit(timer.req_ready, 1'b0, "reset backpressure");

    repeat (2) @(posedge clk);
    #1;
    check_dword(dut.mtime_q, 64'b0, "mtime reset value");
    check_dword(
      dut.mtimecmp_q,
      64'hffff_ffff_ffff_ffff,
      "mtimecmp reset value"
    );
    check_bit(mtip, 1'b0, "MTIP clear after reset");
    check_bit(timer.rsp_valid, 1'b0, "response clear after reset");

    rst = 1'b0;
    #1;
    check_bit(timer.req_ready, 1'b1, "ready after reset");

    // Reads sample the selected half at the request edge while mtime continues
    // to advance. The first post-reset low-half read therefore returns zero.
    timer_access(
      1'b0,
      MTIME_LO_ADDR,
      32'b0,
      4'b0000,
      1'b0,
      1'b1,
      32'b0,
      "mtime low read"
    );
    timer_access(
      1'b0,
      MTIME_HI_ADDR,
      32'b0,
      4'b0000,
      1'b0,
      1'b1,
      32'b0,
      "mtime high read"
    );

    timer_before = dut.mtime_q;
    @(posedge clk);
    #1;
    check_dword(dut.mtime_q, timer_before + 64'd1, "autonomous mtime tick");
    check_bit(timer.rsp_valid, 1'b0, "read response retires");

    // A write to either mtime half suppresses that edge's autonomous tick and
    // leaves the opposite half unchanged.
    timer_before = dut.mtime_q;
    write_word(MTIME_HI_ADDR, 32'h1234_5678, "mtime high write");
    check_dword(
      dut.mtime_q,
      {32'h1234_5678, timer_before[31:0]},
      "mtime high write isolation"
    );

    write_word(MTIME_LO_ADDR, 32'h89ab_cdef, "mtime low write");
    check_dword(
      dut.mtime_q,
      64'h1234_5678_89ab_cdef,
      "mtime low write isolation"
    );

    // Unsupported transfer shapes and offsets return an error and have no
    // timer-register write side effect.
    compare_before = dut.mtimecmp_q;
    timer_before   = dut.mtime_q;
    timer_access(
      1'b1,
      MTIMECMP_LO_ADDR,
      32'h0123_4567,
      4'b0011,
      1'b1,
      1'b0,
      32'b0,
      "partial mtimecmp write rejected"
    );
    check_dword(dut.mtimecmp_q, compare_before, "failed write no compare effect");
    check_dword(dut.mtime_q, timer_before + 64'd1, "failed write does not stop timer");

    timer_access(
      1'b0,
      MTIME_LO_ADDR + 32'd2,
      32'b0,
      4'b0000,
      1'b1,
      1'b0,
      32'b0,
      "misaligned read rejected"
    );
    timer_access(
      1'b0,
      TEST_BASE + 32'h0000_4008,
      32'b0,
      4'b0000,
      1'b1,
      1'b0,
      32'b0,
      "unimplemented offset rejected"
    );
    timer_access(
      1'b0,
      MTIME_LO_ADDR,
      32'b0,
      4'b1111,
      1'b1,
      1'b0,
      32'b0,
      "read with write strobes rejected"
    );

    // Equality must assert MTIP. Raising mtimecmp above the post-write mtime
    // value clears it immediately because MTIP is a pure comparator level.
    set_mtimecmp(64'd104, "program basic compare");
    set_mtime(64'd100, "program basic time");
    check_bit(mtip, 1'b0, "MTIP clear below compare");

    repeat (3) begin
      @(posedge clk);
      #1;
      check_bit(mtip, 1'b0, "MTIP remains clear before equality");
    end
    check_dword(dut.mtime_q, 64'd103, "mtime immediately before compare");

    @(posedge clk);
    #1;
    check_dword(dut.mtime_q, 64'd104, "mtime reaches compare");
    check_bit(mtip, 1'b1, "MTIP asserts at equality");

    write_word(MTIMECMP_LO_ADDR, 32'd106, "advance compare");
    check_dword(dut.mtime_q, 64'd105, "mtime ticks during compare write");
    check_bit(mtip, 1'b0, "MTIP clears below advanced compare");

    @(posedge clk);
    #1;
    check_dword(dut.mtime_q, 64'd106, "mtime reaches advanced compare");
    check_bit(mtip, 1'b1, "MTIP reasserts at advanced compare");

    // Overflow is modulo 2^64, and the comparator follows the wrapped value.
    set_mtimecmp(64'hffff_ffff_ffff_ffff, "program wrap compare");
    set_mtime(64'hffff_ffff_ffff_fffe, "program wrap time");
    check_bit(mtip, 1'b0, "MTIP clear before maximum");
    @(posedge clk);
    #1;
    check_dword(dut.mtime_q, 64'hffff_ffff_ffff_ffff, "mtime maximum");
    check_bit(mtip, 1'b1, "MTIP at maximum equality");
    @(posedge clk);
    #1;
    check_dword(dut.mtime_q, 64'b0, "mtime wraps to zero");
    check_bit(mtip, 1'b0, "MTIP clears after wrap");

    // Demonstrate the architectural RV32 split-write hazard, then prove the
    // specified low=-1/high/low sequence prevents the intermediate interrupt.
    set_mtimecmp(64'hffff_ffff_ffff_ffff, "mask split-write setup");
    set_mtime(64'h0000_0001_0000_0080, "split-write time setup");
    set_mtimecmp(64'h0000_0001_0000_0100, "split-write old compare");
    check_bit(mtip, 1'b0, "old compare is in future");

    write_word(MTIMECMP_LO_ADDR, 32'h0000_0020, "unsafe low-first update");
    check_bit(mtip, 1'b1, "unsafe split write exposes intermediate MTIP");

    write_word(MTIMECMP_LO_ADDR, 32'h0000_0100, "restore old compare");
    check_bit(mtip, 1'b0, "restored compare clears MTIP");

    write_word(MTIMECMP_LO_ADDR, 32'hffff_ffff, "safe split write guard low");
    check_bit(mtip, 1'b0, "safe guard keeps MTIP clear");
    write_word(MTIMECMP_HI_ADDR, 32'h0000_0002, "safe split write new high");
    check_bit(mtip, 1'b0, "safe high update keeps MTIP clear");
    write_word(MTIMECMP_LO_ADDR, 32'h0000_0020, "safe split write new low");
    check_dword(
      dut.mtimecmp_q,
      64'h0000_0002_0000_0020,
      "safe split write final compare"
    );
    check_bit(mtip, 1'b0, "safe split write avoids spurious MTIP");

    // The slave can accept a request every cycle and returns responses in the
    // same order. This becomes important when the demux routes a new request
    // while the previous timer response is being observed.
    @(negedge clk);
    first_read_value = dut.mtime_q[31:0];
    timer.req_valid = 1'b1;
    timer.req_addr  = MTIME_LO_ADDR;
    timer.req_write = 1'b0;
    timer.req_wdata = 32'b0;
    timer.req_wstrb = 4'b0000;

    @(posedge clk);
    #1;
    check_bit(timer.rsp_valid, 1'b1, "back-to-back first response");
    check_word(timer.rsp_rdata, first_read_value, "back-to-back first data");
    timer.req_addr = MTIME_HI_ADDR;

    @(posedge clk);
    #1;
    check_bit(timer.rsp_valid, 1'b1, "back-to-back second response");
    check_word(timer.rsp_rdata, dut.mtime_q[63:32], "back-to-back second data");
    drive_idle();

    @(posedge clk);
    #1;
    check_bit(timer.rsp_valid, 1'b0, "back-to-back responses retire");

    // Reset is repeatable and also cancels any visible bus response.
    @(negedge clk);
    rst = 1'b1;
    @(posedge clk);
    #1;
    check_dword(dut.mtime_q, 64'b0, "final reset mtime");
    check_dword(
      dut.mtimecmp_q,
      64'hffff_ffff_ffff_ffff,
      "final reset mtimecmp"
    );
    check_bit(mtip, 1'b0, "final reset MTIP");
    check_bit(timer.rsp_valid, 1'b0, "final reset response");
    check_bit(timer.req_ready, 1'b0, "final reset backpressure");

    $display("tb_rv32_mtimer: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
