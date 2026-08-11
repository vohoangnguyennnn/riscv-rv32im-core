// SPDX-License-Identifier: MIT

module tb_ex_stage;

  import rv32_pkg::*;

  logic      clk;
  logic      rst;
  logic      kill;
  id_ex_t    id_ex;
  fwd_sel_e  fwd_a_sel;
  fwd_sel_e  fwd_b_sel;
  logic [31:0] ex_mem_fwd_value;
  logic [31:0] mem_wb_fwd_value;
  logic [31:0] csr_rdata;
  logic [31:0] csr_mepc;
  logic        csr_access_illegal;
  logic        result_ready;

  logic [11:0] csr_raddr;
  logic        csr_access_write;
  ex_mem_t     ex_mem;
  redirect_t   control_redirect;
  logic        result_valid;
  logic        wait_ex;
  int          checks;
  int          div_cycles;

  ex_stage dut (
    .clk_i                  (clk),
    .rst_i                  (rst),
    .kill_i                 (kill),
    .id_ex_i                (id_ex),
    .fwd_a_sel_i            (fwd_a_sel),
    .fwd_b_sel_i            (fwd_b_sel),
    .ex_mem_fwd_value_i     (ex_mem_fwd_value),
    .mem_wb_fwd_value_i     (mem_wb_fwd_value),
    .csr_rdata_i            (csr_rdata),
    .csr_mepc_i             (csr_mepc),
    .csr_access_illegal_i   (csr_access_illegal),
    .result_ready_i         (result_ready),
    .csr_raddr_o            (csr_raddr),
    .csr_access_write_o     (csr_access_write),
    .ex_mem_o               (ex_mem),
    .control_redirect_o     (control_redirect),
    .result_valid_o         (result_valid),
    .wait_o                 (wait_ex)
  );

  always #5 clk = ~clk;

  function automatic decode_ctrl_t safe_ctrl;
    decode_ctrl_t ctrl;
    begin
      ctrl          = '0;
      ctrl.op_a_sel = OP_A_ZERO;
      ctrl.op_b_sel = OP_B_IMM;
      ctrl.mem_size = MEM_WORD;
      safe_ctrl     = ctrl;
    end
  endfunction

  task automatic drive_bubble;
    begin
      id_ex               = '0;
      fwd_a_sel           = FWD_REGFILE;
      fwd_b_sel           = FWD_REGFILE;
      ex_mem_fwd_value    = 32'h1111_1111;
      mem_wb_fwd_value    = 32'h2222_2222;
      csr_rdata           = 32'h3333_3333;
      csr_mepc            = 32'h4444_4444;
      csr_access_illegal  = 1'b0;
      result_ready        = 1'b1;
      rst                 = 1'b0;
      kill                = 1'b0;
      #1;
    end
  endtask

  task automatic check_csr_access_write(
    input logic  expected,
    input string test_name
  );
    begin
      if (csr_access_write !== expected) begin
        $fatal(
          1,
          "%s CSR access kind mismatch: write=%0b/%0b",
          test_name,
          csr_access_write,
          expected
        );
      end
      checks++;
    end
  endtask

  task automatic check_outputs(
    input ex_mem_t   expected_ex_mem,
    input redirect_t expected_redirect,
    input logic      expected_valid,
    input logic      expected_wait,
    input logic [11:0] expected_csr_raddr,
    input string     test_name
  );
    begin
      if (ex_mem !== expected_ex_mem) begin
        $fatal(
          1,
          "%s EX/MEM mismatch:\n  expected=%h\n  result  =%h",
          test_name,
          expected_ex_mem,
          ex_mem
        );
      end

      if (control_redirect !== expected_redirect) begin
        $fatal(
          1,
          "%s redirect mismatch:\n  expected=%h\n  result  =%h",
          test_name,
          expected_redirect,
          control_redirect
        );
      end

      if (
        (result_valid !== expected_valid) ||
        (wait_ex !== expected_wait) ||
        (csr_raddr !== expected_csr_raddr)
      ) begin
        $fatal(
          1,
          "%s handshake/CSR mismatch: valid=%0b/%0b wait=%0b/%0b raddr=%03x/%03x",
          test_name,
          result_valid,
          expected_valid,
          wait_ex,
          expected_wait,
          csr_raddr,
          expected_csr_raddr
        );
      end

      checks++;
    end
  endtask

  initial begin
    decode_ctrl_t ctrl;
    ex_mem_t      expected_ex_mem;
    redirect_t    expected_redirect;

    clk    = 1'b0;
    checks = 0;
    drive_bubble();
    rst = 1'b1;
    repeat (2) @(posedge clk);
    #1;
    rst = 1'b0;
    #1;

    // Invalid input is a completely benign bubble.
    expected_ex_mem  = '0;
    expected_redirect = '0;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b0,
      1'b0,
      12'b0,
      "invalid bubble"
    );

    // Register-register ALU operation with no forwarding.
    ctrl               = safe_ctrl();
    ctrl.uses_rs1      = 1'b1;
    ctrl.uses_rs2      = 1'b1;
    ctrl.reg_write     = 1'b1;
    ctrl.alu_op        = ALU_ADD;
    ctrl.op_a_sel      = OP_A_RS1;
    ctrl.op_b_sel      = OP_B_RS2;

    id_ex              = '0;
    id_ex.valid        = 1'b1;
    id_ex.pc           = 32'h0000_1000;
    id_ex.insn         = 32'h0041_82b3;
    id_ex.rs1          = 5'd3;
    id_ex.rs2          = 5'd4;
    id_ex.rd           = 5'd5;
    id_ex.rs1_value    = 32'h1234_0000;
    id_ex.rs2_value    = 32'h0000_5678;
    id_ex.ctrl         = ctrl;
    #1;

    expected_ex_mem               = '0;
    expected_ex_mem.valid         = 1'b1;
    expected_ex_mem.pc            = id_ex.pc;
    expected_ex_mem.insn          = id_ex.insn;
    expected_ex_mem.rd            = 5'd5;
    expected_ex_mem.reg_write     = 1'b1;
    expected_ex_mem.ex_result     = 32'h1234_5678;
    expected_ex_mem.store_data    = 32'h0000_5678;
    expected_ex_mem.mem_size      = MEM_WORD;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "ADD from ID/EX"
    );

    // The two forwarding muxes are independent. The forwarded rs2 value also
    // remains the store-data candidate rather than the immediate ALU operand.
    fwd_a_sel        = FWD_EX_MEM;
    fwd_b_sel        = FWD_MEM_WB;
    ex_mem_fwd_value = 32'h0102_0304;
    mem_wb_fwd_value = 32'h1020_3040;
    #1;

    expected_ex_mem.ex_result  = 32'h1122_3344;
    expected_ex_mem.store_data = 32'h1020_3040;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "independent EX forwarding"
    );

    // LUI selects zero + U-immediate, while AUIPC selects PC + U-immediate.
    // These cases cover both non-register ALU-A mux choices.
    ctrl                  = safe_ctrl();
    ctrl.reg_write        = 1'b1;
    ctrl.alu_op           = ALU_ADD;
    ctrl.op_a_sel         = OP_A_ZERO;
    ctrl.op_b_sel         = OP_B_IMM;
    id_ex.pc              = 32'h0000_1800;
    id_ex.insn            = 32'h1234_52b7;
    id_ex.rd              = 5'd5;
    id_ex.rs1_value       = 32'hffff_ffff;
    id_ex.rs2_value       = 32'heeee_eeee;
    id_ex.imm             = 32'h1234_5000;
    id_ex.ctrl            = ctrl;
    fwd_a_sel             = FWD_EX_MEM;
    fwd_b_sel             = FWD_MEM_WB;
    #1;

    expected_ex_mem               = '0;
    expected_ex_mem.valid         = 1'b1;
    expected_ex_mem.pc            = id_ex.pc;
    expected_ex_mem.insn          = id_ex.insn;
    expected_ex_mem.rd            = 5'd5;
    expected_ex_mem.reg_write     = 1'b1;
    expected_ex_mem.ex_result     = 32'h1234_5000;
    expected_ex_mem.store_data    = mem_wb_fwd_value;
    expected_ex_mem.mem_size      = MEM_WORD;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "LUI zero plus immediate"
    );

    id_ex.insn                   = 32'h1234_5297;
    id_ex.ctrl.op_a_sel          = OP_A_PC;
    expected_ex_mem.insn        = id_ex.insn;
    expected_ex_mem.ex_result   = 32'h1234_6800;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "AUIPC PC plus immediate"
    );

    // Load effective address and all MEM/WB selection metadata pass through EX.
    ctrl                  = safe_ctrl();
    ctrl.uses_rs1         = 1'b1;
    ctrl.reg_write        = 1'b1;
    ctrl.alu_op           = ALU_ADD;
    ctrl.op_a_sel         = OP_A_RS1;
    ctrl.op_b_sel         = OP_B_IMM;
    ctrl.wb_sel           = WB_LOAD;
    ctrl.mem_cmd          = MEM_LOAD;
    ctrl.mem_size         = MEM_BYTE;
    ctrl.load_unsigned    = 1'b1;
    id_ex.pc              = 32'h0000_1804;
    id_ex.insn            = 32'h0071_c283;
    id_ex.rs1             = 5'd3;
    id_ex.rd              = 5'd5;
    id_ex.imm             = 32'h0000_0007;
    id_ex.ctrl            = ctrl;
    fwd_a_sel             = FWD_EX_MEM;
    ex_mem_fwd_value      = 32'h0000_2400;
    #1;

    expected_ex_mem               = '0;
    expected_ex_mem.valid         = 1'b1;
    expected_ex_mem.pc            = id_ex.pc;
    expected_ex_mem.insn          = id_ex.insn;
    expected_ex_mem.rd            = 5'd5;
    expected_ex_mem.reg_write     = 1'b1;
    expected_ex_mem.wb_sel        = WB_LOAD;
    expected_ex_mem.ex_result     = 32'h0000_2407;
    expected_ex_mem.store_data    = mem_wb_fwd_value;
    expected_ex_mem.mem_cmd       = MEM_LOAD;
    expected_ex_mem.mem_size      = MEM_BYTE;
    expected_ex_mem.load_unsigned = 1'b1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "unsigned-byte load metadata"
    );

    // Store effective address uses forwarded rs1 + immediate, while store data
    // uses forwarded rs2 and preserves memory metadata.
    ctrl                  = safe_ctrl();
    ctrl.uses_rs1         = 1'b1;
    ctrl.uses_rs2         = 1'b1;
    ctrl.alu_op           = ALU_ADD;
    ctrl.op_a_sel         = OP_A_RS1;
    ctrl.op_b_sel         = OP_B_IMM;
    ctrl.mem_cmd          = MEM_STORE;
    ctrl.mem_size         = MEM_HALF;

    id_ex.pc              = 32'h0000_1004;
    id_ex.insn            = 32'h0041_9123;
    id_ex.rs1             = 5'd3;
    id_ex.rs2             = 5'd4;
    id_ex.rd              = 5'd2;
    id_ex.rs1_value       = 32'hdead_beef;
    id_ex.rs2_value       = 32'hcafe_babe;
    id_ex.imm             = 32'h0000_0006;
    id_ex.ctrl            = ctrl;
    fwd_a_sel             = FWD_EX_MEM;
    fwd_b_sel             = FWD_MEM_WB;
    ex_mem_fwd_value      = 32'h0000_2000;
    mem_wb_fwd_value      = 32'haabb_ccdd;
    #1;

    expected_ex_mem               = '0;
    expected_ex_mem.valid         = 1'b1;
    expected_ex_mem.pc            = id_ex.pc;
    expected_ex_mem.insn          = id_ex.insn;
    expected_ex_mem.rd            = id_ex.rd;
    expected_ex_mem.ex_result     = 32'h0000_2006;
    expected_ex_mem.store_data    = 32'haabb_ccdd;
    expected_ex_mem.mem_cmd       = MEM_STORE;
    expected_ex_mem.mem_size      = MEM_HALF;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "store address and data forwarding"
    );

    // Backpressure keeps valid asserted and suppresses the one-shot redirect
    // event until the result is actually accepted.
    ctrl                  = safe_ctrl();
    ctrl.uses_rs1         = 1'b1;
    ctrl.uses_rs2         = 1'b1;
    ctrl.branch_kind      = BR_BEQ;
    id_ex.pc              = 32'h0000_3000;
    id_ex.insn            = 32'h0020_8463;
    id_ex.rs1_value       = 32'h0000_0055;
    id_ex.rs2_value       = 32'h0000_0055;
    id_ex.imm             = 32'h0000_0008;
    id_ex.ctrl            = ctrl;
    fwd_a_sel             = FWD_REGFILE;
    fwd_b_sel             = FWD_REGFILE;
    result_ready          = 1'b0;
    #1;

    expected_ex_mem               = '0;
    expected_ex_mem.valid         = 1'b1;
    expected_ex_mem.pc            = id_ex.pc;
    expected_ex_mem.insn          = id_ex.insn;
    expected_ex_mem.rd            = id_ex.rd;
    expected_ex_mem.store_data    = id_ex.rs2_value;
    expected_ex_mem.mem_size      = MEM_WORD;
    expected_ex_mem.control       = 1'b1;
    expected_ex_mem.control_taken = 1'b1;
    expected_ex_mem.control_target = 32'h0000_3008;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b1,
      12'b0,
      "taken branch under backpressure"
    );

    result_ready             = 1'b1;
    expected_redirect.valid  = 1'b1;
    expected_redirect.target = 32'h0000_3008;
    expected_redirect.origin = REDIRECT_FROM_EX;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "taken branch accepted"
    );

    // A not-taken branch records control metadata but does not redirect.
    id_ex.rs2_value = 32'h0000_0066;
    expected_ex_mem.store_data     = 32'h0000_0066;
    expected_ex_mem.control_taken  = 1'b0;
    expected_redirect              = '0;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "branch not taken"
    );

    // Alignment is checked only for a taken control transfer.  The arithmetic
    // target may be misaligned for a not-taken conditional branch without
    // raising an exception.
    id_ex.imm                            = 32'h0000_0002;
    expected_ex_mem.control_target       = 32'h0000_3002;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "not-taken branch ignores target alignment"
    );

    // JAL uses PC-relative targeting, retains its link-register write, and is
    // resolved at the same EX acceptance boundary as a conditional branch.
    ctrl                  = safe_ctrl();
    ctrl.reg_write        = 1'b1;
    ctrl.wb_sel           = WB_PC4;
    ctrl.branch_kind      = BR_JAL;
    id_ex                 = '0;
    id_ex.valid           = 1'b1;
    id_ex.pc              = 32'h0000_3800;
    id_ex.insn            = 32'h0200_02ef;
    id_ex.rd              = 5'd5;
    id_ex.imm             = 32'h0000_0020;
    id_ex.ctrl            = ctrl;
    #1;

    expected_ex_mem                = '0;
    expected_ex_mem.valid          = 1'b1;
    expected_ex_mem.pc             = id_ex.pc;
    expected_ex_mem.insn           = id_ex.insn;
    expected_ex_mem.rd             = 5'd5;
    expected_ex_mem.reg_write      = 1'b1;
    expected_ex_mem.wb_sel         = WB_PC4;
    expected_ex_mem.mem_size       = MEM_WORD;
    expected_ex_mem.control        = 1'b1;
    expected_ex_mem.control_taken  = 1'b1;
    expected_ex_mem.control_target = 32'h0000_3820;
    expected_redirect.valid        = 1'b1;
    expected_redirect.target       = 32'h0000_3820;
    expected_redirect.origin       = REDIRECT_FROM_EX;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "JAL PC-relative redirect"
    );

    // JALR consumes the forwarded rs1 value, clears target bit zero, and emits
    // the aligned target only on acceptance.
    ctrl                  = safe_ctrl();
    ctrl.uses_rs1         = 1'b1;
    ctrl.reg_write        = 1'b1;
    ctrl.wb_sel           = WB_PC4;
    ctrl.branch_kind      = BR_JALR;
    id_ex.pc              = 32'h0000_4000;
    id_ex.insn            = 32'h0041_82e7;
    id_ex.rs1             = 5'd3;
    id_ex.rs2             = 5'd4;
    id_ex.rd              = 5'd5;
    id_ex.rs1_value       = 32'hffff_ffff;
    id_ex.rs2_value       = 32'h7777_7777;
    id_ex.imm             = 32'h0000_0004;
    id_ex.ctrl            = ctrl;
    fwd_a_sel             = FWD_EX_MEM;
    ex_mem_fwd_value      = 32'h0000_5001;
    #1;

    expected_ex_mem                = '0;
    expected_ex_mem.valid          = 1'b1;
    expected_ex_mem.pc             = id_ex.pc;
    expected_ex_mem.insn           = id_ex.insn;
    expected_ex_mem.rd             = 5'd5;
    expected_ex_mem.reg_write      = 1'b1;
    expected_ex_mem.wb_sel         = WB_PC4;
    expected_ex_mem.store_data     = 32'h7777_7777;
    expected_ex_mem.mem_size       = MEM_WORD;
    expected_ex_mem.control        = 1'b1;
    expected_ex_mem.control_taken  = 1'b1;
    expected_ex_mem.control_target = 32'h0000_5004;
    expected_redirect.valid        = 1'b1;
    expected_redirect.target       = 32'h0000_5004;
    expected_redirect.origin       = REDIRECT_FROM_EX;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "JALR forwarded aligned target"
    );

    // IALIGN=32: a taken target with bit one set traps on the control
    // instruction, suppresses its link write, and never redirects.
    ex_mem_fwd_value                 = 32'h0000_5003;
    expected_ex_mem.reg_write        = 1'b0;
    expected_ex_mem.control_target   = 32'h0000_5006;
    expected_ex_mem.exc.valid        = 1'b1;
    expected_ex_mem.exc.cause        = EXC_INST_ADDR_MISALIGNED;
    expected_ex_mem.exc.tval         = 32'h0000_5006;
    expected_redirect                = '0;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "JALR misaligned target"
    );

    // A pre-existing exception wins over otherwise legal control resolution.
    // It must retain its cause and suppress both link write and redirect.
    ex_mem_fwd_value                 = 32'h0000_5001;
    id_ex.exc.valid                  = 1'b1;
    id_ex.exc.cause                  = EXC_INST_ACCESS_FAULT;
    id_ex.exc.tval                   = 32'hfeed_4000;
    expected_ex_mem.control_target   = 32'h0000_5004;
    expected_ex_mem.exc              = id_ex.exc;
    expected_redirect                = '0;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "inherited exception suppresses redirect"
    );

    // Register CSR operation returns the old value and forwards rs1 into the
    // read-modify-write computation; the write itself remains a WB side effect.
    ctrl                  = safe_ctrl();
    ctrl.uses_rs1         = 1'b1;
    ctrl.reg_write        = 1'b1;
    ctrl.wb_sel           = WB_CSR;
    ctrl.csr_cmd          = CSR_RS;
    id_ex.pc              = 32'h0000_5000;
    id_ex.insn            = {CSR_MSCRATCH, 5'd3, FUNCT3_CSRRS, 5'd5, OPCODE_SYSTEM};
    id_ex.rs1             = 5'd3;
    id_ex.rs2             = 5'd0;
    id_ex.rd              = 5'd5;
    id_ex.rs1_value       = 32'h0000_0001;
    id_ex.rs2_value       = 32'b0;
    id_ex.imm             = 32'b0;
    id_ex.ctrl            = ctrl;
    id_ex.exc             = '0;
    fwd_a_sel             = FWD_MEM_WB;
    fwd_b_sel             = FWD_REGFILE;
    mem_wb_fwd_value      = 32'h0000_00f0;
    csr_rdata             = 32'h1234_000f;
    #1;

    expected_ex_mem                = '0;
    expected_ex_mem.valid          = 1'b1;
    expected_ex_mem.pc             = id_ex.pc;
    expected_ex_mem.insn           = id_ex.insn;
    expected_ex_mem.rd             = 5'd5;
    expected_ex_mem.reg_write      = 1'b1;
    expected_ex_mem.wb_sel         = WB_CSR;
    expected_ex_mem.mem_size       = MEM_WORD;
    expected_ex_mem.csr_addr       = CSR_MSCRATCH;
    expected_ex_mem.csr_write      = 1'b1;
    expected_ex_mem.csr_wdata      = 32'h1234_00ff;
    expected_ex_mem.csr_old        = 32'h1234_000f;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      CSR_MSCRATCH,
      "CSRRS register source"
    );
    check_csr_access_write(1'b1, "CSRRS register source");

    // CSRRS with rs1=x0 is read-only even if a forwarded value is nonzero.
    id_ex.rs1                    = 5'd0;
    id_ex.insn[19:15]           = 5'd0;
    expected_ex_mem.insn        = id_ex.insn;
    expected_ex_mem.csr_write   = 1'b0;
    expected_ex_mem.csr_wdata   = 32'h1234_00ff;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      CSR_MSCRATCH,
      "CSRRS x0 suppresses write"
    );
    check_csr_access_write(1'b0, "CSRRS x0 suppresses write");

    // CSRRW uses the forwarded register source and always writes the CSR.
    ctrl.csr_cmd                  = CSR_RW;
    id_ex.ctrl                   = ctrl;
    id_ex.rs1                    = 5'd3;
    id_ex.insn                   = {
      CSR_MSCRATCH,
      5'd3,
      FUNCT3_CSRRW,
      5'd5,
      OPCODE_SYSTEM
    };
    expected_ex_mem.insn         = id_ex.insn;
    expected_ex_mem.csr_write    = 1'b1;
    expected_ex_mem.csr_wdata    = 32'h0000_00f0;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      CSR_MSCRATCH,
      "CSRRW forwarded source"
    );
    check_csr_access_write(1'b1, "CSRRW forwarded source");

    // CSRRWI writes even with zimm=0, while CSRRSI with zimm=0 is read-only.
    ctrl.csr_cmd                  = CSR_RWI;
    id_ex.ctrl                   = ctrl;
    id_ex.rs1                    = 5'd0;
    id_ex.insn                   = {
      CSR_MSCRATCH,
      5'd0,
      FUNCT3_CSRRWI,
      5'd5,
      OPCODE_SYSTEM
    };
    expected_ex_mem.insn         = id_ex.insn;
    expected_ex_mem.csr_write    = 1'b1;
    expected_ex_mem.csr_wdata    = 32'b0;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      CSR_MSCRATCH,
      "CSRRWI zero immediate still writes"
    );
    check_csr_access_write(1'b1, "CSRRWI zero immediate still writes");

    ctrl.csr_cmd                  = CSR_RSI;
    id_ex.ctrl                   = ctrl;
    id_ex.insn[14:12]            = FUNCT3_CSRRSI;
    expected_ex_mem.insn         = id_ex.insn;
    expected_ex_mem.csr_write    = 1'b0;
    expected_ex_mem.csr_wdata    = csr_rdata;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      CSR_MSCRATCH,
      "CSRRSI zero immediate suppresses write"
    );
    check_csr_access_write(1'b0, "CSRRSI zero immediate suppresses write");

    // Immediate CSR forms use the five-bit zimm field, not the forwarded GPR.
    ctrl.csr_cmd                  = CSR_RCI;
    id_ex.ctrl                   = ctrl;
    id_ex.rs1                    = 5'd3;
    id_ex.insn                   = {
      CSR_MSCRATCH,
      5'd3,
      FUNCT3_CSRRCI,
      5'd5,
      OPCODE_SYSTEM
    };
    expected_ex_mem.insn         = id_ex.insn;
    expected_ex_mem.csr_write    = 1'b1;
    expected_ex_mem.csr_wdata    = 32'h1234_000c;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      CSR_MSCRATCH,
      "CSRRCI zimm source"
    );
    check_csr_access_write(1'b1, "CSRRCI zimm source");

    // Illegal CSR access becomes an illegal-instruction exception and
    // suppresses both GPR and CSR writes.
    csr_access_illegal             = 1'b1;
    expected_ex_mem.reg_write      = 1'b0;
    expected_ex_mem.csr_write      = 1'b0;
    expected_ex_mem.exc.valid      = 1'b1;
    expected_ex_mem.exc.cause      = EXC_ILLEGAL_INSN;
    expected_ex_mem.exc.tval       = id_ex.insn;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      CSR_MSCRATCH,
      "illegal CSR access"
    );

    // An exception already attached to ID/EX has priority over an EX-generated
    // CSR exception and keeps its original cause/tval.
    id_ex.exc.valid                 = 1'b1;
    id_ex.exc.cause                 = EXC_INST_ACCESS_FAULT;
    id_ex.exc.tval                  = 32'hfeed_0000;
    expected_ex_mem.exc             = id_ex.exc;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      CSR_MSCRATCH,
      "inherited exception priority"
    );

    // MRET consumes the dedicated architectural mepc value and redirects like
    // other EX control transfers. It is not itself a Zicsr access.
    drive_bubble();
    ctrl                  = safe_ctrl();
    ctrl.is_mret          = 1'b1;
    id_ex.valid           = 1'b1;
    id_ex.pc              = 32'h0000_6000;
    id_ex.insn            = INSN_MRET;
    id_ex.ctrl            = ctrl;
    csr_mepc              = 32'h0000_7000;
    #1;

    expected_ex_mem                = '0;
    expected_ex_mem.valid          = 1'b1;
    expected_ex_mem.pc             = id_ex.pc;
    expected_ex_mem.insn           = INSN_MRET;
    expected_ex_mem.mem_size       = MEM_WORD;
    expected_ex_mem.control        = 1'b1;
    expected_ex_mem.control_taken  = 1'b1;
    expected_ex_mem.control_target = 32'h0000_7000;
    expected_redirect              = '0;
    expected_redirect.valid        = 1'b1;
    expected_redirect.target       = 32'h0000_7000;
    expected_redirect.origin       = REDIRECT_FROM_EX;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "MRET redirect"
    );
    check_csr_access_write(1'b0, "MRET is not a CSR write");

    // A combinational legality indication belongs to Zicsr accesses only and
    // cannot turn a valid MRET into an illegal-instruction exception.
    csr_access_illegal = 1'b1;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "MRET ignores CSR access legality"
    );

    csr_access_illegal              = 1'b0;
    csr_mepc                        = 32'h0000_7002;
    expected_ex_mem.control_target  = 32'h0000_7002;
    expected_ex_mem.exc.valid       = 1'b1;
    expected_ex_mem.exc.cause       = EXC_INST_ADDR_MISALIGNED;
    expected_ex_mem.exc.tval        = 32'h0000_7002;
    expected_redirect               = '0;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "MRET misaligned target"
    );

    // MUL uses the forwarded operands, holds ID/EX while executing, and emits
    // exactly one normal EX/MEM result when its response becomes available.
    drive_bubble();
    @(negedge clk);
    ctrl                  = safe_ctrl();
    ctrl.uses_rs1         = 1'b1;
    ctrl.uses_rs2         = 1'b1;
    ctrl.reg_write        = 1'b1;
    ctrl.mdu_op           = MDU_MUL;
    ctrl.op_a_sel         = OP_A_RS1;
    ctrl.op_b_sel         = OP_B_RS2;
    id_ex.valid           = 1'b1;
    id_ex.pc              = 32'h0000_8000;
    id_ex.insn            = 32'h0241_82b3;
    id_ex.rs1             = 5'd3;
    id_ex.rs2             = 5'd4;
    id_ex.rd              = 5'd5;
    id_ex.rs1_value       = 32'd6;
    id_ex.rs2_value       = 32'd7;
    id_ex.ctrl            = ctrl;
    #1;

    expected_ex_mem  = '0;
    expected_redirect = '0;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b0,
      1'b1,
      12'b0,
      "MUL request wait"
    );

    @(posedge clk);
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b0,
      1'b1,
      12'b0,
      "MUL execute wait"
    );

    @(posedge clk);
    #1;
    expected_ex_mem.valid       = 1'b1;
    expected_ex_mem.pc          = id_ex.pc;
    expected_ex_mem.insn        = id_ex.insn;
    expected_ex_mem.rd          = id_ex.rd;
    expected_ex_mem.reg_write   = 1'b1;
    expected_ex_mem.ex_result   = 32'd42;
    expected_ex_mem.store_data  = 32'd7;
    expected_ex_mem.mem_size    = MEM_WORD;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "MUL response"
    );

    // Keep the same packet through the acceptance edge, just as the real
    // ID/EX register does, then replace it before another request can launch.
    @(posedge clk);
    #1;
    drive_bubble();

    // A DIV response is sticky while EX/MEM is backpressured. The iterative
    // operation must not restart, and its result must remain unchanged.
    @(negedge clk);
    ctrl                  = safe_ctrl();
    ctrl.uses_rs1         = 1'b1;
    ctrl.uses_rs2         = 1'b1;
    ctrl.reg_write        = 1'b1;
    ctrl.mdu_op           = MDU_DIVU;
    ctrl.op_a_sel         = OP_A_RS1;
    ctrl.op_b_sel         = OP_B_RS2;
    id_ex.valid           = 1'b1;
    id_ex.pc              = 32'h0000_8010;
    id_ex.insn            = 32'h0241_d2b3;
    id_ex.rs1             = 5'd3;
    id_ex.rs2             = 5'd4;
    id_ex.rd              = 5'd5;
    id_ex.rs1_value       = 32'd100;
    id_ex.rs2_value       = 32'd7;
    id_ex.ctrl            = ctrl;
    result_ready          = 1'b1;

    @(posedge clk);
    #1;
    result_ready = 1'b0;
    div_cycles   = 0;

    while (!result_valid && (div_cycles < 40)) begin
      @(posedge clk);
      #1;
      div_cycles++;
    end

    if (!result_valid) begin
      $fatal(1, "DIVU did not complete within 32 iterations");
    end

    expected_ex_mem               = '0;
    expected_ex_mem.valid         = 1'b1;
    expected_ex_mem.pc            = id_ex.pc;
    expected_ex_mem.insn          = id_ex.insn;
    expected_ex_mem.rd            = id_ex.rd;
    expected_ex_mem.reg_write     = 1'b1;
    expected_ex_mem.ex_result     = 32'd14;
    expected_ex_mem.store_data    = 32'd7;
    expected_ex_mem.mem_size      = MEM_WORD;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b1,
      12'b0,
      "DIVU response backpressure"
    );

    repeat (2) begin
      @(posedge clk);
      #1;
      check_outputs(
        expected_ex_mem,
        expected_redirect,
        1'b1,
        1'b1,
        12'b0,
        "DIVU sticky response"
      );
    end

    result_ready = 1'b1;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "DIVU response accepted"
    );

    @(posedge clk);
    #1;
    drive_bubble();

    // A pre-existing exception always drains through EX, even if stale control
    // bits still identify an MDU operation.
    id_ex.valid                     = 1'b1;
    id_ex.pc                        = 32'h0000_8020;
    id_ex.insn                      = 32'h0241_d2b3;
    id_ex.rd                        = 5'd5;
    id_ex.rs2_value                 = 32'd7;
    id_ex.ctrl                      = ctrl;
    id_ex.exc.valid                 = 1'b1;
    id_ex.exc.cause                 = EXC_ILLEGAL_INSN;
    id_ex.exc.tval                  = id_ex.insn;
    expected_ex_mem                 = '0;
    expected_ex_mem.valid           = 1'b1;
    expected_ex_mem.pc              = id_ex.pc;
    expected_ex_mem.insn            = id_ex.insn;
    expected_ex_mem.rd              = id_ex.rd;
    expected_ex_mem.store_data      = id_ex.rs2_value;
    expected_ex_mem.mem_size        = MEM_WORD;
    expected_ex_mem.exc             = id_ex.exc;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b1,
      1'b0,
      12'b0,
      "exception drains ahead of MDU wait"
    );

    // Reset and kill dominate a valid packet and clear all visible effects.
    expected_ex_mem  = '0;
    expected_redirect = '0;
    rst              = 1'b1;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b0,
      1'b0,
      12'b0,
      "reset suppression"
    );

    rst  = 1'b0;
    kill = 1'b1;
    #1;
    check_outputs(
      expected_ex_mem,
      expected_redirect,
      1'b0,
      1'b0,
      12'b0,
      "kill suppression"
    );

    $display("PASS: %0d EX-stage checks", checks);
    $finish;
  end

endmodule
