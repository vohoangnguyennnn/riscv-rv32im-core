// Four-target data-memory demultiplexer for the RV32 SoC.
//
// One default memory target and three MMIO apertures are decoded:
//   TCM    fallback for every address not claimed by an MMIO aperture
//   timer  TIMER_BASE_ADDR / TIMER_ADDR_MASK
//   UART   UART_BASE_ADDR  / UART_ADDR_MASK
//   GPIO   GPIO_BASE_ADDR  / GPIO_ADDR_MASK
//
// Payload is broadcast, but req_valid selects exactly one target. The target
// is latched on handshake and owns the transaction until its response.
// The single outstanding slot can retire and accept a new, possibly different,
// target in one cycle, preserving zero-bubble service without a response FIFO.
module rv32_mem_demux #(
  parameter logic [31:0] TIMER_BASE_ADDR = 32'h0200_0000,
  parameter logic [31:0] TIMER_ADDR_MASK = 32'hffff_0000,
  parameter logic [31:0] UART_BASE_ADDR  = 32'h1000_0000,
  parameter logic [31:0] UART_ADDR_MASK  = 32'hffff_0000,
  parameter logic [31:0] GPIO_BASE_ADDR  = 32'h1001_0000,
  parameter logic [31:0] GPIO_ADDR_MASK  = 32'hffff_0000
) (
  input logic clk_i,
  input logic rst_i,

  rv32_mem_if.slave  core_s,
  rv32_mem_if.master tcm_m,
  rv32_mem_if.master timer_m,
  rv32_mem_if.master uart_m,
  rv32_mem_if.master gpio_m
);

  typedef enum logic [1:0] {
    TARGET_TCM,
    TARGET_TIMER,
    TARGET_UART,
    TARGET_GPIO
  } target_e;

  target_e request_target;
  target_e pending_target_q;

  logic pending_q;
  logic pending_rsp_valid;
  logic [31:0] pending_rsp_rdata;
  logic pending_rsp_err;
  logic selected_req_ready;
  logic issue_allowed;
  logic request_fire;
  logic response_seen;

  function automatic logic address_matches(
    input logic [31:0] address,
    input logic [31:0] base,
    input logic [31:0] mask
  );
    address_matches = (((address ^ base) & mask) == 32'b0);
  endfunction

  // Reject overlapping masked regions at elaboration; decode priority would
  // otherwise make part of one device silently unreachable.
  function automatic logic regions_overlap(
    input logic [31:0] base_a,
    input logic [31:0] mask_a,
    input logic [31:0] base_b,
    input logic [31:0] mask_b
  );
    regions_overlap = (((base_a ^ base_b) & mask_a & mask_b) == 32'b0);
  endfunction

  initial begin
    if (regions_overlap(TIMER_BASE_ADDR, TIMER_ADDR_MASK, UART_BASE_ADDR, UART_ADDR_MASK)) begin
      $fatal(1, "rv32_mem_demux timer and UART apertures overlap");
    end
    if (regions_overlap(TIMER_BASE_ADDR, TIMER_ADDR_MASK, GPIO_BASE_ADDR, GPIO_ADDR_MASK)) begin
      $fatal(1, "rv32_mem_demux timer and GPIO apertures overlap");
    end
    if (regions_overlap(UART_BASE_ADDR, UART_ADDR_MASK, GPIO_BASE_ADDR, GPIO_ADDR_MASK)) begin
      $fatal(1, "rv32_mem_demux UART and GPIO apertures overlap");
    end
  end

  always_comb begin
    // TCM is the deterministic fallback and performs its own bounds check.
    request_target = TARGET_TCM;
    if (address_matches(core_s.req_addr, TIMER_BASE_ADDR, TIMER_ADDR_MASK)) begin
      request_target = TARGET_TIMER;
    end else if (address_matches(core_s.req_addr, UART_BASE_ADDR, UART_ADDR_MASK)) begin
      request_target = TARGET_UART;
    end else if (address_matches(core_s.req_addr, GPIO_BASE_ADDR, GPIO_ADDR_MASK)) begin
      request_target = TARGET_GPIO;
    end

    // Only req_valid enables side effects; inactive targets ignore the payload.
    tcm_m.req_valid = 1'b0;
    tcm_m.req_addr  = core_s.req_addr;
    tcm_m.req_write = core_s.req_write;
    tcm_m.req_wdata = core_s.req_wdata;
    tcm_m.req_wstrb = core_s.req_wstrb;

    timer_m.req_valid = 1'b0;
    timer_m.req_addr  = core_s.req_addr;
    timer_m.req_write = core_s.req_write;
    timer_m.req_wdata = core_s.req_wdata;
    timer_m.req_wstrb = core_s.req_wstrb;

    uart_m.req_valid = 1'b0;
    uart_m.req_addr  = core_s.req_addr;
    uart_m.req_write = core_s.req_write;
    uart_m.req_wdata = core_s.req_wdata;
    uart_m.req_wstrb = core_s.req_wstrb;

    gpio_m.req_valid = 1'b0;
    gpio_m.req_addr  = core_s.req_addr;
    gpio_m.req_write = core_s.req_write;
    gpio_m.req_wdata = core_s.req_wdata;
    gpio_m.req_wstrb = core_s.req_wstrb;

    unique case (request_target)
      TARGET_TIMER: selected_req_ready = timer_m.req_ready;
      TARGET_UART:  selected_req_ready = uart_m.req_ready;
      TARGET_GPIO:  selected_req_ready = gpio_m.req_ready;
      default:      selected_req_ready = tcm_m.req_ready;
    endcase

    // Only the pending slot's latched owner may respond to the core.
    pending_rsp_valid = 1'b0;
    pending_rsp_rdata = 32'b0;
    pending_rsp_err   = 1'b0;

    if (pending_q) begin
      unique case (pending_target_q)
        TARGET_TIMER: begin
          pending_rsp_valid = timer_m.rsp_valid;
          pending_rsp_rdata = timer_m.rsp_rdata;
          pending_rsp_err   = timer_m.rsp_err;
        end

        TARGET_UART: begin
          pending_rsp_valid = uart_m.rsp_valid;
          pending_rsp_rdata = uart_m.rsp_rdata;
          pending_rsp_err   = uart_m.rsp_err;
        end

        TARGET_GPIO: begin
          pending_rsp_valid = gpio_m.rsp_valid;
          pending_rsp_rdata = gpio_m.rsp_rdata;
          pending_rsp_err   = gpio_m.rsp_err;
        end

        default: begin
          pending_rsp_valid = tcm_m.rsp_valid;
          pending_rsp_rdata = tcm_m.rsp_rdata;
          pending_rsp_err   = tcm_m.rsp_err;
        end
      endcase
    end

    // Recycle the slot with the response. A backpressured new target is captured
    // only on a later real handshake.
    issue_allowed    = !rst_i && (!pending_q || pending_rsp_valid);
    core_s.req_ready = issue_allowed && selected_req_ready;

    if (issue_allowed && core_s.req_valid) begin
      unique case (request_target)
        TARGET_TIMER: timer_m.req_valid = 1'b1;
        TARGET_UART:  uart_m.req_valid  = 1'b1;
        TARGET_GPIO:  gpio_m.req_valid  = 1'b1;
        default:      tcm_m.req_valid   = 1'b1;
      endcase
    end

    // Hide responses during reset or with no outstanding transaction.
    core_s.rsp_valid = !rst_i && pending_q && pending_rsp_valid;
    core_s.rsp_rdata = core_s.rsp_valid ? pending_rsp_rdata : 32'b0;
    core_s.rsp_err   = core_s.rsp_valid ? pending_rsp_err   : 1'b0;
  end

  assign request_fire  = core_s.req_valid && core_s.req_ready;
  assign response_seen = core_s.rsp_valid;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      pending_q        <= 1'b0;
      pending_target_q <= TARGET_TCM;
    end else begin
      unique case ({request_fire, response_seen})
        2'b10: begin
          pending_q        <= 1'b1;
          pending_target_q <= request_target;
        end

        2'b01: begin
          pending_q <= 1'b0;
        end

        2'b11: begin
          // Transfer ownership atomically as the old response retires.
          pending_q        <= 1'b1;
          pending_target_q <= request_target;
        end

        default: ;
      endcase
    end
  end

endmodule
