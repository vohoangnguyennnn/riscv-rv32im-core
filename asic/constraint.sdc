# Timing constraints for asic_core_top (same role as the .xdc in the FPGA flow).
# CLK_PERIOD_NS comes from the environment so `make asic-* CLK_PERIOD_NS=...`
# can sweep frequency without editing this file.
current_design asic_core_top

set clk_period [expr {[info exists ::env(CLK_PERIOD_NS)] ? $::env(CLK_PERIOD_NS) : 20.0}]
# The core talks to memory outside this block: assume 20% of the cycle is spent
# outside on each side of every I/O path.
set clk_io_pct 0.2

create_clock -name core_clk -period $clk_period [get_ports clk_i]

set_input_delay  [expr {$clk_period * $clk_io_pct}] -clock core_clk [delete_from_list [all_inputs] [get_ports clk_i]]
set_output_delay [expr {$clk_period * $clk_io_pct}] -clock core_clk [all_outputs]
