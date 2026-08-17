# Gates 4/5: EX redirect, two-younger squash, precise exception, trap, and MRET.
do sim/questa/waves/common.do

wave_divider {CLOCK / RESET}
wave_logic sim:/tb_pipeline_control/clk
wave_logic sim:/tb_pipeline_control/rst

wave_divider {PIPELINE PACKETS}
wave_hex sim:/tb_pipeline_control/dut/if_id_q
wave_hex sim:/tb_pipeline_control/dut/id_ex_q
wave_hex sim:/tb_pipeline_control/dut/ex_mem_q
wave_hex sim:/tb_pipeline_control/dut/mem_wb_q

wave_divider {REDIRECT / TWO-STAGE SQUASH}
wave_hex   sim:/tb_pipeline_control/dut/control_redirect
wave_logic sim:/tb_pipeline_control/dut/redirect_valid
wave_hex   sim:/tb_pipeline_control/dut/redirect_pc
wave_logic sim:/tb_pipeline_control/dut/if_id_flush
wave_logic sim:/tb_pipeline_control/dut/id_ex_flush
wave_logic sim:/tb_pipeline_control/dut/ex_mem_flush

wave_divider {PRECISE EXCEPTION PRIORITY}
wave_logic sim:/tb_pipeline_control/dut/id_exception
wave_logic sim:/tb_pipeline_control/dut/ex_exception
wave_logic sim:/tb_pipeline_control/dut/mem_exception
wave_logic sim:/tb_pipeline_control/dut/wb_trap
wave_logic sim:/tb_pipeline_control/dut/u_pipeline_ctrl/action
wave_logic sim:/tb_pipeline_control/dut/u_pipeline_ctrl/trap_drain_q

wave_divider {MACHINE CSR STATE}
wave_hex sim:/tb_pipeline_control/dut/csr_mtvec
wave_hex sim:/tb_pipeline_control/dut/csr_mepc
wave_hex sim:/tb_pipeline_control/dut/u_csr_file/mcause_q
wave_hex sim:/tb_pipeline_control/dut/u_csr_file/mtval_q

wave_divider {RETIREMENT / CONTROL TRACE}
wave_logic sim:/tb_pipeline_control/trace_valid
wave_hex   sim:/tb_pipeline_control/trace_pc
wave_hex   sim:/tb_pipeline_control/trace_insn
wave_logic sim:/tb_pipeline_control/trace_trap
wave_unsigned sim:/tb_pipeline_control/trace_cause
wave_logic sim:/tb_pipeline_control/trace_control
wave_logic sim:/tb_pipeline_control/trace_taken
wave_hex   sim:/tb_pipeline_control/trace_target

wave_finish
