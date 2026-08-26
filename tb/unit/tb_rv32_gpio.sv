module tb_rv32_gpio;

  localparam logic [31:0] TEST_BASE          = 32'h1001_0000;
  localparam logic [31:0] INPUT_ADDR         = TEST_BASE + 32'h00;
  localparam logic [31:0] OUTPUT_ADDR        = TEST_BASE + 32'h04;
  localparam logic [31:0] OUTPUT_ENABLE_ADDR = TEST_BASE + 32'h08;
  localparam logic [31:0] OUTPUT_SET_ADDR    = TEST_BASE + 32'h0c;
  localparam logic [31:0] OUTPUT_CLEAR_ADDR  = TEST_BASE + 32'h10;
  localparam logic [31:0] OUTPUT_TOGGLE_ADDR = TEST_BASE + 32'h14;
  localparam int unsigned TEST_WIDTH         = 16;
  localparam logic [31:0] TEST_OUTPUT_RESET  = 32'h0000_1234;
  localparam logic [31:0] TEST_OE_RESET      = 32'h0000_00f0;

  logic clk;
  logic rst;
  logic [TEST_WIDTH-1:0] gpio_in;
  logic [TEST_WIDTH-1:0] gpio_out;
  logic [TEST_WIDTH-1:0] gpio_oe;
  int checks;

  rv32_mem_if gpio();

  rv32_gpio #(
    .BASE_ADDR                 (TEST_BASE),
    .GPIO_WIDTH                (TEST_WIDTH),
    .OUTPUT_RESET_VALUE        (TEST_OUTPUT_RESET),
    .OUTPUT_ENABLE_RESET_VALUE (TEST_OE_RESET)
  ) dut (
    .clk_i      (clk),
    .rst_i      (rst),
    .gpio_s     (gpio),
    .gpio_in_i  (gpio_in),
    .gpio_out_o (gpio_out),
    .gpio_oe_o  (gpio_oe)
  );

  always #5 clk = ~clk;

  task automatic drive_idle;
    begin
      gpio.req_valid = 1'b0;
      gpio.req_addr  = 32'b0;
      gpio.req_write = 1'b0;
      gpio.req_wdata = 32'b0;
      gpio.req_wstrb = 4'b0000;
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

  task automatic gpio_access(
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
      gpio.req_valid = 1'b1;
      gpio.req_addr  = addr;
      gpio.req_write = write;
      gpio.req_wdata = wdata;
      gpio.req_wstrb = wstrb;
      #1;

      check_bit(gpio.req_ready, 1'b1, {test_name, " request ready"});

      @(posedge clk);
      #1;
      check_bit(gpio.rsp_valid, 1'b1, {test_name, " response valid"});
      check_bit(gpio.rsp_err, expected_err, {test_name, " response error"});

      if (check_rdata) begin
        check_word(gpio.rsp_rdata, expected_rdata, {test_name, " response data"});
      end

      drive_idle();
    end
  endtask

  task automatic read_word(
    input logic [31:0] addr,
    input logic [31:0] expected,
    input string       test_name
  );
    begin
      gpio_access(
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

  task automatic write_register(
    input logic [31:0] addr,
    input logic [31:0] value,
    input logic [3:0]  strobes,
    input string       test_name
  );
    begin
      gpio_access(
        1'b1,
        addr,
        value,
        strobes,
        1'b0,
        1'b0,
        32'b0,
        test_name
      );
    end
  endtask

  initial begin
    clk     = 1'b0;
    rst     = 1'b1;
    gpio_in = '0;
    checks  = 0;
    drive_idle();

    #1;
    check_bit(gpio.req_ready, 1'b0, "reset backpressure");
    check_word({16'b0, gpio_out}, TEST_OUTPUT_RESET, "reset output immediate");
    check_word({16'b0, gpio_oe}, TEST_OE_RESET, "reset output-enable immediate");

    repeat (2) @(posedge clk);
    #1;
    check_bit(gpio.rsp_valid, 1'b0, "reset response clear");
    check_word({16'b0, dut.output_q}, TEST_OUTPUT_RESET, "reset output latch");
    check_word({16'b0, dut.output_enable_q}, TEST_OE_RESET, "reset OE latch");

    rst = 1'b0;
    #1;
    check_bit(gpio.req_ready, 1'b1, "ready after reset");
    read_word(OUTPUT_ADDR, TEST_OUTPUT_RESET, "OUTPUT reset read");
    read_word(OUTPUT_ENABLE_ADDR, TEST_OE_RESET, "OUTPUT_ENABLE reset read");

    // External inputs are visible only after both synchronizer stages. Upper
    // read-data bits remain zero for a GPIO bank narrower than XLEN.
    gpio_in = 16'ha55a;
    repeat (2) @(posedge clk);
    #1;
    check_word({16'b0, dut.input_sync_q}, 32'h0000_a55a, "input synchronizer");
    read_word(INPUT_ADDR, 32'h0000_a55a, "INPUT synchronized read");

    // OUTPUT supports normal byte-enable semantics for SW, SH, and SB stores.
    write_register(OUTPUT_ADDR, 32'h0000_beef, 4'b1111, "OUTPUT word write");
    check_word({16'b0, gpio_out}, 32'h0000_beef, "OUTPUT word result");

    write_register(OUTPUT_ADDR, 32'h0000_00aa, 4'b0001, "OUTPUT low-byte write");
    check_word({16'b0, gpio_out}, 32'h0000_beaa, "OUTPUT low-byte isolation");

    write_register(OUTPUT_ADDR, 32'h0000_5500, 4'b0010, "OUTPUT high-byte write");
    check_word({16'b0, gpio_out}, 32'h0000_55aa, "OUTPUT high-byte isolation");

    write_register(OUTPUT_ADDR, 32'h00ff_0000, 4'b0100, "OUTPUT upper-lane write");
    check_word({16'b0, gpio_out}, 32'h0000_55aa, "narrow GPIO upper lane ignored");

    // OUTPUT_ENABLE has the same byte-mask behavior and independently controls
    // whether each output latch drives its external pin.
    write_register(
      OUTPUT_ENABLE_ADDR,
      32'h0000_f00f,
      4'b0011,
      "OUTPUT_ENABLE halfword write"
    );
    check_word({16'b0, gpio_oe}, 32'h0000_f00f, "OUTPUT_ENABLE result");
    write_register(
      OUTPUT_ENABLE_ADDR,
      32'h0000_00a5,
      4'b0001,
      "OUTPUT_ENABLE low-byte write"
    );
    check_word({16'b0, gpio_oe}, 32'h0000_f0a5, "OUTPUT_ENABLE byte isolation");

    // Atomic aliases modify OUTPUT without a read-modify-write sequence.
    write_register(OUTPUT_ADDR, 32'h0000_1200, 4'b0011, "atomic test seed");
    write_register(OUTPUT_SET_ADDR, 32'h0000_0005, 4'b0001, "OUTPUT_SET");
    check_word({16'b0, gpio_out}, 32'h0000_1205, "OUTPUT_SET result");

    write_register(OUTPUT_CLEAR_ADDR, 32'h0000_0201, 4'b0011, "OUTPUT_CLEAR");
    check_word({16'b0, gpio_out}, 32'h0000_1004, "OUTPUT_CLEAR result");

    write_register(OUTPUT_TOGGLE_ADDR, 32'h0000_00ff, 4'b0001, "OUTPUT_TOGGLE");
    check_word({16'b0, gpio_out}, 32'h0000_10fb, "OUTPUT_TOGGLE result");
    read_word(OUTPUT_ADDR, 32'h0000_10fb, "atomic aliases update OUTPUT readback");

    // Unsupported directions and malformed transfer shapes fault without
    // changing either architectural GPIO output register.
    gpio_access(
      1'b1, INPUT_ADDR, 32'hffff, 4'b0011, 1'b1, 1'b0, 32'b0,
      "INPUT write rejected"
    );
    gpio_access(
      1'b0, OUTPUT_SET_ADDR, 32'b0, 4'b0000, 1'b1, 1'b0, 32'b0,
      "OUTPUT_SET read rejected"
    );
    gpio_access(
      1'b1, OUTPUT_ADDR, 32'hffff, 4'b0000, 1'b1, 1'b0, 32'b0,
      "zero-strobe write rejected"
    );
    gpio_access(
      1'b0, OUTPUT_ADDR, 32'b0, 4'b0001, 1'b1, 1'b0, 32'b0,
      "read with write strobe rejected"
    );
    gpio_access(
      1'b0, TEST_BASE + 32'h18, 32'b0, 4'b0000, 1'b1, 1'b0, 32'b0,
      "unimplemented register rejected"
    );
    gpio_access(
      1'b0, OUTPUT_ADDR + 32'd2, 32'b0, 4'b0000, 1'b1, 1'b0, 32'b0,
      "misaligned register rejected"
    );
    check_word({16'b0, gpio_out}, 32'h0000_10fb, "invalid access no output effect");
    check_word({16'b0, gpio_oe}, 32'h0000_f0a5, "invalid access no OE effect");

    // Response acknowledgements are pulses, and a later reset restores all
    // visible state regardless of previous byte/atomic writes.
    @(posedge clk);
    #1;
    check_bit(gpio.rsp_valid, 1'b0, "response pulse retires");

    @(negedge clk);
    rst = 1'b1;
    #1;
    check_word({16'b0, gpio_out}, TEST_OUTPUT_RESET, "reasserted reset output");
    check_word({16'b0, gpio_oe}, TEST_OE_RESET, "reasserted reset OE");
    @(posedge clk);
    #1;
    check_word({16'b0, dut.input_sync_q}, 32'b0, "reset synchronizer clear");

    $display("tb_rv32_gpio: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
