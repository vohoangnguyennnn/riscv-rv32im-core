# MicroPhase A7-Lite R1.1 constraints for rtl/fpga/fpga_top.sv.
#
# Board references:
#   https://fpga-docs.microphase.cn/en/latest/DEV_BOARD/A7-LITE/A7-Lite_Reference_Manual.html
#   https://github.com/MicroPhase/fpga-docs/blob/master/schematic/A7-LITE_R11.pdf
#
# Target package: Xilinx Artix-7 XC7A35T FGG484, speed grade -1

# The A7-Lite configuration interface uses a 3.3 V configuration bank. These
# properties let Vivado validate bank-0 voltage compatibility and remove the
# CFGBVS-1 implementation DRC warning.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# -----------------------------------------------------------------------------
# 50 MHz single-ended board oscillator (U10, CLK_50M)
# -----------------------------------------------------------------------------

set_property -dict {PACKAGE_PIN J19 IOSTANDARD LVCMOS33} [get_ports {clk_50m_i}]
create_clock -add -name clk_50m -period 20.000 -waveform {0.000 10.000} \
  [get_ports {clk_50m_i}]

# -----------------------------------------------------------------------------
# Board reset button K3
# -----------------------------------------------------------------------------

set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports {reset_ni}]
set_false_path -from [get_ports {reset_ni}]

# -----------------------------------------------------------------------------
# Status outputs
# -----------------------------------------------------------------------------

# fpga_top performs the required inversion and exposes explicit active-low
# port names:
#   led1_n_o -> D6 / LED1: running heartbeat
#   led2_n_o -> D5 / LED2: software PASS
set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} \
  [get_ports {led1_n_o}]
set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} \
  [get_ports {led2_n_o}]

# The RTL exposes four status bits while A7-Lite provides only two on-board
# LEDs. Route the remaining signals to the fixed-3.3-V JP2 header:
#   fail_o -> JP2 pin 1 / GPIO2_0P: software FAIL
#   done_o -> JP2 pin 2 / GPIO2_0N: software DONE
# Connect an external active-high LED (FPGA pin -> resistor -> LED -> GND), a
# logic analyzer, or an oscilloscope to observe these two outputs.
set_property -dict {PACKAGE_PIN W21 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} \
  [get_ports {fail_o}]
set_property -dict {PACKAGE_PIN W22 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} \
  [get_ports {done_o}]

# Status LEDs/GPIO are human-observable asynchronous indicators and are not
# captured by an external clocked interface, so an output-delay constraint is
# not applicable. Exclude only these output paths from timing analysis.
set_false_path -to [get_ports {led1_n_o}]
set_false_path -to [get_ports {led2_n_o}]
set_false_path -to [get_ports {fail_o}]
set_false_path -to [get_ports {done_o}]
