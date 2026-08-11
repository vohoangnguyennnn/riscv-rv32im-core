// SPDX-License-Identifier: MIT

// Asynchronous reset-event synchronizer followed by a fully synchronous
// functional reset.
//
// Only reset_pipe_q sees the external asynchronous reset. The reset delivered
// to the SoC is registered without an asynchronous control, so it can never
// become an asynchronous control source for BRAM address/write logic. FPGA
// initialization holds the functional reset active until the synchronizer has
// observed STAGES consecutive inactive samples.
module reset_sync #(
  parameter int unsigned STAGES = 2
) (
  input  logic clk_i,
  input  logic arst_ni,
  output logic rst_o
);

  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  logic [STAGES-1:0] reset_pipe_q;

  // This register is deliberately free of asynchronous set/reset. Its INIT
  // value is synthesizable on the target FPGA and guarantees a reset state
  // immediately after configuration, before the first board-clock edge.
  logic functional_rst_q;

  initial begin
    reset_pipe_q    = '0;
    functional_rst_q = 1'b1;
  end

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      reset_pipe_q <= '0;
    end else begin
      reset_pipe_q <= {reset_pipe_q[STAGES-2:0], 1'b1};
    end
  end

  // Both assertion and deassertion of the reset seen by the SoC occur only on
  // a rising clock edge. In particular, an asynchronous button press cannot
  // fan out from an async-reset flip-flop into inferred RAM control pins.
  always_ff @(posedge clk_i) begin
    functional_rst_q <= !reset_pipe_q[STAGES-1];
  end

  assign rst_o = functional_rst_q;

endmodule
