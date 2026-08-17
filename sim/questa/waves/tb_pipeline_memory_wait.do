# Gate 4: request backpressure, delayed response, and older-memory priority.
do sim/questa/waves/common.do

wave_divider {CLOCK / RESET}
wave_logic sim:/tb_pipeline_memory_wait/clk
wave_logic sim:/tb_pipeline_memory_wait/rst

wave_divider {PIPELINE PACKETS}
wave_hex sim:/tb_pipeline_memory_wait/dut/id_ex_q
wave_hex sim:/tb_pipeline_memory_wait/dut/ex_mem_q
wave_hex sim:/tb_pipeline_memory_wait/dut/mem_wb_q

wave_divider {WAIT / HOLD POLICY}
wave_logic sim:/tb_pipeline_memory_wait/dut/load_use_hazard
wave_logic sim:/tb_pipeline_memory_wait/dut/ex_wait
wave_logic sim:/tb_pipeline_memory_wait/dut/mem_wait
wave_logic sim:/tb_pipeline_memory_wait/dut/pc_enable
wave_logic sim:/tb_pipeline_memory_wait/dut/if_id_enable
wave_logic sim:/tb_pipeline_memory_wait/dut/id_ex_enable
wave_logic sim:/tb_pipeline_memory_wait/dut/ex_mem_enable
wave_logic sim:/tb_pipeline_memory_wait/dut/mem_wb_flush

wave_divider {DATA MEMORY HANDSHAKE}
wave_logic sim:/tb_pipeline_memory_wait/dmem/req_valid
wave_logic sim:/tb_pipeline_memory_wait/dmem/req_ready
wave_hex   sim:/tb_pipeline_memory_wait/dmem/req_addr
wave_logic sim:/tb_pipeline_memory_wait/dmem/req_write
wave_logic sim:/tb_pipeline_memory_wait/dmem/rsp_valid
wave_logic sim:/tb_pipeline_memory_wait/dmem/rsp_err
wave_hex   sim:/tb_pipeline_memory_wait/dmem/rsp_rdata

wave_divider {RETIREMENT}
wave_logic sim:/tb_pipeline_memory_wait/trace_valid
wave_hex   sim:/tb_pipeline_memory_wait/trace_pc
wave_hex   sim:/tb_pipeline_memory_wait/trace_insn
wave_logic sim:/tb_pipeline_memory_wait/trace_rd_we
wave_hex   sim:/tb_pipeline_memory_wait/trace_rd_data

wave_finish
