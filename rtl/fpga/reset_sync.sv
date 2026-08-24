
// Asynchronous reset-event synchronizer with synchronous functional reset.
// Only reset_pipe_q sees the external asynchronous input; the SoC reset has no
// asynchronous control and therefore cannot feed BRAM control pins that way.
// FPGA initialization holds reset until STAGES consecutive inactive samples.
module reset_sync #(
  parameter int unsigned STAGES = 2
) (
  input  logic clk_i,
  input  logic arst_ni,
  output logic rst_o
);

  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  logic [STAGES-1:0] reset_pipe_q;

  // This register has no asynchronous control; its synthesizable INIT value
  // guarantees reset immediately after FPGA configuration.
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

  // SoC reset asserts and deasserts only on rising edges, preventing an
  // asynchronous button event from reaching inferred RAM controls.
  always_ff @(posedge clk_i) begin
    functional_rst_q <= !reset_pipe_q[STAGES-1];
  end

  assign rst_o = functional_rst_q;

endmodule
