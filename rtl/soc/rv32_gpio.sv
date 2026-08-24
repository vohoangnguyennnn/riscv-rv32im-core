// Memory-mapped general-purpose input/output peripheral for the RV32 SoC.
//
// Project-defined map at the default 0x1001_0000 aperture:
//   +0x00 INPUT          RO  synchronized input pins
//   +0x04 OUTPUT         RW  output data latch
//   +0x08 OUTPUT_ENABLE  RW  1 drives the corresponding output pin
//   +0x0c OUTPUT_SET     WO  atomically set selected OUTPUT bits
//   +0x10 OUTPUT_CLEAR   WO  atomically clear selected OUTPUT bits
//   +0x14 OUTPUT_TOGGLE  WO  atomically toggle selected OUTPUT bits
//
// OUTPUT and OUTPUT_ENABLE honor byte enables. SET/CLEAR/TOGGLE combine data
// with strobes to avoid software read-modify-write races. Responses are
// registered one cycle later; invalid accesses return rsp_err.
module rv32_gpio #(
  parameter logic [31:0] BASE_ADDR = 32'h1001_0000,
  parameter int unsigned GPIO_WIDTH = 32,
  parameter logic [31:0] OUTPUT_RESET_VALUE = 32'b0,
  parameter logic [31:0] OUTPUT_ENABLE_RESET_VALUE = 32'b0
) (
  input logic clk_i,
  input logic rst_i,

  rv32_mem_if.slave gpio_s,

  input  logic [GPIO_WIDTH-1:0] gpio_in_i,
  output logic [GPIO_WIDTH-1:0] gpio_out_o,
  output logic [GPIO_WIDTH-1:0] gpio_oe_o
);

  localparam logic [31:0] INPUT_ADDR         = BASE_ADDR + 32'h0000_0000;
  localparam logic [31:0] OUTPUT_ADDR        = BASE_ADDR + 32'h0000_0004;
  localparam logic [31:0] OUTPUT_ENABLE_ADDR = BASE_ADDR + 32'h0000_0008;
  localparam logic [31:0] OUTPUT_SET_ADDR    = BASE_ADDR + 32'h0000_000c;
  localparam logic [31:0] OUTPUT_CLEAR_ADDR  = BASE_ADDR + 32'h0000_0010;
  localparam logic [31:0] OUTPUT_TOGGLE_ADDR = BASE_ADDR + 32'h0000_0014;

  (* async_reg = "true" *) logic [GPIO_WIDTH-1:0] input_meta_q;
  (* async_reg = "true" *) logic [GPIO_WIDTH-1:0] input_sync_q;
  logic [GPIO_WIDTH-1:0] output_q;
  logic [GPIO_WIDTH-1:0] output_d;
  logic [GPIO_WIDTH-1:0] output_enable_q;
  logic [GPIO_WIDTH-1:0] output_enable_d;

  logic        req_fire;
  logic        read_access_shape;
  logic        write_access_shape;
  logic        addr_implemented;
  logic        access_valid;
  logic [31:0] read_data;
  logic [31:0] write_byte_mask;
  logic [31:0] write_masked_data;
  logic        register_write_accept;

  initial begin
    if ((GPIO_WIDTH == 0) || (GPIO_WIDTH > 32)) begin
      $fatal(1, "rv32_gpio GPIO_WIDTH must be in the range 1..32");
    end
  end

  // Keep external outputs benign before the first synchronous-reset edge.
  assign gpio_out_o = rst_i ? OUTPUT_RESET_VALUE[GPIO_WIDTH-1:0] : output_q;
  assign gpio_oe_o  = rst_i ? OUTPUT_ENABLE_RESET_VALUE[GPIO_WIDTH-1:0] : output_enable_q;

  assign read_access_shape = !gpio_s.req_write && (gpio_s.req_wstrb == 4'b0000);
  assign write_access_shape = gpio_s.req_write && (|gpio_s.req_wstrb);

  assign write_byte_mask = {
    {8{gpio_s.req_wstrb[3]}},
    {8{gpio_s.req_wstrb[2]}},
    {8{gpio_s.req_wstrb[1]}},
    {8{gpio_s.req_wstrb[0]}}
  };
  assign write_masked_data = gpio_s.req_wdata & write_byte_mask;

  always_comb begin
    addr_implemented = 1'b1;
    access_valid     = 1'b0;
    read_data        = 32'b0;

    unique case (gpio_s.req_addr)
      INPUT_ADDR: begin
        access_valid = read_access_shape;
        read_data[GPIO_WIDTH-1:0] = input_sync_q;
      end

      OUTPUT_ADDR: begin
        access_valid = read_access_shape || write_access_shape;
        read_data[GPIO_WIDTH-1:0] = output_q;
      end

      OUTPUT_ENABLE_ADDR: begin
        access_valid = read_access_shape || write_access_shape;
        read_data[GPIO_WIDTH-1:0] = output_enable_q;
      end

      OUTPUT_SET_ADDR,
      OUTPUT_CLEAR_ADDR,
      OUTPUT_TOGGLE_ADDR: begin
        access_valid = write_access_shape;
      end

      default: begin
        addr_implemented = 1'b0;
        access_valid     = 1'b0;
        read_data        = 32'b0;
      end
    endcase

    access_valid = access_valid && addr_implemented && (gpio_s.req_addr[1:0] == 2'b00);
  end

  // GPIO never blocks: invalid requests handshake and return an error rather
  // than deadlocking the LSU or demux.
  assign gpio_s.req_ready = !rst_i;
  assign req_fire = gpio_s.req_valid && gpio_s.req_ready;
  assign register_write_accept = req_fire && access_valid && gpio_s.req_write;

  always_comb begin
    output_d        = output_q;
    output_enable_d = output_enable_q;

    if (register_write_accept) begin
      unique case (gpio_s.req_addr)
        OUTPUT_ADDR: begin
          output_d = (output_q & ~write_byte_mask[GPIO_WIDTH-1:0]) | write_masked_data[GPIO_WIDTH-1:0];
        end

        OUTPUT_ENABLE_ADDR: begin
          output_enable_d = (output_enable_q & ~write_byte_mask[GPIO_WIDTH-1:0]) | write_masked_data[GPIO_WIDTH-1:0];
        end

        OUTPUT_SET_ADDR: begin
          output_d = output_q | write_masked_data[GPIO_WIDTH-1:0];
        end

        OUTPUT_CLEAR_ADDR: begin
          output_d = output_q & ~write_masked_data[GPIO_WIDTH-1:0];
        end

        OUTPUT_TOGGLE_ADDR: begin
          output_d = output_q ^ write_masked_data[GPIO_WIDTH-1:0];
        end

        default: ; // access_valid excludes INPUT and unsupported addresses.
      endcase
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      input_meta_q   <= '0;
      input_sync_q   <= '0;
      output_q       <= OUTPUT_RESET_VALUE[GPIO_WIDTH-1:0];
      output_enable_q <= OUTPUT_ENABLE_RESET_VALUE[GPIO_WIDTH-1:0];

      gpio_s.rsp_valid <= 1'b0;
      gpio_s.rsp_rdata <= 32'b0;
      gpio_s.rsp_err   <= 1'b0;
    end else begin
      input_meta_q    <= gpio_in_i;
      input_sync_q    <= input_meta_q;
      output_q        <= output_d;
      output_enable_q <= output_enable_d;

      gpio_s.rsp_valid <= req_fire;
      gpio_s.rsp_rdata <= 32'b0;
      gpio_s.rsp_err   <= 1'b0;

      if (req_fire) begin
        gpio_s.rsp_err <= !access_valid;

        if (access_valid && !gpio_s.req_write) begin
          gpio_s.rsp_rdata <= read_data;
        end
      end
    end
  end

endmodule
