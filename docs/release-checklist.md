# Release Checklist

This checklist freezes the RV32IM repository around the FreeRTOS FPGA profile.
The authoritative evidence record is [Hardware validation](hardware-validation.md).

## Completed engineering gates

- [x] Strict RTL lint, unit, directed integration, assertion, and software tests pass.
- [x] Pinned `riscv-tests` and Sail-backed ACT4 RV32I/RV32M suites pass.
- [x] FreeRTOS V11.3.0 runs on the production SoC model in Verilator and Questa.
- [x] Directed performance and CRC-valid CoreMark runs are recorded.
- [x] `freertos_demo.mem` is selected by the Vivado top-level generic.
- [x] The ten-port RTL/XDC board boundary appears in the post-route I/O report.
- [x] The 75 MHz implementation is fully routed and meets setup, hold, pulse-width, and DRC gates.
- [x] Firmware, reports, and bitstream are paired with SHA-256 hashes.
- [x] FreeRTOS boot, UART echo, GPIO, PASS/DONE, and reset behavior have been observed on board.

## Required before public `v1.0.0`

- [ ] Review and commit all intended source, third-party pinning, documentation, and CI changes.
- [ ] Confirm `git status --short` is empty at the release commit.
- [ ] Run the full release regression and save its console log.
- [ ] Rebuild the 250 ms board FreeRTOS image from that commit.
- [ ] Re-run synthesis, implementation, and the FreeRTOS release export from that commit.
- [ ] Program the exact exported `fpga_top.bit`; capture UART and board evidence.
- [ ] Record the final commit ID and replacement hashes in `hardware-validation.md`.
- [ ] Tag `v1.0.0` and attach the Vivado evidence directory or a compressed copy to the GitHub release.

## Final commands

```sh
make -j"$(nproc)" test
make act4
make benchmark
make coremark
make fpga-freertos-images
git status --short
```

After `impl_1` completes in the matching Vivado project:

```tcl
set ::release_profile freertos
source {/absolute/path/to/scripts/vivado/export_release_reports.tcl}
```

The exporter writes `Report_vivado/freertos/<timestamp>/`. Do not tag the
release if the manifest reports a dirty source state or if the programmed
bitstream hash differs from that package.
