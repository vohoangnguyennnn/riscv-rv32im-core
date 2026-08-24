// Single-hart machine timer for the RV32 SoC.
//
// Conventional CLINT-compatible map within the 64-KiB aperture:
//   BASE_ADDR + 0x4000 : mtimecmp[31:0]
//   BASE_ADDR + 0x4004 : mtimecmp[63:32]
//   BASE_ADDR + 0xbff8 : mtime[31:0]
//   BASE_ADDR + 0xbffc : mtime[63:32]
//
// Requests receive a registered response one cycle later. Aligned word accesses
// preserve RV32 split-write behavior by updating one 64-bit half at a time.
module rv32_mtimer #(
  parameter logic [31:0] BASE_ADDR            = 32'h0200_0000,
  parameter logic [63:0] MTIME_RESET_VALUE     = 64'b0,
  parameter logic [63:0] MTIMECMP_RESET_VALUE  = 64'hffff_ffff_ffff_ffff
) (
  input logic clk_i,
  input logic rst_i,

  rv32_mem_if.slave timer_s,

  output logic mtip_o
);

  localparam logic [31:0] MTIMECMP_LO_ADDR = BASE_ADDR + 32'h0000_4000;
  localparam logic [31:0] MTIMECMP_HI_ADDR = BASE_ADDR + 32'h0000_4004;
  localparam logic [31:0] MTIME_LO_ADDR    = BASE_ADDR + 32'h0000_bff8;
  localparam logic [31:0] MTIME_HI_ADDR    = BASE_ADDR + 32'h0000_bffc;

  logic [63:0] mtime_q;
  logic [63:0] mtime_d;
  logic [63:0] mtimecmp_q;
  logic [63:0] mtimecmp_d;

  logic        req_fire;
  logic        addr_implemented;
  logic        access_shape_valid;
  logic        access_valid;
  logic [31:0] read_data;

  // Reset backpressures requests so no accepted transfer is discarded.
  assign timer_s.req_ready = !rst_i;
  assign req_fire          = timer_s.req_valid && timer_s.req_ready;

  // MTIP is level-sensitive; maximum mtimecmp prevents a reset-time interrupt.
  assign mtip_o = (mtime_q >= mtimecmp_q);

  always_comb begin
    addr_implemented = 1'b1;
    read_data        = 32'b0;

    unique case (timer_s.req_addr)
      MTIMECMP_LO_ADDR: read_data = mtimecmp_q[31:0];
      MTIMECMP_HI_ADDR: read_data = mtimecmp_q[63:32];
      MTIME_LO_ADDR:    read_data = mtime_q[31:0];
      MTIME_HI_ADDR:    read_data = mtime_q[63:32];

      default: begin
        addr_implemented = 1'b0;
        read_data        = 32'b0;
      end
    endcase

    // Stores must update one RV32 word; narrower or inconsistent accesses fault.
    access_shape_valid = timer_s.req_write ? (timer_s.req_wstrb == 4'b1111) : (timer_s.req_wstrb == 4'b0000);
    access_valid = (timer_s.req_addr[1:0] == 2'b00) && addr_implemented && access_shape_valid;
  end

  always_comb begin
    // Without a software write, mtime advances modulo 2^64 each active clock.
    mtime_d    = mtime_q + 64'd1;
    mtimecmp_d = mtimecmp_q;

    if (req_fire && access_valid && timer_s.req_write) begin
      unique case (timer_s.req_addr)
        MTIMECMP_LO_ADDR: mtimecmp_d[31:0]  = timer_s.req_wdata;
        MTIMECMP_HI_ADDR: mtimecmp_d[63:32] = timer_s.req_wdata;

        MTIME_LO_ADDR: begin
          // A write suppresses the whole tick, keeping the untouched half stable.
          mtime_d       = mtime_q;
          mtime_d[31:0] = timer_s.req_wdata;
        end

        MTIME_HI_ADDR: begin
          mtime_d        = mtime_q;
          mtime_d[63:32] = timer_s.req_wdata;
        end

        default: ; // access_valid excludes this path.
      endcase
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      mtime_q          <= MTIME_RESET_VALUE;
      mtimecmp_q       <= MTIMECMP_RESET_VALUE;
      timer_s.rsp_valid <= 1'b0;
      timer_s.rsp_rdata <= 32'b0;
      timer_s.rsp_err   <= 1'b0;
    end else begin
      mtime_q    <= mtime_d;
      mtimecmp_q <= mtimecmp_d;

      timer_s.rsp_valid <= req_fire;
      timer_s.rsp_rdata <= 32'b0;
      timer_s.rsp_err   <= 1'b0;

      if (req_fire) begin
        timer_s.rsp_err <= !access_valid;

        if (access_valid && !timer_s.req_write) begin
          // Sample on request acceptance; the same-edge tick affects later reads.
          timer_s.rsp_rdata <= read_data;
        end
      end
    end
  end

endmodule
