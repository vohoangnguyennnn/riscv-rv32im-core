# Gate 2: little-endian byte lanes, load extraction, alignment, and bus errors.
do sim/questa/waves/common.do

wave_divider {CLOCK / RESET}
wave_logic sim:/tb_lsu/clk
wave_logic sim:/tb_lsu/rst
wave_logic sim:/tb_lsu/kill

wave_divider {ARCHITECTURAL REQUEST}
wave_logic sim:/tb_lsu/req_valid
wave_logic sim:/tb_lsu/req_ready
wave_logic sim:/tb_lsu/cmd
wave_logic sim:/tb_lsu/size
wave_logic sim:/tb_lsu/load_unsigned
wave_hex   sim:/tb_lsu/addr
wave_hex   sim:/tb_lsu/store_data

wave_divider {LSU / MEMORY HANDSHAKE}
wave_logic sim:/tb_lsu/dut/state_q
wave_logic sim:/tb_lsu/dmem/req_valid
wave_logic sim:/tb_lsu/dmem/req_ready
wave_hex   sim:/tb_lsu/dmem/req_addr
wave_logic sim:/tb_lsu/dmem/req_write
wave_hex   sim:/tb_lsu/dmem/req_wstrb
wave_hex   sim:/tb_lsu/dmem/req_wdata
wave_logic sim:/tb_lsu/dmem/rsp_valid
wave_logic sim:/tb_lsu/dmem/rsp_err
wave_hex   sim:/tb_lsu/dmem/rsp_rdata

wave_divider {ARCHITECTURAL RESPONSE}
wave_logic sim:/tb_lsu/rsp_valid
wave_logic sim:/tb_lsu/rsp_ready
wave_hex   sim:/tb_lsu/load_data
wave_hex   sim:/tb_lsu/exception
wave_hex   sim:/tb_lsu/trace_wstrb
wave_hex   sim:/tb_lsu/trace_wdata

wave_finish
