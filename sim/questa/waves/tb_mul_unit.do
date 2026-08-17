# Gate 2: RV32M MUL/MULH/MULHSU/MULHU request/response and backpressure.
do sim/questa/waves/common.do

wave_divider {CLOCK / RESET}
wave_logic sim:/tb_mul_unit/clk
wave_logic sim:/tb_mul_unit/rst
wave_logic sim:/tb_mul_unit/kill

wave_divider {REQUEST}
wave_logic sim:/tb_mul_unit/req_valid
wave_logic sim:/tb_mul_unit/req_ready
wave_logic sim:/tb_mul_unit/op
wave_hex   sim:/tb_mul_unit/lhs
wave_hex   sim:/tb_mul_unit/rhs

wave_divider {MULTIPLIER STATE}
wave_logic sim:/tb_mul_unit/dut/state_q
wave_logic sim:/tb_mul_unit/dut/op_q
wave_hex   sim:/tb_mul_unit/dut/lhs_q
wave_hex   sim:/tb_mul_unit/dut/rhs_q
wave_hex   sim:/tb_mul_unit/dut/product

wave_divider {RESPONSE / BACKPRESSURE}
wave_logic sim:/tb_mul_unit/rsp_valid
wave_logic sim:/tb_mul_unit/rsp_ready
wave_hex   sim:/tb_mul_unit/result
wave_unsigned sim:/tb_mul_unit/checks

wave_finish
