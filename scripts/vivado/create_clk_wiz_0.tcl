# Recreate the FPGA-only 50 MHz to 75 MHz Clocking Wizard IP in an open project.

if {[llength [get_projects -quiet]] == 0} {
  error "Open or create the Vivado project before sourcing create_clk_wiz_0.tcl."
}

if {[llength [get_ips -quiet clk_wiz_0]] == 0} {
  create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_0
}

set_property -dict [list \
  CONFIG.PRIM_SOURCE {Single_ended_clock_capable_pin} \
  CONFIG.PRIM_IN_FREQ {50.000} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {75.000} \
  CONFIG.CLKOUT1_REQUESTED_PHASE {0.000} \
  CONFIG.CLKOUT1_REQUESTED_DUTY_CYCLE {50.000} \
  CONFIG.USE_RESET {true} \
  CONFIG.RESET_TYPE {ACTIVE_HIGH} \
  CONFIG.USE_LOCKED {true} \
] [get_ips clk_wiz_0]

generate_target all [get_ips clk_wiz_0]
