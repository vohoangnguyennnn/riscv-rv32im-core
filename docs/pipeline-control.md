# Pipeline and Control Microarchitecture

This document specifies the implemented cycle-level control behavior of the
RV32IM five-stage core. It defines how instructions advance, wait, bypass data,
recover from control transfers, and take precise synchronous traps. The
descriptions and priorities below are derived from the checked-in RTL, with the
RISC-V specifications used as the architectural reference.

For the programmer-visible contract and supported ISA subset, see
[Architecture](architecture.md). Test methodology, requirement traceability,
and current evidence are defined in [Verification](verification.md), with
waveform-specific guidance in [Waveform debug](waveform-debug.md).

## 1. Control model and invariants

The processor is single-hart, single-issue, in order, and non-speculative at
architectural retirement. Instructions may be fetched down an unresolved
control path, but GPR writes, normal CSR writes, trap-state updates, and
retirement are all qualified at WB. A non-trapping store updates memory when
its request is accepted in MEM, only after older events can no longer squash
it, and retires after its completion response reaches WB.

The control design preserves five invariants:

1. **Program order:** a younger instruction never retires before an older one,
   and memory requests remain ordered.
2. **Single completion:** a held instruction cannot retire, write a CSR, or
   update `minstret` more than once.
3. **Precise traps:** older instructions may complete; the faulting instruction
   and every younger instruction have no architectural side effects.
4. **Stable transactions:** an accepted or backpressured memory transaction is
   either completed or explicitly drained; it is never silently abandoned.
5. **Age-based priority:** an older wait, fault, or trap overrides every younger
   redirect or dependency event in the same cycle.

The four interstage registers use a valid-bit protocol:

```text
 imem -> IF -> IF/ID -> ID -> ID/EX -> EX -> EX/MEM -> MEM -> MEM/WB -> WB
          ^                         |               |
          +--------- redirect ------+               +---- dmem

          hazard_unit + forwarding_unit + pipeline_ctrl
```

`valid=0` denotes a bubble. Payload fields in an invalid packet are not
architecturally meaningful and are cleared by reset or flush. Every pipeline
register applies the same storage priority:

```text
reset > flush > enable > hold
```

This rule is important when an action asserts both an enable and a flush:
flush wins and the destination receives a bubble.

## 2. Stage and boundary ownership

| Boundary | Packet role | Event that may retain it |
|---|---|---|
| IF response / IF-ID | Fetched PC, instruction, and fetch exception | Decode interlock, front-end hold, or fetch response buffering |
| ID/EX | Decoded controls, source identities and snapshots, immediate, and exception | Blocking EX operation or older MEM wait |
| EX/MEM | Execution result, store data, CSR result, control metadata, and exception | Blocking LSU transaction |
| MEM/WB | Final writeback data, retired store metadata, control metadata, and exception | Never intentionally held after commit; a MEM wait inserts a bubble instead |

The controller distinguishes four storage operations:

- **advance** captures the stage's combinational next packet;
- **hold** retains the current registered packet;
- **bubble** clears a boundary so no instruction occupies the next stage;
- **flush** invalidates a packet because it is reset, wrong-path, or younger
  than a fault.

During an unconstrained cycle, all boundaries advance. The core can then issue
and retire up to one instruction per cycle. Actual throughput is reduced only
by a dependency interlock, a taken control transfer, EX/MEM backpressure, or a
trap sequence.

## 3. Retirement and architectural state updates

MEM/WB is the sole retirement, GPR/CSR commit, and trap-entry point:

```text
wb_trap      = mem_wb.valid &&  mem_wb.exc.valid
wb_retire    = mem_wb.valid && !mem_wb.exc.valid
wb_reg_write = wb_retire && mem_wb.reg_write && (mem_wb.rd != x0)
wb_csr_write = wb_retire && mem_wb.csr_write
```

A normal WB packet may write one GPR, commit one explicit CSR update, increment
`minstret`, and emit one retirement event. A trapping packet emits a trap trace
but does not retire and cannot write a GPR, CSR through the normal CSR path, or
memory.

Memory is the deliberate exception to WB-only state update. An aligned store
drives its byte strobes and data through the LSU in MEM. The in-order controller
prevents that request from being issued behind an older unresolved trap, and
the store is reported as retired only after the memory response has completed
and its metadata reaches MEM/WB.

When MEM is waiting, the existing MEM/WB packet is allowed to commit on the
current edge and MEM/WB is then cleared. It is not held. This prevents repeated
register writes, repeated CSR writes, and duplicate retirement counts during a
long data-memory transaction.

## 4. GPR dependency control

### 4.1 Source qualification

Decode marks whether each encoded source field is semantically consumed with
`uses_rs1` and `uses_rs2`. A RAW match requires all of the following:

```text
producer.valid
&& producer.reg_write
&& !producer.exc.valid
&& producer.rd != x0
&& consumer.uses_rsN
&& producer.rd == consumer.rsN
```

This prevents false dependencies on unused instruction fields, `x0`, bubbles,
and instructions that will trap.

### 4.2 EX forwarding

Two independent muxes select the newest available value for `rs1` and `rs2`.
The younger EX/MEM producer has priority over MEM/WB when both match.

| Source | Eligibility | Forwarded value |
|---|---|---|
| ID/EX snapshot | Default | Register-file value captured in ID, including WB-to-ID bypass |
| EX/MEM | Valid non-trapping GPR writer, `rd != x0`, and not a load | ALU/MDU result, `PC+4`, or old CSR value selected by `wb_sel` |
| MEM/WB | Valid non-trapping GPR writer, `rd != x0` | Final architectural `wb_data`, including completed loads |

The forwarded operands are shared by all EX consumers: ALU operations, branch
comparisons, the JALR base, load/store address generation, store data, register
forms of CSR operations, and MUL/DIV operands. There is no separate control
dependency interlock and no ID-stage branch forwarding path.

### 4.3 Load-use interlock

A load result is unavailable in EX/MEM, so an immediately following consumer
cannot be satisfied by ordinary forwarding. The hazard detector asserts
`load_use` only when the valid, non-trapping ID/EX producer is a load that
writes the decoded consumer's used source register.

The controller then holds PC and IF/ID, allows the load to advance, and clears
ID/EX. With the default one-cycle TCM, the timing is:

| Cycle | Load | Consumer | Control effect |
|---:|---|---|---|
| N | EX | ID | Detect dependency |
| N+1 | MEM | ID | Hold consumer; bubble in EX |
| N+2 | WB | EX | Consumer receives load value from MEM/WB |

Exactly one data-hazard bubble is required for the default TCM. If the memory
response is delayed, the separate `mem_wait` action extends the hold until the
load completes; the hazard detector does not count memory latency as additional
load-use bubbles.

### 4.4 WB-to-ID and held-operand preservation

ID includes an explicit same-cycle WB bypass, so register-file read-during-write
semantics do not depend on FPGA RAM behavior.

A second corner case occurs when a consumer is already in ID/EX and is held by
EX or MEM backpressure. Its producer can commit in WB and then disappear from
the forwarding mux inputs before the consumer fires. While ID/EX is held, a
matching WB write refreshes the stored `rs1_value` or `rs2_value`. The eventual
EX operation therefore observes the committed value rather than a stale decode
snapshot.

## 5. CSR ordering interlocks

CSR state is read in EX and written at WB. The implementation therefore
serializes consumers in ID behind older uncommitted CSR effects.

| ID consumer | Older packets that cause a stall | Reason |
|---|---|---|
| Any CSR instruction | Any actual CSR writer in ID/EX or EX/MEM, regardless of address | Conservative program-order serialization |
| `MRET` | A writer to `mepc` in ID/EX or EX/MEM | `MRET` uses the current `mepc` as its EX target |
| Read of `minstret` or `minstreth` | Any valid, non-trapping packet in ID/EX or EX/MEM | Each older retirement is an implicit counter write |

`CSRRW[I]` always counts as an actual writer. `CSRRS[I]` and `CSRRC[I]` count as
writers only when their register source or `zimm` mask is nonzero.

No stall is required for a writer already in MEM/WB: it commits on the edge
that advances the consumer from ID to EX, and the consumer observes the updated
CSR during its EX cycle. Both load-use and CSR dependencies map to the same ID
hazard action: hold PC and IF/ID, then inject a bubble into ID/EX.

This policy implements the required per-hart, program-ordered CSR observation
without adding CSR-value forwarding.

## 6. Execution and memory backpressure

### 6.1 EX acceptance

EX uses an internal valid/ready contract:

```text
ex_result_ready = !wb_trap && !mem_wait && !mem_exception
ex_fire         = ex_result_valid && ex_result_ready
ex_wait         = active_ID_EX_packet && !ex_fire
```

An ordinary ALU/control/CSR result is combinationally valid. A MUL/DIV result
becomes valid only when its selected unit responds. A result is transferred to
EX/MEM, and a control redirect is emitted, only on `ex_fire`.

During `ex_wait`, PC, IF/ID, and ID/EX hold. The older EX/MEM packet advances,
and EX/MEM is replaced by a bubble until the held instruction can fire. If an
older memory instruction is also waiting, the higher-priority `mem_wait` action
retains EX/MEM instead.

### 6.2 Blocking MUL/DIV

The MDU accepts at most one selected operation at a time. A request is not
launched while an older MEM transaction, MEM exception, or WB trap owns
priority. The completed response remains stable until EX accepts it.

An older WB trap or newly completed MEM fault asserts `kill` to the MDU. This
prevents a wrong-path multiply/divide result from surviving a precise squash.
Division by zero and signed division overflow return the architecturally
defined RV32M values; neither condition generates an exception.

### 6.3 Blocking LSU

A valid load or store owns EX/MEM until the LSU presents a response:

```text
mem_wait = ex_mem.valid
        && !ex_mem.exc.valid
        && (load || store)
        && !lsu_rsp_valid
```

`mem_wait` holds every younger packet and EX/MEM, while MEM/WB receives a
bubble after its older entry commits. Both local alignment faults and external
bus errors complete through the same LSU response path.

Once a request is asserted under backpressure, its command, aligned address,
write data, and byte strobes remain stable until acceptance. A response can be
held until MEM/WB is ready. A killed accepted transaction enters a drop state
and drains its response before the LSU becomes reusable. Stores require a
response before they are considered architecturally complete.

### 6.4 Fetch backpressure and stale responses

IF similarly permits at most one outstanding instruction request and contains
a one-entry fall-through/skid response buffer. A backpressured request keeps a
stable address until accepted.

A flush or redirect invalidates any buffered sequential response and marks an
older outstanding request as stale. The stale response is consumed but never
presented to ID. When the old response arrives as a redirect is accepted, IF
can discard it and launch the target request in the same cycle if the memory
port is available. This guarantees request/response accounting without allowing
wrong-path instructions to re-enter the pipeline.

## 7. Control-transfer recovery

All baseline control transfers resolve in EX using forwarded operands.

| Instruction | Taken condition | Target |
|---|---|---|
| Conditional branch | Comparison selected by `funct3` | `pc + imm` |
| `JAL` | Always | `pc + imm` |
| `JALR` | Always | `(forwarded_rs1 + imm) & ~1` |
| `MRET` | Always | Current `mepc` |

The redirect condition is conceptually:

```text
redirect.valid = ex_fire
              && is_control_transfer
              && control_taken
              && !exception
```

An accepted EX redirect preserves the control instruction by capturing it in
EX/MEM, redirects fetch, and flushes the two younger packets in IF/ID and
ID/EX. `JAL` and `JALR` still retire their `PC+4` link value. A not-taken
conditional branch neither redirects nor flushes.

The redirect packet contains an origin field so the controller interface can
support a future ID-resolution optimization. The current core emits only
`REDIRECT_FROM_EX`; the corresponding flush mask always clears IF/ID and ID/EX.

The core implements fixed 32-bit instructions (`IALIGN=32`). `JALR` first
clears target bit 0 as required by the ISA, then the selected taken target is
checked for four-byte alignment. A target with `target[1:0] != 0` raises an
instruction-address-misaligned exception on the control-transfer instruction
and suppresses both redirect and link-register write. A conditional branch
that is not taken never raises this exception.

With the default one-cycle TCM, an accepted taken transfer squashes two younger
pipeline packets and has a two-cycle control-hazard cost. Longer instruction
memory latency may increase target-fetch delay, but does not change the flush
contract.

## 8. Precise synchronous exceptions

Exceptions travel in the same packet as their PC and instruction. An existing
packet exception has priority over a later check on that packet.

| Origin | Exception | `mtval` payload |
|---|---|---|
| IF | Instruction access fault | Faulting fetch address |
| ID | Illegal instruction | Instruction bits |
| ID | `EBREAK` | Faulting PC |
| ID | M-mode `ECALL` | Zero |
| EX | Illegal CSR access | Instruction bits |
| EX | Taken control target misaligned | Resolved target |
| MEM | Load/store address misaligned | Effective address |
| MEM | Load/store access fault | Effective address |

The central controller treats a fetch exception as an ID-boundary exception
when its packet reaches decode. For a newly selected exception:

1. the offending packet advances toward the next older boundary;
2. every younger packet and unaccepted younger EX result is flushed;
3. the registered `trap_drain` state stops the front end;
4. older packets and the offender continue through any required EX/MEM waits;
5. when the offender reaches WB, trap state is written and all remaining
   pipeline entries are flushed;
6. fetch restarts at the aligned direct-mode `mtvec` base.

At WB, the trap writes `mepc`, `mcause`, and `mtval`. The faulting packet does
not increment `minstret`. `MRET` later redirects to `mepc`, subject to the same
EX acceptance, alignment, and flush rules as other control transfers.

The core implements synchronous exceptions only. Asynchronous interrupt
arbitration and `mstatus`/`mie`/`mip` state are outside the current design.

## 9. Global control priority

`pipeline_ctrl` selects exactly one action per cycle. The order below is the
implemented priority, not enum encoding order:

| Priority | Action | Why it wins |
|---:|---|---|
| 1 | Reset | Establish benign state before all architectural events |
| 2 | WB trap | Oldest possible event; commit trap state and redirect `mtvec` |
| 3 | New MEM exception | Older than all EX/ID work; capture offender in MEM/WB |
| 4 | MEM wait | EX/MEM still belongs to an older memory instruction |
| 5 | New EX exception | Preserve the offending EX packet and squash younger work |
| 6 | EX wait | ID/EX still owns an unaccepted result or active MDU operation |
| 7 | Registered trap drain | Keep fetch stopped while the selected exception approaches WB |
| 8 | EX control redirect | Squash younger sequential-path packets |
| 9 | New ID exception | Advance the offender and stop younger fetch work |
| 10 | ID hazard | Resolve load-use or CSR ordering with a bubble |
| 11 | Normal advance | No constraint is active |

The explicit registered drain at priority 7 is essential: older MEM/EX waits
remain serviceable, while younger redirects and new ID events cannot restart or
replace the selected trap sequence.

### 9.1 Action matrix

The table describes the state installed at the next clock edge. “Capture” means
the current packet transfers to the next boundary before its old boundary is
cleared.

| Selected action | Fetch / PC | IF/ID | ID/EX | EX/MEM | MEM/WB | Additional effect |
|---|---|---|---|---|---|---|
| Reset | Reset to `RESET_VECTOR` | Clear | Clear | Clear | Clear | Clear drain |
| WB trap | Redirect `mtvec` | Clear | Clear | Clear | Clear | Commit trap; clear drain |
| MEM exception | Stop and discard younger fetch | Clear | Clear | Clear after transfer | Capture offender | Set drain |
| MEM wait | Hold | Hold | Hold | Hold | Bubble | Older WB entry commits once |
| EX exception | Stop and discard younger fetch | Clear | Clear after transfer | Capture offender | Advance | Set drain |
| EX wait | Hold | Hold | Hold | Bubble | Advance | Preserve active EX packet |
| Trap drain | Hold | Hold empty boundary | Advance | Advance | Advance | Suppress younger events |
| EX redirect | Redirect target | Clear | Clear after transfer | Capture control packet | Advance | No drain |
| ID exception | Stop and discard younger fetch | Clear after transfer | Capture offender | Advance | Advance | Set drain |
| ID hazard | Hold | Hold | Bubble | Advance | Advance | One interlock action |
| Normal advance | Sequential fetch | Advance | Advance | Advance | Advance | None |

In collision cases, only the highest row in the priority table applies. Key
consequences include:

- a WB trap beats a younger store request, EX redirect, and all stalls;
- a MEM wait beats a ready-looking younger EX result;
- an EX redirect beats an illegal or dependent wrong-path instruction in ID;
- an ID exception beats a dependency indication for that same boundary;
- an older wait remains active while `trap_drain` is set.

## 10. Representative timing expectations

| Sequence or event | Required control behavior |
|---|---|
| ALU producer -> adjacent ALU/branch/store/JALR consumer | Zero bubbles; EX/MEM forwarding |
| Load -> adjacent consumer | One load-use bubble, then MEM/WB forwarding with default TCM |
| Load -> one independent instruction -> consumer | Zero data bubbles; MEM/WB forwarding |
| CSR writer -> CSR reader | Hold reader until older writer reaches commit ordering point |
| Taken branch/JAL/JALR/MRET | Flush IF/ID and ID/EX; current control instruction continues |
| Not-taken conditional branch | No redirect and no control flush |
| MUL/DIV operation | Hold ID/EX until selected MDU response is accepted |
| Delayed load/store | Hold EX/MEM and all younger packets; bubble MEM/WB after old commit |
| Synchronous fault | Squash younger work, drain older work, trap once at WB |

These are microarchitectural timing expectations, not application CPI claims.
The exact duration of MDU, instruction-memory, and data-memory waits depends on
the selected operation and external ready/valid timing.

## 11. Verification and waveform observability

Control verification combines local invariant tests with full-core retirement
checking. The principal directed coverage is:

- `tb_pipeline_ctrl`: action masks, registered drain lifetime, and event
  collisions;
- `tb_hazard_unit` and `tb_forwarding_unit`: source qualification and
  forwarding priority;
- `tb_pipeline_forwarding`: end-to-end RAW paths, load-use bubbles, control
  operands, and wrong-path suppression;
- `tb_pipeline_memory_wait`: request backpressure, delayed responses, held
  operand refresh, and no duplicate retirement;
- `tb_pipeline_control`: redirects, exception priority, precise traps, and
  `MRET` recovery.

For a debug waveform, group pipeline packet `valid`, `pc`, and `insn` fields
with `load_use_hazard`, `csr_dependency`, the two forwarding selects,
`ex_wait`, `mem_wait`, all enable/flush outputs, redirect target, and WB trace.
The retirement trace is the architectural oracle; internal signals explain why
the observed instruction timing occurred.

<p align="center">
  <img
    src="images/full-core-pipeline-waveform.png"
    alt="Full-core waveform showing IF through WB packet flow, forwarding, waits, flushes, redirects, and retirement"
    width="1100"
  >
</p>

<p align="center"><em>Representative full-core control window. The waveform is
supporting microarchitectural evidence; self-checking signatures and retirement
events remain the pass/fail authority.</em></p>

## 12. Design boundaries

The current controller intentionally does not implement branch prediction,
speculative state checkpoints, multiple issue, out-of-order completion,
non-blocking caches, or asynchronous interrupt injection. Adding any of these
features requires revisiting the age model, cancellation rules, and commit
contract rather than only changing the redirect mux.

Any future optimization must preserve the invariants in Section 1 and retain
the existing retirement behavior for the same architectural instruction
stream.

## 13. Normative references

- [RV32I Base Integer Instruction Set, Version 2.1](https://docs.riscv.org/reference/isa/unpriv/rv32.html)
- [M Extension for Integer Multiplication and Division, Version 2.0](https://docs.riscv.org/reference/isa/unpriv/m-st-ext.html)
- [Zicsr Extension for CSR Instructions, Version 2.0](https://docs.riscv.org/reference/isa/unpriv/zicsr.html)
- [Machine-Level ISA](https://docs.riscv.org/reference/isa/priv/machine.html)

The ISA specifications define architectural results and ordering. The RTL in
`rtl/core` is the source of truth for pipeline latency, action priority,
handshake timing, and implementation-specific recovery behavior.
