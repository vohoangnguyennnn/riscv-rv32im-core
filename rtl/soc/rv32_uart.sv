// Compact memory-mapped 8-N-1 UART for the RV32 SoC.
//
// Project-defined register map at the default 0x1000_0000 aperture:
//   +0x00 TXDATA  RW  [31]=busy, [7:0]=transmit byte on write
//   +0x04 RXDATA  RO  [31]=empty, [7:0]=oldest received byte; read pops it
//   +0x08 STATUS  RW  [0]=tx_ready, [1]=tx_busy, [2]=rx_valid,
//                     [3]=rx_overrun, [4]=rx_frame_error; bits 3/4 are W1C
//   +0x0c BAUDDIV RO  rounded clocks per serial bit
//
// TXDATA/STATUS accept aligned stores starting at byte lane zero. TXDATA
// backpressures while busy; malformed or unsupported accesses return rsp_err.
//
// RX uses a two-flop synchronizer and samples at the middle of the start bit,
// then once per data/stop bit. Its one-byte holding register reports sticky
// overrun and framing errors.
module rv32_uart #(
  parameter logic [31:0] BASE_ADDR   = 32'h1000_0000,
  parameter int unsigned CLK_FREQ_HZ = 50_000_000,
  parameter int unsigned BAUD_RATE   = 115_200
) (
  input logic clk_i,
  input logic rst_i,

  rv32_mem_if.slave uart_s,

  input  logic uart_rx_i,
  output logic uart_tx_o
);

  localparam logic [31:0] TXDATA_ADDR  = BASE_ADDR + 32'h0000_0000;
  localparam logic [31:0] RXDATA_ADDR  = BASE_ADDR + 32'h0000_0004;
  localparam logic [31:0] STATUS_ADDR  = BASE_ADDR + 32'h0000_0008;
  localparam logic [31:0] BAUDDIV_ADDR = BASE_ADDR + 32'h0000_000c;

  localparam int unsigned CLKS_PER_BIT_CALC = (BAUD_RATE > 0) ? ((CLK_FREQ_HZ + (BAUD_RATE / 2)) / BAUD_RATE) : 0;
  localparam int unsigned CLKS_PER_BIT = (CLKS_PER_BIT_CALC > 0) ? CLKS_PER_BIT_CALC : 1;
  localparam int unsigned HALF_BIT_CLKS = (CLKS_PER_BIT >= 2) ? (CLKS_PER_BIT / 2) : 1;
  localparam int unsigned BAUD_COUNT_W = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;

  typedef enum logic [1:0] {
    RX_IDLE,
    RX_START,
    RX_DATA,
    RX_STOP
  } rx_state_e;

  logic [9:0] tx_shift_q;
  logic [9:0] tx_shift_d;
  logic [3:0] tx_bit_q;
  logic [3:0] tx_bit_d;
  logic [BAUD_COUNT_W-1:0] tx_count_q;
  logic [BAUD_COUNT_W-1:0] tx_count_d;
  logic tx_busy_q;
  logic tx_busy_d;

  (* async_reg = "true" *) logic rx_meta_q;
  (* async_reg = "true" *) logic rx_sync_q;
  rx_state_e rx_state_q;
  rx_state_e rx_state_d;
  logic [BAUD_COUNT_W-1:0] rx_count_q;
  logic [BAUD_COUNT_W-1:0] rx_count_d;
  logic [2:0] rx_bit_q;
  logic [2:0] rx_bit_d;
  logic [7:0] rx_shift_q;
  logic [7:0] rx_shift_d;
  logic [7:0] rx_data_q;
  logic [7:0] rx_data_d;
  logic rx_valid_q;
  logic rx_valid_d;
  logic rx_overrun_q;
  logic rx_overrun_d;
  logic rx_frame_error_q;
  logic rx_frame_error_d;

  logic        req_fire;
  logic        addr_implemented;
  logic        access_valid;
  logic        read_access_shape;
  logic        write_access_shape;
  logic        request_is_legal_tx_write;
  logic [31:0] read_data;
  logic        tx_write_accept;
  logic        rx_read_accept;
  logic        status_write_accept;
  logic        rx_pop;

  // Fewer than four clocks per bit cannot sample RX robustly near bit center;
  // reject that configuration at elaboration.
  initial begin
    if ((BAUD_RATE == 0) || (CLK_FREQ_HZ == 0) || (CLKS_PER_BIT_CALC < 4)) begin
      $fatal(1,"rv32_uart requires nonzero rates and at least four clocks per bit");
    end
  end

  // Keep TX at the idle level even before the first synchronous-reset edge.
  assign uart_tx_o = (!rst_i && tx_busy_q) ? tx_shift_q[0] : 1'b1;

  // Accept low-lane SB/SH/SW stores; reject shifted or sparse strobe patterns.
  assign read_access_shape  = !uart_s.req_write && (uart_s.req_wstrb == 4'b0000);
  assign write_access_shape = uart_s.req_write && ((uart_s.req_wstrb == 4'b0001) || (uart_s.req_wstrb == 4'b0011) || (uart_s.req_wstrb == 4'b1111));

  always_comb begin
    addr_implemented = 1'b1;
    access_valid     = 1'b0;
    read_data        = 32'b0;

    unique case (uart_s.req_addr)
      TXDATA_ADDR: begin
        access_valid = read_access_shape || write_access_shape;
        read_data[31] = tx_busy_q;
      end

      RXDATA_ADDR: begin
        access_valid = read_access_shape;
        read_data[31] = !rx_valid_q;
        read_data[7:0] = rx_data_q;
      end

      STATUS_ADDR: begin
        access_valid  = read_access_shape || write_access_shape;
        read_data[0]  = !tx_busy_q;
        read_data[1]  = tx_busy_q;
        read_data[2]  = rx_valid_q;
        read_data[3]  = rx_overrun_q;
        read_data[4]  = rx_frame_error_q;
      end

      BAUDDIV_ADDR: begin
        access_valid = read_access_shape;
        read_data    = 32'(CLKS_PER_BIT_CALC);
      end

      default: begin
        addr_implemented = 1'b0;
        access_valid     = 1'b0;
        read_data        = 32'b0;
      end
    endcase

    access_valid = access_valid && addr_implemented && (uart_s.req_addr[1:0] == 2'b00);
  end

  // Only legal TXDATA stores wait for capacity; invalid requests return an error.
  assign request_is_legal_tx_write = (uart_s.req_addr == TXDATA_ADDR) && write_access_shape && (uart_s.req_addr[1:0] == 2'b00);
  assign uart_s.req_ready = !rst_i && (!request_is_legal_tx_write || !tx_busy_q);
  assign req_fire = uart_s.req_valid && uart_s.req_ready;

  assign tx_write_accept = req_fire && access_valid && uart_s.req_write && (uart_s.req_addr == TXDATA_ADDR);
  assign rx_read_accept = req_fire && access_valid && !uart_s.req_write && (uart_s.req_addr == RXDATA_ADDR);
  assign status_write_accept = req_fire && access_valid && uart_s.req_write && (uart_s.req_addr == STATUS_ADDR);
  assign rx_pop = rx_read_accept && rx_valid_q;

  // Transmitter
  always_comb begin
    tx_shift_d = tx_shift_q;
    tx_bit_d   = tx_bit_q;
    tx_count_d = tx_count_q;
    tx_busy_d  = tx_busy_q;

    if (tx_write_accept) begin
      // Frame order is start, eight LSB-first data bits, then stop.
      tx_shift_d = {1'b1, uart_s.req_wdata[7:0], 1'b0};
      tx_bit_d   = 4'd0;
      tx_count_d = BAUD_COUNT_W'(CLKS_PER_BIT - 1);
      tx_busy_d  = 1'b1;
    end else if (tx_busy_q) begin
      if (tx_count_q == '0) begin
        tx_count_d = BAUD_COUNT_W'(CLKS_PER_BIT - 1);

        if (tx_bit_q == 4'd9) begin
          tx_busy_d  = 1'b0;
          tx_shift_d = 10'h3ff;
          tx_bit_d   = 4'd0;
        end else begin
          tx_shift_d = {1'b1, tx_shift_q[9:1]};
          tx_bit_d   = tx_bit_q + 4'd1;
        end
      end else begin
        tx_count_d = tx_count_q - 1'b1;
      end
    end
  end

  // Receiver
  always_comb begin
    rx_state_d       = rx_state_q;
    rx_count_d       = rx_count_q;
    rx_bit_d         = rx_bit_q;
    rx_shift_d       = rx_shift_q;
    rx_data_d        = rx_data_q;
    rx_valid_d       = rx_valid_q;
    rx_overrun_d     = rx_overrun_q;
    rx_frame_error_d = rx_frame_error_q;

    // A new receive error wins over a simultaneous software clear.
    if (status_write_accept) begin
      if (uart_s.req_wdata[3]) begin
        rx_overrun_d = 1'b0;
      end
      if (uart_s.req_wdata[4]) begin
        rx_frame_error_d = 1'b0;
      end
    end

    if (rx_pop) begin
      rx_valid_d = 1'b0;
    end

    unique case (rx_state_q)
      RX_IDLE: begin
        if (!rx_sync_q) begin
          rx_state_d = RX_START;
          rx_count_d = BAUD_COUNT_W'(HALF_BIT_CLKS - 1);
        end
      end

      RX_START: begin
        if (rx_count_q == '0) begin
          if (!rx_sync_q) begin
            rx_state_d = RX_DATA;
            rx_count_d = BAUD_COUNT_W'(CLKS_PER_BIT - 1);
            rx_bit_d   = 3'd0;
          end else begin
            // The line returned high before the center sample: false start.
            rx_state_d = RX_IDLE;
          end
        end else begin
          rx_count_d = rx_count_q - 1'b1;
        end
      end

      RX_DATA: begin
        if (rx_count_q == '0) begin
          rx_shift_d[rx_bit_q] = rx_sync_q;
          rx_count_d           = BAUD_COUNT_W'(CLKS_PER_BIT - 1);

          if (rx_bit_q == 3'd7) begin
            rx_state_d = RX_STOP;
          end else begin
            rx_bit_d = rx_bit_q + 3'd1;
          end
        end else begin
          rx_count_d = rx_count_q - 1'b1;
        end
      end

      RX_STOP: begin
        if (rx_count_q == '0) begin
          // A simultaneous pop frees the slot without a false overrun.
          if (!rx_valid_q || rx_pop) begin
            rx_data_d  = rx_shift_q;
            rx_valid_d = 1'b1;
          end else begin
            rx_overrun_d = 1'b1;
          end

          if (!rx_sync_q) begin
            rx_frame_error_d = 1'b1;
          end

          rx_state_d = RX_IDLE;
          rx_count_d = '0;
          rx_bit_d   = '0;
        end else begin
          rx_count_d = rx_count_q - 1'b1;
        end
      end

      default: begin
        rx_state_d = RX_IDLE;
        rx_count_d = '0;
        rx_bit_d   = '0;
      end
    endcase
  end

  // Every accepted transaction receives one response on the following cycle.
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      tx_shift_q      <= 10'h3ff;
      tx_bit_q        <= 4'd0;
      tx_count_q      <= '0;
      tx_busy_q       <= 1'b0;

      rx_meta_q        <= 1'b1;
      rx_sync_q        <= 1'b1;
      rx_state_q       <= RX_IDLE;
      rx_count_q       <= '0;
      rx_bit_q         <= '0;
      rx_shift_q       <= 8'b0;
      rx_data_q        <= 8'b0;
      rx_valid_q       <= 1'b0;
      rx_overrun_q     <= 1'b0;
      rx_frame_error_q <= 1'b0;

      uart_s.rsp_valid <= 1'b0;
      uart_s.rsp_rdata <= 32'b0;
      uart_s.rsp_err   <= 1'b0;
    end else begin
      tx_shift_q <= tx_shift_d;
      tx_bit_q   <= tx_bit_d;
      tx_count_q <= tx_count_d;
      tx_busy_q  <= tx_busy_d;

      rx_meta_q        <= uart_rx_i;
      rx_sync_q        <= rx_meta_q;
      rx_state_q       <= rx_state_d;
      rx_count_q       <= rx_count_d;
      rx_bit_q         <= rx_bit_d;
      rx_shift_q       <= rx_shift_d;
      rx_data_q        <= rx_data_d;
      rx_valid_q       <= rx_valid_d;
      rx_overrun_q     <= rx_overrun_d;
      rx_frame_error_q <= rx_frame_error_d;

      uart_s.rsp_valid <= req_fire;
      uart_s.rsp_rdata <= 32'b0;
      uart_s.rsp_err   <= 1'b0;

      if (req_fire) begin
        uart_s.rsp_err <= !access_valid;

        if (access_valid && !uart_s.req_write) begin
          uart_s.rsp_rdata <= read_data;
        end
      end
    end
  end

endmodule
