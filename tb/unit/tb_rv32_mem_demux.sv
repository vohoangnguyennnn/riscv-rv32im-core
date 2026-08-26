module tb_rv32_mem_demux;

  localparam logic [31:0] TIMER_BASE = 32'h0200_0000;
  localparam logic [31:0] UART_BASE  = 32'h1000_0000;
  localparam logic [31:0] GPIO_BASE  = 32'h1001_0000;

  localparam logic [1:0] TARGET_TCM   = 2'd0;
  localparam logic [1:0] TARGET_TIMER = 2'd1;
  localparam logic [1:0] TARGET_UART  = 2'd2;
  localparam logic [1:0] TARGET_GPIO  = 2'd3;

  logic clk;
  logic rst;
  int   checks;

  rv32_mem_if core();
  rv32_mem_if tcm();
  rv32_mem_if timer();
  rv32_mem_if uart();
  rv32_mem_if gpio();

  rv32_mem_demux #(
    .TIMER_BASE_ADDR (TIMER_BASE),
    .TIMER_ADDR_MASK (32'hffff_0000),
    .UART_BASE_ADDR  (UART_BASE),
    .UART_ADDR_MASK  (32'hffff_0000),
    .GPIO_BASE_ADDR  (GPIO_BASE),
    .GPIO_ADDR_MASK  (32'hffff_0000)
  ) dut (
    .clk_i   (clk),
    .rst_i   (rst),
    .core_s  (core),
    .tcm_m   (tcm),
    .timer_m (timer),
    .uart_m  (uart),
    .gpio_m  (gpio)
  );

  always #5 clk = ~clk;

  task automatic drive_core_idle;
    begin
      core.req_valid = 1'b0;
      core.req_addr  = 32'b0;
      core.req_write = 1'b0;
      core.req_wdata = 32'b0;
      core.req_wstrb = 4'b0000;
    end
  endtask

  task automatic drive_request(
    input logic [31:0] addr,
    input logic        write,
    input logic [31:0] wdata,
    input logic [3:0]  wstrb
  );
    begin
      core.req_valid = 1'b1;
      core.req_addr  = addr;
      core.req_write = write;
      core.req_wdata = wdata;
      core.req_wstrb = wstrb;
    end
  endtask

  task automatic clear_responses;
    begin
      tcm.rsp_valid   = 1'b0;
      tcm.rsp_rdata   = 32'b0;
      tcm.rsp_err     = 1'b0;
      timer.rsp_valid = 1'b0;
      timer.rsp_rdata = 32'b0;
      timer.rsp_err   = 1'b0;
      uart.rsp_valid  = 1'b0;
      uart.rsp_rdata  = 32'b0;
      uart.rsp_err    = 1'b0;
      gpio.rsp_valid  = 1'b0;
      gpio.rsp_rdata  = 32'b0;
      gpio.rsp_err    = 1'b0;
    end
  endtask

  task automatic set_response(
    input logic [1:0]  target,
    input logic [31:0] rdata,
    input logic        err
  );
    begin
      unique case (target)
        TARGET_TIMER: begin
          timer.rsp_valid = 1'b1;
          timer.rsp_rdata = rdata;
          timer.rsp_err   = err;
        end
        TARGET_UART: begin
          uart.rsp_valid = 1'b1;
          uart.rsp_rdata = rdata;
          uart.rsp_err   = err;
        end
        TARGET_GPIO: begin
          gpio.rsp_valid = 1'b1;
          gpio.rsp_rdata = rdata;
          gpio.rsp_err   = err;
        end
        default: begin
          tcm.rsp_valid = 1'b1;
          tcm.rsp_rdata = rdata;
          tcm.rsp_err   = err;
        end
      endcase
    end
  endtask

  task automatic set_ready(
    input logic [1:0] target,
    input logic       ready
  );
    begin
      unique case (target)
        TARGET_TIMER: timer.req_ready = ready;
        TARGET_UART:  uart.req_ready  = ready;
        TARGET_GPIO:  gpio.req_ready  = ready;
        default:      tcm.req_ready   = ready;
      endcase
    end
  endtask

  task automatic check_bit(
    input logic  actual,
    input logic  expected,
    input string test_name
  );
    begin
      if (actual !== expected) begin
        $fatal(1, "%s mismatch: expected=%0b result=%0b", test_name, expected, actual);
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
        $fatal(1, "%s mismatch: expected=%08x result=%08x", test_name, expected, actual);
      end
      checks++;
    end
  endtask

  task automatic check_target(
    input logic [1:0] actual,
    input logic [1:0] expected,
    input string      test_name
  );
    begin
      if (actual !== expected) begin
        $fatal(1, "%s mismatch: expected=%0d result=%0d", test_name, expected, actual);
      end
      checks++;
    end
  endtask

  task automatic check_selected(
    input logic [1:0] expected_target,
    input string      test_name
  );
    begin
      check_bit(tcm.req_valid, expected_target == TARGET_TCM, {test_name, " TCM select"});
      check_bit(timer.req_valid, expected_target == TARGET_TIMER, {test_name, " timer select"});
      check_bit(uart.req_valid, expected_target == TARGET_UART, {test_name, " UART select"});
      check_bit(gpio.req_valid, expected_target == TARGET_GPIO, {test_name, " GPIO select"});
    end
  endtask

  task automatic check_all_targets_disabled(input string test_name);
    begin
      check_bit(tcm.req_valid, 1'b0, {test_name, " TCM"});
      check_bit(timer.req_valid, 1'b0, {test_name, " timer"});
      check_bit(uart.req_valid, 1'b0, {test_name, " UART"});
      check_bit(gpio.req_valid, 1'b0, {test_name, " GPIO"});
    end
  endtask

  task automatic check_broadcast_payload(
    input logic [31:0] expected_addr,
    input logic        expected_write,
    input logic [31:0] expected_wdata,
    input logic [3:0]  expected_wstrb,
    input string       test_name
  );
    begin
      check_word(tcm.req_addr, expected_addr, {test_name, " TCM address"});
      check_word(timer.req_addr, expected_addr, {test_name, " timer address"});
      check_word(uart.req_addr, expected_addr, {test_name, " UART address"});
      check_word(gpio.req_addr, expected_addr, {test_name, " GPIO address"});
      check_bit(tcm.req_write, expected_write, {test_name, " TCM write"});
      check_bit(timer.req_write, expected_write, {test_name, " timer write"});
      check_bit(uart.req_write, expected_write, {test_name, " UART write"});
      check_bit(gpio.req_write, expected_write, {test_name, " GPIO write"});
      check_word(tcm.req_wdata, expected_wdata, {test_name, " TCM write data"});
      check_word(timer.req_wdata, expected_wdata, {test_name, " timer write data"});
      check_word(uart.req_wdata, expected_wdata, {test_name, " UART write data"});
      check_word(gpio.req_wdata, expected_wdata, {test_name, " GPIO write data"});
      if ((tcm.req_wstrb !== expected_wstrb) ||
          (timer.req_wstrb !== expected_wstrb) ||
          (uart.req_wstrb !== expected_wstrb) ||
          (gpio.req_wstrb !== expected_wstrb)) begin
        $fatal(1, "%s write-strobe broadcast mismatch", test_name);
      end
      checks++;
    end
  endtask

  // Issue one request, then assert every slave response simultaneously with a
  // unique payload. Only the latched target is allowed to reach the core.
  task automatic test_transaction(
    input logic [31:0] addr,
    input logic [1:0]  target,
    input logic [31:0] response_data,
    input logic        response_err,
    input string       test_name
  );
    begin
      @(negedge clk);
      drive_request(addr, 1'b1, 32'ha5a5_5a5a, 4'b1010);
      #1;
      check_bit(core.req_ready, 1'b1, {test_name, " request ready"});
      check_selected(target, {test_name, " one-hot route"});
      check_broadcast_payload(addr, 1'b1, 32'ha5a5_5a5a, 4'b1010, {test_name, " payload"});

      @(posedge clk);
      #1;
      check_bit(dut.pending_q, 1'b1, {test_name, " pending"});
      check_target(dut.pending_target_q, target, {test_name, " latched target"});
      drive_core_idle();
      // Change the live address and make all non-owners noisy. Response routing
      // must depend only on pending_target_q.
      core.req_addr = addr ^ 32'h1201_0040;
      tcm.rsp_valid   = 1'b1;
      tcm.rsp_rdata   = 32'h0000_0000;
      tcm.rsp_err     = 1'b0;
      timer.rsp_valid = 1'b1;
      timer.rsp_rdata = 32'h1111_1111;
      timer.rsp_err   = 1'b0;
      uart.rsp_valid  = 1'b1;
      uart.rsp_rdata  = 32'h2222_2222;
      uart.rsp_err    = 1'b0;
      gpio.rsp_valid  = 1'b1;
      gpio.rsp_rdata  = 32'h3333_3333;
      gpio.rsp_err    = 1'b0;
      set_response(target, response_data, response_err);
      #1;
      check_bit(core.rsp_valid, 1'b1, {test_name, " response valid"});
      check_word(core.rsp_rdata, response_data, {test_name, " response data"});
      check_bit(core.rsp_err, response_err, {test_name, " response error"});

      @(posedge clk);
      #1;
      check_bit(dut.pending_q, 1'b0, {test_name, " response retires"});
      check_bit(core.rsp_valid, 1'b0, {test_name, " response one cycle"});
      clear_responses();
      drive_core_idle();
    end
  endtask

  // Retire the current owner and issue a request to another target at the same
  // edge. This task is chained to exercise every phase-4 target transition.
  task automatic recycle_to(
    input logic [1:0]  old_target,
    input logic [31:0] new_addr,
    input logic [1:0]  new_target,
    input logic [31:0] old_response_data,
    input string       test_name
  );
    begin
      @(negedge clk);
      drive_request(new_addr, 1'b0, 32'b0, 4'b0000);
      #1;
      check_bit(core.req_ready, 1'b0, {test_name, " waits before old response"});
      check_bit(tcm.req_valid | timer.req_valid | uart.req_valid | gpio.req_valid, 1'b0, {test_name, " not issued early"});

      set_response(old_target, old_response_data, 1'b0);
      #1;
      check_bit(core.rsp_valid, 1'b1, {test_name, " old response visible"});
      check_word(core.rsp_rdata, old_response_data, {test_name, " old response data"});
      check_bit(core.req_ready, 1'b1, {test_name, " new request ready"});
      check_selected(new_target, {test_name, " new target selected"});

      @(posedge clk);
      #1;
      check_bit(dut.pending_q, 1'b1, {test_name, " pending slot retained"});
      check_target(dut.pending_target_q, new_target, {test_name, " ownership transferred"});
      clear_responses();
      drive_core_idle();
      #1;
      check_bit(core.rsp_valid, 1'b0, {test_name, " old response hidden"});
    end
  endtask

  initial begin
    clk    = 1'b0;
    rst    = 1'b1;
    checks = 0;

    drive_core_idle();
    clear_responses();
    tcm.req_ready   = 1'b1;
    timer.req_ready = 1'b1;
    uart.req_ready  = 1'b1;
    gpio.req_ready  = 1'b1;

    #1;
    check_bit(core.req_ready, 1'b0, "reset request backpressure");
    check_bit(core.rsp_valid, 1'b0, "reset response hidden");
    check_all_targets_disabled("reset all targets disabled");

    repeat (2) @(posedge clk);
    #1;
    check_bit(dut.pending_q, 1'b0, "pending reset value");
    rst = 1'b0;

    // Basic route, payload, target-latch, response-isolation, error propagation.
    test_transaction(32'h0000_0100, TARGET_TCM,   32'hcafe_0000, 1'b0, "TCM transaction");
    test_transaction(TIMER_BASE + 32'h4000, TARGET_TIMER, 32'hcafe_1111, 1'b1, "timer transaction");
    test_transaction(UART_BASE + 32'h0008, TARGET_UART,   32'hcafe_2222, 1'b0, "UART transaction");
    test_transaction(GPIO_BASE + 32'h0004, TARGET_GPIO,   32'hcafe_3333, 1'b1, "GPIO transaction");

    // Selected-slave backpressure is propagated, but the request and payload
    // remain stable and no ownership is captured without a handshake.
    @(negedge clk);
    uart.req_ready = 1'b0;
    drive_request(UART_BASE, 1'b1, 32'h0000_005a, 4'b0001);
    #1;
    check_bit(core.req_ready, 1'b0, "UART backpressure propagated");
    check_selected(TARGET_UART, "UART backpressured route");
    check_broadcast_payload(UART_BASE, 1'b1, 32'h0000_005a, 4'b0001, "UART held payload");
    @(posedge clk);
    #1;
    check_bit(dut.pending_q, 1'b0, "backpressured request not captured");
    uart.req_ready = 1'b1;
    #1;
    check_bit(core.req_ready, 1'b1, "UART backpressure released");
    @(posedge clk);
    #1;
    check_target(dut.pending_target_q, TARGET_UART, "released UART target captured");
    drive_core_idle();
    set_response(TARGET_UART, 32'h0000_005a, 1'b0);
    #1;
    check_word(core.rsp_rdata, 32'h0000_005a, "released UART response");
    @(posedge clk);
    #1;
    clear_responses();

    // Verify all three complete 64-KiB apertures and their adjacent fallback
    // addresses. Keep every target backpressured so these probes do not create
    // transactions while checking pure decode behavior.
    @(negedge clk);
    tcm.req_ready   = 1'b0;
    timer.req_ready = 1'b0;
    uart.req_ready  = 1'b0;
    gpio.req_ready  = 1'b0;
    drive_request(TIMER_BASE + 32'hfffc, 1'b0, 32'b0, 4'b0000);
    #1;
    check_selected(TARGET_TIMER, "timer upper aperture boundary");
    drive_request(TIMER_BASE - 32'd4, 1'b0, 32'b0, 4'b0000);
    #1;
    check_selected(TARGET_TCM, "below timer aperture fallback");
    drive_request(TIMER_BASE + 32'h1_0000, 1'b0, 32'b0, 4'b0000);
    #1;
    check_selected(TARGET_TCM, "above timer aperture fallback");
    drive_request(UART_BASE + 32'hfffc, 1'b0, 32'b0, 4'b0000);
    #1;
    check_selected(TARGET_UART, "UART upper aperture boundary");
    drive_request(UART_BASE - 32'd4, 1'b0, 32'b0, 4'b0000);
    #1;
    check_selected(TARGET_TCM, "below UART aperture fallback");
    drive_request(GPIO_BASE + 32'hfffc, 1'b0, 32'b0, 4'b0000);
    #1;
    check_selected(TARGET_GPIO, "GPIO upper aperture boundary");
    drive_request(GPIO_BASE + 32'h1_0000, 1'b0, 32'b0, 4'b0000);
    #1;
    check_selected(TARGET_TCM, "above GPIO aperture fallback");
    drive_core_idle();
    tcm.req_ready   = 1'b1;
    timer.req_ready = 1'b1;
    uart.req_ready  = 1'b1;
    gpio.req_ready  = 1'b1;

    // Start at TCM, then recycle the one-entry pending slot across all phase-4
    // targets without a bubble: TCM -> UART -> GPIO -> timer -> TCM.
    @(negedge clk);
    drive_request(32'h0000_0040, 1'b0, 32'b0, 4'b0000);
    @(posedge clk);
    #1;
    drive_core_idle();
    check_target(dut.pending_target_q, TARGET_TCM, "recycle chain starts at TCM");
    recycle_to(TARGET_TCM, UART_BASE, TARGET_UART, 32'h1000_0001, "TCM to UART recycle");
    recycle_to(TARGET_UART, GPIO_BASE, TARGET_GPIO, 32'h1000_0002, "UART to GPIO recycle");
    recycle_to(TARGET_GPIO, TIMER_BASE, TARGET_TIMER, 32'h1000_0003, "GPIO to timer recycle");
    recycle_to(TARGET_TIMER, 32'h0000_0080, TARGET_TCM, 32'h1000_0004, "timer to TCM recycle");
    set_response(TARGET_TCM, 32'h1000_0005, 1'b1);
    #1;
    check_bit(core.rsp_valid, 1'b1, "recycle chain final response valid");
    check_word(core.rsp_rdata, 32'h1000_0005, "recycle chain final response data");
    check_bit(core.rsp_err, 1'b1, "recycle chain final error");
    @(posedge clk);
    #1;
    check_bit(dut.pending_q, 1'b0, "recycle chain drains");
    clear_responses();

    // If the next target is not ready, the old response must still retire. The
    // waiting request is captured only on its later handshake.
    @(negedge clk);
    drive_request(32'h0000_00c0, 1'b0, 32'b0, 4'b0000);
    @(posedge clk);
    #1;
    gpio.req_ready = 1'b0;
    drive_request(GPIO_BASE + 32'h0004, 1'b0, 32'b0, 4'b0000);
    set_response(TARGET_TCM, 32'h2000_0001, 1'b0);
    #1;
    check_bit(core.rsp_valid, 1'b1, "old response drains under GPIO backpressure");
    check_bit(core.req_ready, 1'b0, "new GPIO request remains backpressured");
    check_selected(TARGET_GPIO, "backpressured recycle route");
    @(posedge clk);
    #1;
    check_bit(dut.pending_q, 1'b0, "old owner clears without new handshake");
    clear_responses();
    gpio.req_ready = 1'b1;
    #1;
    check_bit(core.req_ready, 1'b1, "waiting GPIO request later ready");
    @(posedge clk);
    #1;
    check_target(dut.pending_target_q, TARGET_GPIO, "waiting GPIO request later captured");
    drive_core_idle();
    set_response(TARGET_GPIO, 32'h2000_0002, 1'b0);
    @(posedge clk);
    #1;
    clear_responses();
    check_bit(dut.pending_q, 1'b0, "waiting GPIO response drains");

    // Reset cancels ownership and prevents a late response from becoming a
    // post-reset completion.
    @(negedge clk);
    drive_request(TIMER_BASE, 1'b0, 32'b0, 4'b0000);
    @(posedge clk);
    #1;
    drive_core_idle();
    check_bit(dut.pending_q, 1'b1, "reset test request pending");
    @(negedge clk);
    rst = 1'b1;
    set_response(TARGET_TIMER, 32'hffff_0000, 1'b0);
    #1;
    check_bit(core.req_ready, 1'b0, "reset blocks request");
    check_bit(core.rsp_valid, 1'b0, "reset hides pending response");
    check_all_targets_disabled("reset disables every target");
    @(posedge clk);
    #1;
    check_bit(dut.pending_q, 1'b0, "reset clears pending ownership");
    rst = 1'b0;
    #1;
    check_bit(core.rsp_valid, 1'b0, "late timer response ignored after reset");
    clear_responses();

    $display("tb_rv32_mem_demux: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
