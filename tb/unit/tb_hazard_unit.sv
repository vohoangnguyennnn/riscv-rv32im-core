// SPDX-License-Identifier: MIT

module tb_hazard_unit;

  timeunit 1ns;
  timeprecision 1ps;

  import rv32_pkg::*;

  logic         id_valid;
  reg_addr_t    id_rs1;
  reg_addr_t    id_rs2;
  csr_addr_t    id_csr_addr;
  decode_ctrl_t id_ctrl;
  id_ex_t       id_ex;
  ex_mem_t      ex_mem;
  mem_wb_t      mem_wb;

  logic load_use;
  logic csr_dep;
  logic stall_id;
  int   checks;

  hazard_unit dut (
    .id_valid_i (id_valid),
    .id_rs1_i   (id_rs1),
    .id_rs2_i   (id_rs2),
    .id_csr_addr_i (id_csr_addr),
    .id_ctrl_i  (id_ctrl),
    .id_ex_i    (id_ex),
    .ex_mem_i   (ex_mem),
    .mem_wb_i   (mem_wb),
    .load_use_o (load_use),
    .csr_dep_o  (csr_dep),
    .stall_id_o (stall_id)
  );

  task automatic clear_inputs;
    begin
      id_valid = 1'b0;
      id_rs1   = 5'd3;
      id_rs2   = 5'd4;
      id_csr_addr = 12'b0;
      id_ctrl  = '0;
      id_ex    = '0;
      ex_mem   = '0;
      mem_wb   = '0;
      #1ps;
    end
  endtask

  task automatic check_outputs(
    input logic  expected_load_use,
    input logic  expected_csr_dep,
    input string test_name
  );
    logic expected_stall;
    begin
      expected_stall = expected_load_use || expected_csr_dep;
      #1ps;

      if (
        (load_use !== expected_load_use) ||
        (csr_dep !== expected_csr_dep) ||
        (stall_id !== expected_stall)
      ) begin
        $fatal(
          1,
          "%s mismatch: load=%0b/%0b csr=%0b/%0b stall=%0b/%0b",
          test_name,
          load_use,
          expected_load_use,
          csr_dep,
          expected_csr_dep,
          stall_id,
          expected_stall
        );
      end
      checks++;
    end
  endtask

  task automatic enable_id_consumer(
    input logic uses_rs1,
    input logic uses_rs2
  );
    begin
      id_valid             = 1'b1;
      id_ctrl.uses_rs1     = uses_rs1;
      id_ctrl.uses_rs2     = uses_rs2;
    end
  endtask

  task automatic enable_id_ex_load(input reg_addr_t rd);
    begin
      id_ex.valid          = 1'b1;
      id_ex.rd             = rd;
      id_ex.ctrl.reg_write = 1'b1;
      id_ex.ctrl.mem_cmd   = MEM_LOAD;
    end
  endtask

  task automatic enable_id_ex_csr_writer(
    input csr_cmd_e command,
    input reg_addr_t source,
    input csr_addr_t address
  );
    begin
      id_ex.valid        = 1'b1;
      id_ex.ctrl.csr_cmd = command;
      id_ex.rs1          = source;
      id_ex.insn[31:20]  = address;
    end
  endtask

  task automatic enable_ex_mem_csr_writer(input csr_addr_t address);
    begin
      ex_mem.valid     = 1'b1;
      ex_mem.csr_write = 1'b1;
      ex_mem.csr_addr  = address;
    end
  endtask

  initial begin
    checks = 0;

    clear_inputs();
    check_outputs(1'b0, 1'b0, "all packets invalid");

    // ----------------------------------------------------------------------
    // Load-use interlock
    // ----------------------------------------------------------------------
    enable_id_consumer(1'b1, 1'b1);
    enable_id_ex_load(id_rs1);
    check_outputs(1'b1, 1'b0, "load dependency on rs1");

    id_ex.rd = id_rs2;
    check_outputs(1'b1, 1'b0, "load dependency on rs2");

    id_rs2 = id_rs1;
    id_ex.rd = id_rs1;
    check_outputs(1'b1, 1'b0, "load dependency on both sources");

    id_valid = 1'b0;
    check_outputs(1'b0, 1'b0, "invalid ID consumer");

    id_valid             = 1'b1;
    id_ctrl.uses_rs1     = 1'b0;
    id_ctrl.uses_rs2     = 1'b0;
    check_outputs(1'b0, 1'b0, "unused encoded source fields");

    id_ctrl.uses_rs1 = 1'b1;
    id_ex.rd         = 5'd9;
    check_outputs(1'b0, 1'b0, "non-matching load destination");

    id_ex.rd = 5'd0;
    id_rs1   = 5'd0;
    check_outputs(1'b0, 1'b0, "load destination x0");

    id_rs1                    = 5'd3;
    id_ex.rd                  = id_rs1;
    id_ex.valid               = 1'b0;
    check_outputs(1'b0, 1'b0, "invalid load producer");

    id_ex.valid               = 1'b1;
    id_ex.ctrl.reg_write      = 1'b0;
    check_outputs(1'b0, 1'b0, "load reg_write disabled");

    id_ex.ctrl.reg_write      = 1'b1;
    id_ex.ctrl.mem_cmd        = MEM_NONE;
    check_outputs(1'b0, 1'b0, "non-load ID/EX producer");

    id_ex.ctrl.mem_cmd        = MEM_LOAD;
    id_ex.exc.valid           = 1'b1;
    check_outputs(1'b0, 1'b0, "faulting load producer");

    // Branch/JALR and store dependencies are represented by the same source
    // usage metadata, so no special control-dependency detector is needed.
    clear_inputs();
    enable_id_consumer(1'b1, 1'b0);
    id_ctrl.branch_kind = BR_JALR;
    enable_id_ex_load(id_rs1);
    check_outputs(1'b1, 1'b0, "load to JALR source");

    clear_inputs();
    enable_id_consumer(1'b1, 1'b1);
    id_ctrl.mem_cmd = MEM_STORE;
    enable_id_ex_load(id_rs2);
    check_outputs(1'b1, 1'b0, "load to store data");

    // ----------------------------------------------------------------------
    // General CSR serialization
    // ----------------------------------------------------------------------
    clear_inputs();
    id_valid       = 1'b1;
    id_ctrl.csr_cmd = CSR_RS;
    id_csr_addr    = CSR_MSCRATCH;
    enable_id_ex_csr_writer(CSR_RW, 5'd0, CSR_MSCRATCH);
    check_outputs(1'b0, 1'b1, "CSRRW x0 remains a writer");

    id_ex.ctrl.csr_cmd = CSR_RWI;
    check_outputs(1'b0, 1'b1, "CSRRWI zimm zero remains a writer");

    id_ex.ctrl.csr_cmd = CSR_RS;
    id_ex.rs1          = 5'd7;
    check_outputs(1'b0, 1'b1, "CSRRS nonzero source writes");

    id_ex.rs1 = 5'd0;
    check_outputs(1'b0, 1'b0, "CSRRS x0 suppresses write");

    id_ex.ctrl.csr_cmd = CSR_RC;
    check_outputs(1'b0, 1'b0, "CSRRC x0 suppresses write");

    id_ex.ctrl.csr_cmd = CSR_RSI;
    check_outputs(1'b0, 1'b0, "CSRRSI zimm zero suppresses write");

    id_ex.ctrl.csr_cmd = CSR_RCI;
    check_outputs(1'b0, 1'b0, "CSRRCI zimm zero suppresses write");

    id_ex.rs1 = 5'd1;
    check_outputs(1'b0, 1'b1, "CSRRCI nonzero zimm writes");

    id_ex.exc.valid = 1'b1;
    check_outputs(1'b0, 1'b0, "faulting ID/EX CSR writer excluded");

    id_ex.valid = 1'b0;
    enable_ex_mem_csr_writer(CSR_MSCRATCH);
    check_outputs(1'b0, 1'b1, "EX/MEM CSR writer");

    // General CSR consumers serialize conservatively even when the older
    // writer targets a different CSR.
    ex_mem.csr_addr = CSR_MTVEC;
    check_outputs(1'b0, 1'b1, "CSR address-independent serialization");

    ex_mem.csr_write = 1'b0;
    check_outputs(1'b0, 1'b0, "EX/MEM CSR write suppressed");

    ex_mem.csr_write = 1'b1;
    ex_mem.exc.valid = 1'b1;
    check_outputs(1'b0, 1'b0, "faulting EX/MEM CSR writer excluded");

    ex_mem.exc.valid = 1'b0;
    id_ctrl.csr_cmd  = CSR_NONE;
    check_outputs(1'b0, 1'b0, "non-CSR ID instruction");

    // ----------------------------------------------------------------------
    // minstret program-order interlock
    // ----------------------------------------------------------------------
    clear_inputs();
    id_valid        = 1'b1;
    id_ctrl.csr_cmd = CSR_RS;
    id_csr_addr     = CSR_MINSTRET;
    id_ex.valid     = 1'b1;
    check_outputs(1'b0, 1'b1, "minstret waits for older ID/EX retirement");

    id_ex.exc.valid = 1'b1;
    check_outputs(1'b0, 1'b0, "minstret ignores faulting ID/EX packet");

    id_ex.valid     = 1'b0;
    ex_mem.valid    = 1'b1;
    check_outputs(1'b0, 1'b1, "minstret waits for older EX/MEM retirement");

    ex_mem.exc.valid = 1'b1;
    check_outputs(1'b0, 1'b0, "minstret ignores faulting EX/MEM packet");

    ex_mem.valid     = 1'b0;
    mem_wb.valid     = 1'b1;
    id_csr_addr      = CSR_MINSTRETH;
    check_outputs(1'b0, 1'b0, "minstreth needs no MEM/WB stall");

    mem_wb.valid = 1'b0;
    id_csr_addr  = CSR_MCYCLE;
    id_ex.valid  = 1'b1;
    check_outputs(1'b0, 1'b0, "mcycle needs no retirement drain");

    // ----------------------------------------------------------------------
    // MRET dependency is specific to mepc
    // ----------------------------------------------------------------------
    clear_inputs();
    id_valid       = 1'b1;
    id_ctrl.is_mret = 1'b1;
    enable_id_ex_csr_writer(CSR_RW, 5'd2, CSR_MEPC);
    check_outputs(1'b0, 1'b1, "MRET waits for ID/EX mepc write");

    id_ex.insn[31:20] = CSR_MSCRATCH;
    check_outputs(1'b0, 1'b0, "MRET ignores unrelated ID/EX CSR");

    id_ex.ctrl.csr_cmd = CSR_RS;
    id_ex.rs1          = 5'd0;
    id_ex.insn[31:20]  = CSR_MEPC;
    check_outputs(1'b0, 1'b0, "MRET ignores suppressed mepc write");

    id_ex.valid = 1'b0;
    enable_ex_mem_csr_writer(CSR_MEPC);
    check_outputs(1'b0, 1'b1, "MRET waits for EX/MEM mepc write");

    ex_mem.csr_addr = CSR_MCAUSE;
    check_outputs(1'b0, 1'b0, "MRET ignores unrelated EX/MEM CSR");

    // A writer already in MEM/WB commits as MRET advances into ID/EX, so it
    // must not add a third serialization bubble.
    ex_mem.valid      = 1'b0;
    mem_wb.valid      = 1'b1;
    mem_wb.csr_write  = 1'b1;
    mem_wb.csr_addr   = CSR_MEPC;
    check_outputs(1'b0, 1'b0, "MEM/WB mepc writer needs no stall");

    // Load-use and CSR dependency outputs retain their independent meanings;
    // stall_id is their OR reduction.
    clear_inputs();
    enable_id_consumer(1'b1, 1'b0);
    id_ctrl.csr_cmd = CSR_RW;
    enable_id_ex_load(id_rs1);
    enable_ex_mem_csr_writer(CSR_MSCRATCH);
    check_outputs(1'b1, 1'b1, "simultaneous load and CSR hazards");

    $display("tb_hazard_unit: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
