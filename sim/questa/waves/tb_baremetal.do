# Gates 5/6: software execution viewed at the architectural retirement boundary.
do sim/questa/waves/common.do

wave_divider {CLOCK / RESET}
wave_logic sim:/tb_baremetal/clk
wave_logic sim:/tb_baremetal/rst

wave_divider {PIPELINE}
wave_hex sim:/tb_baremetal/dut/if_id_q
wave_hex sim:/tb_baremetal/dut/id_ex_q
wave_hex sim:/tb_baremetal/dut/ex_mem_q
wave_hex sim:/tb_baremetal/dut/mem_wb_q
wave_logic sim:/tb_baremetal/dut/ex_wait
wave_logic sim:/tb_baremetal/dut/mem_wait
wave_logic sim:/tb_baremetal/dut/redirect_valid
wave_hex   sim:/tb_baremetal/dut/redirect_pc

wave_divider {ARCHITECTURAL RETIREMENT}
wave_logic sim:/tb_baremetal/trace_valid
wave_hex   sim:/tb_baremetal/trace_pc
wave_hex   sim:/tb_baremetal/trace_insn
wave_logic sim:/tb_baremetal/trace_rd_we
wave_unsigned sim:/tb_baremetal/trace_rd_addr
wave_hex   sim:/tb_baremetal/trace_rd_data
wave_hex   sim:/tb_baremetal/trace_mem_addr
wave_hex   sim:/tb_baremetal/trace_mem_wstrb
wave_hex   sim:/tb_baremetal/trace_mem_wdata
wave_logic sim:/tb_baremetal/trace_trap
wave_unsigned sim:/tb_baremetal/trace_cause

wave_divider {HARNESS STATUS}
wave_unsigned sim:/tb_baremetal/cycles
wave_unsigned sim:/tb_baremetal/trace_events
wave_unsigned sim:/tb_baremetal/trap_count

wave_finish
