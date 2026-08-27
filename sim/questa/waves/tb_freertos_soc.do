# End-to-end FreeRTOS bring-up: MTIP/ECALL trap return, task switching,
# GPIO blink, UART ready/echo, and retirement-qualified completion.
do sim/questa/waves/common.do

wave_divider {CLOCK / RESET}
wave_logic sim:/tb_freertos_soc/clk
wave_logic sim:/tb_freertos_soc/rst

wave_divider {SCHEDULER TRAPS}
wave_unsigned sim:/tb_freertos_soc/cycles
wave_unsigned sim:/tb_freertos_soc/timer_traps
wave_unsigned sim:/tb_freertos_soc/yield_traps
wave_unsigned sim:/tb_freertos_soc/mret_retirements
wave_logic sim:/tb_freertos_soc/dut/mtip
wave_logic sim:/tb_freertos_soc/trace_trap
wave_unsigned sim:/tb_freertos_soc/trace_cause
wave_logic sim:/tb_freertos_soc/trace_is_interrupt
wave_hex sim:/tb_freertos_soc/trace_pc
wave_hex sim:/tb_freertos_soc/trace_insn

wave_divider {MACHINE INTERRUPT STATE}
wave_logic sim:/tb_freertos_soc/dut/u_core/mtimer_irq_eligible
wave_logic sim:/tb_freertos_soc/dut/u_core/id_interrupt_candidate
wave_logic sim:/tb_freertos_soc/dut/u_core/trap_drain
wave_hex sim:/tb_freertos_soc/dut/u_core/u_csr_file/mstatus_q
wave_hex sim:/tb_freertos_soc/dut/u_core/u_csr_file/mie_q
wave_hex sim:/tb_freertos_soc/dut/u_core/u_csr_file/mepc_q
wave_hex sim:/tb_freertos_soc/dut/u_core/u_csr_file/mcause_q

wave_divider {UART / GPIO}
wave_logic sim:/tb_freertos_soc/uart_rx
wave_logic sim:/tb_freertos_soc/uart_tx
wave_hex sim:/tb_freertos_soc/gpio_out
wave_hex sim:/tb_freertos_soc/gpio_oe
wave_unsigned sim:/tb_freertos_soc/gpio_transitions

wave_divider {MMIO RETIREMENT}
wave_logic sim:/tb_freertos_soc/trace_valid
wave_hex sim:/tb_freertos_soc/trace_mem_addr
wave_hex sim:/tb_freertos_soc/trace_mem_wstrb
wave_hex sim:/tb_freertos_soc/trace_mem_wdata

wave_divider {COMPLETION}
wave_logic sim:/tb_freertos_soc/test_done
wave_logic sim:/tb_freertos_soc/test_pass
wave_logic sim:/tb_freertos_soc/test_fail
wave_hex sim:/tb_freertos_soc/test_status

wave_finish
