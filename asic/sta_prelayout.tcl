# Pre-layout STA on the synthesized netlist (front-end timing check).
# No wires exist yet, so only cell delays count: results are optimistic and are
# used to find the critical path early, not to report final Fmax.
# Run via `make asic-sta` (needs `make asic-synth` first).

set netlist $::env(ASIC_NETLIST)
set pdk     /OpenROAD-flow-scripts/flow/platforms/sky130hd
set lib     $pdk/lib/sky130_fd_sc_hd__tt_025C_1v80.lib

# 0. OpenROAD needs the technology/cell LEF before a netlist can be read
#    (physical data; STA itself does not use it at this stage).
read_lef $pdk/lef/sky130_fd_sc_hd.tlef
read_lef $pdk/lef/sky130_fd_sc_hd_merged.lef
# 1. Timing library: delay/slew tables for every sky130 cell (tt, 25 C, 1.8 V).
read_liberty $lib
# 2. Gate-level netlist from synthesis, linked under its top module.
read_verilog $netlist
link_design asic_core_top
# 3. Constraints: same SDC the synthesis used.
read_sdc $::env(ASIC_SDC)

puts "\n==== Setup (max delay): worst path ===="
report_checks -path_delay max -format full_clock_expanded -fields {fanout} -digits 3

# The overall worst path may be an I/O path whose budget is an SDC guess;
# the register-to-register path is what sets the core's own Fmax.
puts "\n==== Setup: worst register-to-register path ===="
report_checks -path_delay max -from [all_registers -clock_pins] -to [all_registers -data_pins] -fields {fanout} -digits 3

puts "\n==== Hold (min delay): worst path ===="
report_checks -path_delay min -digits 3

puts "\n==== Top 10 setup endpoints ===="
report_checks -path_delay max -group_path_count 10 -endpoint_path_count 1 -format end -digits 3

puts "\n==== Summary ===="
report_wns -digits 3
report_tns -digits 3
report_worst_slack -max -digits 3
report_worst_slack -min -digits 3
