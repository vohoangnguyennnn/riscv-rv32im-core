# Gates 4/5: EX redirect, two-younger squash, precise exception, trap, and MRET.
do sim/questa/waves/common.do

wave_divider {CLOCK / RESET}
wave_logic sim:/tb_core_control_flow/clk
wave_logic sim:/tb_core_control_flow/rst

wave_divider {PIPELINE PACKETS}
wave_hex sim:/tb_core_control_flow/dut/if_id_q
wave_hex sim:/tb_core_control_flow/dut/id_ex_q
wave_hex sim:/tb_core_control_flow/dut/ex_mem_q
wave_hex sim:/tb_core_control_flow/dut/mem_wb_q

wave_divider {REDIRECT / TWO-STAGE SQUASH}
wave_hex   sim:/tb_core_control_flow/dut/control_redirect
wave_logic sim:/tb_core_control_flow/dut/redirect_valid
wave_hex   sim:/tb_core_control_flow/dut/redirect_pc
wave_logic sim:/tb_core_control_flow/dut/if_id_flush
wave_logic sim:/tb_core_control_flow/dut/id_ex_flush
wave_logic sim:/tb_core_control_flow/dut/ex_mem_flush

wave_divider {PRECISE EXCEPTION PRIORITY}
wave_logic sim:/tb_core_control_flow/dut/id_exception
wave_logic sim:/tb_core_control_flow/dut/ex_exception
wave_logic sim:/tb_core_control_flow/dut/mem_exception
wave_logic sim:/tb_core_control_flow/dut/wb_trap
wave_logic sim:/tb_core_control_flow/dut/u_pipeline_ctrl/action
wave_logic sim:/tb_core_control_flow/dut/u_pipeline_ctrl/trap_drain_q

wave_divider {MACHINE CSR STATE}
wave_hex sim:/tb_core_control_flow/dut/csr_mtvec
wave_hex sim:/tb_core_control_flow/dut/csr_mepc
wave_hex sim:/tb_core_control_flow/dut/u_csr_file/mcause_q
wave_hex sim:/tb_core_control_flow/dut/u_csr_file/mtval_q

wave_divider {RETIREMENT / CONTROL TRACE}
wave_logic sim:/tb_core_control_flow/trace_valid
wave_hex   sim:/tb_core_control_flow/trace_pc
wave_hex   sim:/tb_core_control_flow/trace_insn
wave_logic sim:/tb_core_control_flow/trace_trap
wave_unsigned sim:/tb_core_control_flow/trace_cause
wave_logic sim:/tb_core_control_flow/trace_control
wave_logic sim:/tb_core_control_flow/trace_taken
wave_hex   sim:/tb_core_control_flow/trace_target

wave_finish
