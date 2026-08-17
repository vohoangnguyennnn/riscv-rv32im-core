# SPDX-License-Identifier: MIT

# Shared, intentionally small GUI policy. Signal selection stays in each
# test-specific file so every screenshot has an explicit verification purpose.
onerror {resume}
onfinish stop

view wave
view structure
view signals
quietly WaveActivateNextPane {} 0

proc wave_divider {label} {
  add wave -noupdate -divider $label
}

proc wave_logic {path} {
  if {[catch {add wave -noupdate $path} reason]} {
    puts "WAVE NOTE: skipped $path ($reason)"
  }
}

proc wave_hex {path} {
  if {[catch {add wave -noupdate -radix hexadecimal $path} reason]} {
    puts "WAVE NOTE: skipped $path ($reason)"
  }
}

proc wave_unsigned {path} {
  if {[catch {add wave -noupdate -radix unsigned $path} reason]} {
    puts "WAVE NOTE: skipped $path ($reason)"
  }
}

proc wave_finish {} {
  configure wave -namecolwidth 300
  configure wave -valuecolwidth 140
  configure wave -justifyvalue left
  configure wave -timelineunits ns
  configure wave -gridperiod 10
  configure wave -griddelta 40
  configure wave -rowmargin 4
  update
  run -all
  wave zoom full
}
