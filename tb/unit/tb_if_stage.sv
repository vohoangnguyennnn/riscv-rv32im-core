// SPDX-License-Identifier: MIT

module tb_if_stage;

  localparam logic [31:0] RESET_VECTOR = 32'h0000_1000;
  localparam logic [31:0] REDIRECT_A   = 32'h0000_2000;
  localparam logic [31:0] REDIRECT_B   = 32'h0000_3000;
  localparam logic [31:0] REDIRECT_C   = 32'h0000_4000;

  logic        clk;
  logic        rst;
  logic        enable;
  logic        consume;
  logic        flush;
  logic        redirect_valid;
  logic [31:0] redirect_pc;
  int          checks;

  rv32_mem_if imem();

  logic        stalled_request_q;
  logic [31:0] stalled_addr_q;
  logic        stalled_write_q;
  logic [31:0] stalled_wdata_q;
  logic [3:0]  stalled_wstrb_q;
  logic        fetch_valid;
  logic [31:0] fetch_pc;
  logic [31:0] fetch_insn;
  rv32_pkg::exc_t fetch_exc;

  if_stage #(
    .RESET_VECTOR (RESET_VECTOR)
  ) dut (
    .clk_i            (clk),
    .rst_i            (rst),
    .enable_i         (enable),
    .consume_i        (consume),
    .flush_i          (flush),
    .redirect_valid_i (redirect_valid),
    .redirect_pc_i    (redirect_pc),
    .imem_m           (imem),
    .fetch_valid_o    (fetch_valid),
    .fetch_pc_o       (fetch_pc),
    .fetch_insn_o     (fetch_insn),
    .fetch_exc_o      (fetch_exc)
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

  task automatic check_cause(
    input rv32_pkg::exc_cause_e actual,
    input rv32_pkg::exc_cause_e expected,
    input string                test_name
  );
    begin
      if (actual !== expected) begin
        $fatal(
          1,
          "%s mismatch: expected=%0d result=%0d",
          test_name,
          expected,
          actual
        );
      end
      checks++;
    end
  endtask

  task automatic check_no_request(input string test_name);
    begin
      check_bit(imem.req_valid, 1'b0, {test_name, " request valid"});
    end
  endtask

  task automatic check_read_request(
    input logic [31:0] expected_addr,
    input string       test_name
  );
    begin
      check_bit(imem.req_valid, 1'b1, {test_name, " request valid"});
      check_word(imem.req_addr, expected_addr, {test_name, " request address"});
      check_bit(imem.req_write, 1'b0, {test_name, " request write"});
      check_word(imem.req_wdata, 32'b0, {test_name, " request write data"});
      if (imem.req_wstrb !== 4'b0000) begin
        $fatal(
          1,
          "%s request strobe mismatch: expected=0 result=%x",
          test_name,
          imem.req_wstrb
        );
      end
      checks++;
    end
  endtask

  task automatic check_no_fetch(input string test_name);
    begin
      check_bit(fetch_valid, 1'b0, {test_name, " fetch valid"});
    end
  endtask

  task automatic check_fetch_success(
    input logic [31:0] expected_pc,
    input logic [31:0] expected_insn,
    input string       test_name
  );
    begin
      check_bit(fetch_valid, 1'b1, {test_name, " fetch valid"});
      check_word(fetch_pc, expected_pc, {test_name, " fetch PC"});
      check_word(fetch_insn, expected_insn, {test_name, " fetch instruction"});
      check_bit(fetch_exc.valid, 1'b0, {test_name, " fetch exception valid"});
    end
  endtask

  task automatic check_fetch_fault(
    input logic [31:0] expected_pc,
    input string       test_name
  );
    begin
      check_bit(fetch_valid, 1'b1, {test_name, " fetch valid"});
      check_word(fetch_pc, expected_pc, {test_name, " fetch PC"});
      check_word(fetch_insn, 32'b0, {test_name, " fetch instruction"});
      check_bit(fetch_exc.valid, 1'b1, {test_name, " fetch exception valid"});
      check_cause(
        fetch_exc.cause,
        rv32_pkg::EXC_INST_ACCESS_FAULT,
        {test_name, " fetch exception cause"}
      );
      check_word(fetch_exc.tval, expected_pc, {test_name, " fetch exception tval"});
    end
  endtask

  task automatic wait_for_request(
    input logic [31:0] expected_addr,
    input string       test_name
  );
    int waited_cycles;
    begin
      waited_cycles = 0;
      while ((imem.req_valid !== 1'b1) && (waited_cycles < 8)) begin
        @(negedge clk);
        #1;
        waited_cycles++;
      end

      if (imem.req_valid !== 1'b1) begin
        $fatal(1, "%s timed out waiting for request", test_name);
      end
      check_read_request(expected_addr, test_name);
    end
  endtask

  task automatic accept_request(
    input logic [31:0] expected_addr,
    input string       test_name
  );
    begin
      wait_for_request(expected_addr, test_name);
      @(negedge clk);
      imem.req_ready = 1'b1;
      #1;
      check_read_request(expected_addr, {test_name, " accepted"});
      @(posedge clk);
      #1;
      imem.req_ready = 1'b0;
    end
  endtask

  task automatic reset_stage(input logic enable_after_reset);
    begin
      @(negedge clk);
      rst            = 1'b1;
      enable         = 1'b0;
      consume        = 1'b0;
      flush          = 1'b0;
      redirect_valid = 1'b0;
      redirect_pc    = 32'b0;

      imem.req_ready = 1'b0;
      imem.rsp_valid = 1'b0;
      imem.rsp_rdata = 32'b0;
      imem.rsp_err   = 1'b0;

      repeat (2) @(posedge clk);
      #1;
      check_no_request("reset");
      check_no_fetch("reset");

      @(negedge clk);
      rst     = 1'b0;
      enable  = enable_after_reset;
      consume = 1'b1;
      #1;
    end
  endtask

  // Ready/valid payloads may not change while a request is back-pressured.
  // This monitor also catches any instruction-port write attempt.
  always_ff @(posedge clk) begin
    if (rst) begin
      stalled_request_q <= 1'b0;
      stalled_addr_q    <= 32'b0;
      stalled_write_q   <= 1'b0;
      stalled_wdata_q   <= 32'b0;
      stalled_wstrb_q   <= 4'b0000;
    end else begin
      if (imem.req_valid) begin
        if (
          imem.req_write !== 1'b0
          || imem.req_wdata !== 32'b0
          || imem.req_wstrb !== 4'b0000
        ) begin
          $fatal(1, "instruction request is not read-only");
        end
      end

      if (stalled_request_q) begin
        if (
          imem.req_valid !== 1'b1
          || imem.req_addr !== stalled_addr_q
          || imem.req_write !== stalled_write_q
          || imem.req_wdata !== stalled_wdata_q
          || imem.req_wstrb !== stalled_wstrb_q
        ) begin
          $fatal(1, "back-pressured instruction request changed");
        end
      end

      stalled_request_q <= imem.req_valid && !imem.req_ready;
      if (imem.req_valid && !imem.req_ready) begin
        stalled_addr_q  <= imem.req_addr;
        stalled_write_q <= imem.req_write;
        stalled_wdata_q <= imem.req_wdata;
        stalled_wstrb_q <= imem.req_wstrb;
      end
    end
  end

  initial begin
    clk               = 1'b0;
    rst               = 1'b1;
    enable            = 1'b0;
    consume           = 1'b0;
    flush             = 1'b0;
    redirect_valid    = 1'b0;
    redirect_pc       = 32'b0;
    checks            = 0;

    imem.req_ready    = 1'b0;
    imem.rsp_valid    = 1'b0;
    imem.rsp_rdata    = 32'b0;
    imem.rsp_err      = 1'b0;

    // Sticky request: valid and payload remain stable until ready.
    reset_stage(1'b1);
    wait_for_request(RESET_VECTOR, "sticky initial");
    repeat (3) begin
      @(posedge clk);
      #1;
      check_read_request(RESET_VECTOR, "sticky held");
      check_no_fetch("sticky no response");
    end
    accept_request(RESET_VECTOR, "sticky");

    @(negedge clk);
    enable         = 1'b0;
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h1111_0001;
    #1;
    check_fetch_success(RESET_VECTOR, 32'h1111_0001, "sticky response");
    check_no_request("sticky response disabled");
    @(posedge clk);
    #1;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;
    #1;
    check_no_fetch("sticky response consumed");

    // A consumed response and the next request can use the port in the same
    // cycle, sustaining one instruction per cycle with a one-cycle TCM.
    reset_stage(1'b1);
    accept_request(RESET_VECTOR, "throughput first");

    @(negedge clk);
    imem.req_ready = 1'b1;
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h2222_0001;
    #1;
    check_fetch_success(RESET_VECTOR, 32'h2222_0001, "throughput first response");
    check_read_request(RESET_VECTOR + 32'd4, "throughput second request");
    @(posedge clk);
    #1;
    imem.req_ready = 1'b0;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;
    enable         = 1'b0;

    @(negedge clk);
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h2222_0002;
    #1;
    check_fetch_success(
      RESET_VECTOR + 32'd4,
      32'h2222_0002,
      "throughput second response"
    );
    check_no_request("throughput stops when disabled");
    @(posedge clk);
    #1;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;

    // Response skid/hold: an unconsumed packet is buffered and remains stable.
    reset_stage(1'b1);
    consume = 1'b0;
    accept_request(RESET_VECTOR, "skid first");

    @(negedge clk);
    imem.req_ready = 1'b1;
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h3333_0001;
    #1;
    check_fetch_success(RESET_VECTOR, 32'h3333_0001, "skid direct response");
    check_no_request("skid blocks next request");
    @(posedge clk);
    #1;
    imem.req_ready = 1'b0;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;
    #1;
    check_fetch_success(RESET_VECTOR, 32'h3333_0001, "skid buffered");

    repeat (3) begin
      @(posedge clk);
      #1;
      check_fetch_success(RESET_VECTOR, 32'h3333_0001, "skid stable");
      check_no_request("skid stable blocks request");
    end

    @(negedge clk);
    consume        = 1'b1;
    imem.req_ready = 1'b1;
    #1;
    check_fetch_success(RESET_VECTOR, 32'h3333_0001, "skid consumed");
    check_read_request(RESET_VECTOR + 32'd4, "skid refill request");
    @(posedge clk);
    #1;
    enable         = 1'b0;
    imem.req_ready = 1'b0;
    check_no_fetch("skid retires");

    @(negedge clk);
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h3333_0002;
    #1;
    check_fetch_success(
      RESET_VECTOR + 32'd4,
      32'h3333_0002,
      "skid refill response"
    );
    @(posedge clk);
    #1;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;

    // Instruction bus errors become precise instruction-access-fault packets.
    reset_stage(1'b1);
    accept_request(RESET_VECTOR, "access fault");
    enable = 1'b0;

    @(negedge clk);
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'hdead_beef;
    imem.rsp_err   = 1'b1;
    #1;
    check_fetch_fault(RESET_VECTOR, "access fault response");
    check_no_request("access fault no next request");
    @(posedge clk);
    #1;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;
    imem.rsp_err   = 1'b0;
    #1;
    check_no_fetch("access fault consumed");

    // Flushing a buffered packet invalidates it immediately.
    reset_stage(1'b1);
    consume = 1'b0;
    accept_request(RESET_VECTOR, "flush buffered");

    @(negedge clk);
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h4444_0001;
    #1;
    check_fetch_success(RESET_VECTOR, 32'h4444_0001, "flush buffered response");
    @(posedge clk);
    #1;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;
    #1;
    check_fetch_success(RESET_VECTOR, 32'h4444_0001, "flush buffered held");

    @(negedge clk);
    enable = 1'b0;
    flush  = 1'b1;
    #1;
    check_no_fetch("flush buffered immediate");
    @(posedge clk);
    #1;
    flush = 1'b0;
    check_no_fetch("flush buffered cleared");

    // Flushing an outstanding transaction drains its eventual response.
    reset_stage(1'b1);
    accept_request(RESET_VECTOR, "flush outstanding");

    @(negedge clk);
    enable = 1'b0;
    flush  = 1'b1;
    #1;
    check_no_request("flush outstanding waits");
    check_no_fetch("flush outstanding no packet");
    @(posedge clk);
    #1;
    flush = 1'b0;

    @(negedge clk);
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h4444_0002;
    #1;
    check_no_fetch("flush outstanding drops response");
    check_no_request("flush outstanding disabled");
    @(posedge clk);
    #1;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;
    check_no_fetch("flush outstanding drained");

    // Redirect from idle launches the target rather than the reset vector.
    reset_stage(1'b0);
    @(negedge clk);
    enable         = 1'b0;
    redirect_valid = 1'b1;
    redirect_pc    = REDIRECT_A;
    imem.req_ready = 1'b1;
    #1;
    check_read_request(REDIRECT_A, "redirect idle target");
    check_no_fetch("redirect idle no stale packet");
    @(posedge clk);
    #1;
    redirect_valid = 1'b0;
    redirect_pc    = 32'b0;
    imem.req_ready = 1'b0;
    enable         = 1'b0;

    @(negedge clk);
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h5555_0001;
    #1;
    check_fetch_success(REDIRECT_A, 32'h5555_0001, "redirect idle response");
    @(posedge clk);
    #1;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;

    // A redirect while a response is delayed is remembered. When the stale
    // response arrives, it is dropped while the target request is accepted.
    reset_stage(1'b1);
    accept_request(RESET_VECTOR, "redirect outstanding old");

    @(negedge clk);
    redirect_valid = 1'b1;
    redirect_pc    = REDIRECT_A;
    imem.req_ready = 1'b1;
    #1;
    check_no_request("redirect outstanding blocked");
    check_no_fetch("redirect outstanding no packet");
    @(posedge clk);
    #1;
    redirect_valid = 1'b0;
    redirect_pc    = 32'b0;
    imem.req_ready = 1'b0;

    @(posedge clk);
    #1;
    check_no_request("redirect outstanding still waiting");

    @(negedge clk);
    imem.req_ready = 1'b1;
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h6666_0001;
    #1;
    check_no_fetch("redirect outstanding drops old response");
    check_read_request(REDIRECT_A, "redirect outstanding target");
    @(posedge clk);
    #1;
    imem.req_ready = 1'b0;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;
    enable         = 1'b0;

    @(negedge clk);
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h6666_0002;
    #1;
    check_fetch_success(
      REDIRECT_A,
      32'h6666_0002,
      "redirect outstanding target response"
    );
    @(posedge clk);
    #1;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;

    // Fast path: redirect and stale response occur in the same cycle.
    reset_stage(1'b1);
    accept_request(RESET_VECTOR, "redirect same-cycle old");

    @(negedge clk);
    redirect_valid = 1'b1;
    redirect_pc    = REDIRECT_B;
    imem.req_ready = 1'b1;
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h7777_0001;
    #1;
    check_no_fetch("redirect same-cycle drops old response");
    check_read_request(REDIRECT_B, "redirect same-cycle target");
    @(posedge clk);
    #1;
    redirect_valid = 1'b0;
    redirect_pc    = 32'b0;
    imem.req_ready = 1'b0;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;
    enable         = 1'b0;

    @(negedge clk);
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h7777_0002;
    #1;
    check_fetch_success(
      REDIRECT_B,
      32'h7777_0002,
      "redirect same-cycle target response"
    );
    @(posedge clk);
    #1;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;

    // A presented request cannot be withdrawn or have its payload changed when
    // redirect arrives under request backpressure.
    reset_stage(1'b1);
    wait_for_request(RESET_VECTOR, "redirect backpressured old");

    @(negedge clk);
    redirect_valid = 1'b1;
    redirect_pc    = REDIRECT_B;
    #1;
    check_read_request(RESET_VECTOR, "redirect backpressured remains old");
    @(posedge clk);
    #1;
    redirect_valid = 1'b0;
    redirect_pc    = 32'b0;

    repeat (2) begin
      @(posedge clk);
      #1;
      check_read_request(RESET_VECTOR, "redirect backpressured stable");
    end

    @(negedge clk);
    imem.req_ready = 1'b1;
    #1;
    check_read_request(RESET_VECTOR, "redirect backpressured old accepted");
    @(posedge clk);
    #1;
    imem.req_ready = 1'b0;

    @(negedge clk);
    imem.req_ready = 1'b1;
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h8888_0001;
    #1;
    check_no_fetch("redirect backpressured drops old response");
    check_read_request(REDIRECT_B, "redirect backpressured target");
    @(posedge clk);
    #1;
    imem.req_ready = 1'b0;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;
    enable         = 1'b0;

    @(negedge clk);
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h8888_0002;
    #1;
    check_fetch_success(
      REDIRECT_B,
      32'h8888_0002,
      "redirect backpressured target response"
    );
    @(posedge clk);
    #1;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;

    // If redirects stack while an old transaction is draining, the most recent
    // target wins.
    reset_stage(1'b1);
    accept_request(RESET_VECTOR, "latest redirect old");

    @(negedge clk);
    redirect_valid = 1'b1;
    redirect_pc    = REDIRECT_A;
    #1;
    check_no_request("latest redirect A waits");
    @(posedge clk);
    #1;

    @(negedge clk);
    redirect_pc = REDIRECT_C;
    #1;
    check_no_request("latest redirect C waits");
    @(posedge clk);
    #1;
    redirect_valid = 1'b0;
    redirect_pc    = 32'b0;

    @(negedge clk);
    imem.req_ready = 1'b1;
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h9999_0001;
    #1;
    check_no_fetch("latest redirect drops old response");
    check_read_request(REDIRECT_C, "latest redirect target");
    @(posedge clk);
    #1;
    imem.req_ready = 1'b0;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;
    enable         = 1'b0;

    @(negedge clk);
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'h9999_0002;
    #1;
    check_fetch_success(
      REDIRECT_C,
      32'h9999_0002,
      "latest redirect target response"
    );
    @(posedge clk);
    #1;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;

    // A combinational slave may complete a request in its acceptance cycle.
    // The fall-through path must expose that packet without creating a phantom
    // outstanding transaction.
    reset_stage(1'b1);
    imem.req_ready = 1'b1;
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'habab_0001;
    #1;
    check_read_request(RESET_VECTOR, "zero-latency request");
    check_fetch_success(
      RESET_VECTOR,
      32'habab_0001,
      "zero-latency response"
    );
    @(posedge clk);
    #1;
    enable         = 1'b0;
    imem.req_ready = 1'b0;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;
    #1;
    check_no_request("zero-latency request retires");
    check_no_fetch("zero-latency response retires");

    // Reset cannot cancel an already accepted memory transaction.  Drain its
    // late response before restarting from RESET_VECTOR, without exposing the
    // pre-reset instruction or mistagging it as the new fetch.
    reset_stage(1'b1);
    accept_request(RESET_VECTOR, "reset drain old");

    @(negedge clk);
    rst     = 1'b1;
    enable  = 1'b0;
    consume = 1'b0;
    #1;
    check_no_request("reset drain suppresses request");
    check_no_fetch("reset drain suppresses fetch");

    repeat (2) begin
      @(posedge clk);
      #1;
      check_no_request("reset drain held request");
      check_no_fetch("reset drain held fetch");
    end

    @(negedge clk);
    rst     = 1'b0;
    enable  = 1'b1;
    consume = 1'b1;
    #1;
    check_no_request("reset drain waits for old response");
    check_no_fetch("reset drain has no old packet");

    @(negedge clk);
    imem.req_ready = 1'b1;
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'haaaa_0001;
    #1;
    check_no_fetch("reset drain drops old response");
    check_read_request(RESET_VECTOR, "reset drain restart request");
    @(posedge clk);
    #1;
    imem.req_ready = 1'b0;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;
    enable         = 1'b0;

    @(negedge clk);
    imem.rsp_valid = 1'b1;
    imem.rsp_rdata = 32'haaaa_0002;
    #1;
    check_fetch_success(
      RESET_VECTOR,
      32'haaaa_0002,
      "reset drain restarted response"
    );
    @(posedge clk);
    #1;
    imem.rsp_valid = 1'b0;
    imem.rsp_rdata = 32'b0;

    $display("tb_if_stage: PASS (%0d checks)", checks);
    $finish;
  end

  initial begin
    #20_000;
    $fatal(1, "tb_if_stage timeout");
  end

endmodule
