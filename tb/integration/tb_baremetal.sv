// SPDX-License-Identifier: MIT

// Generic software harness for RV32IM/Zicsr ELF-derived memory images.
// Programs report completion by storing 1 (pass) or an odd failure status to
// the final TCM word. The harness retains a compact retirement history so a CI
// failure is actionable without first reproducing a waveform locally.
module tb_baremetal #(
  parameter int unsigned TCM_BYTES = 64 * 1024
);

  timeunit 1ns;
  timeprecision 1ps;

  localparam int unsigned WORDS         = TCM_BYTES / 4;
  localparam int unsigned HISTORY_DEPTH = 256;
  localparam logic [31:0] TOHOST_ADDR   = TCM_BYTES - 4;
  localparam logic [31:0] PASS_STATUS   = 32'h0000_0001;

  logic clk;
  logic rst;

  rv32_mem_if imem();
  rv32_mem_if dmem();

  logic        trace_valid;
  logic [31:0] trace_pc;
  logic [31:0] trace_insn;
  logic        trace_rd_we;
  logic [4:0]  trace_rd_addr;
  logic [31:0] trace_rd_data;
  logic [31:0] trace_mem_addr;
  logic [3:0]  trace_mem_wstrb;
  logic [31:0] trace_mem_wdata;
  logic        trace_trap;
  logic [4:0]  trace_cause;
  logic        trace_control;
  logic        trace_taken;
  logic [31:0] trace_target;

  string mem_file;
  string test_name;
  string trace_file;
  integer trace_fd;
  int unsigned max_cycles;
  int unsigned max_trace_events;
  int unsigned cycles;
  int unsigned trace_events;
  int unsigned trap_count;
  int unsigned history_write_index;

  logic [31:0] history_pc        [0:HISTORY_DEPTH-1];
  logic [31:0] history_insn      [0:HISTORY_DEPTH-1];
  logic        history_rd_we     [0:HISTORY_DEPTH-1];
  logic [4:0]  history_rd_addr   [0:HISTORY_DEPTH-1];
  logic [31:0] history_rd_data   [0:HISTORY_DEPTH-1];
  logic [31:0] history_mem_addr  [0:HISTORY_DEPTH-1];
  logic [3:0]  history_mem_wstrb [0:HISTORY_DEPTH-1];
  logic [31:0] history_mem_wdata [0:HISTORY_DEPTH-1];
  logic        history_trap      [0:HISTORY_DEPTH-1];
  logic [4:0]  history_cause     [0:HISTORY_DEPTH-1];

  rv32_core dut (
    .clk_i             (clk),
    .rst_i             (rst),
    .imem_m            (imem),
    .dmem_m            (dmem),
    .trace_valid_o     (trace_valid),
    .trace_pc_o        (trace_pc),
    .trace_insn_o      (trace_insn),
    .trace_rd_we_o     (trace_rd_we),
    .trace_rd_addr_o   (trace_rd_addr),
    .trace_rd_data_o   (trace_rd_data),
    .trace_mem_addr_o  (trace_mem_addr),
    .trace_mem_wstrb_o (trace_mem_wstrb),
    .trace_mem_wdata_o (trace_mem_wdata),
    .trace_trap_o      (trace_trap),
    .trace_cause_o     (trace_cause),
    .trace_control_o   (trace_control),
    .trace_taken_o     (trace_taken),
    .trace_target_o    (trace_target)
  );

  rv32_tcm #(
    .BYTES     (TCM_BYTES),
    .BASE_ADDR (32'h0000_0000)
  ) u_tcm (
    .clk_i  (clk),
    .imem_s (imem),
    .dmem_s (dmem)
  );

  always #5 clk = ~clk;

  task automatic dump_recent_trace;
    int unsigned entry_count;
    int unsigned first_entry;
    int unsigned slot;
    begin
      entry_count = (trace_events < HISTORY_DEPTH)
                  ? trace_events
                  : HISTORY_DEPTH;
      first_entry = (history_write_index + HISTORY_DEPTH - entry_count)
                  % HISTORY_DEPTH;

      $display("--- last %0d retirement events for %s ---", entry_count, test_name);
      for (int unsigned entry = 0; entry < entry_count; entry++) begin
        slot = (first_entry + entry) % HISTORY_DEPTH;
        $display(
          "pc=%08x insn=%08x rd=%0b/x%0d/%08x mem=%08x/%x/%08x trap=%0b cause=%0d",
          history_pc[slot],
          history_insn[slot],
          history_rd_we[slot],
          history_rd_addr[slot],
          history_rd_data[slot],
          history_mem_addr[slot],
          history_mem_wstrb[slot],
          history_mem_wdata[slot],
          history_trap[slot],
          history_cause[slot]
        );
      end
      $display("--- end retirement history ---");
    end
  endtask

  initial begin : initialize_harness
    clk                 = 1'b0;
    rst                 = 1'b1;
    trace_fd            = 0;
    test_name           = "baremetal";
    trace_file          = "";
    max_cycles          = 200_000;
    max_trace_events    = 100_000;
    cycles              = 0;
    trace_events        = 0;
    trap_count          = 0;
    history_write_index = 0;

    if (!$value$plusargs("mem=%s", mem_file)) begin
      $fatal(1, "missing required +mem=<word-oriented Verilog hex image>");
    end
    void'($value$plusargs("test=%s", test_name));
    void'($value$plusargs("max_cycles=%d", max_cycles));
    void'($value$plusargs("max_trace_events=%d", max_trace_events));

    for (int unsigned word_index = 0; word_index < WORDS; word_index++) begin
      u_tcm.mem[word_index] = 32'b0;
    end
    $readmemh(mem_file, u_tcm.mem);

    if ($value$plusargs("trace=%s", trace_file)) begin
      trace_fd = $fopen(trace_file, "w");
      if (trace_fd == 0) begin
        $fatal(1, "could not open retirement trace file '%s'", trace_file);
      end
      $fdisplay(
        trace_fd,
        "event,pc,insn,rd_we,rd_addr,rd_data,mem_addr,mem_wstrb,mem_wdata,trap,cause,control,taken,target"
      );
    end

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
  end

  always @(posedge clk) begin : monitor_software
    int unsigned slot;
    logic [31:0] failure_code;

    #1ps;
    if (!rst) begin
      cycles++;

      if (trace_valid) begin
        slot = history_write_index;
        history_pc[slot]        = trace_pc;
        history_insn[slot]      = trace_insn;
        history_rd_we[slot]     = trace_rd_we;
        history_rd_addr[slot]   = trace_rd_addr;
        history_rd_data[slot]   = trace_rd_data;
        history_mem_addr[slot]  = trace_mem_addr;
        history_mem_wstrb[slot] = trace_mem_wstrb;
        history_mem_wdata[slot] = trace_mem_wdata;
        history_trap[slot]      = trace_trap;
        history_cause[slot]     = trace_cause;
        history_write_index     = (history_write_index + 1) % HISTORY_DEPTH;
        trace_events++;
        if (trace_trap) trap_count++;

        if (trace_fd != 0) begin
          $fdisplay(
            trace_fd,
            "%0d,%08x,%08x,%0b,%0d,%08x,%08x,%x,%08x,%0b,%0d,%0b,%0b,%08x",
            trace_events,
            trace_pc,
            trace_insn,
            trace_rd_we,
            trace_rd_addr,
            trace_rd_data,
            trace_mem_addr,
            trace_mem_wstrb,
            trace_mem_wdata,
            trace_trap,
            trace_cause,
            trace_control,
            trace_taken,
            trace_target
          );
        end

        if ((trace_mem_wstrb != 4'b0000) && (trace_mem_addr == TOHOST_ADDR)) begin
          if (trace_mem_wstrb !== 4'b1111) begin
            dump_recent_trace();
            $fatal(1, "%s: tohost must be written as one aligned word", test_name);
          end

          if (trace_mem_wdata == PASS_STATUS) begin
            if (trace_fd != 0) $fclose(trace_fd);
            $display(
              "tb_baremetal: PASS %s (%0d cycles, %0d trace events, %0d traps)",
              test_name,
              cycles,
              trace_events,
              trap_count
            );
            $finish;
          end else begin
            failure_code = trace_mem_wdata >> 1;
            dump_recent_trace();
            if (trace_fd != 0) $fclose(trace_fd);
            $fatal(
              1,
              "%s: software reported failure status=%08x code=%08x",
              test_name,
              trace_mem_wdata,
              failure_code
            );
          end
        end
      end

      if ((cycles > max_cycles) || (trace_events > max_trace_events)) begin
        dump_recent_trace();
        if (trace_fd != 0) $fclose(trace_fd);
        $fatal(
          1,
          "%s: timeout cycles=%0d/%0d trace_events=%0d/%0d",
          test_name,
          cycles,
          max_cycles,
          trace_events,
          max_trace_events
        );
      end
    end
  end

endmodule
