# RV32IM Core Engineering Documentation

<p align="center">
  <img
    src="images/rv32im-project-banner.png"
    alt="RV32IM five-stage pipelined core project banner"
    width="1100"
  >
</p>

This directory is the engineering documentation portal for the implemented
RV32IM five-stage processor. The root [project README](../README.md) provides
the public overview, results, and quick start; the documents below define the
reviewed architecture, microarchitectural control, verification evidence,
software contract, and FPGA integration behind those claims.

[Architecture](architecture.md) ·
[Pipeline and control](pipeline-control.md) ·
[Verification](verification.md) ·
[Software](software.md) ·
[Performance](performance.md) ·
[CoreMark](coremark.md) ·
[FPGA](fpga.md) ·
[Hardware validation](hardware-validation.md) ·
[Release checklist](release-checklist.md) ·
[Waveforms](waveform-debug.md)

## 1. Implemented baseline

| Area | Documented configuration |
|---|---|
| Processor | Single-hart, single-issue, in-order IF–ID–EX–MEM–WB core |
| ISA | RV32I 2.1 and the complete RV32M 2.0 instruction set |
| Additional support | Six Zicsr 2.0 operations, implemented M-mode CSR subset, direct precise traps, `MRET`, and machine-timer interrupts |
| Memory boundary | Independent blocking instruction/data request-response ports; at most one outstanding transaction per port |
| Baseline SoC | Unified 64 KiB true-dual-port TCM plus memory-mapped timer, UART, GPIO, and transaction-owning demultiplexer |
| Software | Freestanding ILP32 runtime/BSP plus pinned FreeRTOS V11.3.0 blink and UART-echo demo |
| Verification | 21 unit + 7 directed integration + FreeRTOS SoC simulation, two bare-metal programs, 48 pinned `riscv-tests`, and 47 Sail-backed ACT4 tests |
| FPGA | MicroPhase A7-Lite R1.1, Artix-7 `xc7a35tfgg484-2`; FreeRTOS image fully routed at 75 MHz with the complete ten-port boundary (see [Hardware validation](hardware-validation.md)) |

This is a deliberately bounded processor implementation. It does not claim
official RISC-V certification, the complete Privileged Architecture, caches,
an MMU, U/S modes, software/external interrupt controllers, a standard SoC
bus, production RTOS qualification, or silicon validation. Exact inclusions
and exclusions are normative in
[Architecture §2](architecture.md#2-design-scope-and-compliance-boundary).

## 2. Document ownership

Each document answers a distinct engineering question. Keeping these
responsibilities separate prevents a project summary, implementation detail,
and verification result from being mistaken for one another.

| Document | Engineering question and owned content |
|---|---|
| [Architecture](architecture.md) | **What does the processor implement?** ISA boundary, programmer-visible state, five-stage organization, memory contract, RV32M behavior, CSR/trap subset, retirement interface, and baseline timing characteristics |
| [Pipeline and control](pipeline-control.md) | **How is in-order correctness preserved cycle by cycle?** Stage ownership, forwarding, interlocks, CSR ordering, MDU/LSU waits, stale fetch responses, redirects, precise-trap drain, and global action priority |
| [Verification](verification.md) | **What proves the implementation claims?** Test architecture, requirement-to-evidence traceability, regression counts, independent suites, CI, failure triage, sign-off rules, and explicitly open verification work |
| [Software](software.md) | **How does executable software use the SoC?** ILP32 ABI, startup, BSP, linker map, mailbox, FreeRTOS port/configuration, task demo, and ELF-to-memory-image flow |
| [Performance](performance.md) | **How does the core behave across directed workloads?** Complete-run instruction counts, cycles, CPI/IPC, and stall diagnostics |
| [CoreMark](coremark.md) | **What is the measured CoreMark result?** Source provenance, build configuration, CRC validation, CoreMark/MHz, CPI/IPC, and bottleneck counters |
| [FPGA implementation](fpga.md) | **How is the design realized and observed on hardware?** Board boundary, reset, TCM initialization, XDC, Vivado flow, implementation results, bring-up, and the public hardware-evidence boundary |
| [Hardware validation](hardware-validation.md) | **What evidence is currently supported?** Functional and performance records, post-route FreeRTOS implementation, board observation, artifact hashes, and the boundary between release-candidate and release evidence |
| [Release checklist](release-checklist.md) | **What remains before publishing?** Clean-source, implementation, artifact, board, and GitHub release gates |
| [Waveform debug](waveform-debug.md) | **How are cycle-level failures inspected?** Questa commands, curated signal groups, full-core waveform reading, capture procedure, and evidence policy |

## 3. Requirement-to-evidence flow

Public claims should remain traceable through the repository in this order:

1. the official RISC-V specifications define standard architectural behavior;
2. [Architecture](architecture.md) selects and bounds the implemented behavior;
3. [Pipeline and control](pipeline-control.md) defines the cycle-level mechanism
   and invariants used to preserve it;
4. the checked-in RTL implements those contracts;
5. [Verification](verification.md) maps requirements to self-checking evidence;
6. [Software](software.md) and [FPGA implementation](fpga.md) define the
   integration conditions under which end-to-end results are valid;
7. [Hardware validation](hardware-validation.md) records provenance and keeps
   functional, performance, implementation, and physical-board evidence
   separate unless they are explicitly bound to the same artifact;
8. the root [README](../README.md) reports only the resulting public claims.

Useful cross-document review points are:

| Concern | Design contract | Acceptance evidence |
|---|---|---|
| ISA and visible state | [Architecture §§2–3](architecture.md#2-design-scope-and-compliance-boundary) | [Verification §4.1](verification.md#41-architectural-requirements) |
| Forwarding, hazards, and waits | [Pipeline §§3–4](pipeline-control.md#3-dependencies-and-forwarding) | [Verification §4.2](verification.md#42-microarchitectural-and-interface-requirements) |
| Redirect and precise-trap ordering | [Pipeline §§5–7](pipeline-control.md#5-control-transfer-recovery) | [Verification §§6–7](verification.md#6-integration-verification) |
| Memory map and completion mailbox | [Software §§4–7](software.md#4-memory-and-linker-contract) | [Verification §7.1](verification.md#71-bare-metal-programs) |
| MTIP, timer, UART, GPIO, and FreeRTOS | [Architecture §§6–7](architecture.md#6-memory-architecture), [Software §5](software.md#5-freertos-profile) | [Verification §§5.2–7.1](verification.md#52-pipeline-and-soc-invariants) |
| FPGA timing and board behavior | [FPGA §§8–10](fpga.md#8-latest-supplied-implementation-result) | [Verification §10](verification.md#10-sign-off-policy) |

Waveforms are supporting debug evidence, not the pass/fail oracle. Simulation,
architectural regression, routed timing, estimated power, and physical-board
observation are separate evidence classes and must not be presented as
interchangeable results.

## 4. RTL review entry points

| Review focus | Primary implementation files |
|---|---|
| Types and pipeline packets | [`rv32_pkg.sv`](../rtl/core/rv32_pkg.sv) |
| Core integration and commit | [`rv32_core.sv`](../rtl/core/rv32_core.sv) |
| Global ordering and dependencies | [`pipeline_ctrl.sv`](../rtl/core/pipeline_ctrl.sv), [`hazard_unit.sv`](../rtl/core/hazard_unit.sv), [`forwarding_unit.sv`](../rtl/core/forwarding_unit.sv) |
| Execute and RV32M | [`ex_stage.sv`](../rtl/core/ex_stage.sv), [`mul_unit.sv`](../rtl/core/mul_unit.sv), [`div_unit.sv`](../rtl/core/div_unit.sv) |
| Memory protocol and TCM | [`rv32_mem_if.sv`](../rtl/core/rv32_mem_if.sv), [`lsu.sv`](../rtl/core/lsu.sv), [`rv32_tcm.sv`](../rtl/soc/rv32_tcm.sv) |
| CSR state and precise traps | [`csr_file.sv`](../rtl/core/csr_file.sv) |
| SoC fabric and peripherals | [`rv32_mem_demux.sv`](../rtl/soc/rv32_mem_demux.sv), [`rv32_mtimer.sv`](../rtl/soc/rv32_mtimer.sv), [`rv32_uart.sv`](../rtl/soc/rv32_uart.sv), [`rv32_gpio.sv`](../rtl/soc/rv32_gpio.sv) |
| SoC and board integration | [`soc_tcm_top.sv`](../rtl/soc/soc_tcm_top.sv), [`fpga_top.sv`](../rtl/fpga/fpga_top.sv), [`main.xdc`](../constraint/main.xdc) |
| Build and regression inventory | [Top-level Makefile](../Makefile), [`core.f`](../files/core.f), [`integration.f`](../files/integration.f), and [`fpga.f`](../files/fpga.f) |

## 5. Suggested review paths

- **Recruiter or first-time reviewer:** project README → Architecture →
  Verification.
- **CPU/RTL reviewer:** Architecture → Pipeline and control → Verification →
  Waveform debug.
- **Software or SoC integrator:** Architecture §6 → Software → Verification.
- **FPGA reviewer:** Architecture §6 → FPGA implementation → Verification §10.
- **Contributor changing behavior:** relevant design contract → RTL →
  requirement traceability → focused test → full regression.
- **Release reviewer:** Verification → FPGA implementation → Hardware
  validation → project README claim review.

## 6. Source-of-truth policy

| Subject | Authority |
|---|---|
| Standard instruction and CSR semantics | Official RISC-V specifications |
| Implemented ISA, CSR, trap, memory, and retirement boundary | `architecture.md` reviewed against the checked-in RTL |
| Pipeline latency, ordering, hold, flush, and recovery behavior | `pipeline-control.md` and the checked-in RTL |
| Software ABI, linker layout, runtime, and mailbox | `software.md` plus the corresponding checked-in software sources |
| FPGA part, pins, reset, image, and implementation result | `fpga.md`, synthesis RTL, XDC, and archived Vivado evidence |
| Passing status and remaining gaps | `verification.md` and reproducible regression artifacts |
| Hardware evidence identity, compatibility, and artifact hashes | `hardware-validation.md`, referencing the architecture, verification, software, and FPGA authorities above |
| Public summary | Root `README.md`, derived from the authorities above |

Any disagreement between a document, RTL, test, constraint, or software image
is a release defect—not permission to choose the most favorable claim. A
behavioral change should update its owning specification and traceability row
in the same change as the implementation and tests.

## 7. Evidence gallery

The committed visual evidence is routed through its owning document:

| Evidence | Owning document |
|---|---|
| SoC memory-map diagram | [Architecture](architecture.md) |
| Public regression and ACT4 logs | [Verification](verification.md) |
| FreeRTOS Verilator and Questa runs | [Verification](verification.md), [Hardware validation](hardware-validation.md) |
| FPGA firmware build and SHA-256 output | [Software](software.md), [Hardware validation](hardware-validation.md) |
| Timing, utilization, power, device, and hierarchy views | [FPGA implementation](fpga.md), [Hardware validation](hardware-validation.md) |
| Physical board and CH340 UART observation | [FPGA implementation](fpga.md), [Hardware validation](hardware-validation.md) |

Screenshots support review but do not replace self-checking logs, hashed text
reports, source provenance, or exact artifact identity.

## 8. Specification baseline

<p align="center">
  <img src="images/riscv-logo.png" alt="RISC-V logo" width="420">
</p>

<p align="center"><em>The standard ISA behavior referenced by this project is
defined by the official RISC-V specifications listed below.</em></p>

Architectural review uses the official ratified specifications:

- [RV32I Base Integer Instruction Set, Version 2.1](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)
- [M Extension for Integer Multiplication and Division, Version 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/m-st-ext.html)
- [Zicsr Extension for CSR Instructions, Version 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicsr.html)
- [Machine-Level ISA, Version 1.13](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html)
- [FreeRTOS Kernel V11.3.0](https://github.com/FreeRTOS/FreeRTOS-Kernel/releases/tag/V11.3.0)

The RISC-V specifications define architectural behavior; they do not prescribe
this core's five-stage organization, latency, memory interface, CSR subset, or
FPGA integration.
