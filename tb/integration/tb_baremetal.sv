
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
  localparam int unsigned COREMARK_REPORT_WORD = 32'h0000_e000 / 4;
  localparam logic [31:0] COREMARK_REPORT_MAGIC = 32'h434d_524b;

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
  logic        trace_is_interrupt;
  logic        trace_control;
  logic        trace_taken;
  logic [31:0] trace_target;
  logic [63:0] perf_cycle;
  logic [63:0] perf_instret;
  logic [63:0] perf_load_use_stall;
  logic [63:0] perf_csr_stall;
  logic [63:0] perf_mdu_stall;
  logic [63:0] perf_mem_stall;
  logic [63:0] perf_redirect;
  logic [63:0] perf_squash;

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
  logic perf_report;
  logic coremark_mode;

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
    .mtip_i            (1'b0),
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
    .trace_is_interrupt_o (trace_is_interrupt),
    .trace_control_o   (trace_control),
    .trace_taken_o     (trace_taken),
    .trace_target_o    (trace_target),
    .perf_cycle_o          (perf_cycle),
    .perf_instret_o        (perf_instret),
    .perf_load_use_stall_o (perf_load_use_stall),
    .perf_csr_stall_o      (perf_csr_stall),
    .perf_mdu_stall_o      (perf_mdu_stall),
    .perf_mem_stall_o      (perf_mem_stall),
    .perf_redirect_o       (perf_redirect),
    .perf_squash_o         (perf_squash)
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

  task automatic check_and_print_coremark_report;
    logic [31:0] version;
    logic [31:0] run_type;
    logic [31:0] clock_hz;
    logic [31:0] iterations;
    logic [63:0] report_cycles;
    logic [63:0] report_instructions;
    logic [31:0] seedcrc;
    logic [31:0] crclist;
    logic [31:0] crcmatrix;
    logic [31:0] crcstate;
    logic [31:0] crcfinal;
    logic [31:0] valid;
    logic [31:0] errors;
    begin
      version             = u_tcm.mem[COREMARK_REPORT_WORD + 1];
      run_type            = u_tcm.mem[COREMARK_REPORT_WORD + 2];
      clock_hz            = u_tcm.mem[COREMARK_REPORT_WORD + 3];
      iterations          = u_tcm.mem[COREMARK_REPORT_WORD + 4];
      report_cycles       = {u_tcm.mem[COREMARK_REPORT_WORD + 6],
                             u_tcm.mem[COREMARK_REPORT_WORD + 5]};
      report_instructions = {u_tcm.mem[COREMARK_REPORT_WORD + 8],
                             u_tcm.mem[COREMARK_REPORT_WORD + 7]};
      seedcrc             = u_tcm.mem[COREMARK_REPORT_WORD + 9];
      crclist             = u_tcm.mem[COREMARK_REPORT_WORD + 10];
      crcmatrix           = u_tcm.mem[COREMARK_REPORT_WORD + 11];
      crcstate            = u_tcm.mem[COREMARK_REPORT_WORD + 12];
      crcfinal            = u_tcm.mem[COREMARK_REPORT_WORD + 13];
      valid               = u_tcm.mem[COREMARK_REPORT_WORD + 14];
      errors              = u_tcm.mem[COREMARK_REPORT_WORD + 15];

      $display(
        "COREMARK benchmark=%s run_type=%0d clock_hz=%0d iterations=%0d cycles=%0d instructions=%0d seedcrc=%04x crclist=%04x crcmatrix=%04x crcstate=%04x crcfinal=%04x valid=%0d errors=%0d",
        test_name,
        run_type,
        clock_hz,
        iterations,
        report_cycles,
        report_instructions,
        seedcrc,
        crclist,
        crcmatrix,
        crcstate,
        crcfinal,
        valid,
        errors
      );

      if (u_tcm.mem[COREMARK_REPORT_WORD] != COREMARK_REPORT_MAGIC)
        $fatal(1, "%s: missing CoreMark report magic", test_name);
      if ((version != 1) || (clock_hz != 75_000_000))
        $fatal(1, "%s: invalid CoreMark report version/clock", test_name);
      if ((iterations == 0) || (report_cycles < (64'(clock_hz) * 10))
          || (report_instructions == 0))
        $fatal(1, "%s: CoreMark timed region is not reportable", test_name);
      if ((valid != 1) || (errors != 0))
        $fatal(1, "%s: CoreMark validation failed", test_name);

      case (run_type)
        0: begin
          if ((seedcrc != 32'h0000_e9f5) || (crclist != 32'h0000_e714)
              || (crcmatrix != 32'h0000_1fd7) || (crcstate != 32'h0000_8e3a))
            $fatal(1, "%s: CoreMark performance CRC mismatch", test_name);
        end
        1: begin
          if ((seedcrc != 32'h0000_18f2) || (crclist != 32'h0000_e3c1)
              || (crcmatrix != 32'h0000_0747) || (crcstate != 32'h0000_8d84))
            $fatal(1, "%s: CoreMark validation CRC mismatch", test_name);
        end
        default: $fatal(1, "%s: unknown CoreMark run type %0d", test_name, run_type);
      endcase
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
    perf_report         = $test$plusargs("perf");
    coremark_mode       = $test$plusargs("coremark");

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
            if (coremark_mode) check_and_print_coremark_report();
            if (perf_report) begin
              if (perf_cycle != {32'b0, cycles}) begin
                $fatal(1, "%s: performance cycle counter mismatch rtl=%0d tb=%0d", test_name, perf_cycle, cycles);
              end
              // The completion store is the retirement event sampled at this
              // edge; nonblocking counter state becomes externally visible on
              // the following cycle, which the harness intentionally never
              // enters. Account for that final non-trapping retirement here.
              if ((perf_instret + 64'd1) != {32'b0, (trace_events - trap_count)}) begin
                $fatal(
                  1,
                  "%s: performance retire counter mismatch rtl=%0d trace=%0d",
                  test_name,
                  perf_instret + 64'd1,
                  trace_events - trap_count
                );
              end
              $display(
                "PERF benchmark=%s cycles=%0d instructions=%0d load_use=%0d csr=%0d mdu=%0d memory=%0d redirects=%0d squashed=%0d",
                test_name,
                perf_cycle,
                perf_instret + 64'd1,
                perf_load_use_stall,
                perf_csr_stall,
                perf_mdu_stall,
                perf_mem_stall,
                perf_redirect,
                perf_squash
              );
            end
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
