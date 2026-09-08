# Pipeline and Control Microarchitecture

This document specifies the implemented cycle-level behavior of the RV32IM
five-stage pipeline: packet movement, dependency handling, backpressure,
control recovery, and precise trap ordering. The programmer-visible contract
is defined in [Architecture](architecture.md); verification ownership is in
[Verification](verification.md), and signal-level debug guidance is in
[Waveform debug](waveform-debug.md).

<p align="center">
  <a href="images/pipeline-diagram.png">
    <img src="images/pipeline-diagram.png" alt="Five-stage IF-ID-EX-MEM-WB stage diagram with interstage hazard markers" width="1050">
  </a>
</p>

<p align="center"><em>High-level IF–ID–EX–MEM–WB stage sequence with
interstage hazard/bubble markers. The hold, flush, redirect, and retirement
rules that actually govern packet flow are specified in the sections below,
not depicted in this diagram.</em></p>

The [annotated end-to-end datapath](images/pipeline_datapath.jpg) maps these
rules onto the pipeline registers, forwarding muxes, branch/CSR paths, LSU, and
writeback selection. It is intended as a navigation aid while reading the RTL;
the control priorities and cycle contracts in this document remain normative.

## 1. Control model and invariants

The core is single-hart, single-issue, and in order. Instructions may be
fetched beyond an unresolved control transfer, but architectural state changes
remain ordered. GPR writes, normal CSR writes, trap-state updates, and
retirement are qualified at MEM/WB. A store updates memory through the LSU in
MEM only after older events can no longer squash it, and retires after its
response completes.

Five invariants govern the control implementation:

1. **Program order:** no younger instruction retires before an older one.
2. **Single completion:** a held packet cannot retire or update state twice.
3. **Precise traps:** older work may complete; the offender and younger work
   have no architectural side effects.
4. **Stable transactions:** a backpressured or accepted memory request remains
   stable and is completed or explicitly drained.
5. **Age priority:** an older trap, fault, or wait defeats every younger event
   in the same cycle.

The datapath carries typed packets through four valid-bit boundaries:

```text
 imem -> IF -> IF/ID -> ID -> ID/EX -> EX -> EX/MEM -> MEM -> MEM/WB -> WB
          ^                         |               |
          +--------- redirect ------+               +---- dmem

          hazard_unit + forwarding_unit + pipeline_ctrl
```

`valid=0` is a bubble. Invalid payload fields are not architecturally
meaningful. Every pipeline register uses the same storage priority:

```text
reset > flush > enable > hold
```

This matters when an action both enables and flushes a boundary: the next
state is a bubble, not the combinational input packet.

## 2. Boundary ownership and commit

| Boundary | Packet ownership | Reason it may remain occupied |
|---|---|---|
| IF response / IF-ID | Fetched PC, instruction, fetch exception | ID interlock or response buffering |
| ID/EX | Decoded controls, source IDs/values, immediate, exception | Blocking EX/MDU operation or older MEM wait |
| EX/MEM | Result, store data, CSR/control metadata, exception | Blocking LSU request/response |
| MEM/WB | Final writeback, memory trace, control and exception metadata | Not intentionally held after commit |

Normal operation advances all four boundaries and permits one issue and one
retirement per cycle. A controller action may instead hold a packet, capture
it into the next boundary and clear its old slot, or flush it as wrong-path or
fault-younger work.

MEM/WB is the only retirement and architectural commit source:

```text
wb_trap      = mem_wb.valid &&  mem_wb.exc.valid
wb_retire    = mem_wb.valid && !mem_wb.exc.valid
wb_reg_write = wb_retire && mem_wb.reg_write && (mem_wb.rd != x0)
wb_csr_write = wb_retire && mem_wb.csr_write
```

A normal packet may write one GPR, commit one explicit CSR operation,
increment `minstret`, and emit one retirement trace. A trap packet emits a
trap trace but does not retire or carry a GPR, CSR, `MRET`, or memory side
effect.

Memory writes are the intentional exception to WB-only state update. The LSU
issues aligned byte strobes in MEM, but the store is reported as retired only
after its response reaches MEM/WB. During `mem_wait`, an older MEM/WB packet
commits on the current edge and MEM/WB is then bubbled rather than held. This
prevents repeated writeback, CSR updates, and retirement counts.

## 3. Dependencies and forwarding

### 3.1 GPR RAW handling

Decode marks actual operand use with `uses_rs1` and `uses_rs2`. A RAW match
requires a valid, non-trapping producer that writes a nonzero destination and
a consumer that semantically uses the matching source. Encoded but unused
instruction fields therefore do not create false hazards.

EX selects each operand independently. The youngest available producer wins:

| Source | Eligibility | Value |
|---|---|---|
| ID/EX snapshot | Default | Decode value, including same-cycle WB-to-ID bypass |
| EX/MEM | Valid non-trapping GPR writer; not an incomplete load | EX result, `PC+4`, or old CSR value |
| MEM/WB | Valid non-trapping GPR writer | Final `wb_data`, including completed loads |

Forwarded values feed every EX consumer: ALU, branch compare, JALR base,
address generation, store data, CSR register forms, and MUL/DIV operands.

An immediately following load consumer cannot use EX/MEM forwarding because
the load data is not yet available. The load-use action holds PC and IF/ID,
allows the load to advance, and bubbles ID/EX:

| Cycle | Load | Consumer | Result |
|---:|---|---|---|
| N | EX | ID | Dependency detected |
| N+1 | MEM | ID | Consumer held; EX bubble |
| N+2 | WB | EX | MEM/WB value forwarded |

This is one data-hazard bubble with the default TCM. Additional memory latency
is counted as `mem_wait`, not as more load-use bubbles.

ID also bypasses a same-cycle WB write explicitly. If ID/EX remains held after
its producer leaves the forwarding windows, a matching WB write refreshes the
stored source snapshot. A long MDU or memory wait therefore cannot expose a
stale operand.

### 3.2 CSR ordering

CSR state is read in EX and committed in WB. There is no CSR-value forwarding;
the hazard unit stalls only for a real architectural conflict:

| ID consumer | Older ID/EX or EX/MEM condition |
|---|---|
| CSR instruction | Actual writer to the same CSR state |
| `mcycle` / `mcycleh` | Writer to either half of the shared 64-bit counter |
| `minstret` / `minstreth` | Writer to either half, or any older non-trapping packet whose retirement is still pending |
| `MRET` | Writer to `mepc` |

`CSRRW[I]` always writes. `CSRRS[I]` and `CSRRC[I]` write only when `rs1` or
`zimm` is nonzero. Unrelated CSR addresses do not stall each other. A writer
already in MEM/WB needs no stall: it commits on the edge that moves the reader
to ID/EX, and EX observes the updated CSR state.

### 3.3 Machine-interrupt state ordering

MTIP eligibility uses committed `mstatus.MIE`, `mie.MTIE`, and live
`mip.MTIP`. A writer to `mstatus` or `mie`, or an `MRET`, in ID/EX or EX/MEM
holds the ID boundary because its final enable state is not yet known.

Once that packet reaches MEM/WB, the CSR file exposes eligibility from its
prioritized post-commit next state. A pending MTIP can therefore be injected
immediately after an enabling write or `MRET`; a disabling write blocks it
without a shadow instruction. An older EX/MEM wait or redirect still wins, and
the level-sensitive candidate is reevaluated at the next valid ID boundary.

## 4. Blocking units and transaction lifetime

### 4.1 EX and MDU acceptance

EX follows a valid/ready contract:

```text
ex_result_ready = !wb_trap && !mem_wait && !mem_exception
ex_fire         = ex_result_valid && ex_result_ready
ex_wait         = active_ID_EX_packet && !ex_fire
```

ALU, control, and CSR results are combinationally valid. MUL/DIV becomes valid
only when the selected unit responds. EX/MEM captures a result and a control
redirect is emitted only on `ex_fire`, so a held instruction cannot redirect
or complete twice.

During the selected EX-wait action, PC, IF/ID, and ID/EX hold while EX/MEM is
bubbled after any older entry advances. A simultaneous older `mem_wait` keeps
EX/MEM occupied and has higher priority.

The multiplier has one operation in flight and registers operands and result
around the inferred multiply. The restoring divider produces one quotient bit
per cycle for 32 normal iterations; divide-by-zero, signed overflow, and
smaller-magnitude cases complete through local architectural shortcuts. Both
units hold a completed response until accepted. A WB trap or newly completed
MEM fault kills younger MDU work.

### 4.2 LSU ownership

A valid load or store owns EX/MEM until the LSU response is available:

```text
mem_wait = ex_mem.valid
        && !ex_mem.exc.valid
        && (load || store)
        && !lsu_rsp_valid
```

The LSU permits one transaction. A request held under backpressure preserves
its command, aligned address, write data, and byte strobes. Local alignment
faults and external access faults return through the same sticky response
path. Loads apply little-endian extraction and sign/zero extension; stores
require a response before architectural completion.

An accepted transaction cannot be cancelled at the external interface. If an
older WB trap kills it, the LSU marks the transaction for discard and drains
the response before becoming reusable. Reset applies the same rule: an
already-accepted request is retained internally only long enough to discard
its single outstanding response, preventing a pre-reset response from being
misassociated with post-reset work.

### 4.3 Fetch response ownership

IF also permits one outstanding request and has one fall-through/skid response
slot. A backpressured request keeps a stable address. Flush, redirect, or reset
invalidates any buffered sequential packet and marks an already-accepted
request stale; its response is consumed but never delivered to ID.

If a stale response arrives as a redirect is accepted, IF may discard it and
launch the target request in the same cycle. After reset, any pre-reset
accepted request is similarly drained before fetching again from
`RESET_VECTOR`.

## 5. Control-transfer recovery

All implemented control transfers resolve in EX with forwarded operands:

| Instruction | Taken condition | Target |
|---|---|---|
| Conditional branch | `funct3` comparison | `pc + imm` |
| `JAL` | Always | `pc + imm` |
| `JALR` | Always | `(forwarded_rs1 + imm) & ~1` |
| `MRET` | Always | Current `mepc` |

```text
redirect.valid = ex_fire
              && is_control_transfer
              && control_taken
              && !exception
```

On an accepted redirect, the control instruction is captured into EX/MEM and
its old ID/EX slot is cleared. IF/ID is flushed, and any buffered or outstanding
sequential fetch response is invalidated and drained. `JAL` and `JALR` retain
their `PC+4` link result. A not-taken branch does not redirect or flush.

The core uses `IALIGN=32`. JALR clears target bit zero before the selected
taken target is checked for four-byte alignment. A target with
`target[1:0] != 0` raises an instruction-address-misaligned exception on the
control instruction and suppresses redirect and link-register write. A
not-taken branch never raises a target-alignment exception.

Recovery latency depends on instruction-memory response timing. The control
contract is therefore expressed as packet squash and target-request ownership,
not as a universal fixed branch penalty.

## 6. Precise traps and MTIP injection

Exceptions travel with the instruction packet. An exception already attached
to a packet outranks a later check on that packet.

| Origin | Exception | `mtval` |
|---|---|---|
| IF | Instruction access fault | Fetch address |
| ID | Illegal instruction | Instruction bits |
| ID | `EBREAK` | Faulting PC |
| ID | M-mode `ECALL` | Zero |
| EX | Illegal CSR access | Instruction bits |
| EX | Taken target misaligned | Resolved target |
| MEM | Load/store address misaligned | Effective address |
| MEM | Load/store access fault | Effective address |

When a new exception is selected, the offender advances one boundary, all
younger work is flushed, and registered `trap_drain` stops new front-end work.
Older packets and the offender continue through required EX/MEM waits. At WB,
trap state is committed once, every remaining pipeline entry is flushed, and
fetch redirects to the aligned direct-mode `mtvec` base. The offender does not
retire or increment `minstret`.

An eligible machine-timer interrupt replaces the decoded ID packet with a
synthetic exception packet containing the interrupted boundary PC, cause 7,
`is_interrupt=1`, zero instruction bits, and zero `mtval`. The original
instruction has not executed and is refetched from `mepc` after `MRET`. An
attached synchronous exception wins over interrupt injection.

Exception and interrupt packets drain identically after selection. Trap entry
saves and clears global interrupt enable at WB. `MRET` redirects in EX but
restores `MIE/MPIE` only when it retires, so a squashed `MRET` cannot change
interrupt state.

## 7. Central action priority

`pipeline_ctrl` chooses exactly one action per cycle. Source order in the RTL,
not enum encoding, defines priority:

| Priority | Action | Architectural reason |
|---:|---|---|
| 1 | Reset | Establish benign state |
| 2 | WB trap | Oldest event; commit trap and redirect `mtvec` |
| 3 | New MEM exception | Older than all EX/ID work |
| 4 | MEM wait | EX/MEM still owns a memory operation |
| 5 | New EX exception | Preserve offender; squash younger work |
| 6 | EX wait | ID/EX still owns an unaccepted result |
| 7 | Registered trap drain | Stop younger work until trap commit |
| 8 | EX control redirect | Discard younger sequential-path work |
| 9 | Interrupt-state wait | Await older `mstatus`/`mie`/`MRET` state |
| 10 | New ID exception | Advance synchronous offender |
| 11 | New ID interrupt | Advance synthetic MTIP packet |
| 12 | ID hazard | Resolve load-use or CSR ordering |
| 13 | Normal advance | No constraint active |

The state installed at the next clock edge is:

| Action | Fetch/PC | IF/ID | ID/EX | EX/MEM | MEM/WB | Extra effect |
|---|---|---|---|---|---|---|
| Reset | Hold reset PC | Clear | Clear | Clear | Clear | Clear drain |
| WB trap | Redirect `mtvec` | Clear | Clear | Clear | Clear | Commit trap; clear drain |
| MEM exception | Stop | Clear | Clear | Clear after capture | Capture offender | Set drain |
| MEM wait | Hold | Hold | Hold | Hold | Bubble | Older WB commits once |
| EX exception | Stop | Clear | Clear after capture | Capture offender | Advance | Set drain |
| EX wait | Hold | Hold | Hold | Bubble | Advance | Preserve EX owner |
| Trap drain | Hold | Hold, normally empty | Advance | Advance | Advance | Suppress younger events |
| EX redirect | Redirect target | Clear | Clear after capture | Capture control | Advance | No drain |
| IRQ-state wait | Hold | Hold | Bubble | Advance | Advance | Use post-commit state |
| ID exception | Stop | Clear after capture | Capture offender | Advance | Advance | Set drain |
| ID interrupt | Stop | Clear after capture | Capture synthetic trap | Advance | Advance | Set drain |
| ID hazard | Hold | Hold | Bubble | Advance | Advance | One interlock action |
| Advance | Sequential | Advance | Advance | Advance | Advance | None |

Only the highest-priority row applies in a collision. Important consequences
are:

- a WB trap prevents a younger memory request, redirect, or stall from winning;
- a MEM wait defeats a ready-looking younger EX result;
- a MEM exception kills a simultaneous younger EX redirect or MDU operation;
- an EX redirect defeats wrong-path ID exception, interrupt, and hazard events;
- an ID exception defeats interrupt injection and dependency handling at the
  same boundary;
- EX/MEM waits remain serviceable while `trap_drain` is active.

## 8. Timing observability and verification

| Sequence | Required behavior |
|---|---|
| ALU producer -> adjacent EX consumer | EX/MEM forwarding; no bubble |
| Load -> adjacent consumer | One load-use bubble, then MEM/WB forwarding |
| CSR writer -> conflicting reader | Hold until the writer reaches commit ordering |
| Taken branch/JAL/JALR/`MRET` | Capture control, squash sequential younger work |
| Not-taken branch | No redirect or control flush |
| MUL/DIV | Hold ID/EX until the selected response is accepted |
| Delayed load/store | Hold EX/MEM and younger packets; bubble MEM/WB |
| Synchronous exception | Squash younger work, drain, trap once at WB |
| Eligible MTIP | Replace one ID packet, drain, trap once at WB |

The implementation exposes read-only performance counters without feeding
them back into control. Stall counters follow the same mutually exclusive
priority selection as the controller. `perf_redirect` counts accepted EX
redirects; `perf_squash` counts valid younger IF/ID and fetch packets actually
discarded. These counters explain measured CPI but do not redefine the control
contract. Frozen measurements belong in [Performance](performance.md),
[CoreMark](coremark.md), and [Hardware validation](hardware-validation.md).

Principal directed evidence is:

| Test | Control responsibility |
|---|---|
| `tb_pipeline_ctrl` | Action masks, collision priority, drain lifetime |
| `tb_hazard_unit`, `tb_forwarding_unit` | Source qualification, CSR conflicts, youngest-producer selection |
| `tb_pipeline_forwarding` | End-to-end RAW paths and wrong-path suppression |
| `tb_pipeline_memory_wait` | Backpressure, held-operand refresh, single completion |
| `tb_core_control_flow` | Redirects, exception priority, traps, `MRET` |
| `tb_timer_interrupt_core` | MTIP injection, enable/disable boundaries, pending retrigger |
| `tb_freertos_soc` | Repeated MTIP and ECALL yields under software load |

Retirement trace is the architectural oracle. Internal packet valids, wait and
hazard signals, forwarding selects, enable/flush masks, and redirect state
explain how that result was reached.

## 9. Design boundary

The controller intentionally excludes branch prediction, speculative state
checkpoints, multiple issue, out-of-order completion, non-blocking caches,
nested interrupts, and software/external interrupt injection. Adding any of
these changes the age, cancellation, or commit model and requires a new
control contract rather than a local mux change.

The checked-in RTL under `rtl/core` is authoritative for implementation timing
and arbitration. Architectural results remain governed by the RV32I, RV32M,
Zicsr, and documented machine-mode specifications listed in
[Architecture](architecture.md#12-normative-references).
