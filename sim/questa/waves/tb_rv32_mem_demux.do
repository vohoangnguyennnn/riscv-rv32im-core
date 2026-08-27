# SoC fabric appendix: one-outstanding ownership and zero-bubble target changes.
do sim/questa/waves/common.do

wave_divider {CLOCK / RESET}
wave_logic sim:/tb_rv32_mem_demux/clk
wave_logic sim:/tb_rv32_mem_demux/rst

wave_divider {CORE REQUEST / RESPONSE}
wave_logic sim:/tb_rv32_mem_demux/core/req_valid
wave_logic sim:/tb_rv32_mem_demux/core/req_ready
wave_hex   sim:/tb_rv32_mem_demux/core/req_addr
wave_logic sim:/tb_rv32_mem_demux/core/rsp_valid
wave_hex   sim:/tb_rv32_mem_demux/core/rsp_rdata
wave_logic sim:/tb_rv32_mem_demux/core/rsp_err

wave_divider {DECODE / PENDING OWNER}
wave_unsigned sim:/tb_rv32_mem_demux/dut/request_target
wave_logic    sim:/tb_rv32_mem_demux/dut/request_fire
wave_logic    sim:/tb_rv32_mem_demux/dut/pending_q
wave_unsigned sim:/tb_rv32_mem_demux/dut/pending_target_q
wave_logic    sim:/tb_rv32_mem_demux/dut/response_seen

wave_divider {ONE-HOT SLAVE REQUESTS}
wave_logic sim:/tb_rv32_mem_demux/tcm/req_valid
wave_logic sim:/tb_rv32_mem_demux/timer/req_valid
wave_logic sim:/tb_rv32_mem_demux/uart/req_valid
wave_logic sim:/tb_rv32_mem_demux/gpio/req_valid

wave_divider {SLAVE RESPONSES}
wave_logic sim:/tb_rv32_mem_demux/tcm/rsp_valid
wave_logic sim:/tb_rv32_mem_demux/timer/rsp_valid
wave_logic sim:/tb_rv32_mem_demux/uart/rsp_valid
wave_logic sim:/tb_rv32_mem_demux/gpio/rsp_valid

wave_finish
