# RV32IM Verification Strategy

This document defines the verification strategy, requirement traceability, and
current evidence for the RV32IM five-stage core. It describes checks that exist
in the repository today; planned techniques are identified explicitly and are
not included in the passing baseline.

The programmer-visible contract is defined in
[Architecture](architecture.md), cycle-level ordering is defined in
[Pipeline and control](pipeline-control.md), and the software execution
environment is defined in [Software](software.md). The project-level result
summary and quick-start commands remain in the
[README](../README.md#verification).

## 1. Verification objectives

The verification plan is organized around four objectives:

1. **Architectural correctness:** every implemented RV32I, RV32M, Zicsr, and
   machine-mode-subset operation produces the documented programmer-visible
   result.
2. **Precise in-order execution:** dependencies, waits, redirects, and traps
   preserve program order and suppress faulting or wrong-path side effects.
3. **Interface correctness:** instruction/data requests remain stable under
   backpressure, each accepted request receives one ordered response, and
   killed responses are drained without re-entering the pipeline.
4. **Reproducibility:** tests are self-checking, have deterministic termination,
   use pinned external test sources where practical, and retain actionable
   failure artifacts.

The verification target is the checked-in implementation, not an abstract
fully privileged RISC-V platform. The core intentionally excludes interrupts,
U/S modes, PMP, caches, an MMU, debug mode, compressed instructions, and all
other ISA extensions listed outside the architectural scope.

## 2. Reference baseline and claim boundary

| Requirement source | Applied scope |
|---|---|
| RISC-V RV32I, version 2.1 | Integer state, instruction results, control flow, loads/stores, `FENCE`, `ECALL`, and `EBREAK` |
| RISC-V M extension, version 2.0 | Four multiply and four divide/remainder operations, including divide-by-zero and signed-overflow results |
| RISC-V Zicsr, version 2.0 | Six CSR read-modify-write instruction semantics over the implemented CSR address set |
| RISC-V Machine-Level ISA, version 1.13 | Only the documented synchronous trap/CSR subset and `MRET` behavior |
| Architecture and pipeline specifications | Implemented scope, pipeline structure, interfaces, action priority, and completion behavior |
| Checked-in RTL | Implementation-specific latency, handshake, action priority, and recovery behavior |

The official ISA documents define architectural results; they do not prescribe
this core's five-stage timing. Conversely, passing the regressions below does
not imply official RISC-V certification, full Zicsr compliance, or full
Privileged Architecture compliance. ACT4 is an independent architectural-test
layer for the I/M claim and does not replace design-specific verification of
pipeline control, CSRs, or traps.

## 3. Verification architecture

The environment is deliberately lightweight and audit-friendly. It uses
self-checking SystemVerilog testbenches, compiler-generated bare-metal images,
architectural signatures, and a retirement-event interface rather than a UVM
class hierarchy.

```text
           direct expected values and protocol invariants
                              |
        +---------------------+---------------------+
        |                     |                     |
   leaf/stage unit       full-core directed    software/ISA ELF
      testbenches          integration             images
        |                     |                     |
        +---------- SystemVerilog RTL -------------+
                              |
                 architectural retirement trace
                              |
             signatures / tohost / CSV diagnostics
```

### 3.1 Layered regression

| Layer | DUT boundary | Primary oracle | Current baseline |
|---|---|---|---:|
| Static RTL | Core, TCM, SoC, reset, FPGA top | Strict Verilator lint with documented structural waivers | PASS |
| Unit simulation | Combinational units, stateful units, stages, and controller | Direct expected values plus handshake/state invariants | 17/17 PASS |
| Integration simulation | Core pipeline, CSR/trap path, SoC/TCM, and FPGA wrapper | Architectural signatures, retirement events, and selected internal invariants | 7/7 PASS |
| Bare-metal software | Full core + 64 KiB TCM + runtime | Retirement-qualified `tohost` status | 2/2 PASS |
| Pinned `riscv-tests` | Full core + 64 KiB TCM | Upstream self-checking signatures and `tohost` | 40 RV32I + 8 RV32M PASS |
| ACT4 + Sail | Full core + simulation-only 1 MiB TCM | Sail-derived expected signatures in self-checking ELFs | 39 RV32I + 8 RV32M PASS |
| Questa portfolio | Eleven selected hardware testbenches | Same self-checkers plus curated waveform inspection | Local debug/evidence flow |
| FPGA smoke | FPGA top + initialized TCM | Board-visible heartbeat/PASS/FAIL/DONE | Observed locally; public evidence bundle pending |

`make test` is the public RTL regression entry point. It runs lint, all 24 RTL
simulations, both bare-metal programs, and all 48 pinned `riscv-tests`
programs. ACT4 is separate because it requires additional pinned generators,
the Sail model, and network/tool bootstrap steps.

### 3.2 Design-gate closure

The original staged plan remains useful as a release audit trail:

| Design gate | Closure evidence | Status |
|---|---|---:|
| Gate 0 — lint/build | Verilator lint for five synthesis boundaries; shared ordered source manifests | PASS |
| Gate 1 — combinational units | Immediate, decoder, ALU, and branch unit tests | PASS |
| Gate 2 — stateful leaf units | Regfile, IF/ID/EX, LSU, MDU, CSR, TCM, reset, and controller tests | PASS |
| Gate 3 — hazard-free pipeline | Full-core directed execution and bare-metal smoke path | PASS |
| Gate 4 — forwarding/hazards | Three dedicated pipeline integration tests plus unit invariants | PASS |
| Gate 5 — machine-mode subset | CSR core integration, precise-control integration, and trap software | PASS |
| Gate 6 — `riscv-tests` | 40 RV32I and 8 RV32M programs | PASS |
| Gate 6A — ACT4 | 39 RV32I and 8 RV32M Sail-backed tests | PASS |
| Gate 7 — differential/random | Retirement differential and generated random programs | OPEN |
| Gate 8 — FPGA | Routed 50 MHz image and local on-board smoke | Local closure; public evidence pending |

Gate 7 is intentionally not folded into the baseline result. Gate 8 concerns
implementation and hardware evidence rather than replacing functional RTL
verification.

### 3.3 Checker and oracle policy

- Unit tests calculate expected results independently of the DUT datapath and
  terminate with `$fatal` on the first mismatch.
- Integration tests prefer architectural memory signatures and retirement
  events. Internal signals are checked only where an architectural signature
  cannot prove an exact microarchitectural invariant, such as forwarding
  priority, bubble count, payload stability, or flush mask.
- Software and ISA tests complete only through a retired aligned full-word
  store to the configured `tohost` address. A speculative, faulting, or
  squashed store cannot falsely report PASS.
- Every software image starts from a cleared TCM, is loaded independently, and
  has both cycle and retirement-event timeouts.
- The bare-metal harness retains the most recent 256 retirement events and can
  emit a complete CSV trace for failure triage.

The current suite uses deterministic procedural checkers. Verilator is invoked
with assertion support, but this baseline does not claim a concurrent-SVA,
formal-proof, UVM, constrained-random, code-coverage, or functional-coverage
closure.

## 4. Requirement-to-evidence traceability

### 4.1 Architectural requirements

| Requirement | Principal evidence |
|---|---|
| RV32I decode and integer results | `tb_decoder`, `tb_imm_gen`, `tb_alu`, `tb_branch_unit`; 40 pinned RV32I programs; 39 ACT4 RV32I tests |
| Complete RV32M results | `tb_mul_unit`, `tb_div_unit`, `tb_ex_stage`; all 8 pinned RV32M programs; all 8 ACT4 RV32M tests |
| `x0`, GPR addresses, and WB semantics | `tb_regfile`, `tb_id_stage`, `tb_rv32_core`, retirement trace checks |
| JAL/JALR/branch results and targets | `tb_branch_unit`, `tb_ex_stage`, `tb_pipeline_control`, RV32I control-flow programs |
| Little-endian byte/half/word accesses | `tb_lsu`, `tb_rv32_tcm`, `tb_soc_tcm_top`, RV32I memory programs |
| Misalignment and access-fault policy | `tb_lsu`, `tb_if_stage`, `tb_pipeline_control` |
| Six Zicsr operations and CSR legality | `tb_decoder`, `tb_csr`, `tb_csr_core`, `tb_rv32_core` |
| `mcycle`/`minstret` and explicit writes | `tb_csr`, `tb_csr_core`, full-core retirement accounting |
| Precise synchronous traps and `MRET` | `tb_pipeline_ctrl`, `tb_pipeline_control`, `tb_csr_core`, bare-metal `trap` |
| Freestanding RV32IM/Zicsr execution | Bare-metal `smoke` and `trap` through the production startup, linker, TCM, and core |

### 4.2 Microarchitectural and interface requirements

| Invariant | Principal evidence |
|---|---|
| A valid instruction retires or traps at most once | MEM-wait integration checks, retirement-event counts, software harness history |
| EX/MEM forwarding wins over an older MEM/WB match | `tb_forwarding_unit`, `tb_pipeline_forwarding` |
| An adjacent load consumer receives exactly one bubble with the default TCM | `tb_hazard_unit`, `tb_pipeline_forwarding` |
| False `rs1`/`rs2` field matches do not stall or forward | `tb_hazard_unit`, decoder source-use metadata, directed LUI/load sequence |
| Request payload remains stable until `req_ready` | `tb_if_stage`, `tb_lsu`, `tb_pipeline_memory_wait` |
| Delayed responses hold the owner without duplicate commit | `tb_pipeline_memory_wait`, `tb_pipeline_ctrl` |
| A killed accepted request is drained and cannot return stale state | `tb_if_stage`, `tb_lsu`, redirect and fault scenarios |
| Taken EX control flushes IF/ID and ID/EX; not-taken control does not | `tb_pipeline_ctrl`, `tb_pipeline_control` |
| Older trap/fault/wait wins over younger redirect or execution | `tb_pipeline_ctrl`, `tb_pipeline_control` |
| Wrong-path register, CSR, memory, and MDU side effects are suppressed | `tb_pipeline_forwarding`, `tb_pipeline_control`, sentinel checks |
| Reset clears control state without resetting the TCM array | `tb_reset_sync`, `tb_rv32_tcm`, `tb_fpga_top` |

The tables above retain the requirement-to-checker mapping for dependencies,
priority collisions, waits, redirects, and precise squash. Cycle-level action
semantics are defined in [Pipeline and control](pipeline-control.md), not
duplicated here.

## 5. Unit verification

The 17 unit tests isolate datapath, protocol, and state-machine behavior before
full-pipeline interactions can mask a defect.

| Testbench | Verification responsibility | Baseline checks |
|---|---|---:|
| `tb_alu` | Arithmetic, logic, comparison, and shift boundaries | 32 |
| `tb_imm_gen` | I/S/B/U/J immediate reconstruction and sign extension | 21 |
| `tb_decoder` | Legal RV32IM/Zicsr decode and illegal encodings | 73 |
| `tb_branch_unit` | Signed/unsigned branches and control targets | 26 |
| `tb_regfile` | `x0`, x1-x31, synchronous write behavior | 72 |
| `tb_reset_sync` | Asynchronous assertion and synchronous release | 15 |
| `tb_rv32_tcm` | Dual-port access, byte writes, latency, and range errors | 86 |
| `tb_lsu` | Lane formatting, extraction, faults, backpressure, kill/drain | 438 |
| `tb_if_stage` | Fetch sequencing, request holds, redirect, stale-response discard | 339 |
| `tb_id_stage` | Decode/register-read integration and same-cycle WB bypass | 15 |
| `tb_forwarding_unit` | Independent operands, result classes, producer priority | 23 |
| `tb_hazard_unit` | Load-use/CSR dependencies and source qualification | 41 |
| `tb_mul_unit` | Four multiply variants, boundary vectors, hold, and kill | 755 |
| `tb_div_unit` | Four divide/remainder variants, identities, corner cases, hold, and reset | 8,041 |
| `tb_ex_stage` | ALU/control/CSR/MDU integration and EX acceptance | 43 |
| `tb_pipeline_ctrl` | All action masks, drain state, and priority collisions | 28 |
| `tb_csr` | CSR access, counters, trap entry, and `MRET` state | 47 |

The check counts describe the current deterministic vector set; they are not a
coverage percentage and should not be used to compare verification quality
between blocks.

## 6. Integration verification

| Testbench | Scope | Reproduced baseline |
|---|---|---|
| `tb_rv32_core` | End-to-end RV32IM pipeline and retirement stream | 191 cycles, 27 trace events |
| `tb_csr_core` | Zicsr dependencies, counters, precise traps, and return | 51 cycles |
| `tb_soc_tcm_top` | Core/TCM boundary and retirement-qualified mailbox | 32 checks |
| `tb_fpga_top` | Reset release, initialized image, heartbeat, and status pins | 33 checks |
| `tb_pipeline_forwarding` | RAW matrix, result classes, control consumers, and load-use | 237 cycles, 57 checks, 4 load-use bubbles |
| `tb_pipeline_memory_wait` | Request backpressure, delayed response, holds, and single retirement | 125 cycles, 96 MEM-wait cycles, 32 request-backpressure cycles |
| `tb_pipeline_control` | Branch/jump recovery, exception priority, trap drain, and `MRET` | 87 cycles, 44 checks, 2 precise traps |

Directed pipeline programs are encoded with helpers in
`tb/common/rv32_tb_pkg.sv`. Expected signatures remain independent of the RTL
decoder, while readable instruction construction keeps failures auditable.

The `make test` values in Sections 5–7 were reproduced locally on 2026-08-14.
The ACT4 baseline is tracked separately because it is not part of `make test`.

## 7. Software and architectural regressions

### 7.1 Bare-metal programs

The [software environment](software.md) builds freestanding ELF32 little-endian
binaries with `-march=rv32im_zicsr -mabi=ilp32` and loads them through the same
core/TCM hierarchy used by ISA tests.

| Program | Principal coverage | Baseline |
|---|---|---|
| `smoke` | Startup, ABI, stack alignment, initialized data, BSS, calls, memory, RV32M, and identification CSRs | 451 cycles, 171 trace events, 0 traps |
| `trap` | ECALL, EBREAK, illegal instruction, `mcause/mepc/mtval`, handler return, and three `MRET` recoveries | 838 cycles, 346 trace events, 3 traps |

Runtime, linker, mailbox, and image details are documented in
[Software](software.md).

### 7.2 Pinned `riscv-tests`

The repository vendors a minimal source snapshot from commit
`447a5fcb8253627ddb5f6a226f64e43463afcdd5`. The manifest runs 40 in-scope
`rv32ui` programs and all 8 `rv32um` programs independently on the complete
pipeline.

`fence_i` is excluded because Zifencei is outside the design scope. `ma_data`
is excluded because it assumes successful misaligned data accesses, while this
execution environment deliberately raises precise misalignment traps. These
are scope exclusions, not passing waivers. The exact program matrix is
maintained in `sw/isa/tests.mk`; upstream provenance is pinned in
`third_party/riscv-tests/UPSTREAM.md`.

### 7.3 ACT4 with Sail

ACT4 release 4.0.0 is pinned at commit
`a7c99303516f4e668f7488f172043392e23b9dfd`. The checked-in UDB configuration
selects I 2.1, M 2.0, Zicsr 2.0, RV32 little-endian execution, and the documented
misalignment/trap policy. Sail RISC-V 0.10 supplies expected signatures; ACT4
then builds 47 self-checking ELFs that run on the RTL.

The ACT4 result is 39/39 RV32I and 8/8 RV32M. Privileged ACTs are disabled
because the RTL implements only a minimal M-mode subset. The ACT4 TCM is
expanded to 1 MiB for generated images; this simulation parameter does not
change the 64 KiB FPGA configuration. Reproducible DUT configuration is kept
under `verification/act4/config`, while the pinned bootstrap and artifact flow
is implemented by the top-level `Makefile` and `verification/act4/run.py`.

<p align="center">
  <a href="images/act4.png">
    <img
      src="images/act4.png"
      alt="ACT4 4.0.0 regression showing all 47 RV32I and RV32M tests passing"
      width="900"
    >
  </a>
</p>

<p align="center"><em>Sail-backed ACT4 evidence: 39 RV32I and 8 RV32M
architectural tests passing on the RTL.</em></p>

## 8. Regression operation

### 8.1 Primary commands

| Command | Purpose |
|---|---|
| `make lint` | Lint core, TCM, SoC, reset synchronizer, and FPGA top |
| `make unit` | Run all 17 unit tests |
| `make integration` | Run all 7 integration tests |
| `make gate4` | Run forwarding, memory-wait, and control acceptance tests |
| `make baremetal` | Build and execute both freestanding programs |
| `make isa` | Run all 48 pinned `riscv-tests` programs |
| `make test` | Run lint, 24 RTL simulations, bare-metal, and ISA regression |
| `make act4` | Generate and run the separate 47-test ACT4 I/M regression |
| `make questa-check` | Run the 11-test local Questa debug/evidence portfolio |

One test can be isolated with its target name, for example:

```sh
make tb_pipeline_control
make isa-rv32ui-jalr
make act4-test ACT4_TEST='M-div*'
```

Generated Verilator models, software images, traces, Questa libraries, and
ACT4 work trees are kept below `/tmp/rv32im-core-*`. This avoids polluting the
repository and supports checkout paths containing spaces.

### 8.2 Continuous integration

`.github/workflows/rtl-regression.yml` runs `make test` on pushes, pull
requests, and manual dispatch. The job installs the open-source RTL and RISC-V
toolchain, prints tool versions, and uploads ELF, map, disassembly, and trace
diagnostics when the ISA job fails.

`.github/workflows/act4-regression.yml` is path-filtered to RTL and ACT4-relevant
changes. It checks the ACT4 commit, Sail archive checksum, and Z3 checksum, then
runs `make act4`; failure artifacts are retained for diagnosis. Questa remains
a local debug companion because commercial simulator licensing is unsuitable
for the required public CI gate.

## 9. Failure triage and waveform policy

Use the narrowest failing layer first:

1. reproduce the exact target without parallel jobs;
2. inspect the first `$fatal` and expected/actual values;
3. for software, map the failing retirement PC to the `.dump` file;
4. rerun with a CSV retirement trace;
5. open the matching curated Questa view only when cycle-level causality is
   still required;
6. preserve a minimal failing vector, program, ELF, or seed as a regression.

Example software trace capture:

```sh
make baremetal-smoke \
  BAREMETAL_PLUSARGS='+trace=/tmp/smoke.csv +max_cycles=300000'

make isa-rv32ui-add \
  ISA_PLUSARGS='+trace=/tmp/rv32ui-add.csv +max_cycles=300000'
```

Waveforms explain timing but are not the pass/fail oracle. Screenshots used as
portfolio evidence must be paired with a self-checking PASS transcript and a
caption stating the stimulus, invariant, and observed cycle window. The
curated signal groups and capture procedure are documented in
[Waveform debug](waveform-debug.md).

## 10. Sign-off policy

An RTL change affecting decode, execution, hazards, LSU, control, CSR, or
retirement is acceptable for the documented RV32IM baseline only when:

1. `make test` completes without an unexplained lint warning or test failure;
2. `make act4` passes for changes that can affect I/M architectural behavior;
3. directed CSR/trap tests and both bare-metal programs pass for changes to
   exception, CSR, counter, or retirement logic;
4. request/response and precise-squash tests pass for memory/control changes;
5. documentation, source manifests, and external-suite provenance remain
   consistent with the implementation.

FPGA-specific changes additionally require synthesis/implementation review and
an on-board smoke run. A public hardware claim should include board revision,
bitstream and firmware hashes, plus a photograph or logic-analyzer capture.
The complete procedure and current evidence boundary are defined in
[FPGA implementation](fpga.md).

### 10.1 Open verification work

The following items are useful extensions, not hidden prerequisites of the
current passing baseline:

- retirement-stream differential checking against Spike or another independent
  architectural model;
- deterministic constrained-random instruction generation with retained seeds;
- formal properties for handshakes, single retirement, and precise squash;
- simulator code coverage and requirement-linked functional coverage;
- asynchronous interrupt verification after the missing architectural state is
  implemented;
- cache/MMU/coherency verification if those blocks enter the design scope.

Until implemented, these items must not appear in project or CV claims as
completed verification methods.

## 11. Adding verification content

- Add a leaf or integration testbench under `tb/unit` or `tb/integration`, add
  its source list and target to the top-level `Makefile`, and keep it
  self-checking.
- Add readable directed instruction encoders to `tb/common/rv32_tb_pkg.sv`
  rather than copying decoder logic into a scoreboard.
- Add a freestanding software test under `sw/tests` and register it in
  `sw/tests/programs.mk`.
- Change the public ISA corpus only through `sw/isa/tests.mk`, with provenance
  retained in `third_party/riscv-tests/UPSTREAM.md` and exclusion rationale
  updated in this document.
- Add ACT4 configuration changes under `verification/act4/config` and rerun the
  complete generated count, not only a filtered test.
- Update this traceability matrix whenever a requirement, checker, or public
  verification claim changes.

## 12. References

- [RV32I Base Integer Instruction Set, Version 2.1](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)
- [M Extension for Integer Multiplication and Division, Version 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/m-st-ext.html)
- [Zicsr Extension for CSR Instructions, Version 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicsr.html)
- [Machine-Level ISA, Version 1.13](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html)
- [RISC-V Architectural Certification Tests](https://github.com/riscv/riscv-arch-test/tree/4.0.0)
- [Pinned `riscv-tests` provenance](../third_party/riscv-tests/UPSTREAM.md)
