// SPDX-License-Identifier: MIT

module tb_lsu;

  import rv32_pkg::*;

  localparam word_t TEST_BASE = 32'h0000_1000;

  logic      clk;
  logic      rst;
  logic      kill;
  logic      req_valid;
  logic      req_ready;
  mem_cmd_e  cmd;
  mem_size_e size;
  logic      load_unsigned;
  word_t     addr;
  word_t     store_data;
  logic      rsp_valid;
  logic      rsp_ready;
  word_t     load_data;
  exc_t      exception;
  logic [3:0] trace_wstrb;
  word_t      trace_wdata;
  int         checks;

  rv32_mem_if dmem();

  lsu dut (
    .clk_i           (clk),
    .rst_i           (rst),
    .kill_i          (kill),
    .req_valid_i     (req_valid),
    .req_ready_o     (req_ready),
    .cmd_i           (cmd),
    .size_i          (size),
    .load_unsigned_i (load_unsigned),
    .addr_i          (addr),
    .store_data_i    (store_data),
    .dmem_m          (dmem),
    .rsp_valid_o     (rsp_valid),
    .rsp_ready_i     (rsp_ready),
    .load_data_o     (load_data),
    .exception_o     (exception),
    .trace_wstrb_o   (trace_wstrb),
    .trace_wdata_o   (trace_wdata)
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

  task automatic check_nibble(
    input logic [3:0] actual,
    input logic [3:0] expected,
    input string      test_name
  );
    begin
      if (actual !== expected) begin
        $fatal(
          1,
          "%s mismatch: expected=%04b result=%04b",
          test_name,
          expected,
          actual
        );
      end
      checks++;
    end
  endtask

  task automatic check_word(
    input word_t actual,
    input word_t expected,
    input string test_name
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

  task automatic check_exception(
    input logic       expected_valid,
    input exc_cause_e expected_cause,
    input word_t      expected_tval,
    input string      test_name
  );
    begin
      check_bit(exception.valid, expected_valid, {test_name, " valid"});
      if (expected_valid) begin
        if (exception.cause !== expected_cause) begin
          $fatal(
            1,
            "%s cause mismatch: expected=%0d result=%0d",
            test_name,
            expected_cause,
            exception.cause
          );
        end
        checks++;
        check_word(exception.tval, expected_tval, {test_name, " tval"});
      end
    end
  endtask

  task automatic start_request(
    input mem_cmd_e  test_cmd,
    input mem_size_e test_size,
    input logic      test_unsigned,
    input word_t     test_addr,
    input word_t     test_store_data,
    input string     test_name
  );
    begin
      @(negedge clk);
      cmd           = test_cmd;
      size          = test_size;
      load_unsigned = test_unsigned;
      addr           = test_addr;
      store_data     = test_store_data;
      req_valid      = 1'b1;
      #1;

      check_bit(req_ready, 1'b1, {test_name, " input ready"});

      @(posedge clk);
      #1;
      req_valid = 1'b0;
    end
  endtask

  task automatic check_memory_request(
    input logic       expected_write,
    input word_t      expected_addr,
    input logic [3:0] expected_wstrb,
    input word_t      expected_wdata,
    input string      test_name
  );
    begin
      check_bit(dmem.req_valid, 1'b1, {test_name, " memory valid"});
      check_bit(dmem.req_write, expected_write, {test_name, " memory write"});
      check_word(dmem.req_addr, expected_addr, {test_name, " memory address"});
      check_nibble(dmem.req_wstrb, expected_wstrb, {test_name, " memory strobe"});
      check_word(dmem.req_wdata, expected_wdata, {test_name, " memory write data"});
    end
  endtask

  task automatic accept_memory_request(
    input logic       expected_write,
    input word_t      expected_addr,
    input logic [3:0] expected_wstrb,
    input word_t      expected_wdata,
    input string      test_name
  );
    begin
      @(negedge clk);
      dmem.req_ready = 1'b1;
      #1;
      check_memory_request(
        expected_write,
        expected_addr,
        expected_wstrb,
        expected_wdata,
        test_name
      );

      @(posedge clk);
      #1;
      dmem.req_ready = 1'b0;
      check_bit(dmem.req_valid, 1'b0, {test_name, " request retires"});
      check_bit(rsp_valid, 1'b0, {test_name, " waits for response"});
      check_bit(req_ready, 1'b0, {test_name, " blocks next operation"});
    end
  endtask

  task automatic send_memory_response(
    input word_t      read_data,
    input logic       error,
    input word_t      expected_load_data,
    input logic       expected_exception_valid,
    input exc_cause_e expected_cause,
    input word_t      expected_tval,
    input logic [3:0] expected_trace_wstrb,
    input word_t      expected_trace_wdata,
    input string      test_name
  );
    begin
      @(negedge clk);
      dmem.rsp_rdata = read_data;
      dmem.rsp_err   = error;
      dmem.rsp_valid = 1'b1;
      #1;

      check_bit(rsp_valid, 1'b1, {test_name, " response valid"});
      check_word(load_data, expected_load_data, {test_name, " load data"});
      check_exception(
        expected_exception_valid,
        expected_cause,
        expected_tval,
        {test_name, " exception"}
      );
      check_nibble(
        trace_wstrb,
        expected_trace_wstrb,
        {test_name, " trace strobe"}
      );
      check_word(
        trace_wdata,
        expected_trace_wdata,
        {test_name, " trace write data"}
      );

      @(posedge clk);
      #1;
      dmem.rsp_valid = 1'b0;
      dmem.rsp_rdata = 32'b0;
      dmem.rsp_err   = 1'b0;
      #1;
      check_bit(rsp_valid, 1'b0, {test_name, " response retires"});
      check_bit(req_ready, 1'b1, {test_name, " LSU ready again"});
    end
  endtask

  task automatic run_store(
    input mem_size_e test_size,
    input word_t     test_addr,
    input word_t     test_store_data,
    input logic [3:0] expected_wstrb,
    input word_t      expected_wdata,
    input string      test_name
  );
    word_t aligned_addr;
    begin
      aligned_addr = {test_addr[31:2], 2'b00};
      start_request(
        MEM_STORE,
        test_size,
        1'b0,
        test_addr,
        test_store_data,
        test_name
      );
      check_memory_request(
        1'b1,
        aligned_addr,
        expected_wstrb,
        expected_wdata,
        test_name
      );
      accept_memory_request(
        1'b1,
        aligned_addr,
        expected_wstrb,
        expected_wdata,
        test_name
      );
      send_memory_response(
        32'b0,
        1'b0,
        32'b0,
        1'b0,
        EXC_INST_ADDR_MISALIGNED,
        32'b0,
        expected_wstrb,
        expected_wdata,
        test_name
      );
    end
  endtask

  task automatic run_load(
    input mem_size_e test_size,
    input logic      test_unsigned,
    input word_t     test_addr,
    input word_t     read_data,
    input word_t     expected_load_data,
    input string     test_name
  );
    word_t aligned_addr;
    begin
      aligned_addr = {test_addr[31:2], 2'b00};
      start_request(
        MEM_LOAD,
        test_size,
        test_unsigned,
        test_addr,
        32'b0,
        test_name
      );
      check_memory_request(
        1'b0,
        aligned_addr,
        4'b0000,
        32'b0,
        test_name
      );
      accept_memory_request(
        1'b0,
        aligned_addr,
        4'b0000,
        32'b0,
        test_name
      );
      send_memory_response(
        read_data,
        1'b0,
        expected_load_data,
        1'b0,
        EXC_INST_ADDR_MISALIGNED,
        32'b0,
        4'b0000,
        32'b0,
        test_name
      );
    end
  endtask

  task automatic run_misaligned(
    input mem_cmd_e   test_cmd,
    input mem_size_e  test_size,
    input word_t      test_addr,
    input exc_cause_e expected_cause,
    input string      test_name
  );
    begin
      start_request(
        test_cmd,
        test_size,
        1'b0,
        test_addr,
        32'hdead_beef,
        test_name
      );
      #1;
      check_bit(dmem.req_valid, 1'b0, {test_name, " no memory request"});
      check_bit(rsp_valid, 1'b1, {test_name, " local response valid"});
      check_word(load_data, 32'b0, {test_name, " local load data"});
      check_exception(1'b1, expected_cause, test_addr, test_name);
      check_nibble(trace_wstrb, 4'b0000, {test_name, " no trace strobe"});
      check_word(trace_wdata, 32'b0, {test_name, " no trace write data"});

      @(posedge clk);
      #1;
      check_bit(rsp_valid, 1'b0, {test_name, " local response retires"});
      check_bit(req_ready, 1'b1, {test_name, " LSU ready again"});
    end
  endtask

  initial begin
    clk               = 1'b0;
    rst               = 1'b1;
    kill              = 1'b0;
    req_valid         = 1'b0;
    cmd               = MEM_NONE;
    size              = MEM_WORD;
    load_unsigned     = 1'b0;
    addr              = 32'b0;
    store_data        = 32'b0;
    rsp_ready         = 1'b1;
    checks            = 0;

    dmem.req_ready    = 1'b0;
    dmem.rsp_valid    = 1'b0;
    dmem.rsp_rdata    = 32'b0;
    dmem.rsp_err      = 1'b0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    #1;
    check_bit(req_ready, 1'b1, "reset leaves LSU ready");
    check_bit(dmem.req_valid, 1'b0, "reset leaves memory idle");
    check_bit(rsp_valid, 1'b0, "reset leaves response idle");

    // Every little-endian store lane and supported store width.
    run_store(
      MEM_BYTE, TEST_BASE + 32'd0, 32'h1234_56a0,
      4'b0001, 32'h0000_00a0, "SB lane 0"
    );
    run_store(
      MEM_BYTE, TEST_BASE + 32'd1, 32'h1234_56b1,
      4'b0010, 32'h0000_b100, "SB lane 1"
    );
    run_store(
      MEM_BYTE, TEST_BASE + 32'd2, 32'h1234_56c2,
      4'b0100, 32'h00c2_0000, "SB lane 2"
    );
    run_store(
      MEM_BYTE, TEST_BASE + 32'd3, 32'h1234_56d3,
      4'b1000, 32'hd300_0000, "SB lane 3"
    );
    run_store(
      MEM_HALF, TEST_BASE + 32'd0, 32'h1234_a1b2,
      4'b0011, 32'h0000_a1b2, "SH low half"
    );
    run_store(
      MEM_HALF, TEST_BASE + 32'd2, 32'h5678_c3d4,
      4'b1100, 32'hc3d4_0000, "SH high half"
    );
    run_store(
      MEM_WORD, TEST_BASE + 32'd4, 32'h89ab_cdef,
      4'b1111, 32'h89ab_cdef, "SW"
    );

    // Signed and unsigned extraction from both sub-word positions.
    run_load(
      MEM_BYTE, 1'b0, TEST_BASE + 32'd3,
      32'h80ff_7f01, 32'hffff_ff80, "LB sign extension"
    );
    run_load(
      MEM_BYTE, 1'b1, TEST_BASE + 32'd3,
      32'h80ff_7f01, 32'h0000_0080, "LBU zero extension"
    );
    run_load(
      MEM_HALF, 1'b0, TEST_BASE + 32'd2,
      32'h80ff_7f01, 32'hffff_80ff, "LH sign extension"
    );
    run_load(
      MEM_HALF, 1'b1, TEST_BASE + 32'd2,
      32'h80ff_7f01, 32'h0000_80ff, "LHU zero extension"
    );
    run_load(
      MEM_WORD, 1'b0, TEST_BASE + 32'd4,
      32'h89ab_cdef, 32'h89ab_cdef, "LW"
    );

    // Architectural alignment exceptions complete locally and never reach
    // memory. Byte accesses were already shown legal at every byte offset.
    run_misaligned(
      MEM_LOAD, MEM_HALF, TEST_BASE + 32'd1,
      EXC_LOAD_ADDR_MISALIGNED, "misaligned LH"
    );
    run_misaligned(
      MEM_LOAD, MEM_WORD, TEST_BASE + 32'd2,
      EXC_LOAD_ADDR_MISALIGNED, "misaligned LW"
    );
    run_misaligned(
      MEM_STORE, MEM_HALF, TEST_BASE + 32'd3,
      EXC_STORE_ADDR_MISALIGNED, "misaligned SH"
    );
    run_misaligned(
      MEM_STORE, MEM_WORD, TEST_BASE + 32'd1,
      EXC_STORE_ADDR_MISALIGNED, "misaligned SW"
    );

    // Request payload must remain stable while the memory applies
    // backpressure, even if the upstream inputs change after acceptance.
    start_request(
      MEM_STORE,
      MEM_BYTE,
      1'b0,
      TEST_BASE + 32'd2,
      32'h0000_005a,
      "request backpressure"
    );
    check_memory_request(
      1'b1,
      TEST_BASE,
      4'b0100,
      32'h005a_0000,
      "request backpressure initial"
    );

    @(negedge clk);
    cmd        = MEM_LOAD;
    size       = MEM_WORD;
    addr       = 32'hffff_fffc;
    store_data = 32'hdead_beef;
    #1;
    check_memory_request(
      1'b1,
      TEST_BASE,
      4'b0100,
      32'h005a_0000,
      "request backpressure stable"
    );
    check_bit(req_ready, 1'b0, "request backpressure blocks input");

    @(posedge clk);
    #1;
    check_memory_request(
      1'b1,
      TEST_BASE,
      4'b0100,
      32'h005a_0000,
      "request backpressure stable across edge"
    );
    accept_memory_request(
      1'b1,
      TEST_BASE,
      4'b0100,
      32'h005a_0000,
      "request backpressure"
    );
    send_memory_response(
      32'b0,
      1'b0,
      32'b0,
      1'b0,
      EXC_INST_ADDR_MISALIGNED,
      32'b0,
      4'b0100,
      32'h005a_0000,
      "request backpressure"
    );

    // The LSU must absorb a pulse response because the memory interface has
    // no rsp_ready signal, then hold it for the pipeline.
    rsp_ready = 1'b0;
    start_request(
      MEM_LOAD,
      MEM_BYTE,
      1'b0,
      TEST_BASE + 32'd2,
      32'b0,
      "response backpressure"
    );
    accept_memory_request(
      1'b0,
      TEST_BASE,
      4'b0000,
      32'b0,
      "response backpressure"
    );

    @(negedge clk);
    dmem.rsp_valid = 1'b1;
    dmem.rsp_rdata = 32'h00fe_0000;
    #1;
    check_bit(rsp_valid, 1'b1, "response backpressure pass-through valid");
    check_word(load_data, 32'hffff_fffe, "response backpressure pass-through data");

    @(posedge clk);
    #1;
    dmem.rsp_valid = 1'b0;
    dmem.rsp_rdata = 32'h1234_5678;
    #1;
    check_bit(rsp_valid, 1'b1, "response backpressure sticky valid");
    check_word(load_data, 32'hffff_fffe, "response backpressure sticky data");

    repeat (2) begin
      @(posedge clk);
      #1;
      check_bit(rsp_valid, 1'b1, "response backpressure remains valid");
      check_word(load_data, 32'hffff_fffe, "response backpressure remains stable");
      check_bit(req_ready, 1'b0, "response backpressure blocks input");
    end

    @(negedge clk);
    rsp_ready = 1'b1;
    @(posedge clk);
    #1;
    check_bit(rsp_valid, 1'b0, "response backpressure consumed");
    check_bit(req_ready, 1'b1, "response backpressure releases LSU");

    // Bus errors map to the standard load/store access-fault causes and retain
    // the original effective byte address in mtval.
    start_request(
      MEM_LOAD,
      MEM_BYTE,
      1'b1,
      TEST_BASE + 32'd3,
      32'b0,
      "load access fault"
    );
    accept_memory_request(
      1'b0,
      TEST_BASE,
      4'b0000,
      32'b0,
      "load access fault"
    );
    send_memory_response(
      32'hffff_ffff,
      1'b1,
      32'b0,
      1'b1,
      EXC_LOAD_ACCESS_FAULT,
      TEST_BASE + 32'd3,
      4'b0000,
      32'b0,
      "load access fault"
    );

    start_request(
      MEM_STORE,
      MEM_HALF,
      1'b0,
      TEST_BASE + 32'd2,
      32'h0000_cafe,
      "store access fault"
    );
    accept_memory_request(
      1'b1,
      TEST_BASE,
      4'b1100,
      32'hcafe_0000,
      "store access fault"
    );
    send_memory_response(
      32'b0,
      1'b1,
      32'b0,
      1'b1,
      EXC_STORE_ACCESS_FAULT,
      TEST_BASE + 32'd2,
      4'b1100,
      32'hcafe_0000,
      "store access fault"
    );

    // Killing a request under memory backpressure must not violate ready/valid:
    // the request remains asserted, then the eventual response is drained.
    start_request(
      MEM_STORE,
      MEM_WORD,
      1'b0,
      TEST_BASE,
      32'h1357_9bdf,
      "killed request"
    );
    check_memory_request(
      1'b1,
      TEST_BASE,
      4'b1111,
      32'h1357_9bdf,
      "killed request initial"
    );

    @(negedge clk);
    kill = 1'b1;
    #1;
    check_memory_request(
      1'b1,
      TEST_BASE,
      4'b1111,
      32'h1357_9bdf,
      "killed request remains valid"
    );
    check_bit(rsp_valid, 1'b0, "killed request suppresses response");

    @(posedge clk);
    @(negedge clk);
    kill           = 1'b0;
    dmem.req_ready = 1'b1;
    #1;
    check_memory_request(
      1'b1,
      TEST_BASE,
      4'b1111,
      32'h1357_9bdf,
      "killed request accepts"
    );

    @(posedge clk);
    #1;
    dmem.req_ready = 1'b0;
    check_bit(req_ready, 1'b0, "killed request waits to drain");
    check_bit(rsp_valid, 1'b0, "killed request has no pipeline response");

    @(negedge clk);
    dmem.rsp_valid = 1'b1;
    #1;
    check_bit(rsp_valid, 1'b0, "killed response discarded");

    @(posedge clk);
    #1;
    dmem.rsp_valid = 1'b0;
    #1;
    check_bit(req_ready, 1'b1, "killed response releases LSU");

    // Kill after request acceptance exercises the separate outstanding
    // response drain path.
    start_request(
      MEM_LOAD,
      MEM_WORD,
      1'b0,
      TEST_BASE,
      32'b0,
      "killed outstanding load"
    );
    accept_memory_request(
      1'b0,
      TEST_BASE,
      4'b0000,
      32'b0,
      "killed outstanding load"
    );

    @(negedge clk);
    kill = 1'b1;
    #1;
    check_bit(rsp_valid, 1'b0, "killed outstanding load suppresses response");

    @(posedge clk);
    @(negedge clk);
    kill           = 1'b0;
    dmem.rsp_valid = 1'b1;
    dmem.rsp_rdata = 32'hfeed_face;
    #1;
    check_bit(rsp_valid, 1'b0, "killed outstanding load drains response");

    @(posedge clk);
    #1;
    dmem.rsp_valid = 1'b0;
    dmem.rsp_rdata = 32'b0;
    #1;
    check_bit(req_ready, 1'b1, "killed outstanding load releases LSU");

    // A zero-latency slave may return a response in the request-acceptance
    // cycle. This is not required by the TCM, but the LSU supports it without
    // losing the response.
    start_request(
      MEM_LOAD,
      MEM_BYTE,
      1'b1,
      TEST_BASE + 32'd1,
      32'b0,
      "same-cycle memory response"
    );

    @(negedge clk);
    dmem.req_ready = 1'b1;
    dmem.rsp_valid = 1'b1;
    dmem.rsp_rdata = 32'h0000_aa00;
    #1;
    check_memory_request(
      1'b0,
      TEST_BASE,
      4'b0000,
      32'b0,
      "same-cycle memory response"
    );
    check_bit(rsp_valid, 1'b1, "same-cycle memory response valid");
    check_word(load_data, 32'h0000_00aa, "same-cycle memory response data");
    check_exception(
      1'b0,
      EXC_INST_ADDR_MISALIGNED,
      32'b0,
      "same-cycle memory response"
    );

    @(posedge clk);
    #1;
    dmem.req_ready = 1'b0;
    dmem.rsp_valid = 1'b0;
    dmem.rsp_rdata = 32'b0;
    #1;
    check_bit(req_ready, 1'b1, "same-cycle memory response releases LSU");

    // MEM_NONE is not an architectural LSU request, but completing it locally
    // and benignly avoids a deadlock if integration asserts req_valid by error.
    start_request(
      MEM_NONE,
      MEM_WORD,
      1'b0,
      TEST_BASE,
      32'hffff_ffff,
      "benign non-memory request"
    );
    #1;
    check_bit(dmem.req_valid, 1'b0, "benign non-memory request stays local");
    check_bit(rsp_valid, 1'b1, "benign non-memory request completes");
    check_word(load_data, 32'b0, "benign non-memory request data");
    check_exception(
      1'b0,
      EXC_INST_ADDR_MISALIGNED,
      32'b0,
      "benign non-memory request"
    );
    check_nibble(trace_wstrb, 4'b0000, "benign non-memory trace strobe");

    @(posedge clk);
    #1;
    check_bit(req_ready, 1'b1, "benign non-memory request releases LSU");

    $display("tb_lsu: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
