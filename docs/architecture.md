# RV32IM Core Architecture

This document defines the implemented architecture of the RV32IM five-stage
processor in this repository. It is an implementation specification: statements
here are derived from the checked-in RTL rather than from planned features or
superseded design alternatives.

The core is a synthesizable, single-hart, single-issue, in-order RV32IM
processor with a classic IF–ID–EX–MEM–WB pipeline. It implements the complete
RV32I base integer instruction set and RV32M multiply/divide extension, the six
Zicsr read-modify-write instructions over a documented CSR set, and a minimal
machine-mode trap environment. It is intentionally not a complete
implementation of the RISC-V Privileged Architecture.

For cycle-level hazard, stall, flush, and redirect behavior, see
[Pipeline and control](pipeline-control.md). Requirement traceability and the
current verification evidence are defined in
[Verification](verification.md), while the runtime, linker, trap ABI, and
firmware-image flow are defined in [Software](software.md). The board-level
integration, implementation evidence, and hardware sign-off boundary are
defined in [FPGA implementation](fpga.md).

## 1. Architectural profile

| Property | Implemented configuration |
|---|---|
| ISA | RV32I 2.1 + RV32M 2.0 |
| Additional instructions | Six Zicsr 2.0 operations and `MRET` |
| XLEN | 32 bits |
| Hart model | One hart, single issue, in order |
| Pipeline | IF, ID, EX, MEM, WB |
| Instruction encoding | Fixed 32-bit instructions; `IALIGN=32` |
| Endianness | Little-endian |
| Register file | 32 × 32-bit GPRs; two asynchronous reads and one synchronous write |
| Control-transfer resolution | EX stage |
| Memory architecture | Independent instruction and data request/response ports |
| Default memory system | Unified 64 KiB true-dual-port TCM |
| Exception model | Precise synchronous exceptions committed at WB |
| Execution environment | Minimal M-mode-only bare-metal environment |
| Interrupts | Not implemented |
| Caches, MMU, PMP | Not implemented |

The baseline can accept and retire one instruction per cycle when there is no
data dependency requiring an interlock, no control redirect, no memory delay,
and no multicycle M-extension operation. This is a throughput capability, not
an application CPI claim.

<p align="center">
  <img
    src="images/rv32im-core-overview.png"
    alt="RV32IM core integrated with separate instruction and data paths, a dual-port TCM, reset synchronization, and firmware initialization"
    width="1000"
  >
</p>

<p align="center"><em>Implemented FPGA/SoC boundary: a five-stage RV32IM core,
separate instruction and data paths, and a firmware-initialized dual-port
TCM.</em></p>

## 2. Design scope and compliance boundary

### 2.1 Implemented instruction scope

| Class | Instructions |
|---|---|
| Upper immediate | `LUI`, `AUIPC` |
| Integer immediate | `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI` |
| Integer register-register | `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND` |
| Control transfer | `JAL`, `JALR`, `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |
| Loads | `LB`, `LH`, `LW`, `LBU`, `LHU` |
| Stores | `SB`, `SH`, `SW` |
| Memory ordering | `FENCE` |
| Environment | `ECALL`, `EBREAK` |
| RV32M multiply | `MUL`, `MULH`, `MULHSU`, `MULHU` |
| RV32M divide/remainder | `DIV`, `DIVU`, `REM`, `REMU` |
| CSR access | `CSRRW`, `CSRRS`, `CSRRC`, `CSRRWI`, `CSRRSI`, `CSRRCI` |
| Trap return | `MRET` within the documented M-mode subset |

<p align="center">
  <img
    src="images/rv32im-instruction-scope.png"
    alt="Implemented RV32I and RV32M instruction scope"
    width="1000"
  >
</p>

<p align="center"><em>Implemented RV32I/RV32M instruction boundary. The Zicsr
operations and minimal machine-mode control flow are summarized separately
below. Optional ISA, privilege, memory-system, and debug features are not
claimed.</em></p>

<p align="center">
  <img
    src="images/Zicsr.png"
    alt="Implemented Zicsr read, write, set, and clear instruction forms"
    width="420"
  >
</p>

<p align="center"><em>Implemented Zicsr CSR read/modify/write instruction
forms. The supported CSR addresses and access permissions are defined in
Section 3.2.</em></p>

The decoder validates the relevant opcode, `funct3`, and `funct7` fields.
Unsupported or reserved encodings generate an illegal-instruction exception
instead of being interpreted as a nearby legal operation.

`FENCE` is a legal ordering no-op in the implemented execution environment.
The current system is single-hart, uncached, blocking, and permits at most one
outstanding transaction per core memory port, so earlier memory operations have
completed before a later operation advances past them. `FENCE.I` belongs to
Zifencei and remains illegal because instruction-fetch synchronization for a
self-modifying or cached execution environment is outside this scope.

### 2.2 Explicitly unsupported

The architecture does not implement:

- the C, A, F, D, V, B, or other optional ISA extensions;
- Zifencei and instruction-cache synchronization;
- asynchronous interrupts or the `mie`, `mip`, and interrupt-enable fields;
- U-mode, S-mode, delegation, virtual memory, page tables, or `satp`;
- PMP, debug mode, triggers, or a JTAG debug transport;
- caches, coherency, branch prediction, speculative retirement, or multiple
  issue;
- AXI, AHB, APB, DDR, or memory-mapped peripheral integration in the baseline
  SoC.

Passing RV32I/RV32M regressions does not imply official RISC-V certification or
full privileged-architecture compliance. In particular, the implemented
`MRET` redirects to `mepc` but does not update an `mstatus` privilege/interrupt
stack because `mstatus` and interrupts are not present.

## 3. Programmer-visible state

### 3.1 Integer state

The hart exposes 32 integer registers, `x0`–`x31`, and a 32-bit program
counter. Register `x0` always reads as zero and ignores writes. Registers
`x1`–`x31` have no architectural reset requirement; startup software must not
assume an initial value.

The register file has two combinational read ports and one rising-edge write
port. An explicit WB-to-ID bypass defines same-cycle read-after-write behavior
independently of FPGA memory inference semantics.

### 3.2 Implemented machine CSRs

| CSR | Address | Access | Implemented behavior |
|---|---:|---:|---|
| `misa` | `0x301` | RO | `MXL=1`; I and M bits set (`0x4000_1100`) |
| `mtvec` | `0x305` | RW | Direct mode only; low two bits are forced to zero |
| `mscratch` | `0x340` | RW | General trap-handler scratch register |
| `mepc` | `0x341` | RW | Faulting PC; low two bits are forced to zero |
| `mcause` | `0x342` | RW/WLRL subset | Implemented synchronous cause in bits `[4:0]` |
| `mtval` | `0x343` | RW | Fault address, target, instruction, or zero as listed below |
| `mcycle` | `0xB00` | RW | Low half of a 64-bit cycle counter |
| `mcycleh` | `0xB80` | RW | High half of the cycle counter |
| `minstret` | `0xB02` | RW | Low half of a 64-bit retirement counter |
| `minstreth` | `0xB82` | RW | High half of the retirement counter |
| `mvendorid` | `0xF11` | RO | Reads zero |
| `marchid` | `0xF12` | RO | Reads zero |
| `mimpid` | `0xF13` | RO | Reads zero |
| `mhartid` | `0xF14` | RO | Reads zero for the single hart |

`mcycle` normally increments once per non-reset clock, and `minstret` normally
increments once for each non-trapping instruction retired at WB. An explicit
write to either RV32 counter half suppresses the corresponding implicit 64-bit
counter increment on that edge and replaces only the addressed half.

CSR reads and legality checks occur in EX, but state changes occur only at WB.
`CSRRW` and `CSRRWI` always request a write. The set/clear forms suppress their
write when `rs1=x0` or `zimm=0`, allowing read-only CSR access without an
illegal write. Access to an unimplemented CSR, or an actual write to a read-only
CSR, raises an illegal-instruction exception.

## 4. Microarchitecture

### 4.1 Top-level organization

```text
                    branch/JAL/JALR/MRET redirect
                                  |
                                  v
 imem <-> IF -> IF/ID -> ID -> ID/EX -> EX -> EX/MEM -> MEM -> MEM/WB -> WB
          |              |           |               |                 |
          |              |           |               +---- dmem       +-- GPR commit
          |              |           +-- ALU / branch / MUL / DIV      +-- CSR/trap commit
          |              +-- decode / immediate / register file        +-- retirement trace
          +-- PC / request tracking / stale-response discard

                         centralized pipeline control
          load-use + CSR dependency + EX wait + MEM wait + exception + redirect
```

The four interstage registers are packed structures defined in
`rv32_pkg.sv` and owned by `rv32_core.sv`. Each packet carries a `valid` bit;
`valid=0` represents a bubble. Pipeline storage follows the same priority rule:

```text
reset > flush > enable > hold
```

Clearing a packet on reset or flush prevents invalid payload fields from
creating accidental dependencies or side effects.

### 4.2 Stage responsibilities

| Stage | Primary responsibilities |
|---|---|
| IF | Track PC, issue instruction requests, buffer one response, discard stale responses after redirects, and attach instruction access faults |
| ID | Strict decode, immediate generation, GPR reads, WB-to-ID bypass, illegal instruction detection, and creation of the ID/EX packet |
| EX | Operand forwarding, ALU execution, address generation, branch/jump/MRET resolution, CSR read-modify-write, and blocking MUL/DIV execution |
| MEM | Drive the LSU, wait for data responses, format load results, and attach load/store faults |
| WB | Commit GPR/CSR state, take precise traps, increment `minstret`, and emit the architectural trace |

The core is in order from fetch through commit. There is no reorder buffer,
scoreboard, speculative state checkpoint, or out-of-order completion path.
Multicycle EX and delayed MEM operations hold the owning pipeline packet until
their response is accepted.

### 4.3 Data hazards and forwarding

Two independent EX operand muxes select the register-file snapshot, the newest
eligible EX/MEM result, or the final MEM/WB writeback value. EX/MEM has priority
over MEM/WB when both packets target the same source register. EX/MEM forwarding
supports ALU/MDU results, link values (`PC+4`), and old CSR values; loads are
excluded until their data reaches MEM/WB.

An immediately dependent load consumer receives one bubble with the default
one-cycle TCM. If memory takes longer, the blocking LSU and centralized
pipeline control extend the hold until the response arrives. Forwarded operands
are shared by ALU, branch/JALR comparison, store address/data, CSR, and MDU
consumers.

CSR accesses use a conservative serialization rule: a CSR instruction in ID
waits behind any older uncommitted CSR writer in ID/EX or EX/MEM. `MRET` waits
only for an older write to `mepc`; reads of `minstret` drain older retirement
events so the observed count remains program ordered.

Detailed priority and timing examples are specified in
[Pipeline and control](pipeline-control.md).

### 4.4 Control transfers

Conditional branches, `JAL`, `JALR`, and `MRET` resolve in EX using forwarded
source operands. Branch and `JAL` targets are PC-relative. `JALR` computes
`rs1 + imm` and clears bit 0 before the `IALIGN=32` alignment check.

A taken transfer flushes the younger IF/ID and ID/EX packets. With the default
one-cycle TCM this produces two control bubbles. A not-taken conditional branch
does not redirect or flush. A taken target with either low address bit set
raises an instruction-address-misaligned exception on the control-transfer
instruction; no redirect is issued.

Fetch can have one request in flight. If a redirect or trap invalidates that
request, IF marks its response stale, drains it without exposing it to decode,
and preserves the pending target until the instruction port is free.

## 5. RV32M execution

### 5.1 Multiplication

The multiplier supports all four RV32M multiply operations. Operands are
extended to 33 bits according to the required signedness, registered, and
multiplied through a synthesis-friendly expression. A second registered stage
selects the low or high 32-bit architectural result. The request/response
interface allows one operation in flight and holds a completed result stable
until EX accepts it.

| Operation | Operand interpretation | Result |
|---|---|---|
| `MUL` | Low-half result is signedness independent | Product `[31:0]` |
| `MULH` | Signed × signed | Product `[63:32]` |
| `MULHSU` | Signed × unsigned | Product `[63:32]` |
| `MULHU` | Unsigned × unsigned | Product `[63:32]` |

The generic RTL does not instantiate a vendor primitive. The registered
multiply boundary permits FPGA synthesis to infer DSP resources while keeping
the core portable.

### 5.2 Division and remainder

`DIV`, `DIVU`, `REM`, and `REMU` share a blocking radix-2 restoring divider.
Normal operations produce one quotient bit per cycle for 32 iterations and
apply sign correction at the boundary. Signed quotient rounding is toward zero,
and a nonzero signed remainder has the dividend's sign.

RISC-V defines arithmetic results rather than traps for the two divider corner
cases:

| Condition | Quotient | Remainder |
|---|---:|---:|
| Divisor is zero | `0xFFFF_FFFF` | Original dividend |
| `INT_MIN / -1` | `0x8000_0000` | `0x0000_0000` |

These cases complete locally without entering the 32-iteration loop. Neither
case generates an exception.

## 6. Memory architecture

### 6.1 Core memory-port contract

The core exposes separate `rv32_mem_if` master ports for instruction and data
traffic. Each port uses a blocking request/response protocol:

| Signal | Direction from core | Meaning |
|---|---:|---|
| `req_valid` | Output | Request and payload are valid |
| `req_ready` | Input | Slave can accept the request |
| `req_addr[31:0]` | Output | Byte address; physical bus request is word aligned |
| `req_write` | Output | Data write request |
| `req_wdata[31:0]` | Output | Lane-aligned write data |
| `req_wstrb[3:0]` | Output | Active byte lanes |
| `rsp_valid` | Input | Response is available |
| `rsp_rdata[31:0]` | Input | Returned aligned word |
| `rsp_err` | Input | Access failed |

A request is accepted on `req_valid && req_ready`. The slave returns exactly
one ordered response for each accepted request, including stores. There is no
response-ready signal because a core master always consumes the external
response, buffering it internally when the downstream pipeline is held. Each
port permits at most one outstanding request, although a slave may return the
old response and accept a new request in the same cycle.

This interface is the architectural integration seam for replacing the TCM
with a cache or bus bridge. Any replacement must preserve ordering, response,
error, and killed-request-drain behavior at the core boundary.

### 6.2 Load/store unit

The LSU supports byte, halfword, and word accesses. It calculates byte strobes
and shifted write data for little-endian stores, and extracts and sign- or
zero-extends returned subwords for loads. The bus sees an aligned word address;
the original effective byte address remains attached to the instruction for
formatting, tracing, and fault reporting.

Misaligned halfword or word accesses trap locally and do not issue a memory
request. An aligned request whose word address lies outside the configured TCM
range returns `rsp_err` and becomes a load/store access fault. A request that
was already presented before a kill cannot be withdrawn: the LSU completes the
handshake and drains the response without exposing a stale result to the
pipeline.

### 6.3 Dual-port TCM and SoC boundary

The default `rv32_tcm` is a unified, true-dual-port memory:

- port A is a read-only instruction port;
- port B supports data reads and byte-enabled writes;
- both ports return a registered response one cycle after acceptance;
- instruction and data accesses can proceed concurrently;
- out-of-range accesses and invalid instruction-port requests return an error
  response;
- the memory array is not reset, preserving block-RAM inference;
- an optional word-oriented `$readmemh` image initializes simulation or FPGA
  block RAM.

`soc_tcm_top` connects the two core ports to the TCM and exposes retirement and
test-status signals. Its principal parameters are:

| Parameter | Default | Purpose |
|---|---:|---|
| `RESET_VECTOR` | `0x0000_0000` | First fetch address after reset |
| `TRAP_VECTOR` | `0x0000_0100` | Reset value of direct-mode `mtvec` |
| `TCM_BYTES` | 64 KiB | Unified TCM capacity |
| `TCM_BASE_ADDR` | `0x0000_0000` | TCM base byte address |
| `TCM_INIT_FILE` | Empty | Optional word-oriented initialization image |
| `TEST_STATUS_ADDR` | Last TCM word | Completion mailbox address |
| `TEST_PASS_VALUE` | `1` | Passing mailbox value |

The completion mailbox observes a retired aligned full-word store, not the raw
data request. Therefore a wrong-path, faulting, or squashed store cannot report
false completion. This mailbox is SoC observability logic and is not RISC-V
architectural state.

### 6.4 Reset contract

`rv32_core` and `soc_tcm_top` consume a synchronous, active-high `rst_i`. Core
state, pipeline-valid bits, outstanding-transaction state, CSRs, counters, and
the completion mailbox change reset state only on a rising clock edge. The TCM
array itself is deliberately not reset; firmware is supplied through its
initialization image or by the simulation harness.

At the FPGA boundary, `reset_sync` is the only block exposed to the external
active-low asynchronous reset event on `reset_ni`. Its synchronization pipeline
captures that event, while the functional reset delivered to the SoC is a
separate register without asynchronous control. Consequently, both assertion
and deassertion of the reset observed by the CPU occur only on rising edges of
the 50 MHz board clock. The default wrapper uses two synchronization stages.

Any alternative integration must preserve the synchronous `rst_i` contract and
must not introduce asynchronous reset controls into the TCM address, data, or
write-enable paths.

## 7. Synchronous exceptions and precise traps

### 7.1 Implemented exception causes

| Cause | Code | Detection point | `mtval` value |
|---|---:|---|---|
| Instruction address misaligned | 0 | EX control-transfer target check | Misaligned target |
| Instruction access fault | 1 | IF memory response | Faulting fetch address |
| Illegal instruction | 2 | ID decode or EX CSR access | Instruction bits |
| Breakpoint | 3 | ID (`EBREAK`) | Instruction PC |
| Load address misaligned | 4 | MEM/LSU | Effective address |
| Load access fault | 5 | MEM/LSU | Effective address |
| Store address misaligned | 6 | MEM/LSU | Effective address |
| Store access fault | 7 | MEM/LSU | Effective address |
| Environment call from M-mode | 11 | ID (`ECALL`) | Zero |

Exceptions are carried in the same pipeline packet as the faulting instruction.
The first exception attached to a packet wins over later checks. When a new
exception is detected, younger packets are flushed and the front end stops
while the faulting packet drains to WB. Older instructions retain normal
program-order completion.

At WB, a trapping packet:

1. writes the aligned faulting PC to `mepc`;
2. writes the synchronous cause to `mcause`;
3. writes the documented value to `mtval`;
4. suppresses GPR, CSR, and memory side-effect metadata;
5. does not increment `minstret`;
6. redirects fetch to the aligned direct-mode `mtvec` value.

An older WB trap or MEM exception has priority over younger EX work and control
redirects. Stores are allowed to reach the data port only after older hazards
and exceptions can no longer invalidate them. These ordering rules ensure that
wrong-path and faulting instructions do not create architectural state.

`MRET` redirects to the aligned `mepc` value and retires as a normal control
instruction. Because this is a same-privilege, interrupt-free environment, no
privilege-mode or interrupt-enable stack is implemented.

<p align="center">
  <img
    src="images/mret.png"
    alt="Minimal machine-mode synchronous trap entry and MRET return flow"
    width="1000"
  >
</p>

<p align="center"><em>Minimal synchronous machine-mode trap flow. Normal
firmware and the trap handler execute at the same privilege level; interrupts,
`mstatus` transitions, and U-mode are outside the implemented scope.</em></p>

## 8. Architectural retirement interface

`rv32_core` exports one stable observation point at MEM/WB. `trace_valid_o`
marks either a non-trapping retirement or a trap event; `trace_trap_o`
distinguishes the latter.

| Trace field | Meaning |
|---|---|
| `trace_pc_o`, `trace_insn_o` | Committed or trapping instruction identity |
| `trace_rd_we_o` | Architectural GPR write enable |
| `trace_rd_addr_o`, `trace_rd_data_o` | Destination register and committed value |
| `trace_mem_addr_o` | Effective address for a completed load or store; `trace_mem_wstrb_o` distinguishes stores |
| `trace_mem_wstrb_o`, `trace_mem_wdata_o` | Retired store byte lanes and data |
| `trace_trap_o`, `trace_cause_o` | Synchronous trap event and cause |
| `trace_control_o` | Retired control-transfer instruction |
| `trace_taken_o`, `trace_target_o` | Taken state and resolved target |

The trace is not a debug-mode implementation and does not alter architectural
execution. It decouples verification, software completion, and future
differential checking from internal pipeline-register names.

## 9. Module ownership

| RTL block | Architectural responsibility |
|---|---|
| `rv32_pkg` | ISA constants, control enums, exception type, and pipeline packets |
| `rv32_core` | Pipeline integration, interstage storage, commit, and trace |
| `if_stage` | Fetch request tracking, PC sequencing, redirect recovery, and fetch faults |
| `decoder`, `imm_gen`, `id_stage`, `regfile` | Instruction decode and operand preparation |
| `alu`, `branch_unit`, `ex_stage` | Integer execution, address generation, control resolution, and CSR RMW |
| `forwarding_unit`, `hazard_unit`, `pipeline_ctrl` | Dependency handling and global pipeline ordering |
| `mul_unit`, `div_unit` | Blocking RV32M execution |
| `lsu` | Load/store formatting, protocol handling, and data faults |
| `csr_file` | Implemented CSR state, counters, and trap entry |
| `rv32_tcm`, `soc_tcm_top` | Unified TCM and minimal SoC integration |
| `reset_sync`, `fpga_top` | Board reset boundary and FPGA-visible status |

The synthesizable core source order is maintained in `files/core.f`; the SoC
and FPGA additions are maintained in `files/fpga.f`. No verification-only
behavior is instantiated inside `rv32_core`.

## 10. Baseline timing characteristics

These values describe the implemented microarchitecture under the default TCM;
they are not workload benchmark results.

| Event | Baseline behavior |
|---|---|
| Independent instruction stream | Up to one issue and one retirement per cycle |
| TCM request | Registered response one cycle after acceptance |
| Immediate load consumer | One interlock bubble with one-cycle TCM |
| Not-taken conditional branch | No redirect bubble |
| Taken branch, `JAL`, `JALR`, or `MRET` | Two younger packets flushed |
| Multiply | Registered two-stage request/response operation |
| Normal divide/remainder | 32 restoring iterations |
| Divide-by-zero or signed overflow | Local result without iterative run |
| Outstanding transactions | At most one per core memory port |

Application CPI depends on instruction mix, dependencies, control flow, and
memory latency. Software can measure a defined interval using the 64-bit
`mcycle` and `minstret` counters.

## 11. Integration and extension boundaries

The implementation exposes deliberate seams for future work without claiming
those features today:

- a cache or bus bridge may replace the TCM behind the two blocking memory
  interfaces;
- the retirement trace can drive a differential checker or debug bridge;
- asynchronous interrupts require a complete addition of `mstatus`, `mie`,
  `mip`, prioritization, and xRET state transitions;
- caches require Zifencei behavior and a defined instruction/data coherence
  policy;
- higher privilege modes require the corresponding architectural state,
  protection, delegation, and address translation rather than isolated CSR
  additions.

Changes at these seams must preserve in-order commit, precise exceptions,
request/response accounting, and stale-transaction cancellation.

## 12. Normative references

The architectural behavior implemented here was reviewed against the official
RISC-V ratified specifications:

- [RV32I Base Integer Instruction Set, Version 2.1](https://docs.riscv.org/reference/isa/unpriv/rv32.html)
- [M Extension for Integer Multiplication and Division, Version 2.0](https://docs.riscv.org/reference/isa/unpriv/m-st-ext.html)
- [Zicsr Extension for CSR Instructions, Version 2.0](https://docs.riscv.org/reference/isa/unpriv/zicsr.html)
- [Machine-Level ISA](https://docs.riscv.org/reference/isa/priv/machine.html)
- [Privileged CSR conventions](https://docs.riscv.org/reference/isa/priv/priv-csrs.html)

The RISC-V specifications define architectural behavior. The checked-in RTL is
the source of truth for microarchitectural latency, interface timing, supported
CSR subset, SoC parameters, and implementation-specific observability.
