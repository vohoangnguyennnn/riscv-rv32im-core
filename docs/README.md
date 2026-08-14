# RV32IM Core Engineering Documentation

This directory is the engineering documentation portal for the implemented
RV32IM five-stage processor. The root [project README](../README.md) provides
the public overview, results, and quick start; the documents below define the
reviewed architecture, microarchitectural control, verification evidence,
software contract, and FPGA integration behind those claims.

[Architecture](architecture.md) ·
[Pipeline and control](pipeline-control.md) ·
[Verification](verification.md) ·
[Software](software.md) ·
[FPGA](fpga.md) ·
[Waveforms](waveform-debug.md) ·
[Release](release-checklist.md)

## 1. Implemented baseline

| Area | Documented configuration |
|---|---|
| Processor | Single-hart, single-issue, in-order IF–ID–EX–MEM–WB core |
| ISA | RV32I 2.1 and the complete RV32M 2.0 instruction set |
| Additional support | Six Zicsr 2.0 operations over the implemented CSR set, `MRET`, and precise synchronous M-mode traps |
| Memory boundary | Independent blocking instruction/data request-response ports; at most one outstanding transaction per port |
| Baseline SoC | Unified 64 KiB true-dual-port TCM with optional firmware initialization |
| Software | Freestanding `rv32im_zicsr`/ILP32 runtime, direct trap entry, linker-defined memory map, and retirement-qualified completion mailbox |
| Verification | Self-checking unit/integration tests, compiled software, pinned `riscv-tests`, Sail-backed ACT4, and FPGA smoke tests |
| FPGA | MicroPhase A7-Lite R1.1, Artix-7 `xc7a35tfgg484-2`, implemented at 50 MHz and exercised on the physical board |

This is a deliberately bounded processor implementation. It does not claim
official RISC-V certification, the complete Privileged Architecture, caches,
an MMU, interrupts, a standard SoC bus, an operating system, or silicon
validation. Exact inclusions and exclusions are normative in
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
| [Software](software.md) | **How does executable software use the core?** ILP32 ABI, startup, trap wrapper, linker map, runtime API, mailbox encoding, ELF-to-memory-image flow, and FPGA firmware contract |
| [FPGA implementation](fpga.md) | **How is the design realized and observed on hardware?** Board boundary, reset, TCM initialization, XDC, Vivado flow, implementation results, bring-up, and the public hardware-evidence boundary |
| [Waveform debug](waveform-debug.md) | **How are cycle-level failures inspected?** Questa commands, curated signal groups, full-core waveform reading, capture procedure, and evidence policy |
| [Release checklist](release-checklist.md) | **What must be true before publication?** Regression, repository hygiene, evidence capture, versioning, GitHub configuration, and release metadata |

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
7. the root [README](../README.md) reports only the resulting public claims.

Useful cross-document review points are:

| Concern | Design contract | Acceptance evidence |
|---|---|---|
| ISA and visible state | [Architecture §§2–3](architecture.md#2-design-scope-and-compliance-boundary) | [Verification §4.1](verification.md#41-architectural-requirements) |
| Forwarding, hazards, and waits | [Pipeline §§4–6](pipeline-control.md#4-gpr-dependency-control) | [Verification §4.2](verification.md#42-microarchitectural-and-interface-requirements) |
| Redirect and precise-trap ordering | [Pipeline §§7–9](pipeline-control.md#7-control-transfer-recovery) | [Verification §§6–7](verification.md#6-integration-verification) |
| Memory map and completion mailbox | [Software §§4–7](software.md#4-memory-and-linker-contract) | [Verification §7.1](verification.md#71-bare-metal-programs) |
| FPGA timing and board behavior | [FPGA §§8–10](fpga.md#8-reviewed-implementation-result) | [Verification §10](verification.md#10-sign-off-policy) |

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
- **Release owner:** Verification → FPGA implementation → Release checklist →
  project README claim review.

## 6. Source-of-truth policy

| Subject | Authority |
|---|---|
| Standard instruction and CSR semantics | Official RISC-V specifications |
| Implemented ISA, CSR, trap, memory, and retirement boundary | `architecture.md` reviewed against the checked-in RTL |
| Pipeline latency, ordering, hold, flush, and recovery behavior | `pipeline-control.md` and the checked-in RTL |
| Software ABI, linker layout, runtime, and mailbox | `software.md` plus the corresponding checked-in software sources |
| FPGA part, pins, reset, image, and implementation result | `fpga.md`, synthesis RTL, XDC, and archived Vivado evidence |
| Passing status and remaining gaps | `verification.md` and reproducible regression artifacts |
| Public summary | Root `README.md`, derived from the authorities above |

Any disagreement between a document, RTL, test, constraint, or software image
is a release defect—not permission to choose the most favorable claim. A
behavioral change should update its owning specification and traceability row
in the same change as the implementation and tests.

## 7. Specification baseline

Architectural review uses the official ratified specifications:

- [RV32I Base Integer Instruction Set, Version 2.1](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)
- [M Extension for Integer Multiplication and Division, Version 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/m-st-ext.html)
- [Zicsr Extension for CSR Instructions, Version 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicsr.html)
- [Machine-Level ISA, Version 1.13](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html)

The RISC-V specifications define architectural behavior; they do not prescribe
this core's five-stage organization, latency, memory interface, CSR subset, or
FPGA integration.

## 8. Historical design scope

[`rv32im-5stage-design.md`](rv32im-5stage-design.md) is retained as the original
implementation plan, gate history, and design rationale. It is useful for
understanding how the project reached the current baseline, but it is not the
current implementation specification. When it differs from the reviewed
English document set or checked-in RTL, treat the discrepancy as historical
context and use the current documents and implementation for release decisions.
