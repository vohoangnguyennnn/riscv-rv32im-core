# Gate 4: producer/consumer forwarding matrix and one-cycle load-use bubble.
do sim/questa/waves/common.do

wave_divider {CLOCK / RESET}
wave_logic sim:/tb_pipeline_forwarding/clk
wave_logic sim:/tb_pipeline_forwarding/rst

wave_divider {PIPELINE PACKETS IF-ID-EX-MEM-WB}
wave_hex sim:/tb_pipeline_forwarding/dut/if_id_q
wave_hex sim:/tb_pipeline_forwarding/dut/id_ex_q
wave_hex sim:/tb_pipeline_forwarding/dut/ex_mem_q
wave_hex sim:/tb_pipeline_forwarding/dut/mem_wb_q

wave_divider {FORWARDING DECISION}
wave_logic sim:/tb_pipeline_forwarding/dut/ex_fwd_a_sel
wave_logic sim:/tb_pipeline_forwarding/dut/ex_fwd_b_sel
wave_hex   sim:/tb_pipeline_forwarding/dut/ex_mem_fwd_value
wave_hex   sim:/tb_pipeline_forwarding/dut/mem_wb_fwd_value

wave_divider {HAZARD / BUBBLE}
wave_logic sim:/tb_pipeline_forwarding/dut/load_use_hazard
wave_logic sim:/tb_pipeline_forwarding/dut/pc_enable
wave_logic sim:/tb_pipeline_forwarding/dut/if_id_enable
wave_logic sim:/tb_pipeline_forwarding/dut/id_ex_flush

wave_divider {ARCHITECTURAL RETIREMENT}
wave_logic sim:/tb_pipeline_forwarding/trace_valid
wave_hex   sim:/tb_pipeline_forwarding/trace_pc
wave_hex   sim:/tb_pipeline_forwarding/trace_insn
wave_logic sim:/tb_pipeline_forwarding/trace_rd_we
wave_unsigned sim:/tb_pipeline_forwarding/trace_rd_addr
wave_hex   sim:/tb_pipeline_forwarding/trace_rd_data

wave_finish
