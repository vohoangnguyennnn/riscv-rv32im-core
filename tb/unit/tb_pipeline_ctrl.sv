// SPDX-License-Identifier: MIT

module tb_pipeline_ctrl;

  timeunit 1ns;
  timeprecision 1ps;

  import rv32_pkg::*;

  typedef struct packed {
    logic        pc_enable;
    logic        if_id_enable;
    logic        id_ex_enable;
    logic        ex_mem_enable;
    logic        mem_wb_enable;
    logic        if_id_flush;
    logic        id_ex_flush;
    logic        ex_mem_flush;
    logic        mem_wb_flush;
    logic        redirect_valid;
    logic [31:0] redirect_pc;
    logic        trap_drain;
  } ctrl_outputs_t;

  logic      clk;
  logic      rst;
  logic      load_use;
  logic      csr_dep;
  logic      ex_wait;
  logic      mem_wait;
  logic      id_exception;
  logic      ex_exception;
  logic      mem_exception;
  logic      wb_trap;
  redirect_t control_redirect;
  logic [31:0] mtvec;

  logic        pc_enable;
  logic        if_id_enable;
  logic        id_ex_enable;
  logic        ex_mem_enable;
  logic        mem_wb_enable;
  logic        if_id_flush;
  logic        id_ex_flush;
  logic        ex_mem_flush;
  logic        mem_wb_flush;
  logic        redirect_valid;
  logic [31:0] redirect_pc;
  logic        trap_drain;

  ctrl_outputs_t observed;
  int            checks;

  pipeline_ctrl dut (
    .clk_i                (clk),
    .rst_i                (rst),
    .load_use_i           (load_use),
    .csr_dep_i            (csr_dep),
    .ex_wait_i            (ex_wait),
    .mem_wait_i           (mem_wait),
    .id_exception_i       (id_exception),
    .ex_exception_i       (ex_exception),
    .mem_exception_i      (mem_exception),
    .wb_trap_i            (wb_trap),
    .control_redirect_i   (control_redirect),
    .mtvec_i              (mtvec),
    .pc_enable_o          (pc_enable),
    .if_id_enable_o       (if_id_enable),
    .id_ex_enable_o       (id_ex_enable),
    .ex_mem_enable_o      (ex_mem_enable),
    .mem_wb_enable_o      (mem_wb_enable),
    .if_id_flush_o        (if_id_flush),
    .id_ex_flush_o        (id_ex_flush),
    .ex_mem_flush_o       (ex_mem_flush),
    .mem_wb_flush_o       (mem_wb_flush),
    .redirect_valid_o     (redirect_valid),
    .redirect_pc_o        (redirect_pc),
    .trap_drain_o         (trap_drain)
  );

  always #5 clk = ~clk;

  always_comb begin
    observed.pc_enable      = pc_enable;
    observed.if_id_enable   = if_id_enable;
    observed.id_ex_enable   = id_ex_enable;
    observed.ex_mem_enable  = ex_mem_enable;
    observed.mem_wb_enable  = mem_wb_enable;
    observed.if_id_flush    = if_id_flush;
    observed.id_ex_flush    = id_ex_flush;
    observed.ex_mem_flush   = ex_mem_flush;
    observed.mem_wb_flush   = mem_wb_flush;
    observed.redirect_valid = redirect_valid;
    observed.redirect_pc    = redirect_pc;
    observed.trap_drain     = trap_drain;
  end

  function automatic ctrl_outputs_t normal_outputs;
    ctrl_outputs_t value;
    begin
      value                  = '0;
      value.pc_enable        = 1'b1;
      value.if_id_enable     = 1'b1;
      value.id_ex_enable     = 1'b1;
      value.ex_mem_enable    = 1'b1;
      value.mem_wb_enable    = 1'b1;
      normal_outputs         = value;
    end
  endfunction

  task automatic clear_events;
    begin
      rst              = 1'b0;
      load_use         = 1'b0;
      csr_dep           = 1'b0;
      ex_wait           = 1'b0;
      mem_wait          = 1'b0;
      id_exception      = 1'b0;
      ex_exception      = 1'b0;
      mem_exception     = 1'b0;
      wb_trap           = 1'b0;
      control_redirect  = '0;
      mtvec             = 32'h0000_0100;
    end
  endtask

  task automatic check(
    input ctrl_outputs_t expected,
    input string         test_name
  );
    begin
      #1ps;
      if (observed !== expected) begin
        $fatal(
          1,
          "%s mismatch:\n  expected=%h\n  result  =%h",
          test_name,
          expected,
          observed
        );
      end
      checks++;
    end
  endtask

  task automatic tick;
    begin
      @(posedge clk);
      #1ps;
    end
  endtask

  initial begin
    ctrl_outputs_t expected;

    clk    = 1'b0;
    checks = 0;
    clear_events();

    // Reset is synchronous internally but the control outputs are immediately
    // benign: all pipeline entries are flushed and no redirect is generated.
    rst                     = 1'b1;
    wb_trap                 = 1'b1;
    mem_exception           = 1'b1;
    tick();
    expected                = '0;
    expected.if_id_flush    = 1'b1;
    expected.id_ex_flush    = 1'b1;
    expected.ex_mem_flush   = 1'b1;
    expected.mem_wb_flush   = 1'b1;
    check(expected, "reset priority");

    clear_events();
    expected = normal_outputs();
    check(expected, "normal advance");

    // A disabled redirect ignores target/origin payload completely.
    control_redirect.target = 32'hdead_beef;
    control_redirect.origin = REDIRECT_FROM_EX;
    check(expected, "invalid redirect payload ignored");

    // Load-use and CSR dependencies share the same hold + ID/EX bubble action.
    clear_events();
    load_use               = 1'b1;
    expected               = normal_outputs();
    expected.pc_enable     = 1'b0;
    expected.if_id_enable  = 1'b0;
    expected.id_ex_flush   = 1'b1;
    check(expected, "load-use hazard");

    clear_events();
    csr_dep = 1'b1;
    check(expected, "CSR dependency");

    load_use = 1'b1;
    check(expected, "simultaneous ID hazards");

    // EX wait holds ID/EX and lets the older EX/MEM entry advance before
    // replacing it with a bubble.
    clear_events();
    ex_wait                = 1'b1;
    expected               = normal_outputs();
    expected.pc_enable     = 1'b0;
    expected.if_id_enable  = 1'b0;
    expected.id_ex_enable  = 1'b0;
    expected.ex_mem_flush  = 1'b1;
    check(expected, "EX wait");

    // EX wait is older than both an EX redirect event and any ID dependency.
    control_redirect.valid  = 1'b1;
    control_redirect.target = 32'h0000_2000;
    control_redirect.origin = REDIRECT_FROM_EX;
    load_use                = 1'b1;
    check(expected, "EX wait beats redirect and ID hazard");

    // MEM wait retains EX/MEM. MEM/WB is cleared after its previous instruction
    // commits so WB cannot repeat a side effect.
    clear_events();
    mem_wait                = 1'b1;
    expected                = normal_outputs();
    expected.pc_enable      = 1'b0;
    expected.if_id_enable   = 1'b0;
    expected.id_ex_enable   = 1'b0;
    expected.ex_mem_enable  = 1'b0;
    expected.mem_wb_flush   = 1'b1;
    check(expected, "MEM wait");

    // EX-origin redirect squashes both younger pipeline packets.
    clear_events();
    control_redirect.valid  = 1'b1;
    control_redirect.target = 32'h1234_5678;
    control_redirect.origin = REDIRECT_FROM_EX;
    expected                = normal_outputs();
    expected.if_id_flush    = 1'b1;
    expected.id_ex_flush    = 1'b1;
    expected.redirect_valid = 1'b1;
    expected.redirect_pc    = 32'h1234_5678;
    check(expected, "EX redirect");

    // The dormant Option-A contract keeps its ID control packet and squashes
    // only the younger IF/ID entry.
    control_redirect.origin = REDIRECT_FROM_ID;
    expected.id_ex_flush    = 1'b0;
    check(expected, "ID redirect flush mask");

    // An ID exception advances to ID/EX and starts precise draining.
    clear_events();
    id_exception           = 1'b1;
    expected               = normal_outputs();
    expected.pc_enable     = 1'b0;
    expected.if_id_flush   = 1'b1;
    check(expected, "ID exception action");
    tick();

    // trap_drain is registered. Once active, the front end remains held while
    // all older/offending packets continue toward WB.
    clear_events();
    expected                = normal_outputs();
    expected.pc_enable      = 1'b0;
    expected.if_id_enable   = 1'b0;
    expected.trap_drain     = 1'b1;
    check(expected, "trap drain active");

    // Younger redirects and ID hazards are ignored throughout the drain.
    control_redirect.valid  = 1'b1;
    control_redirect.target = 32'hffff_0000;
    control_redirect.origin = REDIRECT_FROM_EX;
    load_use                = 1'b1;
    id_exception            = 1'b1;
    check(expected, "drain suppresses younger events");

    // An older multi-cycle EX operation keeps its normal hold/bubble action
    // while precise drain remains latched.
    clear_events();
    ex_wait                 = 1'b1;
    expected                = normal_outputs();
    expected.pc_enable      = 1'b0;
    expected.if_id_enable   = 1'b0;
    expected.id_ex_enable   = 1'b0;
    expected.ex_mem_flush   = 1'b1;
    expected.trap_drain     = 1'b1;
    check(expected, "EX wait during drain");

    // An older MEM wait remains effective during the drain.
    clear_events();
    mem_wait                 = 1'b1;
    expected                 = normal_outputs();
    expected.pc_enable       = 1'b0;
    expected.if_id_enable    = 1'b0;
    expected.id_ex_enable    = 1'b0;
    expected.ex_mem_enable   = 1'b0;
    expected.mem_wb_flush    = 1'b1;
    expected.trap_drain      = 1'b1;
    check(expected, "MEM wait during drain");

    // WB trap terminates the drain, flushes all younger packets, and aligns
    // mtvec before redirecting.
    clear_events();
    wb_trap                  = 1'b1;
    mtvec                    = 32'h0000_0183;
    expected                 = normal_outputs();
    expected.if_id_flush     = 1'b1;
    expected.id_ex_flush     = 1'b1;
    expected.ex_mem_flush    = 1'b1;
    expected.mem_wb_flush    = 1'b1;
    expected.redirect_valid  = 1'b1;
    expected.redirect_pc     = 32'h0000_0180;
    expected.trap_drain      = 1'b1;
    check(expected, "WB trap commit");
    tick();

    clear_events();
    expected = normal_outputs();
    check(expected, "trap drain cleared");

    // EX exception advances the offending packet and squashes IF/ID + ID/EX.
    ex_exception           = 1'b1;
    expected               = normal_outputs();
    expected.pc_enable     = 1'b0;
    expected.if_id_flush   = 1'b1;
    expected.id_ex_flush   = 1'b1;
    check(expected, "EX exception action");

    // EX exception must beat a simultaneous MDU wait and redirect.
    ex_wait                 = 1'b1;
    control_redirect.valid  = 1'b1;
    control_redirect.target = 32'h0000_4000;
    control_redirect.origin = REDIRECT_FROM_EX;
    check(expected, "EX exception priority");

    // MEM wait is older than an EX exception.
    mem_wait                 = 1'b1;
    expected                 = normal_outputs();
    expected.pc_enable       = 1'b0;
    expected.if_id_enable    = 1'b0;
    expected.id_ex_enable    = 1'b0;
    expected.ex_mem_enable   = 1'b0;
    expected.mem_wb_flush    = 1'b1;
    check(expected, "MEM wait beats EX exception");

    // A newly detected MEM exception beats the wait and advances into MEM/WB.
    mem_exception            = 1'b1;
    expected                 = normal_outputs();
    expected.pc_enable       = 1'b0;
    expected.if_id_flush     = 1'b1;
    expected.id_ex_flush     = 1'b1;
    expected.ex_mem_flush    = 1'b1;
    check(expected, "MEM exception priority");

    // WB trap is globally oldest and wins every collision.
    wb_trap                  = 1'b1;
    mtvec                    = 32'h8000_0103;
    expected                 = normal_outputs();
    expected.if_id_flush     = 1'b1;
    expected.id_ex_flush     = 1'b1;
    expected.ex_mem_flush    = 1'b1;
    expected.mem_wb_flush    = 1'b1;
    expected.redirect_valid  = 1'b1;
    expected.redirect_pc     = 32'h8000_0100;
    check(expected, "WB trap global priority");

    // Redirect beats an ID exception/hazard, because the ID instruction is on
    // the wrong path and must be squashed instead of becoming a trap.
    clear_events();
    control_redirect.valid  = 1'b1;
    control_redirect.target = 32'h0000_9000;
    control_redirect.origin = REDIRECT_FROM_EX;
    id_exception            = 1'b1;
    load_use                = 1'b1;
    expected                = normal_outputs();
    expected.if_id_flush    = 1'b1;
    expected.id_ex_flush    = 1'b1;
    expected.redirect_valid = 1'b1;
    expected.redirect_pc    = 32'h0000_9000;
    check(expected, "redirect beats ID events");

    // ID exception is older than an ID dependency indication for the same
    // boundary and therefore advances into ID/EX rather than inserting a bubble.
    clear_events();
    id_exception          = 1'b1;
    csr_dep               = 1'b1;
    expected              = normal_outputs();
    expected.pc_enable    = 1'b0;
    expected.if_id_flush  = 1'b1;
    check(expected, "ID exception beats hazard");

    // Verify that both other exception origins set the registered drain state.
    clear_events();
    ex_exception = 1'b1;
    tick();
    clear_events();
    expected                = normal_outputs();
    expected.pc_enable      = 1'b0;
    expected.if_id_enable   = 1'b0;
    expected.trap_drain     = 1'b1;
    check(expected, "EX exception enters drain");

    wb_trap = 1'b1;
    tick();
    clear_events();
    mem_exception = 1'b1;
    tick();
    clear_events();
    check(expected, "MEM exception enters drain");

    // Final WB trap returns the state machine to normal operation.
    wb_trap = 1'b1;
    tick();
    clear_events();
    expected = normal_outputs();
    check(expected, "final drain clear");

    $display("PASS: %0d pipeline-controller checks", checks);
    $finish;
  end

endmodule
