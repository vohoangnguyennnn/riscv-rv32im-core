# Reproducible zoom windows measured from the current self-checking tests.
# Source this file after a test-specific waveform recipe has finished:
#   do sim/questa/waves/capture_ranges.do
#   rv32_zoom forwarding_load_use

proc rv32_zoom {case_name} {
  switch -- $case_name {
    pipeline_retirement { wave zoom range 780ns 930ns }
    forwarding_load_use { wave zoom range 1120ns 1220ns }
    memory_backpressure { wave zoom range 70ns 180ns }
    branch_redirect     { wave zoom range 115ns 175ns }
    trap_mret           { wave zoom range 375ns 535ns }

    timer_enable_mret   { wave zoom range 105ns 265ns }
    timer_div_race      { wave zoom range 690ns 1135ns }
    timer_redirect_race { wave zoom range 1310ns 1410ns }
    timer_sync_priority { wave zoom range 1620ns 1690ns }
    timer_trap_drain    { wave zoom range 1815ns 1870ns }

    demux_back_to_back  { wave zoom range 140ns 195ns }
    lsu_reset_drain     { wave zoom range 750ns 840ns }
    divider_iteration  { wave zoom range 270ns 640ns }

    freertos_mtip_entry { wave zoom range 1059580ns 1059780ns }
    freertos_mret       { wave zoom range 1065700ns 1065900ns }
    freertos_gpio       { wave zoom range 648430ns 648570ns }
    freertos_uart_echo  { wave zoom range 690000ns 1130000ns }
    freertos_completion { wave zoom range 4066600ns 4066780ns }

    default {
      puts "unknown capture case: $case_name"
      rv32_zoom_list
      return -code error
    }
  }
}

proc rv32_zoom_list {} {
  puts "pipeline_retirement  forwarding_load_use  memory_backpressure"
  puts "branch_redirect      trap_mret"
  puts "timer_enable_mret    timer_div_race         timer_redirect_race"
  puts "timer_sync_priority  timer_trap_drain"
  puts "demux_back_to_back   lsu_reset_drain        divider_iteration"
  puts "freertos_mtip_entry  freertos_mret          freertos_gpio"
  puts "freertos_uart_echo   freertos_completion"
}
