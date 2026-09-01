
// Bindable assertions for one blocking rv32_mem_if channel. This module is
// compiled only into verification targets; production RTL remains free of
// assertion instances and simulator-only state.
module rv32_mem_protocol_sva #(
  parameter int unsigned PORT_ID = 0
) (
  input logic        clk_i,
  input logic        rst_i,
  input logic        req_valid_i,
  input logic        req_ready_i,
  input logic [31:0] req_addr_i,
  input logic        req_write_i,
  input logic [31:0] req_wdata_i,
  input logic [3:0]  req_wstrb_i,
  input logic        rsp_valid_i
);

  logic outstanding_q;
  logic request_fire;

  assign request_fire = req_valid_i && req_ready_i;

  // Preserve an accepted transaction across a synchronous core reset: the
  // external memory port has no cancellation signal, so its stale response
  // must still be accounted for and drained after reset.
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      if (rsp_valid_i) begin
        outstanding_q <= 1'b0;
      end
    end else begin
      unique case ({request_fire, rsp_valid_i})
        2'b10: outstanding_q <= 1'b1;
        2'b01: outstanding_q <= 1'b0;
        // With both asserted, either a new request completed immediately or
        // an old response was recycled into a new outstanding request.
        2'b11: outstanding_q <= outstanding_q;
        default: ;
      endcase
    end
  end

  property p_request_stable_until_ready;
    @(posedge clk_i)
    disable iff (rst_i)
    req_valid_i && !req_ready_i
      |=> req_valid_i && $stable({
        req_addr_i,
        req_write_i,
        req_wdata_i,
        req_wstrb_i
      });
  endproperty

  property p_no_response_without_request;
    @(posedge clk_i)
    disable iff (rst_i)
    rsp_valid_i |-> outstanding_q || request_fire;
  endproperty

  property p_at_most_one_outstanding;
    @(posedge clk_i)
    disable iff (rst_i)
    outstanding_q && !rsp_valid_i |-> !request_fire;
  endproperty

  property p_request_is_word_aligned;
    @(posedge clk_i)
    disable iff (rst_i)
    req_valid_i |-> (req_addr_i[1:0] == 2'b00);
  endproperty

  property p_read_has_no_write_strobes;
    @(posedge clk_i)
    disable iff (rst_i)
    req_valid_i && !req_write_i |-> (req_wstrb_i == 4'b0000);
  endproperty

  property p_write_has_active_strobe;
    @(posedge clk_i)
    disable iff (rst_i)
    req_valid_i && req_write_i |-> (req_wstrb_i != 4'b0000);
  endproperty

  a_request_stable_until_ready: assert property (p_request_stable_until_ready)
    else $error("rv32_mem port %0d changed request under backpressure", PORT_ID);

  a_no_response_without_request: assert property (p_no_response_without_request)
    else $error("rv32_mem port %0d returned a response without a request", PORT_ID);

  a_at_most_one_outstanding: assert property (p_at_most_one_outstanding)
    else $error("rv32_mem port %0d accepted more than one outstanding request", PORT_ID);

  a_request_is_word_aligned: assert property (p_request_is_word_aligned)
    else $error("rv32_mem port %0d issued an unaligned physical request", PORT_ID);

  a_read_has_no_write_strobes: assert property (p_read_has_no_write_strobes)
    else $error("rv32_mem port %0d asserted byte strobes on a read", PORT_ID);

  a_write_has_active_strobe: assert property (p_write_has_active_strobe)
    else $error("rv32_mem port %0d issued a write with no active byte lane", PORT_ID);

  c_request_accepted: cover property (
    @(posedge clk_i) disable iff (rst_i) request_fire
  );

  c_request_backpressured: cover property (
    @(posedge clk_i) disable iff (rst_i) req_valid_i && !req_ready_i
  );

  c_response_observed: cover property (
    @(posedge clk_i) disable iff (rst_i) rsp_valid_i
  );

  c_response_and_reissue: cover property (
    @(posedge clk_i) disable iff (rst_i)
    outstanding_q && rsp_valid_i && request_fire
  );

endmodule
