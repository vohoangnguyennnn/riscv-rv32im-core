// RV32 integer register file: two asynchronous read ports and one
// rising-edge synchronous write port. Architectural register x0 is hardwired
// to zero; the remaining registers intentionally have no reset requirement.
// Same-cycle WB-to-ID bypass belongs to the pipeline integration, not here.
module regfile (
  input  logic        clk_i,
  input  logic        we_i,
  input  logic [4:0]  waddr_i,
  input  logic [31:0] wdata_i,
  input  logic [4:0]  raddr1_i,
  input  logic [4:0]  raddr2_i,
  output logic [31:0] rdata1_o,
  output logic [31:0] rdata2_o
);

  // x0 needs no storage because reads are forced to zero and writes ignored.
  logic [31:0] regs [1:31];

  always_ff @(posedge clk_i) begin
    if (we_i && (waddr_i != 5'd0)) begin
      regs[waddr_i] <= wdata_i;
    end
  end

  always_comb begin
    rdata1_o = 32'b0;
    rdata2_o = 32'b0;

    if (raddr1_i != 5'd0) begin
      rdata1_o = regs[raddr1_i];
    end

    if (raddr2_i != 5'd0) begin
      rdata2_o = regs[raddr2_i];
    end
  end

endmodule
