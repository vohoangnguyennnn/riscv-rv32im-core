# Gate 2: restoring divider latency, special cases, kill, and sticky response.
do sim/questa/waves/common.do

wave_divider {CLOCK / RESET}
wave_logic sim:/tb_div_unit/clk
wave_logic sim:/tb_div_unit/rst
wave_logic sim:/tb_div_unit/kill

wave_divider {REQUEST}
wave_logic sim:/tb_div_unit/req_valid
wave_logic sim:/tb_div_unit/req_ready
wave_logic sim:/tb_div_unit/op
wave_hex   sim:/tb_div_unit/lhs
wave_hex   sim:/tb_div_unit/rhs

wave_divider {RESTORING ITERATION}
wave_logic    sim:/tb_div_unit/dut/state_q
wave_logic    sim:/tb_div_unit/dut/op_q
wave_unsigned sim:/tb_div_unit/dut/iter_q
wave_hex      sim:/tb_div_unit/dut/divisor_q
wave_hex      sim:/tb_div_unit/dut/quotient_q
wave_hex      sim:/tb_div_unit/dut/remainder_q

wave_divider {RESPONSE / BACKPRESSURE}
wave_logic sim:/tb_div_unit/rsp_valid
wave_logic sim:/tb_div_unit/rsp_ready
wave_hex   sim:/tb_div_unit/result
wave_unsigned sim:/tb_div_unit/checks

wave_finish
