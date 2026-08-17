# SPDX-License-Identifier: MIT

# Non-interactive companion to the curated GUI waveform flow. Any assertion,
# $fatal, or simulator error must make the Make target fail.
onerror {quit -code 1 -force}
onbreak {quit -code 1 -force}
onfinish exit

run -all
quit -code 0 -force
