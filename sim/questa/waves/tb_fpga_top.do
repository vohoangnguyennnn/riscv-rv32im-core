# Gate 8 boundary: contained async reset event, synchronous SoC reset, and LEDs.
do sim/questa/waves/common.do

wave_divider {BOARD CLOCK / RESET}
wave_logic sim:/tb_fpga_top/clk
wave_logic sim:/tb_fpga_top/reset_n
wave_logic sim:/tb_fpga_top/dut/soc_rst

wave_divider {RESET SYNCHRONIZER}
wave_hex sim:/tb_fpga_top/dut/u_reset_sync/reset_pipe_q
wave_logic sim:/tb_fpga_top/dut/u_reset_sync/functional_rst_q

wave_divider {FPGA STATUS}
wave_hex   sim:/tb_fpga_top/dut/heartbeat_q
wave_logic sim:/tb_fpga_top/dut/test_done
wave_logic sim:/tb_fpga_top/dut/test_pass
wave_logic sim:/tb_fpga_top/dut/test_fail
wave_hex   sim:/tb_fpga_top/led

wave_divider {SOC / CORE EXECUTION}
wave_logic sim:/tb_fpga_top/dut/u_soc/trace_valid_o
wave_hex   sim:/tb_fpga_top/dut/u_soc/trace_pc_o
wave_hex   sim:/tb_fpga_top/dut/u_soc/trace_insn_o
wave_hex   sim:/tb_fpga_top/dut/u_soc/u_core/if_id_q
wave_hex   sim:/tb_fpga_top/dut/u_soc/u_core/id_ex_q
wave_hex   sim:/tb_fpga_top/dut/u_soc/u_core/ex_mem_q
wave_hex   sim:/tb_fpga_top/dut/u_soc/u_core/mem_wb_q

wave_finish
