# Hardware Validation Evidence Record

This document records the validation evidence for the RV32IM core and
its FreeRTOS FPGA SoC integration. It separates reproducible simulation,
post-route implementation, artifact identity, and physical-board observation
so that no one class of evidence is presented as another.

Detailed contracts remain in [Architecture](architecture.md),
[Verification](verification.md), [Software](software.md), and
[FPGA implementation](fpga.md).

## 1. Validation disposition

| Evidence class | Disposition |
|---|---|
| RTL, software, and ISA regressions | PASS for the recorded final runs |
| FreeRTOS Verilator and Questa integration | PASS |
| FreeRTOS Vivado implementation | PASS at the constrained 75 MHz point |
| Routing and DRC | PASS; fully routed, zero DRC errors |
| Current ten-port board boundary | PASS in the post-route I/O report |
| Bitstream generation and artifact pairing | PASS; firmware and bitstream are hash-identified |
| Physical FreeRTOS bring-up | PASS recorded for board boot, UART echo, GPIO, and status outputs |
| Exact clean-package bitstream `94603524...` deployed on the target board | **PASS** |

The current implementation package uses `TCM_INIT_FILE=freertos_demo.mem`,
contains all ten constrained top-level ports, and was exported from clean
implementation commit `fc57a72`. The exact manifest-identified bitstream was
programmed and passed the documented FreeRTOS board checks. The remaining
`v1.0.0` work is repository/release publication rather than hardware
validation.

This project does not claim official RISC-V certification, an EEMBC-certified
CoreMark submission, FPGA Fmax, measured board power, production PVT closure,
or silicon qualification.

## 2. FreeRTOS implementation provenance

The local source package is:

```text
Report_vivado/freertos/20260903_103705/
```

| Item | Recorded value |
|---|---|
| Generated | 2026-09-03 10:37:07 +07 |
| Git HEAD | `fc57a72d88ff85bdc19b1840a5341c5878c2d966` |
| Source state | clean |
| Vivado | 2024.1, build 5076996 |
| FPGA | AMD/Xilinx Artix-7 `xc7a35tfgg484-2` |
| Top | `fpga_top` |
| Strategies | Vivado synthesis and implementation defaults |
| Input/generated clocks | 50 MHz / 75 MHz |
| Top generics | `TCM_INIT_FILE=freertos_demo.mem SOC_CLK_FREQ_HZ=75000000` |
| Synthesis | Complete |
| Placement and routing | Complete |
| Bitstream | Generated from the opened implemented design |

The export wrapper verifies that the project-visible `.mem` file and selected
release `.mem` file have the same SHA-256 before collecting reports. It then
writes a new bitstream from that implemented design and records the firmware
and bitstream hashes in one manifest.

## 3. Functional and architectural evidence

| Validation gate | Result |
|---|---:|
| Strict synthesizable RTL lint | PASS |
| Unit RTL simulation | 21/21 PASS |
| Directed integration RTL simulation | 7/7 PASS |
| Bare-metal programs | 2/2 PASS |
| FreeRTOS SoC integration | PASS on Verilator and Questa |
| Pinned `riscv-tests` | 40 RV32I + 8 RV32M PASS |
| ACT4 4.0.0 + Sail | 39 RV32I + 8 RV32M PASS |

The recorded FreeRTOS simulation observes:

| Metric | Verilator | Questa |
|---|---:|---:|
| Completion | PASS | PASS |
| Harness cycles | 406,672 | 406,673 |
| Machine-timer traps | 5 | 5 |
| M-mode ECALL yields | 13 | 13 |
| `MRET` retirements | 18 | 18 |
| GPIO transitions | 3 | 3 |
| UART behavior | `READY\n`, echo `0xA5` | Same |

Simulation is the quantitative oracle for trap, scheduler, GPIO, and UART
counts. Physical observation establishes that the integrated image operates on
the named board; it does not expose every internal count.

<p align="center">
  <a href="images/test-log.png">
    <img src="images/test-log.png" alt="Complete Verilator RTL software and pinned ISA regression PASS summary" width="920">
  </a>
</p>

<p align="center"><em>The public gate closes lint, 29 RTL simulations, two
bare-metal programs, FreeRTOS, and all 48 pinned ISA programs.</em></p>

<p align="center">
  <a href="images/freertos-verilator.png">
    <img src="images/freertos-verilator.png" alt="FreeRTOS Verilator PASS with scheduler and interrupt counts" width="900">
  </a>
</p>

<p align="center">
  <a href="images/freertos-questa.png">
    <img src="images/freertos-questa.png" alt="FreeRTOS Questa PASS with matching scheduler and interrupt counts" width="900">
  </a>
</p>

<p align="center"><em>Both simulators reach the same architectural result;
the one-cycle harness difference is expected and explicitly recorded.</em></p>

<p align="center">
  <a href="images/act4.png">
    <img src="images/act4.png" alt="All 47 ACT4 RV32I and RV32M tests passing against Sail-backed expectations" width="560">
  </a>
</p>

## 4. Performance evidence

Directed counters cover complete bare-metal runs from reset release through
the retirement-qualified completion store.

| Workload | Instructions | Cycles | CPI | IPC |
|---|---:|---:|---:|---:|
| Arithmetic | 9,251 | 10,287 | 1.112 | 0.899 |
| Branch | 19,758 | 29,190 | 1.477 | 0.677 |
| Memory | 5,370 | 9,011 | 1.678 | 0.596 |
| MDU | 866 | 1,613 | 1.863 | 0.537 |
| **Weighted aggregate** | **35,245** | **50,101** | **1.422** | **0.703** |

| CoreMark run | Iterations | ROI instructions | ROI cycles | CPI | CoreMark/MHz | CRC |
|---|---:|---:|---:|---:|---:|---:|
| Performance | 2,000 | 572,705,031 | 940,486,831 | 1.642 | **2.127** | PASS |
| Validation | 2,000 | 573,444,174 | 943,000,304 | 1.644 | 2.121 | PASS |

These are RTL counter-derived results evaluated at the architectural 75 MHz
clock. They are not FPGA wall-clock measurements.

## 5. Post-route implementation results

### 5.1 Timing and routing

| Metric | Post-route result |
|---|---:|
| Board clock | 50 MHz / 20.000 ns |
| Generated SoC clock | 75 MHz / 13.333 ns |
| Setup WNS / TNS | +0.070 ns / 0.000 ns |
| Setup failing endpoints | 0 / 6,890 |
| Hold WHS / THS | +0.066 ns / 0.000 ns |
| Hold failing endpoints | 0 / 6,890 |
| Worst pulse-width slack / TPWS | +5.537 ns / 0.000 ns |
| Unclocked sequential pins | 0 |
| Unconstrained internal paths | 0 |
| Combinational loops | 0 |
| Failed or unrouted nets | 0 |

The positive slack closes this specific implementation at 75 MHz. The small
setup margin is not an Fmax claim and should not be described as broad timing
headroom.

<p align="center">
  <a href="images/timing_report.png">
    <img src="images/timing_report.png" alt="FreeRTOS post-route Vivado timing summary at 75 MHz" width="900">
  </a>
</p>

<p align="center"><em>All user-specified timing constraints are met with
positive setup, hold, and pulse-width slack.</em></p>

### 5.2 Utilization

| Resource | Used / available | Utilization |
|---|---:|---:|
| Slice LUTs | 3,815 / 20,800 | 18.34% |
| LUT as logic | 3,771 / 20,800 | 18.13% |
| LUT as memory | 44 / 9,600 | 0.46% |
| Slice registers | 2,001 / 41,600 | 4.81% |
| Slices | 1,154 / 8,150 | 14.16% |
| Block RAM tiles | 16 / 50 | 32.00% |
| DSP48E1 | 4 / 90 | 4.44% |
| Bonded I/O | 10 / 250 | 4.00% |
| BUFGCTRL | 2 / 32 | 6.25% |
| MMCME2_ADV | 1 / 5 | 20.00% |

DRC reports zero errors and eight warnings: four `DPOP-1` and four `DPOP-2`
DSP pipelining advisories. They are accepted for the documented 75 MHz point
because routed timing closes; they remain optimization guidance rather than a
general waiver.

The methodology report contains 21 reviewed warnings: one `LUTAR-1`, four
`SYNTH-10`, and sixteen `SYNTH-15`. The `SYNTH-10` and `SYNTH-15` findings
describe the selected wide-multiplier and byte-write-enabled TCM mappings.
`LUTAR-1` flags the LUT that combines reset requests and MMCM `locked` before
the asynchronous-assert, synchronous-release reset chain. A transient at that
point can conservatively restart this board prototype; this disposition is not
a production reset-safety waiver.

<p align="center">
  <a href="images/utilization_report.png">
    <img src="images/utilization_report.png" alt="Hierarchical utilization for the routed FreeRTOS FPGA implementation" width="1000">
  </a>
</p>

<p align="center"><em>The implementation uses 3,815 LUTs, 2,001 registers,
16 BRAM tiles, four DSPs, and all ten constrained board I/O ports.</em></p>

### 5.3 Power estimate

| Metric | Post-route estimate |
|---|---:|
| Total on-chip power | 0.253 W |
| Dynamic | 0.180 W |
| Device static | 0.073 W |
| Junction / ambient temperature | 25.7 °C / 25.0 °C |
| Confidence | Medium |

This is a vectorless post-route estimate. It is not measured board power and
does not model observed FreeRTOS workload activity with a VCD/SAIF file.

<p align="center">
  <a href="images/power_report.png">
    <img src="images/power_report.png" alt="Vectorless post-route Vivado power estimate for the FreeRTOS implementation" width="780">
  </a>
</p>

<p align="center"><em>The 0.253 W result has Medium confidence and remains an
implementation estimate, not a physical power measurement.</em></p>

## 6. I/O and physical-board validation

The post-route I/O report contains the complete ten-port boundary:

| Package pin | Port | Direction | Role |
|---|---|---|---|
| J19 | `clk_50m_i` | Input | Board oscillator |
| L18 | `reset_ni` | Input | K3 clocking-boundary reset |
| AA1 | `user_reset_ni` | Input | K1 synchronous SoC reset request |
| U2 | `uart_rx_i` | Input | CH340 TX to FPGA RX |
| V2 | `uart_tx_o` | Output | FPGA TX to CH340 RX |
| N17 | `gpio_led_o` | Output | GPIO0 on JP2 pin 3 |
| M18 | `led1_n_o` | Output | Active-low D6 heartbeat |
| N18 | `led2_n_o` | Output | Active-low D5 PASS |
| W21 | `fail_o` | Output | Active-high FAIL on JP2 pin 1 |
| W22 | `done_o` | Output | Active-high DONE on JP2 pin 2 |

The recorded board bring-up observed boot, UART `READY`, UART echo, GPIO
activity, PASS/DONE, and repeatable reset on a MicroPhase A7-Lite R1.1. Those
checks were repeated with the exact clean-package bitstream identified in
Section 7. The photographs and terminal capture remain qualitative supporting
evidence; the manifest is the artifact-identity authority.

<p align="center">
  <a href="images/board.png">
    <img src="images/board.png" alt="RV32IM FreeRTOS bring-up on the MicroPhase A7-Lite board" width="900">
  </a>
</p>

<p align="center"><em>MicroPhase A7-Lite R1.1 powered and running the local
FreeRTOS bring-up image.</em></p>

<p align="center">
  <a href="images/uart-terminal.png">
    <img src="images/uart-terminal.png" alt="Physical FreeRTOS READY output and UART character echo through CH340" width="520">
  </a>
</p>

<p align="center"><em>The physical 115200 8N1 session records repeatable boot
readiness and a character returned by the UART echo task. It does not by itself
bind the observed session to a bitstream hash.</em></p>

## 7. Artifact identity

### 7.1 FreeRTOS release payload

<p align="center">
  <a href="images/firmware-rtos.png">
    <img src="images/firmware-rtos.png" alt="FreeRTOS board firmware build and ELF MEM SHA-256 output" width="850">
  </a>
</p>

<p align="center"><em>The build capture illustrates the 64 KiB TCM image flow.
The current values below and the packaged manifest are the artifact-identity
authority.</em></p>

| Artifact | SHA-256 |
|---|---|
| `freertos_demo.elf` | `9a220086ab3629aa791374ccf843b6349d307da419ec0392afae031f984de359` |
| `freertos_demo.mem` | `1ab72163b3fd5469a48981e549343f1979dd47039002231c715ae70b6c9022b4` |
| `freertos_demo.map` | `a986b44ee4e8f8c242701de177fc1a5682ffb26a6c50105cefdc1be09fa48e00` |
| `freertos_demo.dump` | `f18e4d9fd3207dba49e5c0c4a7897cb6f6bd8dc9d4490400ee8d217f58ed90d4` |
| `fpga_top.bit` | `9460352401ae6037545aa4671e3dd4e46c49ad779eea0c142569b6194865581a` |

### 7.2 Sign-off report hashes

| Report | SHA-256 |
|---|---|
| `timing_summary.rpt` | `4d27050523c6d1d59955bb1dd2a34327f81a6536717bae6df220329b5c945067` |
| `utilization_flat.rpt` | `4fbca832bd25542bc3cc3cfc11b3d90e5262d8d131857600ac6bc872e87482ba` |
| `drc.rpt` | `0a30143ab28c3a9803e9f53e021e277db49cb83896c5425d785d9ce18b64355e` |
| `methodology.rpt` | `565c18ab23ab28bb539bbefc21aae54750a1621e2271c1b1c246741b3ca67311` |
| `io.rpt` | `40ea6ef07bb712da24756b07aed173f2e2e89fe67b5c69ac7dbbd9a6e60062cf` |
| `power.rpt` | `1b0cff6693e45331b366f95afdf0eafe214400813caea3a20fe84c9011c36894` |
| `route_status.rpt` | `d946bd7284237a8d6dfe4b98ea6bf5be91554a3d8546d988252249bdd2645edf` |

These hashes identify the clean-source implementation package that was used
for the exact-bitstream board retest. `artifact_manifest.txt` in the release
archive remains authoritative.

## 8. Two-stage board validation model

| Stage | Purpose | Required evidence |
|---|---|---|
| Phase 1: bare-metal smoke | Fast boot, reset, TCM, mailbox, PASS/DONE sanity | Program/image hash and one board PASS capture |
| Phase 2: FreeRTOS | MTIP scheduling, context switching, UART echo, GPIO, and integrated PASS | Full Vivado package, UART capture, GPIO/board capture, exact artifact hashes |

The FreeRTOS package is the implementation sign-off source. Smoke remains a
layered functional check and does not require a duplicate public set of timing,
utilization, DRC, and power reports when RTL, XDC, part, clock, and strategies
are unchanged.

## 9. Release gate

- [x] RTL, software, ISA, ACT4, benchmark, and CoreMark runs pass.
- [x] FreeRTOS Verilator and Questa runs pass.
- [x] The current FreeRTOS image is paired with the implemented bitstream.
- [x] The ten-port RTL/XDC boundary is present in `io.rpt`.
- [x] Routing, timing, and DRC sign-off gates pass.
- [x] Firmware, bitstream, and reports have SHA-256 identities.
- [x] The Vivado DRC and methodology warnings are classified and documented.
- [x] The package was exported from clean implementation commit `fc57a72`.
- [x] The exact clean-package bitstream passed UART/GPIO/PASS/reset board checks.
- [ ] Commit the complete release source and documentation so the tree is clean.
- [ ] Tag and publish `v1.0.0` with the packaged artifacts.

Hardware validation is complete. Until the final two publication items close,
the accurate status is **validated release candidate**, not an immutable tagged
release.
