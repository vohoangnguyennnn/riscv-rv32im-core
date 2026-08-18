// SPDX-License-Identifier: MIT

// Gate-4 directed regression for GPR forwarding and load-use interlocks.
// Architectural signatures prove end-to-end correctness; a small number of
// internal selector checks distinguish EX/MEM, MEM/WB, and WB-to-ID paths that
// cannot be identified from retirement trace alone.
module tb_pipeline_forwarding;

  timeunit 1ns;
  timeprecision 1ps;

  import rv32_pkg::*;
  import rv32_tb_pkg::*;

  localparam int unsigned TCM_BYTES = 2048;
  localparam int unsigned WORDS     = TCM_BYTES / 4;
  localparam logic [31:0] SIG_BASE  = 32'h0000_0700;
  localparam logic [31:0] DATA_BASE = 32'h0000_0780;
  localparam logic [31:0] DONE_ADDR = 32'h0000_07fc;

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

  int unsigned program_word;
  int unsigned cycles;
  int unsigned checks;
  int unsigned expected_hazards;
  int unsigned observed_hazards;
  logic        jal_pc4_forward_seen;
  logic        jalr_pc4_forward_seen;

  logic       fwd_check_valid [0:WORDS-1];
  fwd_sel_e   fwd_a_expected  [0:WORDS-1];
  fwd_sel_e   fwd_b_expected  [0:WORDS-1];
  logic       fwd_check_seen  [0:WORDS-1];
  logic       hazard_expected [0:WORDS-1];
  int unsigned hazard_seen    [0:WORDS-1];
  logic       forbidden_pc    [0:WORDS-1];
  int unsigned retire_count   [0:WORDS-1];

  logic [31:0] auipc_signature_expected;
  logic [31:0] jal_pc;
  logic [31:0] jalr_pc;
  logic [31:0] jalr_signature_expected;
  logic [31:0] jal_signature_expected;
  logic [31:0] load_jalr_signature_expected;
  logic [31:0] load_gap_jalr_signature_expected;
  logic [31:0] csr_jalr_signature_expected;

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

  task automatic check_word(
    input logic [31:0] actual,
    input logic [31:0] expected,
    input string       test_name
  );
    begin
      if (actual !== expected) begin
        $fatal(1, "%s: expected=%08x actual=%08x", test_name, expected, actual);
      end
      checks++;
    end
  endtask

  task automatic emit(input logic [31:0] insn);
    begin
      u_tcm.mem[program_word] = insn;
      program_word++;
    end
  endtask

  task automatic emit_fwd(
    input logic [31:0] insn,
    input fwd_sel_e   expected_a,
    input fwd_sel_e   expected_b
  );
    begin
      fwd_check_valid[program_word] = 1'b1;
      fwd_a_expected[program_word]  = expected_a;
      fwd_b_expected[program_word]  = expected_b;
      emit(insn);
    end
  endtask

  task automatic emit_load_consumer(
    input logic [31:0] insn,
    input fwd_sel_e   expected_a,
    input fwd_sel_e   expected_b
  );
    begin
      hazard_expected[program_word] = 1'b1;
      expected_hazards++;
      emit_fwd(insn, expected_a, expected_b);
    end
  endtask

  task automatic emit_forbidden(input logic [31:0] insn);
    begin
      forbidden_pc[program_word] = 1'b1;
      emit(insn);
    end
  endtask

  task automatic emit_signature_store(
    input logic [4:0]  source,
    input logic [11:0] offset
  );
    emit(enc_sw(source, 5'd31, offset));
  endtask

  task automatic validate_signatures;
    begin
      check_word(u_tcm.mem[(SIG_BASE + 32'd0)  >> 2], 32'd12,        "adjacent ALU rs1 forwarding");
      check_word(u_tcm.mem[(SIG_BASE + 32'd4)  >> 2], 32'd9,         "adjacent ALU rs2 forwarding");
      check_word(u_tcm.mem[(SIG_BASE + 32'd8)  >> 2], 32'd11,        "distance-two dependency");
      check_word(u_tcm.mem[(SIG_BASE + 32'd12) >> 2], 32'd22,        "distance-three WB-to-ID dependency");
      check_word(u_tcm.mem[(SIG_BASE + 32'd16) >> 2], 32'd3,         "youngest producer priority");
      check_word(u_tcm.mem[(SIG_BASE + 32'd20) >> 2], 32'd1,         "x0 producer exclusion");
      check_word(u_tcm.mem[(SIG_BASE + 32'd24) >> 2], 32'h0006_0000, "unused encoded source fields");
      check_word(u_tcm.mem[(SIG_BASE + 32'd28) >> 2], 32'h1234_5067, "LUI producer");
      check_word(u_tcm.mem[(SIG_BASE + 32'd32) >> 2], auipc_signature_expected, "AUIPC producer");
      check_word(u_tcm.mem[(SIG_BASE + 32'd36) >> 2], 32'd6,         "CSR old value to ALU");
      check_word(u_tcm.mem[(SIG_BASE + 32'd40) >> 2], 32'd43,        "MUL producer/dependent ALU");
      check_word(u_tcm.mem[(SIG_BASE + 32'd44) >> 2], 32'd1,         "DIV producer/dependent branch");
      check_word(u_tcm.mem[(SIG_BASE + 32'd48) >> 2], 32'h0000_0055, "load to store-data");
      check_word(u_tcm.mem[(SIG_BASE + 32'd52) >> 2], 32'd12,        "load to ALU");
      check_word(u_tcm.mem[(SIG_BASE + 32'd56) >> 2], 32'd1,         "load to adjacent branch");
      check_word(u_tcm.mem[(SIG_BASE + 32'd60) >> 2], 32'd2,         "load-gap-branch");
      check_word(u_tcm.mem[(SIG_BASE + 32'd64) >> 2], 32'd3,         "ALU to branch");
      check_word(u_tcm.mem[(SIG_BASE + 32'd68) >> 2], jalr_signature_expected, "ALU to JALR/link consumer");
      check_word(u_tcm.mem[(SIG_BASE + 32'd72) >> 2], jal_signature_expected, "JAL link to branch consumer");
      check_word(u_tcm.mem[(SIG_BASE + 32'd76) >> 2], load_jalr_signature_expected, "load to adjacent JALR");
      check_word(u_tcm.mem[(SIG_BASE + 32'd80) >> 2], load_gap_jalr_signature_expected, "load-gap-JALR");
      check_word(u_tcm.mem[(SIG_BASE + 32'd84) >> 2], csr_jalr_signature_expected, "CSR old value to JALR");
      check_word(u_tcm.mem[(SIG_BASE + 32'd88) >> 2], 32'd9,         "CSR old value to branch");
      check_word(u_tcm.mem[32'h0000_075c >> 2], 32'h0000_0077, "forwarded store address and data");
      check_word(u_tcm.mem[32'h0000_0760 >> 2], 32'hdead_beef, "wrong-path store 0");
      check_word(u_tcm.mem[32'h0000_0764 >> 2], 32'hdead_beef, "wrong-path store 1");
      check_word(u_tcm.mem[32'h0000_0768 >> 2], 32'hdead_beef, "wrong-path store 2");
      check_word(u_tcm.mem[32'h0000_076c >> 2], 32'hdead_beef, "wrong-path store 3");

      if (observed_hazards != expected_hazards) begin
        $fatal(
          1,
          "load-use hazard count mismatch: expected=%0d actual=%0d",
          expected_hazards,
          observed_hazards
        );
      end
      checks++;

      if (!jal_pc4_forward_seen || !jalr_pc4_forward_seen) begin
        $fatal(
          1,
          "PC+4 forwarding value was not observed for JAL/JALR: jal=%0b jalr=%0b",
          jal_pc4_forward_seen,
          jalr_pc4_forward_seen
        );
      end
      checks++;

      for (int unsigned word_index = 0; word_index < WORDS; word_index++) begin
        if (fwd_check_valid[word_index] && !fwd_check_seen[word_index]) begin
          $fatal(1, "forwarding checkpoint at pc=%08x was not observed", word_index << 2);
        end
        if (hazard_expected[word_index] && (hazard_seen[word_index] != 1)) begin
          $fatal(
            1,
            "load-use checkpoint at pc=%08x expected once, observed %0d",
            word_index << 2,
            hazard_seen[word_index]
          );
        end
      end
    end
  endtask

  initial begin : initialize_program
    logic [31:0] producer_pc;
    logic [31:0] jalr_target;
    logic [31:0] jal_expected_link;
    logic [31:0] load_jalr_pc;
    logic [31:0] load_jalr_target;
    logic [31:0] load_gap_jalr_pc;
    logic [31:0] load_gap_jalr_target;
    logic [31:0] csr_jalr_pc;
    logic [31:0] csr_jalr_target;

    clk              = 1'b0;
    rst              = 1'b1;
    cycles           = 0;
    checks           = 0;
    program_word     = 0;
    expected_hazards = 0;
    observed_hazards = 0;
    jal_pc4_forward_seen  = 1'b0;
    jalr_pc4_forward_seen = 1'b0;

    for (int unsigned word_index = 0; word_index < WORDS; word_index++) begin
      u_tcm.mem[word_index]       = TB_NOP;
      fwd_check_valid[word_index] = 1'b0;
      fwd_a_expected[word_index]  = FWD_REGFILE;
      fwd_b_expected[word_index]  = FWD_REGFILE;
      fwd_check_seen[word_index]  = 1'b0;
      hazard_expected[word_index] = 1'b0;
      hazard_seen[word_index]     = 0;
      forbidden_pc[word_index]    = 1'b0;
      retire_count[word_index]    = 0;
    end

    u_tcm.mem[(DATA_BASE + 32'd0)  >> 2] = 32'h0000_0055;
    u_tcm.mem[(DATA_BASE + 32'd4)  >> 2] = 32'd11;
    u_tcm.mem[(DATA_BASE + 32'd8)  >> 2] = 32'd7;
    u_tcm.mem[(DATA_BASE + 32'd12) >> 2] = 32'd8;
    u_tcm.mem[32'h0000_075c >> 2] = 32'hdead_beef;
    u_tcm.mem[32'h0000_0760 >> 2] = 32'hdead_beef;
    u_tcm.mem[32'h0000_0764 >> 2] = 32'hdead_beef;
    u_tcm.mem[32'h0000_0768 >> 2] = 32'hdead_beef;
    u_tcm.mem[32'h0000_076c >> 2] = 32'hdead_beef;
    u_tcm.mem[DONE_ADDR >> 2]     = 32'b0;

    emit(enc_addi(5'd31, 5'd0, SIG_BASE[11:0]));
    emit(enc_addi(5'd30, 5'd0, DATA_BASE[11:0]));

    // Adjacent rs1/rs2 consumers and store-data forwarding.
    emit(enc_addi(5'd1, 5'd0, 12'd5));
    emit_fwd(enc_addi(5'd2, 5'd1, 12'd7), FWD_EX_MEM, FWD_REGFILE);
    emit_fwd(enc_sw(5'd2, 5'd31, 12'd0), FWD_REGFILE, FWD_EX_MEM);

    emit(enc_addi(5'd3, 5'd0, 12'd9));
    emit_fwd(enc_add(5'd4, 5'd0, 5'd3), FWD_REGFILE, FWD_EX_MEM);
    emit_signature_store(5'd4, 12'd4);

    // Producer/consumer distances 2 and 3.
    emit(enc_addi(5'd5, 5'd0, 12'd10));
    emit(TB_NOP);
    emit_fwd(enc_addi(5'd6, 5'd5, 12'd1), FWD_MEM_WB, FWD_REGFILE);
    emit_signature_store(5'd6, 12'd8);

    emit(enc_addi(5'd7, 5'd0, 12'd20));
    emit(TB_NOP);
    emit(TB_NOP);
    emit_fwd(enc_addi(5'd8, 5'd7, 12'd2), FWD_REGFILE, FWD_REGFILE);
    emit_signature_store(5'd8, 12'd12);

    // Both EX/MEM and MEM/WB match x9; the younger EX/MEM value must win.
    emit(enc_addi(5'd9, 5'd0, 12'd1));
    emit_fwd(enc_addi(5'd9, 5'd9, 12'd1), FWD_EX_MEM, FWD_REGFILE);
    emit_fwd(enc_addi(5'd10, 5'd9, 12'd1), FWD_EX_MEM, FWD_REGFILE);
    emit_signature_store(5'd10, 12'd16);

    // x0 never forwards. A load followed by LUI proves encoded rs fields are
    // ignored when decoder uses_rs1/uses_rs2 are both clear.
    emit(enc_addi(5'd0, 5'd0, 12'd123));
    emit_fwd(enc_addi(5'd11, 5'd0, 12'd1), FWD_REGFILE, FWD_REGFILE);
    emit_signature_store(5'd11, 12'd20);
    emit(enc_lw(5'd12, 5'd30, 12'd0));
    emit_fwd(enc_lui(5'd13, 20'h00060), FWD_REGFILE, FWD_REGFILE);
    emit_signature_store(5'd13, 12'd24);

    // LUI and AUIPC are ordinary EX/MEM producers.
    emit(enc_lui(5'd14, 20'h12345));
    emit_fwd(enc_addi(5'd15, 5'd14, 12'h067), FWD_EX_MEM, FWD_REGFILE);
    emit_signature_store(5'd15, 12'd28);

    producer_pc = program_word << 2;
    emit(enc_auipc(5'd16, 20'h00001));
    emit_fwd(enc_addi(5'd17, 5'd16, 12'd4), FWD_EX_MEM, FWD_REGFILE);
    emit_signature_store(5'd17, 12'd32);
    auipc_signature_expected = producer_pc + 32'h0000_1004;

    // CSR old value forwards to a normal ALU consumer after conservative CSR
    // ordering, then a second CSR read feeds a branch directly. No special
    // control-dependency interlock is permitted.
    emit(enc_addi(5'd18, 5'd0, 12'd5));
    emit(enc_csr(CSR_MSCRATCH, FUNCT3_CSRRW, 5'd0, 5'd18));
    emit(enc_csr(CSR_MSCRATCH, FUNCT3_CSRRW, 5'd19, 5'd0));
    emit_fwd(enc_addi(5'd20, 5'd19, 12'd1), FWD_EX_MEM, FWD_REGFILE);
    emit_signature_store(5'd20, 12'd36);
    emit(enc_csr(CSR_MSCRATCH, FUNCT3_CSRRW, 5'd0, 5'd18));
    emit(enc_csr(CSR_MSCRATCH, FUNCT3_CSRRW, 5'd19, 5'd0));
    emit_fwd(enc_branch(FUNCT3_BEQ, 5'd19, 5'd18, 13'd12), FWD_EX_MEM, FWD_REGFILE);
    emit_forbidden(enc_sw(5'd0, 5'd31, 12'h060));
    emit_forbidden(enc_mdu(FUNCT3_MUL, 5'd20, 5'd1, 5'd2));
    emit(enc_addi(5'd20, 5'd0, 12'd9));
    emit_signature_store(5'd20, 12'd88);

    // ALU operands forward into MDU; completed MDU results forward to ALU and
    // to an immediately dependent control transfer.
    emit(enc_addi(5'd23, 5'd0, 12'd6));
    emit(enc_addi(5'd24, 5'd0, 12'd7));
    emit_fwd(enc_mdu(FUNCT3_MUL, 5'd25, 5'd23, 5'd24), FWD_MEM_WB, FWD_EX_MEM);
    emit_fwd(enc_addi(5'd26, 5'd25, 12'd1), FWD_EX_MEM, FWD_REGFILE);
    emit_signature_store(5'd26, 12'd40);
    emit(enc_addi(5'd29, 5'd0, 12'd7));
    emit(enc_mdu(FUNCT3_DIV, 5'd28, 5'd25, 5'd23));
    emit_fwd(enc_branch(FUNCT3_BEQ, 5'd28, 5'd29, 13'd12), FWD_EX_MEM, FWD_REGFILE);
    emit_forbidden(enc_sw(5'd0, 5'd31, 12'h060));
    emit_forbidden(enc_addi(5'd27, 5'd0, 12'h7ff));
    emit(enc_addi(5'd27, 5'd0, 12'd1));
    emit_signature_store(5'd27, 12'd44);

    // Load-use: store data, ALU rs1, and control-transfer operands each get
    // exactly one bubble and consume the completed load from MEM/WB.
    emit(enc_lw(5'd1, 5'd30, 12'd0));
    emit_load_consumer(enc_sw(5'd1, 5'd31, 12'd48), FWD_REGFILE, FWD_MEM_WB);

    emit(enc_lw(5'd2, 5'd30, 12'd4));
    emit_load_consumer(enc_addi(5'd3, 5'd2, 12'd1), FWD_MEM_WB, FWD_REGFILE);
    emit_signature_store(5'd3, 12'd52);

    emit(enc_addi(5'd5, 5'd0, 12'd7));
    emit(enc_lw(5'd4, 5'd30, 12'd8));
    emit_load_consumer(enc_branch(FUNCT3_BEQ, 5'd4, 5'd5, 13'd12), FWD_MEM_WB, FWD_REGFILE);
    emit_forbidden(enc_sw(5'd0, 5'd31, 12'h064));
    emit_forbidden(enc_addi(5'd6, 5'd0, 12'h7ff));
    emit(enc_addi(5'd6, 5'd0, 12'd1));
    emit_signature_store(5'd6, 12'd56);

    // One independent instruction between load and branch requires no ID
    // interlock; the architectural result must still be current.
    emit(enc_addi(5'd8, 5'd0, 12'd8));
    emit(enc_lw(5'd7, 5'd30, 12'd12));
    emit(TB_NOP);
    emit_fwd(enc_branch(FUNCT3_BEQ, 5'd7, 5'd8, 13'd12), FWD_MEM_WB, FWD_REGFILE);
    emit_forbidden(enc_sw(5'd0, 5'd31, 12'h068));
    emit_forbidden(enc_addi(5'd9, 5'd0, 12'h7ff));
    emit(enc_addi(5'd9, 5'd0, 12'd2));
    emit_signature_store(5'd9, 12'd60);

    // A branch consumes the same just-produced ALU register on both ports.
    emit(enc_addi(5'd9, 5'd0, 12'd1));
    emit_fwd(enc_branch(FUNCT3_BEQ, 5'd9, 5'd9, 13'd12), FWD_EX_MEM, FWD_EX_MEM);
    emit_forbidden(enc_sw(5'd0, 5'd31, 12'h06c));
    emit_forbidden(enc_addi(5'd10, 5'd0, 12'h7ff));
    emit(enc_addi(5'd10, 5'd0, 12'd3));
    emit_signature_store(5'd10, 12'd64);

    // ALU -> JALR uses EX/MEM forwarding. The target immediately consumes the
    // JALR link value through the normal WB-to-ID/forwarding path.
    jalr_pc     = (program_word + 1) << 2;
    jalr_target = (program_word + 4) << 2;
    emit(enc_addi(5'd11, 5'd0, jalr_target[11:0]));
    emit_fwd(enc_jalr(5'd12, 5'd11, 12'd0), FWD_EX_MEM, FWD_REGFILE);
    emit_forbidden(enc_sw(5'd0, 5'd31, 12'h060));
    emit_forbidden(enc_mdu(FUNCT3_MUL, 5'd13, 5'd1, 5'd2));
    emit(enc_addi(5'd13, 5'd12, 12'd4));
    emit_signature_store(5'd13, 12'd68);
    jalr_signature_expected = jalr_pc + 32'd8;

    // JAL link is compared by a branch at the redirect target. The redirect
    // bubbles mean the link may already be in the register file, but this
    // remains an end-to-end PC+4 producer/control-consumer check.
    jal_pc            = (program_word + 1) << 2;
    jal_expected_link = jal_pc + 32'd4;
    emit(enc_addi(5'd16, 5'd0, jal_expected_link[11:0]));
    emit(enc_jal(5'd14, 21'd12));
    emit_forbidden(enc_sw(5'd0, 5'd31, 12'h064));
    emit_forbidden(enc_mdu(FUNCT3_MUL, 5'd15, 5'd1, 5'd2));
    emit(enc_branch(FUNCT3_BEQ, 5'd14, 5'd16, 13'd12));
    emit_forbidden(enc_sw(5'd0, 5'd31, 12'h068));
    emit_forbidden(enc_mdu(FUNCT3_DIV, 5'd15, 5'd2, 5'd1));
    emit(enc_addi(5'd15, 5'd14, 12'd8));
    emit_signature_store(5'd15, 12'd72);
    jal_signature_expected = jal_pc + 32'd12;

    // A load feeding JALR immediately requires exactly one load-use bubble.
    // The same dependency with one independent instruction has no ID stall
    // and obtains the value from MEM/WB.
    load_jalr_pc     = (program_word + 1) << 2;
    load_jalr_target = (program_word + 4) << 2;
    u_tcm.mem[(DATA_BASE + 32'd16) >> 2] = load_jalr_target;
    emit(enc_lw(5'd21, 5'd30, 12'd16));
    emit_load_consumer(enc_jalr(5'd22, 5'd21, 12'd0), FWD_MEM_WB, FWD_REGFILE);
    emit_forbidden(enc_sw(5'd0, 5'd31, 12'h06c));
    emit_forbidden(enc_mdu(FUNCT3_MUL, 5'd23, 5'd1, 5'd2));
    emit(enc_addi(5'd23, 5'd22, 12'd8));
    emit_signature_store(5'd23, 12'd76);
    load_jalr_signature_expected = load_jalr_pc + 32'd12;

    load_gap_jalr_pc     = (program_word + 2) << 2;
    load_gap_jalr_target = (program_word + 5) << 2;
    u_tcm.mem[(DATA_BASE + 32'd20) >> 2] = load_gap_jalr_target;
    emit(enc_lw(5'd24, 5'd30, 12'd20));
    emit(TB_NOP);
    emit_fwd(enc_jalr(5'd25, 5'd24, 12'd0), FWD_MEM_WB, FWD_REGFILE);
    emit_forbidden(enc_sw(5'd0, 5'd31, 12'h060));
    emit_forbidden(enc_mdu(FUNCT3_DIV, 5'd26, 5'd2, 5'd1));
    emit(enc_addi(5'd26, 5'd25, 12'd8));
    emit_signature_store(5'd26, 12'd80);
    load_gap_jalr_signature_expected = load_gap_jalr_pc + 32'd12;

    // A CSR read result can also supply an adjacent JALR base from EX/MEM.
    // Build the target in a GPR, round-trip it through mscratch, then jump.
    csr_jalr_pc     = (program_word + 3) << 2;
    csr_jalr_target = (program_word + 6) << 2;
    emit(enc_addi(5'd27, 5'd0, csr_jalr_target[11:0]));
    emit(enc_csr(CSR_MSCRATCH, FUNCT3_CSRRW, 5'd0, 5'd27));
    emit(enc_csr(CSR_MSCRATCH, FUNCT3_CSRRW, 5'd28, 5'd0));
    emit_fwd(enc_jalr(5'd29, 5'd28, 12'd0), FWD_EX_MEM, FWD_REGFILE);
    emit_forbidden(enc_sw(5'd0, 5'd31, 12'h064));
    emit_forbidden(enc_mdu(FUNCT3_MUL, 5'd27, 5'd1, 5'd2));
    emit(enc_addi(5'd27, 5'd29, 12'd8));
    emit_signature_store(5'd27, 12'd84);
    csr_jalr_signature_expected = csr_jalr_pc + 32'd12;

    // Address and data of a store are independently forwarded.
    emit(enc_addi(5'd17, 5'd0, 12'h077));
    emit(enc_addi(5'd16, 5'd0, 12'h75c));
    emit_fwd(enc_sw(5'd17, 5'd16, 12'd0), FWD_EX_MEM, FWD_MEM_WB);

    emit(enc_addi(5'd18, 5'd0, 12'h05a));
    emit(enc_sw(5'd18, 5'd0, DONE_ADDR[11:0]));
    emit(enc_jal(5'd0, 21'd0));

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
  end

  // Mid-cycle sampling observes the selectors and ID hazard decision that are
  // consumed at the following active edge.
  always @(negedge clk) begin : check_pipeline_controls
    int unsigned pc_word;

    if (!rst) begin
      // Redirect bubbles prevent a real target instruction from being adjacent
      // to its JAL/JALR producer. Observe the core's EX/MEM semantic value
      // directly so WB_PC4 remains part of the compositional forwarding proof.
      if (
        dut.ex_mem_q.valid &&
        (dut.ex_mem_q.wb_sel == WB_PC4) &&
        ((dut.ex_mem_q.pc == jal_pc) || (dut.ex_mem_q.pc == jalr_pc))
      ) begin
        if (dut.ex_mem_fwd_value !== (dut.ex_mem_q.pc + 32'd4)) begin
          $fatal(
            1,
            "PC+4 forwarding value mismatch pc=%08x expected=%08x actual=%08x",
            dut.ex_mem_q.pc,
            dut.ex_mem_q.pc + 32'd4,
            dut.ex_mem_fwd_value
          );
        end
        if (dut.ex_mem_q.pc == jal_pc)  jal_pc4_forward_seen  = 1'b1;
        if (dut.ex_mem_q.pc == jalr_pc) jalr_pc4_forward_seen = 1'b1;
      end

      if (dut.id_ex_q.valid) begin
        pc_word = dut.id_ex_q.pc >> 2;
        // A blocking MDU instruction remains in ID/EX after its launch-edge
        // operands have already been captured. Check each PC only on its first
        // EX observation; later selector changes are irrelevant to that request.
        if (
          (pc_word < WORDS) &&
          fwd_check_valid[pc_word] &&
          !fwd_check_seen[pc_word]
        ) begin
          if (
            (dut.ex_fwd_a_sel !== fwd_a_expected[pc_word]) ||
            (dut.ex_fwd_b_sel !== fwd_b_expected[pc_word])
          ) begin
            $fatal(
              1,
              "forward select mismatch pc=%08x: a=%0d/%0d b=%0d/%0d",
              dut.id_ex_q.pc,
              dut.ex_fwd_a_sel,
              fwd_a_expected[pc_word],
              dut.ex_fwd_b_sel,
              fwd_b_expected[pc_word]
            );
          end
          fwd_check_seen[pc_word] = 1'b1;
          checks++;
        end
      end

      if (dut.load_use_hazard) begin
        pc_word = dut.id_ex_d.pc >> 2;
        if ((pc_word >= WORDS) || !hazard_expected[pc_word]) begin
          $fatal(1, "unexpected load-use hazard for ID pc=%08x", dut.id_ex_d.pc);
        end

        // An older MEM wait may hold the same load/consumer pair for several
        // cycles. Count the single cycle in which the controller actually
        // selects ACTION_ID_HAZARD and injects the architectural bubble.
        if (
          dut.id_ex_flush &&
          !dut.if_id_enable &&
          dut.ex_mem_enable
        ) begin
          hazard_seen[pc_word]++;
          observed_hazards++;
        end
      end
    end
  end

  always @(posedge clk) begin : monitor_retirement
    int unsigned pc_word;

    #1ps;
    if (!rst) begin
      cycles++;

      if (trace_valid) begin
        pc_word = trace_pc >> 2;
        if (trace_trap) begin
          $fatal(
            1,
            "unexpected trap pc=%08x insn=%08x cause=%0d",
            trace_pc,
            trace_insn,
            trace_cause
          );
        end
        if ((pc_word < WORDS) && forbidden_pc[pc_word]) begin
          $fatal(1, "wrong-path instruction retired at pc=%08x", trace_pc);
        end
        if (pc_word < WORDS) begin
          retire_count[pc_word]++;
          if (retire_count[pc_word] > 1) begin
            $fatal(1, "instruction retired more than once at pc=%08x", trace_pc);
          end
        end

        if ((trace_mem_wstrb != 4'b0000) && (trace_mem_addr == DONE_ADDR)) begin
          check_word(trace_mem_wdata, 32'h0000_005a, "completion store data");
          validate_signatures();
          $display(
            "tb_pipeline_forwarding: PASS (%0d cycles, %0d checks, %0d load-use bubbles)",
            cycles,
            checks,
            observed_hazards
          );
          $finish;
        end
      end

      if (cycles > 2500) begin
        $fatal(1, "pipeline forwarding integration timeout after %0d cycles", cycles);
      end
    end
  end

endmodule
