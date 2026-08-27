# Gate 5: precise MTIP injection, CSR-state serialization, trap drain, and MRET.
do sim/questa/waves/common.do

wave_divider {CLOCK / RESET / MTIP}
wave_logic sim:/tb_timer_interrupt_core/clk
wave_logic sim:/tb_timer_interrupt_core/rst
wave_logic sim:/tb_timer_interrupt_core/mtip

wave_divider {INTERRUPT ELIGIBILITY / INTERLOCK}
wave_logic sim:/tb_timer_interrupt_core/dut/mtimer_irq_eligible
wave_logic sim:/tb_timer_interrupt_core/dut/irq_state_wait
wave_logic sim:/tb_timer_interrupt_core/dut/irq_state_ambiguous
wave_logic sim:/tb_timer_interrupt_core/dut/id_ex_irq_state_writer
wave_logic sim:/tb_timer_interrupt_core/dut/ex_mem_irq_state_writer
wave_logic sim:/tb_timer_interrupt_core/dut/mem_wb_irq_state_writer
wave_logic sim:/tb_timer_interrupt_core/dut/id_interrupt_candidate
wave_logic sim:/tb_timer_interrupt_core/dut/id_interrupt

wave_divider {PIPELINE ORDERING}
wave_hex   sim:/tb_timer_interrupt_core/dut/id_ex_q
wave_hex   sim:/tb_timer_interrupt_core/dut/ex_mem_q
wave_hex   sim:/tb_timer_interrupt_core/dut/mem_wb_q
wave_logic sim:/tb_timer_interrupt_core/dut/ex_wait
wave_logic sim:/tb_timer_interrupt_core/dut/trap_drain
wave_logic sim:/tb_timer_interrupt_core/dut/redirect_valid
wave_hex   sim:/tb_timer_interrupt_core/dut/redirect_pc

wave_divider {MACHINE INTERRUPT STATE}
wave_hex sim:/tb_timer_interrupt_core/dut/u_csr_file/mstatus_q
wave_hex sim:/tb_timer_interrupt_core/dut/u_csr_file/mie_q
wave_hex sim:/tb_timer_interrupt_core/dut/u_csr_file/mepc_q
wave_hex sim:/tb_timer_interrupt_core/dut/u_csr_file/mcause_q

wave_divider {TRAP / MRET RETIREMENT}
wave_logic sim:/tb_timer_interrupt_core/trace_valid
wave_hex   sim:/tb_timer_interrupt_core/trace_pc
wave_hex   sim:/tb_timer_interrupt_core/trace_insn
wave_logic sim:/tb_timer_interrupt_core/trace_trap
wave_unsigned sim:/tb_timer_interrupt_core/trace_cause
wave_logic sim:/tb_timer_interrupt_core/trace_is_interrupt
wave_logic sim:/tb_timer_interrupt_core/trace_control
wave_logic sim:/tb_timer_interrupt_core/trace_taken
wave_hex   sim:/tb_timer_interrupt_core/trace_target

wave_finish
