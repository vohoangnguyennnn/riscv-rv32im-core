// SPDX-License-Identifier: MIT

// Test-only unified memory with independent request and response delays on the
// data port. The instruction port remains fixed one-cycle so a directed test
// can isolate pipeline behavior caused by LSU backpressure.
module rv32_delayed_mem #(
  parameter int unsigned BYTES          = 2048,
  parameter int unsigned DMEM_REQ_DELAY = 2,
  parameter int unsigned DMEM_RSP_DELAY = 5
) (
  input logic clk_i,
  input logic rst_i,
  rv32_mem_if.slave imem_s,
  rv32_mem_if.slave dmem_s
);

  localparam int unsigned WORD_COUNT  = BYTES / 4;
  localparam int unsigned INDEX_WIDTH = (WORD_COUNT > 1) ? $clog2(WORD_COUNT) : 1;

  typedef enum logic [2:0] {
    DMEM_IDLE,
    DMEM_REQ_WAIT,
    DMEM_ACCEPT,
    DMEM_RSP_WAIT,
    DMEM_RSP_PULSE
  } dmem_state_e;

  logic [31:0] mem [0:WORD_COUNT-1];

  dmem_state_e dmem_state_q;
  int unsigned delay_count_q;
  logic [31:0] request_addr_q;
  logic        request_write_q;
  logic [31:0] request_wdata_q;
  logic [3:0]  request_wstrb_q;
  logic [31:0] response_data_q;
  logic        response_error_q;

  logic imem_in_range;
  logic dmem_in_range;
  logic [INDEX_WIDTH-1:0] imem_index;
  logic [INDEX_WIDTH-1:0] dmem_index;

  assign imem_in_range = (imem_s.req_addr < BYTES) && (imem_s.req_addr[1:0] == 2'b00);
  assign dmem_in_range = (request_addr_q < BYTES) && (request_addr_q[1:0] == 2'b00);
  assign imem_index    = imem_s.req_addr[INDEX_WIDTH+1:2];
  assign dmem_index    = request_addr_q[INDEX_WIDTH+1:2];

  assign imem_s.req_ready = 1'b1;
  assign dmem_s.req_ready = (dmem_state_q == DMEM_ACCEPT);

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      imem_s.rsp_valid <= 1'b0;
      imem_s.rsp_rdata <= 32'b0;
      imem_s.rsp_err   <= 1'b0;
    end else begin
      imem_s.rsp_valid <= imem_s.req_valid;
      imem_s.rsp_rdata <= 32'b0;
      imem_s.rsp_err   <= 1'b0;

      if (imem_s.req_valid) begin
        imem_s.rsp_err <= !imem_in_range || imem_s.req_write || (imem_s.req_wstrb != 4'b0000);
        if (imem_in_range && !imem_s.req_write && (imem_s.req_wstrb == 4'b0000)) begin
          imem_s.rsp_rdata <= mem[imem_index];
        end
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      dmem_state_q      <= DMEM_IDLE;
      delay_count_q     <= 0;
      request_addr_q    <= 32'b0;
      request_write_q   <= 1'b0;
      request_wdata_q   <= 32'b0;
      request_wstrb_q   <= 4'b0000;
      response_data_q   <= 32'b0;
      response_error_q  <= 1'b0;
      dmem_s.rsp_valid  <= 1'b0;
      dmem_s.rsp_rdata  <= 32'b0;
      dmem_s.rsp_err    <= 1'b0;
    end else begin
      dmem_s.rsp_valid <= 1'b0;

      unique case (dmem_state_q)
        DMEM_IDLE: begin
          if (dmem_s.req_valid) begin
            request_addr_q  <= dmem_s.req_addr;
            request_write_q <= dmem_s.req_write;
            request_wdata_q <= dmem_s.req_wdata;
            request_wstrb_q <= dmem_s.req_wstrb;
            delay_count_q   <= DMEM_REQ_DELAY;
            dmem_state_q    <= (DMEM_REQ_DELAY == 0) ? DMEM_ACCEPT : DMEM_REQ_WAIT;
          end
        end

        DMEM_REQ_WAIT: begin
          // The request protocol requires every payload field to remain stable
          // until req_valid && req_ready. Make violations immediately visible.
          if (
            !dmem_s.req_valid ||
            (dmem_s.req_addr  !== request_addr_q) ||
            (dmem_s.req_write !== request_write_q) ||
            (dmem_s.req_wdata !== request_wdata_q) ||
            (dmem_s.req_wstrb !== request_wstrb_q)
          ) begin
            $fatal(1, "data-memory request changed while req_ready was low");
          end

          if (delay_count_q <= 1) begin
            dmem_state_q <= DMEM_ACCEPT;
          end else begin
            delay_count_q <= delay_count_q - 1;
          end
        end

        DMEM_ACCEPT: begin
          if (
            !dmem_s.req_valid ||
            (dmem_s.req_addr  !== request_addr_q) ||
            (dmem_s.req_write !== request_write_q) ||
            (dmem_s.req_wdata !== request_wdata_q) ||
            (dmem_s.req_wstrb !== request_wstrb_q)
          ) begin
            $fatal(1, "data-memory request changed on its acceptance cycle");
          end

          response_data_q  <= 32'b0;
          response_error_q <= !dmem_in_range;

          if (dmem_in_range) begin
            response_data_q <= mem[dmem_index];

            if (request_write_q) begin
              if (request_wstrb_q[0]) mem[dmem_index][7:0]   <= request_wdata_q[7:0];
              if (request_wstrb_q[1]) mem[dmem_index][15:8]  <= request_wdata_q[15:8];
              if (request_wstrb_q[2]) mem[dmem_index][23:16] <= request_wdata_q[23:16];
              if (request_wstrb_q[3]) mem[dmem_index][31:24] <= request_wdata_q[31:24];
            end
          end

          delay_count_q <= DMEM_RSP_DELAY;
          dmem_state_q  <= (DMEM_RSP_DELAY == 0) ? DMEM_RSP_PULSE : DMEM_RSP_WAIT;
        end

        DMEM_RSP_WAIT: begin
          if (delay_count_q <= 1) begin
            dmem_s.rsp_valid <= 1'b1;
            dmem_s.rsp_rdata <= response_data_q;
            dmem_s.rsp_err   <= response_error_q;
            dmem_state_q     <= DMEM_RSP_PULSE;
          end else begin
            delay_count_q <= delay_count_q - 1;
          end
        end

        DMEM_RSP_PULSE: begin
          dmem_state_q <= DMEM_IDLE;
        end

        default: dmem_state_q <= DMEM_IDLE;
      endcase
    end
  end

endmodule
