# Collect a self-contained Vivado implementation review package.
# Run from an open Vivado project after impl_1 has completed:
#   source {/absolute/path/to/scripts/vivado/collect_impl_reports.tcl}
# Output defaults to Report_vivado/<timestamp>/ in the repository root.

proc write_text_file {path body} {
  set channel [open $path w]
  puts $channel $body
  close $channel
}

proc safe_property {object property} {
  if {[catch {get_property $property $object} value]} {
    return "<unavailable>"
  }
  if {$value eq ""} {
    return "<unset>"
  }
  return $value
}

proc safe_exec {args} {
  if {[catch {exec {*}$args} value]} {
    return "<unavailable: $value>"
  }
  return [string trim $value]
}

proc sha256_file {path} {
  if {![file isfile $path]} {
    return "<missing>"
  }
  set result [safe_exec sha256sum $path]
  if {[regexp {^([0-9a-fA-F]{64})} $result -> digest]} {
    return [string tolower $digest]
  }
  return $result
}

proc copy_and_record_artifact {source destination_dir manifest_channel label} {
  if {![file isfile $source]} {
    puts $manifest_channel [format "%-24s MISSING  %s" $label $source]
    return
  }
  file mkdir $destination_dir
  set destination [file join $destination_dir [file tail $source]]
  if {[file normalize $source] ne [file normalize $destination]} {
    file copy -force $source $destination
  }
  puts $manifest_channel [format "%-24s %s  %s" \
    $label [sha256_file $destination] [file tail $destination]]
}

proc run_report {name command} {
  puts "INFO: generating $name"
  if {[catch {uplevel #0 $command} message options]} {
    write_text_file [file join $::report_dir "${name}.error.txt"] \
      "COMMAND: $command\nERROR: $message\nOPTIONS: $options"
    puts "WARNING: $name failed: $message"
  }
}

proc dump_object_properties {path object} {
  set channel [open $path w]
  foreach property [lsort [list_property $object]] {
    if {[catch {get_property $property $object} value]} {
      set value "<unavailable>"
    }
    puts $channel [format "%-40s %s" $property $value]
  }
  close $channel
}

proc copy_run_artifacts {run_name destination} {
  file mkdir $destination
  set runs [get_runs -quiet $run_name]
  if {[llength $runs] == 0} {
    write_text_file [file join $destination "missing_run.txt"] \
      "Vivado run '$run_name' does not exist."
    return
  }

  set run_dir [get_property DIRECTORY $runs]
  # Checkpoints are intentionally excluded: they are large and are not needed
  # for a text-based review package.
  foreach pattern {runme.log *.rpt *.rpx *.xml *.pb} {
    foreach source [glob -nocomplain -directory $run_dir $pattern] {
      if {[file isfile $source]} {
        if {[catch {file copy -force $source $destination} message]} {
          puts "WARNING: could not copy $source: $message"
        }
      }
    }
  }
}

set script_path [file normalize [info script]]
set repo_root   [file dirname [file dirname [file dirname $script_path]]]
set timestamp   [clock format [clock seconds] -format %Y%m%d_%H%M%S]
if {![info exists ::release_output_root]} {
  set ::release_output_root [file join $repo_root Report_vivado]
}
set report_dir [file join [file normalize $::release_output_root] $timestamp]
set git_status_at_start [safe_exec git -C $repo_root status --short]
file mkdir $report_dir

if {[llength [get_projects -quiet]] == 0} {
  error "No Vivado project is open. Open the project, then source this script again."
}

set impl_runs [get_runs -quiet impl_1]
if {[llength $impl_runs] == 0} {
  error "Implementation run impl_1 does not exist in the current project."
}

set impl_status [get_property STATUS $impl_runs]
if {![string match "*Complete*" $impl_status]} {
  error "impl_1 is not complete (STATUS='$impl_status'). Complete implementation first."
}

if {[catch {open_run impl_1} message]} {
  error "Unable to open impl_1: $message"
}

set summary ""
append summary "Generated: [clock format [clock seconds]]\n"
append summary "Vivado:   [version]\n"
append summary "Host:     $::tcl_platform(os) $::tcl_platform(osVersion)\n"
append summary "Project:  [get_property NAME [current_project]]\n"
append summary "Part:     [get_property PART [current_project]]\n"
append summary "Top:      [get_property TOP [current_fileset]]\n"
append summary "impl_1:   $impl_status\n"
set synth_runs [get_runs -quiet synth_1]
if {[llength $synth_runs] != 0} {
  append summary "synth_1:  [get_property STATUS $synth_runs]\n"
}
append summary "Git HEAD: [safe_exec git -C $repo_root rev-parse HEAD]\n"
append summary "Git describe: [safe_exec git -C $repo_root describe --always --dirty --tags]\n"
append summary "Synthesis strategy: [safe_property $synth_runs STRATEGY]\n"
append summary "Implementation strategy: [safe_property $impl_runs STRATEGY]\n"
append summary "Top generics: [safe_property [current_fileset] GENERIC]\n"
write_text_file [file join $report_dir summary.txt] $summary

set git_status $git_status_at_start
if {$git_status eq ""} {
  set git_status "clean"
}
write_text_file [file join $report_dir git_status.txt] $git_status

set metrics "FPGA implementation release metrics\n"
append metrics "generated=[clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S%z}]\n"
append metrics "git_head=[safe_exec git -C $repo_root rev-parse HEAD]\n"
append metrics "vivado=[version -short]\n"
append metrics "part=[get_property PART [current_project]]\n"
append metrics "top=[get_property TOP [current_fileset]]\n"
append metrics "synth_status=[safe_property $synth_runs STATUS]\n"
append metrics "impl_status=[safe_property $impl_runs STATUS]\n"
append metrics "synth_strategy=[safe_property $synth_runs STRATEGY]\n"
append metrics "impl_strategy=[safe_property $impl_runs STRATEGY]\n"
append metrics "failed_nets=[safe_property $impl_runs STATS.FAILED_NETS]\n"
append metrics "wns_ns=[safe_property $impl_runs STATS.WNS]\n"
append metrics "tns_ns=[safe_property $impl_runs STATS.TNS]\n"
append metrics "whs_ns=[safe_property $impl_runs STATS.WHS]\n"
append metrics "ths_ns=[safe_property $impl_runs STATS.THS]\n"
append metrics "tpws_ns=[safe_property $impl_runs STATS.TPWS]\n"
append metrics "estimated_total_power_w=[safe_property $impl_runs STATS.TOTAL_POWER]\n"
append metrics "top_generics=[safe_property [current_fileset] GENERIC]\n"
foreach clock [get_clocks -quiet] {
  set clock_name [get_property NAME $clock]
  append metrics "clock.$clock_name.period_ns=[safe_property $clock PERIOD]\n"
  append metrics "clock.$clock_name.waveform=[safe_property $clock WAVEFORM]\n"
}
write_text_file [file join $report_dir release_metrics.txt] $metrics

dump_object_properties [file join $report_dir project_properties.txt] [current_project]
dump_object_properties [file join $report_dir impl_run_properties.txt] $impl_runs
if {[llength $synth_runs] != 0} {
  dump_object_properties [file join $report_dir synth_run_properties.txt] $synth_runs
}

run_report timing_summary [list report_timing_summary \
  -delay_type min_max -report_unconstrained -check_timing_verbose \
  -max_paths 50 -input_pins -file [file join $report_dir timing_summary.rpt]]
run_report timing_setup [list report_timing -delay_type max -max_paths 50 \
  -sort_by group -path_type full_clock_expanded \
  -file [file join $report_dir timing_setup_top50.rpt]]
run_report timing_hold [list report_timing -delay_type min -max_paths 50 \
  -sort_by group -path_type full_clock_expanded \
  -file [file join $report_dir timing_hold_top50.rpt]]
run_report check_timing [list check_timing -verbose \
  -file [file join $report_dir check_timing.rpt]]
run_report utilization [list report_utilization -hierarchical \
  -hierarchical_depth 5 -file [file join $report_dir utilization_hier.rpt]]
run_report utilization_flat [list report_utilization \
  -file [file join $report_dir utilization_flat.rpt]]
run_report ram_utilization [list report_ram_utilization \
  -file [file join $report_dir ram_utilization.rpt]]
run_report drc [list report_drc -file [file join $report_dir drc.rpt]]
run_report methodology [list report_methodology \
  -file [file join $report_dir methodology.rpt]]
run_report power [list report_power -file [file join $report_dir power.rpt]]
run_report clock_utilization [list report_clock_utilization \
  -file [file join $report_dir clock_utilization.rpt]]
run_report route_status [list report_route_status \
  -file [file join $report_dir route_status.rpt]]
run_report clock_interaction [list report_clock_interaction \
  -file [file join $report_dir clock_interaction.rpt]]
run_report cdc [list report_cdc -details \
  -file [file join $report_dir cdc.rpt]]
run_report exceptions [list report_exceptions -summary \
  -file [file join $report_dir timing_exceptions.rpt]]
run_report io [list report_io -file [file join $report_dir io.rpt]]
run_report control_sets [list report_control_sets -verbose \
  -file [file join $report_dir control_sets.rpt]]
run_report high_fanout [list report_high_fanout_nets -timing -load_types \
  -max_nets 100 -file [file join $report_dir high_fanout_nets.rpt]]
run_report datasheet [list report_datasheet \
  -file [file join $report_dir datasheet.rpt]]
run_report design_analysis [list report_design_analysis -timing \
  -setup -max_paths 50 -file [file join $report_dir design_analysis.rpt]]
run_report qor_assessment [list report_qor_assessment \
  -file [file join $report_dir qor_assessment.rpt]]
run_report qor_suggestions [list report_qor_suggestions \
  -file [file join $report_dir qor_suggestions.rpt]]
run_report effective_xdc [list write_xdc -force \
  [file join $report_dir effective_constraints.xdc]]

set inventory_channel [open [file join $report_dir input_inventory.txt] w]
puts $inventory_channel "Project source and constraint inventory"
puts $inventory_channel "Generated: [clock format [clock seconds]]"
foreach fileset [get_filesets -quiet] {
  puts $inventory_channel "\nFILESET [get_property NAME $fileset]"
  puts $inventory_channel "  TYPE: [safe_property $fileset FILESET_TYPE]"
  puts $inventory_channel "  TOP:  [safe_property $fileset TOP]"
  puts $inventory_channel "  GENERIC: [safe_property $fileset GENERIC]"
  foreach source [lsort [get_files -quiet -of_objects $fileset]] {
    puts $inventory_channel "  [file normalize $source]"
  }
}
close $inventory_channel

copy_run_artifacts synth_1 [file join $report_dir synth_1]
copy_run_artifacts impl_1  [file join $report_dir impl_1]

foreach source [list \
  [file join [pwd] vivado.log] \
  [file join [pwd] vivado.jou]] {
  if {[file isfile $source]} {
    file copy -force $source $report_dir
  }
}

# Preserve the exact release payload and record immutable hashes. The default
# firmware paths match this repository; callers may override them before
# sourcing this script by setting the three global variables below.
if {![info exists ::release_firmware_elf]} {
  set ::release_firmware_elf [file join $repo_root build software smoke.elf]
}
if {![info exists ::release_firmware_mem]} {
  set ::release_firmware_mem [file join $repo_root build software smoke.mem]
}
if {![info exists ::release_firmware_map]} {
  set ::release_firmware_map [file join $repo_root build software smoke.map]
}
if {![info exists ::release_firmware_dump]} {
  set ::release_firmware_dump [file join $repo_root build software smoke.dump]
}
set artifact_dir [file join $report_dir release_artifacts]
file mkdir $artifact_dir

# Generate the bitstream directly from the opened implemented design so the
# exported payload always corresponds to the reports in this package. Callers
# may instead set ::release_bitstream before sourcing this script.
if {![info exists ::release_bitstream]} {
  set bitstream_name "[get_property TOP [current_fileset]].bit"
  set generated_bitstream [file join $artifact_dir $bitstream_name]
  puts "INFO: writing release bitstream"
  if {[catch {write_bitstream -force $generated_bitstream} message options]} {
    write_text_file [file join $report_dir bitstream.error.txt] \
      "ERROR: $message\nOPTIONS: $options"
    puts "WARNING: bitstream generation failed: $message"
    set ::release_bitstream ""
  } else {
    set ::release_bitstream $generated_bitstream
  }
}

set manifest_channel [open [file join $report_dir artifact_manifest.txt] w]
puts $manifest_channel "Release artifact SHA-256 manifest"
puts $manifest_channel "Git HEAD: [safe_exec git -C $repo_root rev-parse HEAD]"
puts $manifest_channel "Vivado: [version]"
puts $manifest_channel "Part: [get_property PART [current_project]]"
puts $manifest_channel "Top: [get_property TOP [current_fileset]]"
puts $manifest_channel ""
copy_and_record_artifact $::release_firmware_elf $artifact_dir \
  $manifest_channel firmware_elf
copy_and_record_artifact $::release_firmware_mem $artifact_dir \
  $manifest_channel firmware_mem
copy_and_record_artifact $::release_firmware_map $artifact_dir \
  $manifest_channel firmware_map
copy_and_record_artifact $::release_firmware_dump $artifact_dir \
  $manifest_channel firmware_dump
copy_and_record_artifact $::release_bitstream $artifact_dir \
  $manifest_channel bitstream
foreach debug_probe [glob -nocomplain -directory [get_property DIRECTORY $impl_runs] *.ltx] {
  copy_and_record_artifact $debug_probe $artifact_dir \
    $manifest_channel debug_probes
}
close $manifest_channel

set readme_body "Vivado FPGA release evidence package\n\n"
append readme_body "1. Confirm git_status.txt is 'clean' and Git HEAD is the intended release commit.\n"
append readme_body "2. Review timing_summary.rpt, check_timing.rpt, route_status.rpt, drc.rpt, methodology.rpt, cdc.rpt, and power.rpt.\n"
append readme_body "3. Confirm artifact_manifest.txt contains hashes for firmware_elf, firmware_mem, and bitstream.\n"
append readme_body "4. Treat power.rpt as an estimate unless switching activity was supplied and documented.\n"
append readme_body "5. Review logs for absolute paths, user names, and proprietary data before publishing the full package.\n"
append readme_body "6. Pair the package with the board revision, FPGA marking, and a PASS/DONE photograph or analyzer trace.\n"
write_text_file [file join $report_dir README.txt] $readme_body

puts ""
puts "============================================================"
puts "VIVADO REVIEW PACKAGE CREATED"
puts $report_dir
puts "============================================================"
