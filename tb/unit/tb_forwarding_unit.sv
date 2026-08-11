// SPDX-License-Identifier: MIT

module tb_forwarding_unit;

  timeunit 1ns;
  timeprecision 1ps;

  import rv32_pkg::*;

  id_ex_t  id_ex;
  ex_mem_t ex_mem;
  mem_wb_t mem_wb;
  fwd_sel_e ex_a_sel;
  fwd_sel_e ex_b_sel;
  int checks;

  forwarding_unit dut (
    .id_ex_i    (id_ex),
    .ex_mem_i   (ex_mem),
    .mem_wb_i   (mem_wb),
    .ex_a_sel_o (ex_a_sel),
    .ex_b_sel_o (ex_b_sel)
  );

  task automatic clear_inputs;
    begin
      id_ex = '0;
      ex_mem = '0;
      mem_wb = '0;

      // Use non-zero register numbers so a test must explicitly opt into x0.
      id_ex.rs1 = 5'd3;
      id_ex.rs2 = 5'd4;
      ex_mem.rd = 5'd5;
      mem_wb.rd = 5'd6;
      #1ps;
    end
  endtask

  task automatic check_selects(
    input fwd_sel_e expected_a,
    input fwd_sel_e expected_b,
    input string    test_name
  );
    begin
      #1ps;
      if ((ex_a_sel !== expected_a) || (ex_b_sel !== expected_b)) begin
        $fatal(
          1,
          "%s mismatch: A expected=%0d result=%0d, B expected=%0d result=%0d",
          test_name,
          expected_a,
          ex_a_sel,
          expected_b,
          ex_b_sel
        );
      end
      checks++;
    end
  endtask

  task automatic enable_consumer;
    begin
      id_ex.valid         = 1'b1;
      id_ex.ctrl.uses_rs1 = 1'b1;
      id_ex.ctrl.uses_rs2 = 1'b1;
    end
  endtask

  task automatic enable_ex_mem_producer(
    input reg_addr_t rd,
    input wb_sel_e   wb_sel
  );
    begin
      ex_mem.valid     = 1'b1;
      ex_mem.reg_write = 1'b1;
      ex_mem.rd        = rd;
      ex_mem.wb_sel    = wb_sel;
    end
  endtask

  task automatic enable_mem_wb_producer(input reg_addr_t rd);
    begin
      mem_wb.valid     = 1'b1;
      mem_wb.reg_write = 1'b1;
      mem_wb.rd        = rd;
    end
  endtask

  initial begin
    checks = 0;

    clear_inputs();
    check_selects(FWD_REGFILE, FWD_REGFILE, "all packets invalid");

    // Invalid consumers must produce benign selects even when all register
    // metadata happens to match a valid producer.
    enable_ex_mem_producer(id_ex.rs1, WB_EX_RESULT);
    enable_mem_wb_producer(id_ex.rs2);
    check_selects(FWD_REGFILE, FWD_REGFILE, "invalid consumer");

    clear_inputs();
    enable_consumer();
    enable_ex_mem_producer(id_ex.rs1, WB_EX_RESULT);
    check_selects(FWD_EX_MEM, FWD_REGFILE, "EX/MEM to rs1");

    ex_mem.rd = id_ex.rs2;
    check_selects(FWD_REGFILE, FWD_EX_MEM, "EX/MEM to rs2");

    id_ex.rs2 = id_ex.rs1;
    ex_mem.rd = id_ex.rs1;
    check_selects(FWD_EX_MEM, FWD_EX_MEM, "EX/MEM to both sources");

    clear_inputs();
    enable_consumer();
    enable_mem_wb_producer(id_ex.rs1);
    check_selects(FWD_MEM_WB, FWD_REGFILE, "MEM/WB to rs1");

    mem_wb.rd = id_ex.rs2;
    check_selects(FWD_REGFILE, FWD_MEM_WB, "MEM/WB to rs2");

    id_ex.rs2 = id_ex.rs1;
    mem_wb.rd = id_ex.rs1;
    check_selects(FWD_MEM_WB, FWD_MEM_WB, "MEM/WB to both sources");

    // When both producers target the same register, the younger EX/MEM value
    // must win.  This is the classic back-to-back overwrite case.
    clear_inputs();
    enable_consumer();
    enable_ex_mem_producer(id_ex.rs1, WB_EX_RESULT);
    enable_mem_wb_producer(id_ex.rs1);
    check_selects(FWD_EX_MEM, FWD_REGFILE, "EX/MEM priority over MEM/WB");

    // Selection is independent per operand.
    ex_mem.rd = id_ex.rs1;
    mem_wb.rd = id_ex.rs2;
    check_selects(FWD_EX_MEM, FWD_MEM_WB, "independent producer selection");

    // EX/MEM load data is not ready.  The normal load-use interlock prevents
    // this state architecturally; the selector still follows the documented
    // priority chain and may select an older matching MEM/WB value.
    ex_mem.wb_sel = WB_LOAD;
    mem_wb.rd     = id_ex.rs1;
    check_selects(FWD_MEM_WB, FWD_REGFILE, "EX/MEM load excluded");

    mem_wb.valid = 1'b0;
    check_selects(FWD_REGFILE, FWD_REGFILE, "load without MEM/WB fallback");

    // Every non-load EX/MEM writeback class is forwardable.
    ex_mem.wb_sel = WB_PC4;
    check_selects(FWD_EX_MEM, FWD_REGFILE, "PC+4 producer ready");

    ex_mem.wb_sel = WB_CSR;
    check_selects(FWD_EX_MEM, FWD_REGFILE, "CSR-old producer ready");

    // A producer with no architectural write cannot forward.
    ex_mem.reg_write = 1'b0;
    check_selects(FWD_REGFILE, FWD_REGFILE, "EX/MEM reg_write disabled");

    clear_inputs();
    enable_consumer();
    enable_mem_wb_producer(id_ex.rs1);
    mem_wb.reg_write = 1'b0;
    check_selects(FWD_REGFILE, FWD_REGFILE, "MEM/WB reg_write disabled");

    // x0 never has a producer, even if malformed metadata claims a write.
    clear_inputs();
    enable_consumer();
    id_ex.rs1 = 5'd0;
    id_ex.rs2 = 5'd0;
    enable_ex_mem_producer(5'd0, WB_EX_RESULT);
    enable_mem_wb_producer(5'd0);
    check_selects(FWD_REGFILE, FWD_REGFILE, "x0 producer suppressed");

    // Faulting producers cannot provide architectural values.  If EX/MEM is
    // faulting, an older valid MEM/WB producer remains eligible by the defined
    // priority chain.
    clear_inputs();
    enable_consumer();
    enable_ex_mem_producer(id_ex.rs1, WB_EX_RESULT);
    enable_mem_wb_producer(id_ex.rs1);
    ex_mem.exc.valid = 1'b1;
    check_selects(FWD_MEM_WB, FWD_REGFILE, "EX/MEM exception excluded");

    ex_mem.valid     = 1'b0;
    mem_wb.exc.valid = 1'b1;
    check_selects(FWD_REGFILE, FWD_REGFILE, "MEM/WB exception excluded");

    // Encoded rs fields are not dependencies unless uses_rs1/uses_rs2 says so.
    clear_inputs();
    enable_consumer();
    enable_ex_mem_producer(id_ex.rs1, WB_EX_RESULT);
    enable_mem_wb_producer(id_ex.rs2);
    id_ex.ctrl.uses_rs1 = 1'b0;
    id_ex.ctrl.uses_rs2 = 1'b0;
    check_selects(FWD_REGFILE, FWD_REGFILE, "unused source fields ignored");

    id_ex.ctrl.uses_rs1 = 1'b1;
    check_selects(FWD_EX_MEM, FWD_REGFILE, "rs1 usage enabled independently");

    id_ex.ctrl.uses_rs1 = 1'b0;
    id_ex.ctrl.uses_rs2 = 1'b1;
    check_selects(FWD_REGFILE, FWD_MEM_WB, "rs2 usage enabled independently");

    // An exception-carrying consumer has no remaining architectural work and
    // therefore keeps both forwarding muxes on their benign defaults.
    id_ex.exc.valid = 1'b1;
    check_selects(FWD_REGFILE, FWD_REGFILE, "faulting consumer suppressed");

    $display("tb_forwarding_unit: PASS (%0d checks)", checks);
    $finish;
  end

endmodule
