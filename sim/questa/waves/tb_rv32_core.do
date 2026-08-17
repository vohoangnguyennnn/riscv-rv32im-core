# Gates 3-5: full five-stage pipeline and single architectural commit point.
do sim/questa/waves/common.do

wave_divider {CLOCK / RESET}
wave_logic sim:/tb_rv32_core/clk
wave_logic sim:/tb_rv32_core/rst

wave_divider {IF FETCH}
wave_logic sim:/tb_rv32_core/dut/fetch_valid
wave_hex   sim:/tb_rv32_core/dut/fetch_pc
wave_hex   sim:/tb_rv32_core/dut/fetch_insn
wave_logic sim:/tb_rv32_core/dut/fetch_consume

wave_divider {IF-ID-EX-MEM-WB PACKETS}
wave_hex sim:/tb_rv32_core/dut/if_id_q
wave_hex sim:/tb_rv32_core/dut/id_ex_q
wave_hex sim:/tb_rv32_core/dut/ex_mem_q
wave_hex sim:/tb_rv32_core/dut/mem_wb_q

wave_divider {STALL / FORWARD / FLUSH}
wave_logic sim:/tb_rv32_core/dut/load_use_hazard
wave_logic sim:/tb_rv32_core/dut/csr_dependency
wave_logic sim:/tb_rv32_core/dut/ex_wait
wave_logic sim:/tb_rv32_core/dut/mem_wait
wave_logic sim:/tb_rv32_core/dut/ex_fwd_a_sel
wave_logic sim:/tb_rv32_core/dut/ex_fwd_b_sel
wave_logic sim:/tb_rv32_core/dut/if_id_flush
wave_logic sim:/tb_rv32_core/dut/id_ex_flush

wave_divider {REDIRECT / TRAP}
wave_logic sim:/tb_rv32_core/dut/redirect_valid
wave_hex   sim:/tb_rv32_core/dut/redirect_pc
wave_logic sim:/tb_rv32_core/dut/wb_trap

wave_divider {ARCHITECTURAL COMMIT TRACE}
wave_logic sim:/tb_rv32_core/trace_valid
wave_hex   sim:/tb_rv32_core/trace_pc
wave_hex   sim:/tb_rv32_core/trace_insn
wave_logic sim:/tb_rv32_core/trace_rd_we
wave_unsigned sim:/tb_rv32_core/trace_rd_addr
wave_hex   sim:/tb_rv32_core/trace_rd_data
wave_hex   sim:/tb_rv32_core/trace_mem_addr
wave_hex   sim:/tb_rv32_core/trace_mem_wstrb
wave_hex   sim:/tb_rv32_core/trace_mem_wdata

wave_finish
