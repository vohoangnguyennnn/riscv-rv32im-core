// Unified tightly coupled memory backed by a true dual-port block RAM.
//
// Port A serves instruction reads. Port B serves data reads and byte writes.
// Both ports accept one request per cycle and return a registered response in
// the following cycle. The memory array is intentionally not reset so FPGA
// tools can infer BRAM.
module rv32_tcm #(
  parameter int unsigned   BYTES     = 64 * 1024,
  parameter logic [31:0]   BASE_ADDR = 32'h0000_0000,
  parameter string         INIT_FILE = ""
) (
  input logic clk_i,
  rv32_mem_if.slave imem_s,
  rv32_mem_if.slave dmem_s
);

  localparam int unsigned WORD_COUNT = BYTES / 4;
  localparam int unsigned INDEX_WIDTH = (WORD_COUNT > 1) ? $clog2(WORD_COUNT) : 1;
  localparam logic [32:0] BYTE_COUNT = 33'(BYTES);

  (* ram_style = "block" *)
  logic [31:0] mem [0:WORD_COUNT-1];

  // Vivado maps a constant readmemh file into BRAM INIT attributes. Leaving
  // INIT_FILE empty preserves the uninitialized-memory behavior expected by
  // ASIC flows and by testbenches that load the array explicitly.
  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
  end

  logic [32:0] imem_byte_offset;
  logic [32:0] dmem_byte_offset;
  logic [INDEX_WIDTH-1:0] imem_word_index;
  logic [INDEX_WIDTH-1:0] dmem_word_index;
  logic imem_in_range;
  logic dmem_in_range;
  logic imem_read_ok;

  assign imem_byte_offset = {1'b0, imem_s.req_addr} - {1'b0, BASE_ADDR};
  assign dmem_byte_offset = {1'b0, dmem_s.req_addr} - {1'b0, BASE_ADDR};

  assign imem_word_index = imem_byte_offset[INDEX_WIDTH+1:2];
  assign dmem_word_index = dmem_byte_offset[INDEX_WIDTH+1:2];

  // Request addresses are byte addresses, but every TCM transaction transfers
  // one aligned 32-bit word. LSU handles architectural misalignment earlier.
  assign imem_in_range = (imem_byte_offset < BYTE_COUNT) && (imem_s.req_addr[1:0] == 2'b00);
  assign dmem_in_range = (dmem_byte_offset < BYTE_COUNT) && (dmem_s.req_addr[1:0] == 2'b00);

  // The instruction port is deliberately read-only.
  assign imem_read_ok = imem_in_range && !imem_s.req_write && (imem_s.req_wstrb == 4'b0000);

  // Fixed-latency TCM can accept a new request while returning the previous
  // response. Core-side masters guarantee at most one request outstanding.
  assign imem_s.req_ready = 1'b1;
  assign dmem_s.req_ready = 1'b1;

  // Port A: synchronous instruction read.
  always_ff @(posedge clk_i) begin
    imem_s.rsp_valid <= imem_s.req_valid;
    imem_s.rsp_err   <= 1'b0;
    imem_s.rsp_rdata <= 32'b0;

    if (imem_s.req_valid) begin
      imem_s.rsp_err <= !imem_read_ok;

      if (imem_read_ok) begin
        imem_s.rsp_rdata <= mem[imem_word_index];
      end
    end
  end

  // Port B: synchronous data read/write with read-first behavior.
  always_ff @(posedge clk_i) begin
    dmem_s.rsp_valid <= dmem_s.req_valid;
    dmem_s.rsp_err   <= 1'b0;
    dmem_s.rsp_rdata <= 32'b0;

    if (dmem_s.req_valid) begin
      dmem_s.rsp_err <= !dmem_in_range;

      if (dmem_in_range) begin
        dmem_s.rsp_rdata <= mem[dmem_word_index];

        if (dmem_s.req_write) begin
          if (dmem_s.req_wstrb[0]) begin
            mem[dmem_word_index][7:0] <= dmem_s.req_wdata[7:0];
          end
          if (dmem_s.req_wstrb[1]) begin
            mem[dmem_word_index][15:8] <= dmem_s.req_wdata[15:8];
          end
          if (dmem_s.req_wstrb[2]) begin
            mem[dmem_word_index][23:16] <= dmem_s.req_wdata[23:16];
          end
          if (dmem_s.req_wstrb[3]) begin
            mem[dmem_word_index][31:24] <= dmem_s.req_wdata[31:24];
          end
        end
      end
    end
  end

endmodule
