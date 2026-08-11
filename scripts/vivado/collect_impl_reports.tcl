# SPDX-License-Identifier: MIT

# Collect a self-contained Vivado implementation review package.
# Run from an open Vivado project after impl_1 has completed:
#   source {/absolute/path/to/scripts/vivado/collect_impl_reports.tcl}

proc write_text_file {path body} {
  set channel [open $path w]
  puts $channel $body
  close $channel
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
set report_dir  [file join $repo_root "vivado_review_$timestamp"]
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
append summary "Vivado:   [version -short]\n"
append summary "Host:     $::tcl_platform(os) $::tcl_platform(osVersion)\n"
append summary "Project:  [get_property NAME [current_project]]\n"
append summary "Part:     [get_property PART [current_project]]\n"
append summary "Top:      [get_property TOP [current_fileset]]\n"
append summary "impl_1:   $impl_status\n"
set synth_runs [get_runs -quiet synth_1]
if {[llength $synth_runs] != 0} {
  append summary "synth_1:  [get_property STATUS $synth_runs]\n"
}
write_text_file [file join $report_dir summary.txt] $summary

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
run_report drc [list report_drc -file [file join $report_dir drc.rpt]]
run_report methodology [list report_methodology \
  -file [file join $report_dir methodology.rpt]]
run_report power [list report_power -file [file join $report_dir power.rpt]]
run_report clock_utilization [list report_clock_utilization \
  -file [file join $report_dir clock_utilization.rpt]]
run_report route_status [list report_route_status \
  -file [file join $report_dir route_status.rpt]]
run_report cdc [list report_cdc -details \
  -file [file join $report_dir cdc.rpt]]
run_report exceptions [list report_exceptions -summary \
  -file [file join $report_dir timing_exceptions.rpt]]
run_report effective_xdc [list write_xdc -force \
  [file join $report_dir effective_constraints.xdc]]

copy_run_artifacts synth_1 [file join $report_dir synth_1]
copy_run_artifacts impl_1  [file join $report_dir impl_1]

foreach source [list \
  [file join [pwd] vivado.log] \
  [file join [pwd] vivado.jou]] {
  if {[file isfile $source]} {
    file copy -force $source $report_dir
  }
}

puts ""
puts "============================================================"
puts "VIVADO REVIEW PACKAGE CREATED"
puts $report_dir
puts "============================================================"
