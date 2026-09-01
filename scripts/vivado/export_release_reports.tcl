# Export a provenance-checked Vivado evidence package for one firmware profile.
# Run after impl_1 completes:
#   set ::release_profile freertos
#   source {/absolute/path/to/scripts/vivado/export_release_reports.tcl}
# Valid profiles are "smoke" and "freertos".

if {![info exists ::release_profile]} {
  error "Set ::release_profile to smoke or freertos before sourcing this script."
}

set script_path [file normalize [info script]]
set script_dir  [file dirname $script_path]
set repo_root   [file dirname [file dirname $script_dir]]

proc release_sha256_file {path} {
  set output [exec sha256sum $path]
  if {![regexp {^([0-9a-fA-F]{64})} $output -> digest]} {
    error "Unable to parse SHA-256 for $path: $output"
  }
  return [string tolower $digest]
}

switch -- $::release_profile {
  smoke {
    set firmware_dir  [file join $repo_root build software]
    set firmware_base smoke
  }
  freertos {
    set firmware_dir  [file join $repo_root build fpga-freertos]
    set firmware_base freertos_demo
  }
  default {
    error "Unknown release profile '$::release_profile'; use smoke or freertos."
  }
}

if {[llength [get_projects -quiet]] == 0} {
  error "No Vivado project is open."
}

set expected_mem "${firmware_base}.mem"
set top_generics [get_property GENERIC [get_filesets sources_1]]
if {[lsearch -exact $top_generics "TCM_INIT_FILE=$expected_mem"] < 0} {
  error "Profile '$::release_profile' expects TCM_INIT_FILE=$expected_mem, but current generics are: $top_generics"
}

set ::release_firmware_elf  [file join $firmware_dir "${firmware_base}.elf"]
set ::release_firmware_mem  [file join $firmware_dir "${firmware_base}.mem"]
set ::release_firmware_map  [file join $firmware_dir "${firmware_base}.map"]
set ::release_firmware_dump [file join $firmware_dir "${firmware_base}.dump"]

foreach artifact [list \
  $::release_firmware_elf \
  $::release_firmware_mem \
  $::release_firmware_map \
  $::release_firmware_dump] {
  if {![file isfile $artifact]} {
    error "Missing release artifact: $artifact"
  }
}

set project_mem [get_files -quiet -all "*$expected_mem"]
if {[llength $project_mem] != 1} {
  error "Expected exactly one project memory file named $expected_mem, found [llength $project_mem]."
}

set source_mem_hash  [release_sha256_file $::release_firmware_mem]
set project_mem_hash [release_sha256_file $project_mem]
if {$source_mem_hash ne $project_mem_hash} {
  error "Project memory image does not match release image: project=$project_mem_hash source=$source_mem_hash"
}

set ::release_output_root [file join \
  $repo_root Report_vivado $::release_profile]

# The collector writes a bitstream from the currently opened implemented
# design. Clear a value left by an earlier export in the same Vivado session.
catch {unset ::release_bitstream}

puts "INFO: exporting '$::release_profile' release evidence"
puts "INFO: firmware SHA-256 $source_mem_hash"
source [file join $script_dir collect_impl_reports.tcl]
