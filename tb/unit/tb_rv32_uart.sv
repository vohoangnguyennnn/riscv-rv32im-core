module tb_rv32_uart;

  localparam logic [31:0] TEST_BASE    = 32'h1000_0000;
  localparam logic [31:0] TXDATA_ADDR  = TEST_BASE + 32'h0;
  localparam logic [31:0] RXDATA_ADDR  = TEST_BASE + 32'h4;
  localparam logic [31:0] STATUS_ADDR  = TEST_BASE + 32'h8;
  localparam logic [31:0] BAUDDIV_ADDR = TEST_BASE + 32'hc;
  localparam int unsigned TEST_CLK_HZ  = 1_000_000;
  localparam int unsigned TEST_BAUD    = 100_000;
  localparam int unsigned CLKS_PER_BIT = TEST_CLK_HZ / TEST_BAUD;

  logic clk;
  logic rst;
  logic uart_rx;
  logic uart_tx;
  int   checks;

  rv32_mem_if uart();

  rv32_uart #(
    .BASE_ADDR   (TEST_BASE),
    .CLK_FREQ_HZ (TEST_CLK_HZ),
    .BAUD_RATE   (TEST_BAUD)
  ) dut (
    .clk_i     (clk),
    .rst_i     (rst),
    .uart_s    (uart),
    .uart_rx_i (uart_rx),
    .uart_tx_o (uart_tx)
  );

  always #5 clk = ~clk;

  task automatic drive_bus_idle;
    begin
      uart.req_valid = 1'b0;
      uart.req_addr  = 32'b0;
      uart.req_write = 1'b0;
      uart.req_wdata = 32'b0;
      uart.req_wstrb = 4'b0000;
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

  task automatic uart_access(
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
      uart.req_valid = 1'b1;
      uart.req_addr  = addr;
      uart.req_write = write;
      uart.req_wdata = wdata;
      uart.req_wstrb = wstrb;
      #1;

      check_bit(uart.req_ready, 1'b1, {test_name, " request ready"});

      @(posedge clk);
      #1;
      check_bit(uart.rsp_valid, 1'b1, {test_name, " response valid"});
      check_bit(uart.rsp_err, expected_err, {test_name, " response error"});

      if (check_rdata) begin
        check_word(uart.rsp_rdata, expected_rdata, {test_name, " response data"});
      end

      drive_bus_idle();
    end
  endtask

  task automatic read_word(
    input logic [31:0] addr,
    input logic [31:0] expected,
    input string       test_name
  );
    begin
      uart_access(
        1'b0,
        addr,
        32'b0,
        4'b0000,
        1'b0,
        1'b1,
        expected,
        test_name
      );
    end
  endtask

  task automatic write_low_byte(
    input logic [31:0] addr,
    input logic [7:0]  value,
    input string       test_name
  );
    begin
      uart_access(
        1'b1,
        addr,
        {24'b0, value},
        4'b0001,
        1'b0,
        1'b0,
        32'b0,
        test_name
      );
    end
  endtask

  task automatic check_tx_frame(
    input logic [7:0] expected_data,
    input string      test_name
  );
    begin
      // Called immediately after the launch edge.
      check_bit(uart_tx, 1'b0, {test_name, " start edge"});
      repeat (CLKS_PER_BIT / 2) @(posedge clk);
      #1;
      check_bit(uart_tx, 1'b0, {test_name, " start center"});

      for (int unsigned bit_index = 0; bit_index < 8; bit_index++) begin
        repeat (CLKS_PER_BIT) @(posedge clk);
        #1;
        check_bit(
          uart_tx,
          expected_data[bit_index],
          $sformatf("%s data bit %0d", test_name, bit_index)
        );
      end

      repeat (CLKS_PER_BIT) @(posedge clk);
      #1;
      check_bit(uart_tx, 1'b1, {test_name, " stop center"});

      repeat (CLKS_PER_BIT / 2) @(posedge clk);
      #1;
      check_bit(dut.tx_busy_q, 1'b0, {test_name, " transmitter idle"});
      check_bit(uart_tx, 1'b1, {test_name, " idle high"});
    end
  endtask

  task automatic drive_rx_frame(
    input logic [7:0] data,
    input logic       valid_stop
  );
    begin
      @(negedge clk);
      uart_rx = 1'b0;
      repeat (CLKS_PER_BIT) @(negedge clk);

      for (int unsigned bit_index = 0; bit_index < 8; bit_index++) begin
        uart_rx = data[bit_index];
        repeat (CLKS_PER_BIT) @(negedge clk);
      end

      uart_rx = valid_stop;
      repeat (CLKS_PER_BIT) @(negedge clk);
      uart_rx = 1'b1;

      // Cover synchronizer latency and the receiver's stop-state update.
      repeat (3) @(posedge clk);
      #1;
    end
  endtask

  initial begin
    clk     = 1'b0;
    rst     = 1'b1;
    uart_rx = 1'b1;
    checks  = 0;
    drive_bus_idle();

    #1;
    check_bit(uart.req_ready, 1'b0, "reset backpressure");
    check_bit(uart_tx, 1'b1, "reset TX idle high");

    repeat (2) @(posedge clk);
    #1;
    check_bit(uart.rsp_valid, 1'b0, "reset response clear");
    check_bit(dut.tx_busy_q, 1'b0, "reset transmitter idle");
    check_bit(dut.rx_valid_q, 1'b0, "reset receiver empty");
    check_bit(dut.rx_overrun_q, 1'b0, "reset overrun clear");
    check_bit(dut.rx_frame_error_q, 1'b0, "reset frame error clear");

    rst = 1'b0;
    #1;
    check_bit(uart.req_ready, 1'b1, "ready after reset");

    // Register reset values and fixed baud divisor.
    read_word(TXDATA_ADDR, 32'h0000_0000, "TXDATA idle read");
    read_word(RXDATA_ADDR, 32'h8000_0000, "RXDATA empty read");
    read_word(STATUS_ADDR, 32'h0000_0001, "STATUS reset read");
    read_word(BAUDDIV_ADDR, 32'(CLKS_PER_BIT), "BAUDDIV read");

    // Decode one complete transmitted 8-N-1 frame at bit centers.
    write_low_byte(TXDATA_ADDR, 8'ha5, "TX byte launch");
    check_bit(dut.tx_busy_q, 1'b1, "TX busy after launch");
    check_tx_frame(8'ha5, "TX frame");

    // A second legal write is held while TX is busy and receives no premature
    // response. The original frame remains unaffected.
    write_low_byte(TXDATA_ADDR, 8'h3c, "backpressure source launch");
    @(negedge clk);
    uart.req_valid = 1'b1;
    uart.req_addr  = TXDATA_ADDR;
    uart.req_write = 1'b1;
    uart.req_wdata = 32'h0000_00c3;
    uart.req_wstrb = 4'b0001;
    #1;
    check_bit(uart.req_ready, 1'b0, "busy TX write backpressured");
    @(posedge clk);
    #1;
    check_bit(uart.rsp_valid, 1'b0, "backpressured write has no response");
    drive_bus_idle();
    wait (!dut.tx_busy_q);
    #1;
    check_bit(uart_tx, 1'b1, "TX returns idle after backpressure test");

    // False starts do not create a receive byte or sticky error.
    @(negedge clk);
    uart_rx = 1'b0;
    repeat (2) @(negedge clk);
    uart_rx = 1'b1;
    repeat (CLKS_PER_BIT) @(posedge clk);
    #1;
    check_bit(dut.rx_valid_q, 1'b0, "false start no receive byte");
    check_bit(dut.rx_frame_error_q, 1'b0, "false start no frame error");

    // A valid receive frame is exposed through STATUS/RXDATA. Reading RXDATA
    // returns the byte captured at request time and atomically pops it.
    drive_rx_frame(8'h5a, 1'b1);
    check_bit(dut.rx_valid_q, 1'b1, "RX valid frame captured");
    check_word({24'b0, dut.rx_data_q}, 32'h0000_005a, "RX data captured");
    read_word(STATUS_ADDR, 32'h0000_0005, "STATUS RX valid");
    read_word(RXDATA_ADDR, 32'h0000_005a, "RXDATA read and pop");
    check_bit(dut.rx_valid_q, 1'b0, "RXDATA read clears valid");
    read_word(RXDATA_ADDR, 32'h8000_005a, "RXDATA empty retains last sample");

    // A second frame cannot overwrite unread data. The first byte is retained
    // and overrun stays asserted until software clears STATUS[3].
    drive_rx_frame(8'h11, 1'b1);
    drive_rx_frame(8'h22, 1'b1);
    check_word({24'b0, dut.rx_data_q}, 32'h0000_0011, "overrun retains oldest byte");
    read_word(STATUS_ADDR, 32'h0000_000d, "STATUS overrun sticky");
    read_word(RXDATA_ADDR, 32'h0000_0011, "overrun oldest byte pop");
    read_word(STATUS_ADDR, 32'h0000_0009, "overrun remains after pop");
    write_low_byte(STATUS_ADDR, 8'h08, "clear overrun W1C");
    read_word(STATUS_ADDR, 32'h0000_0001, "overrun cleared");

    // Bad stop bits still deliver the sampled byte but report a sticky framing
    // error, allowing software to decide whether to consume or discard it.
    drive_rx_frame(8'hc7, 1'b0);
    check_word({24'b0, dut.rx_data_q}, 32'h0000_00c7, "framing byte retained");
    read_word(STATUS_ADDR, 32'h0000_0015, "STATUS framing error sticky");
    read_word(RXDATA_ADDR, 32'h0000_00c7, "framing byte pop");
    write_low_byte(STATUS_ADDR, 8'h10, "clear framing error W1C");
    read_word(STATUS_ADDR, 32'h0000_0001, "framing error cleared");

    // Unsupported directions, offsets, and strobe shapes terminate with an
    // error and cannot launch TX or mutate receive state.
    uart_access(
      1'b1, RXDATA_ADDR, 32'h55, 4'b0001, 1'b1, 1'b0, 32'b0,
      "RXDATA write rejected"
    );
    uart_access(
      1'b1, BAUDDIV_ADDR, 32'd20, 4'b1111, 1'b1, 1'b0, 32'b0,
      "BAUDDIV write rejected"
    );
    uart_access(
      1'b1, TXDATA_ADDR, 32'h55, 4'b0101, 1'b1, 1'b0, 32'b0,
      "sparse TX strobe rejected"
    );
    uart_access(
      1'b0, TEST_BASE + 32'h10, 32'b0, 4'b0000, 1'b1, 1'b0, 32'b0,
      "unimplemented register rejected"
    );
    uart_access(
      1'b0, STATUS_ADDR + 32'd2, 32'b0, 4'b0000, 1'b1, 1'b0, 32'b0,
      "misaligned register rejected"
    );
    check_bit(dut.tx_busy_q, 1'b0, "invalid accesses do not launch TX");

    // Response is a one-cycle pulse rather than a sticky acknowledgement.
    @(posedge clk);
    #1;
    check_bit(uart.rsp_valid, 1'b0, "response pulse retires");

    $display("tb_rv32_uart: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
