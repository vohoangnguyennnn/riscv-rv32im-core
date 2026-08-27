# Gate 8 boundary: Harvard core ports over dual-port TCM and completion mailbox.
do sim/questa/waves/common.do

wave_divider {CLOCK / RESET}
wave_logic sim:/tb_soc_tcm_top/clk
wave_logic sim:/tb_soc_tcm_top/rst
wave_unsigned sim:/tb_soc_tcm_top/phase

wave_divider {SOC COMPLETION MAILBOX}
wave_logic sim:/tb_soc_tcm_top/dut/test_status_commit
wave_logic sim:/tb_soc_tcm_top/test_done
wave_logic sim:/tb_soc_tcm_top/test_pass
wave_logic sim:/tb_soc_tcm_top/test_fail
wave_hex   sim:/tb_soc_tcm_top/test_status

wave_divider {CORE PIPELINE}
wave_hex sim:/tb_soc_tcm_top/dut/u_core/if_id_q
wave_hex sim:/tb_soc_tcm_top/dut/u_core/id_ex_q
wave_hex sim:/tb_soc_tcm_top/dut/u_core/ex_mem_q
wave_hex sim:/tb_soc_tcm_top/dut/u_core/mem_wb_q

wave_divider {INSTRUCTION TCM PORT}
wave_logic sim:/tb_soc_tcm_top/dut/imem/req_valid
wave_logic sim:/tb_soc_tcm_top/dut/imem/req_ready
wave_hex   sim:/tb_soc_tcm_top/dut/imem/req_addr
wave_logic sim:/tb_soc_tcm_top/dut/imem/rsp_valid
wave_hex   sim:/tb_soc_tcm_top/dut/imem/rsp_rdata

wave_divider {CORE DATA PORT}
wave_logic sim:/tb_soc_tcm_top/dut/core_dmem/req_valid
wave_logic sim:/tb_soc_tcm_top/dut/core_dmem/req_ready
wave_hex   sim:/tb_soc_tcm_top/dut/core_dmem/req_addr
wave_logic sim:/tb_soc_tcm_top/dut/core_dmem/req_write
wave_hex   sim:/tb_soc_tcm_top/dut/core_dmem/req_wstrb
wave_hex   sim:/tb_soc_tcm_top/dut/core_dmem/req_wdata
wave_logic sim:/tb_soc_tcm_top/dut/core_dmem/rsp_valid
wave_hex   sim:/tb_soc_tcm_top/dut/core_dmem/rsp_rdata

wave_divider {DEMUX OWNERSHIP / SLAVE SELECT}
wave_unsigned sim:/tb_soc_tcm_top/dut/u_dmem_demux/request_target
wave_logic    sim:/tb_soc_tcm_top/dut/u_dmem_demux/request_fire
wave_logic    sim:/tb_soc_tcm_top/dut/u_dmem_demux/pending_q
wave_unsigned sim:/tb_soc_tcm_top/dut/u_dmem_demux/pending_target_q
wave_logic    sim:/tb_soc_tcm_top/dut/u_dmem_demux/response_seen
wave_logic sim:/tb_soc_tcm_top/dut/tcm_dmem/req_valid
wave_logic sim:/tb_soc_tcm_top/dut/timer_bus/req_valid
wave_logic sim:/tb_soc_tcm_top/dut/uart_bus/req_valid
wave_logic sim:/tb_soc_tcm_top/dut/gpio_bus/req_valid

wave_divider {RETIREMENT}
wave_logic sim:/tb_soc_tcm_top/trace_valid
wave_hex   sim:/tb_soc_tcm_top/trace_pc
wave_hex   sim:/tb_soc_tcm_top/trace_insn
wave_hex   sim:/tb_soc_tcm_top/trace_mem_addr
wave_hex   sim:/tb_soc_tcm_top/trace_mem_wstrb
wave_hex   sim:/tb_soc_tcm_top/trace_mem_wdata

wave_finish
