# Gate 5: Zicsr execution, serialized dependencies, counters, trap, and MRET.
do sim/questa/waves/common.do

wave_divider {CLOCK / RESET}
wave_logic sim:/tb_csr_core/clk
wave_logic sim:/tb_csr_core/rst

wave_divider {PIPELINE CSR FLOW}
wave_hex   sim:/tb_csr_core/dut/id_ex_q
wave_hex   sim:/tb_csr_core/dut/ex_mem_q
wave_hex   sim:/tb_csr_core/dut/mem_wb_q
wave_logic sim:/tb_csr_core/dut/csr_dependency
wave_hex   sim:/tb_csr_core/dut/csr_raddr
wave_hex   sim:/tb_csr_core/dut/csr_rdata
wave_logic sim:/tb_csr_core/dut/wb_csr_write

wave_divider {MACHINE CSR STATE}
wave_hex sim:/tb_csr_core/dut/u_csr_file/mtvec_q
wave_hex sim:/tb_csr_core/dut/u_csr_file/mepc_q
wave_hex sim:/tb_csr_core/dut/u_csr_file/mcause_q
wave_hex sim:/tb_csr_core/dut/u_csr_file/mtval_q
wave_hex sim:/tb_csr_core/dut/u_csr_file/mcycle_q
wave_hex sim:/tb_csr_core/dut/u_csr_file/minstret_q

wave_divider {TRAP / RETIREMENT}
wave_logic sim:/tb_csr_core/dut/wb_trap
wave_logic sim:/tb_csr_core/dut/redirect_valid
wave_hex   sim:/tb_csr_core/dut/redirect_pc
wave_logic sim:/tb_csr_core/trace_valid
wave_hex   sim:/tb_csr_core/trace_pc
wave_hex   sim:/tb_csr_core/trace_insn
wave_logic sim:/tb_csr_core/trace_trap
wave_unsigned sim:/tb_csr_core/trace_cause

wave_finish
