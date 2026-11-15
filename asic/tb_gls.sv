// Gate-level simulation harness for asic_core_top.
// The same testbench is compiled twice: once against the RTL wrapper and once
// against the synthesized netlist + sky130 cell models. Both runs must report
// PASS with the identical cycle count; any difference means synthesis changed
// behaviour (or the RTL relied on something gates do not reproduce, e.g. X).
// Trace ports do not exist on the ASIC top, so completion is detected on the
// data bus: the program stores 1 (pass) or an odd code (fail) to the last TCM
// word, the same tohost convention as tb_baremetal.
module tb_gls;

  timeunit 1ns;
  timeprecision 1ps;

  localparam int unsigned TCM_BYTES   = 64 * 1024;
  localparam logic [31:0] TOHOST_ADDR = TCM_BYTES - 4;

  logic clk = 1'b0;
  logic rst = 1'b1;
  // Power-up: the POR circuit asserts por together with rst.
  logic por = 1'b1;
  always #5 clk = ~clk;

  rv32_mem_if imem ();
  rv32_mem_if dmem ();

  // imem is read-only: the ASIC top does not expose write/wdata/wstrb for it.
  assign imem.req_write = 1'b0;
  assign imem.req_wdata = 32'b0;
  assign imem.req_wstrb = 4'b0000;

  asic_core_top dut (
    .clk_i            (clk),
    .rst_i            (rst),
    .por_i            (por),
    .mtip_i           (1'b0),
    .imem_req_valid_o (imem.req_valid),
    .imem_req_ready_i (imem.req_ready),
    .imem_req_addr_o  (imem.req_addr),
    .imem_rsp_valid_i (imem.rsp_valid),
    .imem_rsp_rdata_i (imem.rsp_rdata),
    .imem_rsp_err_i   (imem.rsp_err),
    .dmem_req_valid_o (dmem.req_valid),
    .dmem_req_ready_i (dmem.req_ready),
    .dmem_req_addr_o  (dmem.req_addr),
    .dmem_req_write_o (dmem.req_write),
    .dmem_req_wdata_o (dmem.req_wdata),
    .dmem_req_wstrb_o (dmem.req_wstrb),
    .dmem_rsp_valid_i (dmem.rsp_valid),
    .dmem_rsp_rdata_i (dmem.rsp_rdata),
    .dmem_rsp_err_i   (dmem.rsp_err)
  );

  rv32_tcm #(.BYTES(TCM_BYTES), .BASE_ADDR(32'h0)) u_tcm (
    .clk_i  (clk),
    .imem_s (imem),
    .dmem_s (dmem)
  );

  string       mem_file;
  string       test_name = "gls";
  int unsigned max_cycles = 200_000;
  int unsigned cycles = 0;

  initial begin
    if (!$value$plusargs("mem=%s", mem_file)) $fatal(1, "missing +mem=<image>");
    void'($value$plusargs("test=%s", test_name));
    void'($value$plusargs("max_cycles=%d", max_cycles));
    for (int unsigned i = 0; i < TCM_BYTES / 4; i++) u_tcm.mem[i] = 32'b0;
    $readmemh(mem_file, u_tcm.mem);
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    por = 1'b0;
  end

  always @(posedge clk) begin
    if (!rst) begin
      cycles++;

      // 4-state check: an X/Z on a bus control pin means some flop was never
      // initialised or reset - exactly the class of bug only GLS can show.
      if ($isunknown({imem.req_valid, dmem.req_valid}))
        $fatal(1, "%s: X on bus valid at cycle %0d", test_name, cycles);
      if (imem.req_valid && $isunknown(imem.req_addr))
        $fatal(1, "%s: X on imem address at cycle %0d", test_name, cycles);
      if (dmem.req_valid && $isunknown({dmem.req_write, dmem.req_addr, dmem.req_wstrb}))
        $fatal(1, "%s: X on dmem request at cycle %0d", test_name, cycles);

      if (dmem.req_valid && dmem.req_ready && dmem.req_write && dmem.req_addr == TOHOST_ADDR) begin
        if (dmem.req_wdata === 32'h1) begin
          $display("tb_gls: PASS %s (%0d cycles)", test_name, cycles);
          $finish;
        end
        $fatal(1, "%s: software reported failure status=%08x", test_name, dmem.req_wdata);
      end

      if (cycles > max_cycles) $fatal(1, "%s: timeout after %0d cycles", test_name, cycles);
    end
  end

endmodule
