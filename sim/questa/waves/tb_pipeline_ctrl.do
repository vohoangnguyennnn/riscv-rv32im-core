# Gate 2/4: centralized age-priority arbitration and flush/hold masks.
do sim/questa/waves/common.do

wave_divider {CLOCK / RESET}
wave_logic sim:/tb_pipeline_ctrl/clk
wave_logic sim:/tb_pipeline_ctrl/rst

wave_divider {CONTROL CAUSES}
wave_logic sim:/tb_pipeline_ctrl/load_use
wave_logic sim:/tb_pipeline_ctrl/csr_dep
wave_logic sim:/tb_pipeline_ctrl/ex_wait
wave_logic sim:/tb_pipeline_ctrl/mem_wait
wave_logic sim:/tb_pipeline_ctrl/id_exception
wave_logic sim:/tb_pipeline_ctrl/ex_exception
wave_logic sim:/tb_pipeline_ctrl/mem_exception
wave_logic sim:/tb_pipeline_ctrl/wb_trap
wave_hex   sim:/tb_pipeline_ctrl/control_redirect

wave_divider {SELECTED PRIORITY ACTION}
wave_logic sim:/tb_pipeline_ctrl/dut/action
wave_logic sim:/tb_pipeline_ctrl/trap_drain
wave_logic sim:/tb_pipeline_ctrl/redirect_valid
wave_hex   sim:/tb_pipeline_ctrl/redirect_pc

wave_divider {PIPELINE ENABLE MASK}
wave_logic sim:/tb_pipeline_ctrl/pc_enable
wave_logic sim:/tb_pipeline_ctrl/if_id_enable
wave_logic sim:/tb_pipeline_ctrl/id_ex_enable
wave_logic sim:/tb_pipeline_ctrl/ex_mem_enable
wave_logic sim:/tb_pipeline_ctrl/mem_wb_enable

wave_divider {PIPELINE FLUSH MASK}
wave_logic sim:/tb_pipeline_ctrl/if_id_flush
wave_logic sim:/tb_pipeline_ctrl/id_ex_flush
wave_logic sim:/tb_pipeline_ctrl/ex_mem_flush
wave_logic sim:/tb_pipeline_ctrl/mem_wb_flush

wave_finish
