# QuestaSim waveform and portfolio evidence flow

## Purpose

This flow turns the existing self-checking regression into reproducible,
reviewable waveform evidence. Verilator remains the fast regression and CI
engine. QuestaSim is the interactive debug companion for inspecting timing,
pipeline occupancy, arbitration priority, and precise architectural commit.

The waveform set follows the implemented contracts in
[Architecture](architecture.md) and
[Pipeline and control](pipeline-control.md): a single-issue in-order
IF-ID-EX-MEM-WB RV32IM core, EX-resolved control transfers, EX/MEM and MEM/WB
forwarding, one-bubble load-use interlock, blocking memory/MDU operations,
minimal Machine mode/Zicsr, and a single commit point in MEM/WB.

The local `refs/riscv` core is used only as an implementation concept reference
for iterative division, pipeline hold/squash, and CSR cause handling. Its RTL is
not compiled into this design. Architectural results follow the official RV32I
2.1, M 2.0, and Machine ISA 1.13 references linked in the design document.

## Scope and honest claims

Waveforms in this directory support these claims:

- five-stage RV32IM execution and architectural retirement;
- RAW forwarding, load-use interlock, memory and MDU backpressure;
- EX-resolved branch/JAL/JALR/MRET redirect and two-younger squash;
- precise exception ordering and Machine-mode trap/MRET behavior;
- dual-port TCM integration and an FPGA-facing reset/status wrapper.

They do not claim cache, MMU, S/U modes, interrupts, superscalar execution,
ACT4 or differential Spike sign-off from waveform evidence alone, FPGA timing
closure, or physical board validation. Waveforms complement self-checking
tests; a picture alone is not functional coverage or certification.

## Prerequisites

Questa commands must be in `PATH`:

```sh
export PATH="/path/to/questa/bin:$PATH"
vlog -version
vsim -version
```

The flow has been exercised with Questa Altera Starter FPGA Edition 2025.2.
Tool names can be overridden without changing the Makefile, for example:

```sh
make questa-run TEST=tb_rv32_core QUESTA_VSIM=/opt/questa/bin/vsim
```

Generated libraries, transcripts, and WLF databases are isolated at
`/tmp/rv32im-core-questa-<uid>/<test>/`. This is important because the repository
path may contain spaces and because parallel test libraries must not collide.

## Commands

List the curated portfolio:

```sh
make questa-list
```

Compile only, run headless, or open the GUI:

```sh
make questa-compile TEST=tb_rv32_core
make questa-run     TEST=tb_rv32_core
make questa-gui     TEST=tb_rv32_core
```

Run all 11 curated hardware tests in batch mode:

```sh
make questa-check
```

Debug software and ISA images through the shared bare-metal harness:

```sh
make questa-baremetal-gui PROGRAM=smoke
make questa-baremetal-gui PROGRAM=trap
make questa-isa-gui ISA_TEST=rv32ui-add
make questa-isa-gui ISA_TEST=rv32um-div
```

Remove only the generated Questa tree:

```sh
make questa-clean
```

`TEST` must have a matching `<test>_SRCS` manifest in the top-level Makefile.
The compile order is package, interface, leaf RTL, core/integration RTL, common
testbench utilities, and one testbench top. Compiling one top at a time prevents
unrelated initial blocks from participating in a GUI session.

The default simulator flags contain one narrow waiver, `-suppress 7061`.
Integration testbenches preload `u_tcm.mem[]` through a verification backdoor,
while the synthesizable TCM writes the same array in `always_ff`. Questa treats
those two procedural sources as an error even though preload completes before
reset release. The waiver keeps the RAM coding style suitable for BRAM inference
and suppresses no architectural assertion or protocol diagnostic. Override
`QUESTA_VSIM_FLAGS` if a project variant does not use backdoor preload.

## Curated verification matrix

| Order | Architecture gate | Testbench | Waveform proof objective |
|---:|---|---|---|
| 1 | Gate 2 | `tb_mul_unit` | Four RV32M multiply variants, registered result, response backpressure and kill |
| 2 | Gate 2 | `tb_div_unit` | 32-step restoring divide, signed correction, divide-by-zero/overflow, sticky response |
| 3 | Gate 2 | `tb_lsu` | Little-endian byte lanes, LB/LBU/LH/LHU extraction, alignment and access faults |
| 4 | Gates 2/4 | `tb_pipeline_ctrl` | Age-ordered action selection and exact enable/flush/redirect masks |
| 5 | Gate 4 | `tb_pipeline_forwarding` | EX/MEM priority, MEM/WB forwarding, WB-to-ID behavior and one load-use bubble |
| 6 | Gate 4 | `tb_pipeline_memory_wait` | Request backpressure, delayed response, global hold, and MDU suppression behind memory |
| 7 | Gates 4/5 | `tb_pipeline_control` | Taken/not-taken control, two-stage squash, exception priority, trap drain and MRET |
| 8 | Gate 5 | `tb_csr_core` | Zicsr dependencies, CSR commit, counters, trap state and redirection |
| 9 | Gates 3-5 | `tb_rv32_core` | End-to-end IF-ID-EX-MEM-WB occupancy and single architectural commit stream |
| 10 | Gate 8 boundary | `tb_soc_tcm_top` | Independent instruction/data handshakes over TCM and retirement-qualified mailbox |
| 11 | Gate 8 boundary | `tb_fpga_top` | Async reset assertion, synchronous release, heartbeat, PASS/FAIL/DONE LEDs |
| 12 | Gates 5/6 | `tb_baremetal` | Real software/ISA execution at the retirement boundary; launched by image-specific targets |

The first 11 form `make questa-check`. `tb_baremetal` is separate because it
requires `+test` and `+mem` runtime arguments.

## Reading the full-core waveform

<p align="center">
  <a href="images/full-core-pipeline-waveform.png">
    <img
      src="images/full-core-pipeline-waveform.png"
      alt="Full-core five-stage pipeline waveform with stage occupancy, control, memory, and retirement signals"
      width="1100"
    >
  </a>
</p>

<p align="center"><em>Representative full-core capture. The self-checking
test result remains the oracle; the waveform explains cycle-level causality.</em></p>

The four packed registers are the authoritative stage-boundary state:

```text
fetch -> if_id_q -> id_ex_q -> ex_mem_q -> mem_wb_q -> trace/commit
```

For each screenshot, start with `valid`, `pc`, and `insn` in those packets. Then
use the relevant control group:

- data hazard: `ex_fwd_a_sel`, `ex_fwd_b_sel`, and `load_use_hazard`;
- structural wait: `ex_wait`, `mem_wait`, and stage enable/flush outputs;
- control hazard: `control_redirect`, `redirect_valid`, `redirect_pc`,
  `if_id_flush`, and `id_ex_flush`;
- precise trap: exception events, controller `action`, `trap_drain_q`, `wb_trap`,
  `mepc`, `mcause`, and `mtval`;
- architectural proof: `trace_valid`, trace PC/instruction, GPR writeback, memory
  write strobes/data, trap cause, and control target.

Important invariants visible in the curated waves are:

1. EX/MEM forwarding wins over MEM/WB when both match.
2. A load-use dependency holds PC and IF/ID and flushes ID/EX for one bubble.
3. A memory wait holds the owning EX/MEM packet and prevents repeated WB commit.
4. A taken EX control transfer flushes IF/ID and ID/EX; a not-taken branch does not.
5. An older MEM fault or WB trap wins over a younger EX redirect.
6. Faulting or squashed instructions never assert architectural side effects.
7. Only MEM/WB drives a valid retirement event.

## Report capture procedure

For every selected figure:

1. Run the corresponding Verilator test first, for example
   `make tb_pipeline_forwarding`.
2. Run `make questa-run TEST=<test>` and retain its PASS transcript.
3. Open `make questa-gui TEST=<test>`; the curated `.do` file loads and runs.
4. Locate one event, then zoom to roughly 10-30 cycles around it instead of
   capturing the entire simulation.
5. Expand packed pipeline records only as far as needed to show `valid`, `pc`,
   `insn`, destination metadata, and exception state.
6. Keep hexadecimal radix for addresses/instructions/data and symbolic display
   for enums such as the controller action and forwarding selects.
7. Caption the stimulus, expected invariant, observed cycles, and final PASS.

A strong portfolio report uses six to eight focused figures rather than one
image per test. Recommended headline figures are forwarding/load-use, memory
wait, branch squash, precise trap/MRET, full-core retirement, and SoC/FPGA
completion. MUL/DIV/LSU unit figures can appear in an appendix.

Do not commit WLF databases, local libraries, `modelsim.ini`, or transcripts.
They are machine/tool-version artifacts and are ignored by Git. Commit the
source manifests, `.do` recipes, documentation, and self-checking testbenches.

## GitHub and CV presentation strategy

A reviewable commit sequence is:

1. `sim: add isolated Questa compile and batch flow`
2. `sim: add architecture-aligned waveform recipes`
3. `docs: add Questa evidence and report workflow`

Before pushing, run:

```sh
make test
make questa-check
git diff --check
```

Commercial Questa licensing normally makes GitHub-hosted CI unsuitable. Keep
Verilator as the required public CI job and publish the exact local
`make questa-check` command plus a concise PASS summary. Do not upload Siemens
tool binaries, license files, proprietary logs, or copied reference RTL.

A defensible CV bullet is:

> Built a reproducible QuestaSim debug/evidence flow for a SystemVerilog
> five-stage RV32IM core, with architecture-focused views for forwarding,
> load-use and memory stalls, branch squash, precise Machine-mode traps,
> retirement, dual-port TCM integration, and FPGA reset/status behavior.

## Troubleshooting

- `unknown TEST`: use `make questa-list` and check the `<test>_SRCS` manifest.
- missing internal signals: launch through `make questa-gui`; it supplies
  `-voptargs=+acc` so optimized internal state remains visible.
- `couldn't open socket`: run from a normal desktop shell. Sandboxes/containers
  can block the local socket used by Questa even in console mode.
- missing FPGA memory image: start from the repository root through Make; the
  testbench intentionally uses the repository-relative `tb/data` path.
- stale elaboration: run `make questa-clean`, then rebuild the selected test.
- very slow GUI: remove broad recursive signals; the curated files deliberately
  select contract-level state instead of `add wave -r /*`.
