# Bare-Metal Software Environment

This document defines the software contract for the RV32IM five-stage core. It
covers the freestanding runtime, linker layout, trap ABI, completion protocol,
image generation, simulation flow, and FPGA firmware initialization implemented
in this repository.

The programmer-visible hardware contract is defined in
[Architecture](architecture.md), pipeline ordering and precise-trap behavior in
[Pipeline and control](pipeline-control.md), and software verification evidence
in [Verification](verification.md).

## 1. Purpose and scope

The software layer has three responsibilities:

1. establish a valid ILP32 C execution environment after reset;
2. provide deterministic trap handling and PASS/FAIL termination for
   self-checking programs;
3. convert linked programs into the word-oriented TCM image consumed by
   simulation and FPGA block-RAM initialization.

It is a compact bare-metal runtime, not an operating system, bootloader, SBI,
generic board-support package, or hosted C environment. There are no system
calls, dynamic loader, filesystem, console, heap allocator, scheduler,
interrupt service framework, or standard C library.

### 1.1 Source ownership

| Component | Responsibility |
|---|---|
| `sw/Makefile` | Compile, link, inspect, disassemble, and generate 64 KiB TCM images |
| `sw/link.ld` | Production bare-metal memory map, entry point, stack, and mailbox assertions |
| `sw/runtime/crt0.S` | Reset entry, `gp`/`sp` initialization, BSS clear, `mtvec`, and `main` call |
| `sw/runtime/trap.S` | Integer-context save/restore, C trap callback, and `MRET` |
| `sw/runtime/runtime.c` | Completion API, default trap policy, and minimal memory primitives |
| `sw/include/baremetal.h` | Public runtime API, status definitions, and CSR helpers |
| `sw/tests` | Freestanding C programs used for end-to-end validation |
| `sw/isa` | DUT environment and linker flow for the pinned upstream ISA tests |
| `tools/bin_to_memh.py` | Dense flat-binary to 32-bit Verilog hex conversion |
| `tools/elf_to_memh.py` | Validated sparse ELF32 `PT_LOAD` conversion used by ACT4 |

## 2. Target software profile

| Property | Implemented contract |
|---|---|
| ISA string | `rv32im_zicsr` |
| ABI | `ilp32`, integer calling convention, soft-float ABI |
| ELF format | ELF32, little-endian, RISC-V `ET_EXEC` |
| Privilege environment | Single hart, M-mode only |
| Reset entry | `_start` at `0x0000_0000` |
| Instruction alignment | 32-bit instructions; no compressed code |
| Code model | `medlow` |
| Linking | Static, freestanding, non-PIC, no default startup or libraries |
| Data alignment policy | Compiler emits strict-alignment accesses |
| Relaxation policy | Disabled for deterministic addressing and `gp` initialization |

The `riscv64-unknown-elf-` tool prefix is intentional: the GNU bare-metal
toolchain driver supports an RV32 multilib selected by `-march=rv32im_zicsr`
and `-mabi=ilp32`. `CROSS_COMPILE` can override the prefix, but the selected
compiler must provide a compatible RV32 ILP32 multilib.

### 2.1 Calling-convention contract

The runtime follows the standard integer calling convention:

- `a0`–`a7` carry arguments; `a0`–`a1` also carry return values;
- `ra`, `t0`–`t6`, and `a0`–`a7` are caller-saved;
- `s0`–`s11` are callee-saved;
- `gp` and `tp` are treated as fixed ABI registers;
- the stack grows toward lower addresses and remains aligned to 16 bytes at
  every C procedure boundary.

`_start` initializes `gp` from `__global_pointer$` inside an explicit
`.option norelax` region. Both compile and link commands also use
`-mno-relax`, preventing linker relaxation from rewriting the initialization
sequence before `gp` is valid.

The initial stack pointer is `0x0000_FF00`, which is 16-byte aligned. Trap entry
allocates a 128-byte frame, so the C trap callback receives the same alignment
guarantee.

### 2.2 Build policy

Production C files are compiled with optimization and strict diagnostics:

```text
-march=rv32im_zicsr -mabi=ilp32 -mcmodel=medlow
-mstrict-align -mno-relax -ffreestanding -fno-common -fno-pic
-ffunction-sections -fdata-sections -O2 -std=gnu11
-Wall -Wextra -Werror -g3
```

Linking uses `-nostdlib -nostartfiles -static`, disables the build ID, garbage
collects unused sections, and treats linker warnings as fatal. Source code must
therefore not assume libc, libgcc helper routines, C++ constructors, TLS, or
hosted-process startup unless the required implementation is added explicitly.

## 3. Build and image flow

The normal firmware path is:

```text
 C / assembly
      |
      v
 RV32 objects + crt0 + trap entry + runtime
      |
      v
 ELF32 executable -----> link map
      |                  disassembly
      v
 flat little-endian binary
      |
      v
 16,384 x 32-bit Verilog hex words
      |
      +------> simulation TCM preload
      +------> FPGA BRAM initialization
```

Run the default software build with:

```sh
make -C sw all
```

By default, generated files are placed below
`/tmp/rv32im-core-software-<uid>/`. The root build uses the same external
directory through `make software-images`, so build products do not pollute the
repository.

### 3.1 Generated artifacts

| Artifact | Purpose |
|---|---|
| `NAME.elf` | ELF32 executable with entry point `0x0000_0000` |
| `NAME.map` | Linker placement, symbol ownership, and section-size audit |
| `NAME.dump` | Source-interleaved disassembly using canonical, non-alias mnemonics |
| `NAME.bin` | Flat little-endian load image |
| `NAME.mem` | Dense 64 KiB, word-oriented Verilog hex image |

`sw/Makefile` verifies that each executable is ELF32. The linker script checks
all fixed placement and range constraints. `bin_to_memh.py` rejects an invalid
TCM size or an oversized binary, zero-pads the remaining capacity, converts
each little-endian group of four bytes into one eight-digit hex word, and emits
exactly 16,384 words for the default 64 KiB TCM.

The ACT4 path is intentionally different. `elf_to_memh.py` validates ELF32,
little-endian encoding, `EM_RISCV`, `ET_EXEC`, entry address, `PT_LOAD` bounds,
and equal virtual/physical addresses, then emits a sparse word-addressed image
for the simulation-only 1 MiB TCM.

## 4. Memory and linker contract

The production runtime and FPGA image use one unified 64 KiB TCM:

| Address range | Linker ownership | Purpose |
|---|---|---|
| `0x0000_0000–0x0000_00FF` | `.init` | Reset entry and early startup; limited to 256 bytes |
| `0x0000_0100–0x0000_03FF` | `.trap` | Direct-mode trap entry; must end before application text |
| `0x0000_0400–__image_end` | `.text`, `.rodata`, `.data`, `.sdata`, `.bss` | Application and runtime image |
| `0x0000_EF00–0x0000_FEFF` | Reserved stack | 4 KiB downward-growing stack |
| `0x0000_FF00–0x0000_FFFB` | Unused | Separation between stack top and mailbox |
| `0x0000_FFFC–0x0000_FFFF` | `.tohost` | One 32-bit completion mailbox |

The linker fails when:

- startup exceeds the space below the trap vector;
- trap entry overlaps application text;
- the linked image reaches the reserved stack;
- `.tohost` is not exactly one 32-bit word.

Text and writable data have distinct ELF `PT_LOAD` permissions, but both map
to the same physical TCM with identical virtual and load addresses. Initialized
`.data` bytes are already present in the memory image, so startup does not copy
them from a separate ROM load address. `.bss` is `NOLOAD` and is explicitly
cleared by `_start`.

The memory map is part of the hardware/software interface. Changing TCM base,
capacity, reset vector, trap vector, stack, or mailbox address requires a
coordinated update to the linker script, runtime headers, SoC/FPGA parameters,
test harness, ISA environment, and documentation.

## 5. Reset and C startup

After the hardware releases its synchronous reset, execution begins at
`_start`:

1. load `gp = __global_pointer$` with relaxation disabled;
2. load `sp = __stack_top`;
3. clear every word in `[__bss_start, __bss_end)`;
4. install `trap_entry` in direct-mode `mtvec`;
5. call `int main(void)` using the ILP32 calling convention;
6. tail-call `bm_exit(main_return_value)`.

Returning zero from `main` reports PASS. Any nonzero return value becomes a
failure code. Startup does not initialize general-purpose registers beyond
those required by the ABI; the architecture does not define reset values for
`x1`–`x31`.

The TCM array itself is never reset. In simulation, the harness clears and
reloads it before every program. On FPGA, firmware is restored by configuring
or reloading the initialized BRAM image, not by asserting the CPU reset. A
runtime reset therefore preserves any data or code that software previously
modified in TCM.

## 6. Trap runtime contract

`trap_entry` is linked at `0x0000_0100` and installed into `mtvec` during
startup. It provides a project-specific bridge from the hardware trap packet to
C:

```c
void bm_trap_handler(uint32_t cause, uint32_t epc, uint32_t tval);
```

The assembly wrapper:

1. allocates a 128-byte, 16-byte-aligned frame;
2. saves every integer register except immutable `x0` and the current `sp`;
3. reads `mcause`, `mepc`, and `mtval` into `a0`, `a1`, and `a2`;
4. calls `bm_trap_handler`;
5. restores the saved integer context and stack pointer;
6. executes `MRET`.

The weak default handler treats every trap as unexpected and reports a failure
derived from the low five cause bits. A program expecting a synchronous trap
overrides the handler, validates its arguments, updates `mepc` when execution
should resume, and returns to the wrapper.

For the fixed-width baseline, advancing past one faulting instruction normally
uses `mepc + 4`; the handler remains responsible for deciding whether that is
correct for the specific cause. The wrapper does not implement nested traps,
interrupt masking, privilege transitions, or an `mstatus` stack because those
features do not exist in the current architecture.

Precise exception priority, implemented cause values, and `mtval` policy are
defined in [Architecture](architecture.md#7-synchronous-exceptions-and-precise-traps).

## 7. Runtime API and completion protocol

### 7.1 Public API

| Interface | Behavior |
|---|---|
| `BM_CHECK(condition, code)` | Report `code` and stop when the condition is false |
| `bm_pass()` | Write PASS status and remain in a `nop` loop |
| `bm_fail(code)` | Encode a nonzero failure status and remain in a `nop` loop |
| `bm_exit(status)` | Map return value zero to PASS and nonzero to failure |
| `bm_trap_handler(cause, epc, tval)` | Weak trap callback overridden by trap-aware programs |
| `bm_csr_read_misa()` | Read the implemented ISA-identification CSR |
| `bm_csr_read_mhartid()` | Read the single-hart ID |
| `bm_csr_write_mepc(value)` | Select the resume PC used by `MRET` |
| `memcpy`, `memset`, `memcmp` | Minimal byte-oriented freestanding implementations |

The memory primitives exist so compiler-generated code can resolve common
freestanding operations without libc. They are functional reference routines,
not optimized processor-library implementations.

### 7.2 Mailbox encoding

The production mailbox is the final TCM word at `0x0000_FFFC`:

| Stored value | Meaning |
|---:|---|
| `1` | PASS |
| `(code << 1) | 1` | FAIL with the original code recoverable by shifting right |
| `3` | FAIL when the caller supplied code zero, avoiding collision with PASS |

`bm_pass` and `bm_fail` issue `fence rw, rw` after the store. In the current
single-hart, uncached, blocking memory system, `FENCE` is a legal ordering no-op;
the compiler `memory` clobber also prevents reordering around the inline
assembly boundary.

Simulation and `soc_tcm_top` recognize only a non-trapping, retired, aligned
full-word store to the configured mailbox address. The first valid completion
is latched until reset. Wrong-path, misaligned, faulting, or byte/halfword
stores cannot report a false result.

## 8. Included bare-metal programs

| Program | End-to-end purpose | Current result |
|---|---|---|
| `smoke.c` | Stack alignment, initialized data, BSS, function calls, little-endian byte access, word access, MUL, signed/unsigned DIV/REM, `misa`, and `mhartid` | PASS: 451 cycles, 171 retirement events, 0 traps |
| `trap.c` | ECALL, EBREAK, illegal instruction, `mcause/mepc/mtval`, C handler override, `mepc + 4`, and three `MRET` recoveries | PASS: 838 cycles, 346 retirement events, 3 traps |

These programs validate the runtime and compiler-generated execution path.
They do not replace the unit, pipeline, ISA, or ACT4 regressions described in
[Verification](verification.md).

## 9. ISA-test software environments

### 9.1 Pinned `riscv-tests`

`sw/isa` reuses the common RTL harness but does not link the production C
runtime. Its `riscv_test.h` adapter:

- starts at `_start = 0x0000_0000`;
- executes the unprivileged instruction tests in the core's M-mode-only
  environment without a proxy kernel or SBI;
- installs an unexpected-trap handler;
- maps the upstream subtest number in `gp` to an odd failure status;
- writes PASS/FAIL to `0x0000_FFFC`.

The ISA linker reserves the final TCM word and checks `_start`, ELF32 format,
image bounds, and the exact `tohost` symbol address. The manifest includes 40
RV32I and all 8 RV32M programs. `fence_i` and `ma_data` remain explicit scope
exclusions for the reasons recorded in [Verification](verification.md#72-pinned-riscv-tests).

### 9.2 ACT4

ACT4 uses its own DUT macros, linker script, Sail-generated expected
signatures, and a simulation-only 1 MiB TCM with mailbox `0x000F_FFFC`.
`elf_to_memh.py` loads its `PT_LOAD` segments directly rather than flattening
the larger sparse address space. This environment validates the I/M claim but
is not the production firmware memory map; configuration and results are
documented in [Verification](verification.md#73-act4-with-sail).

## 10. Running and debugging software

### 10.1 Build and execute

```sh
make software-images       # Build smoke.mem and trap.mem
make baremetal             # Build and execute both programs
make baremetal-smoke       # Execute one production-runtime program
make baremetal-trap
make isa                   # Execute 40 RV32I + 8 RV32M programs
make test                  # Required lint/RTL/software/ISA regression
```

List production programs or build one image directly:

```sh
make -C sw list
make -C sw BUILD_DIR=/tmp/rv32im-sw /tmp/rv32im-sw/smoke.mem
```

The second command demonstrates an explicit output directory; the default
`make software-images` target selects a per-user `/tmp` directory automatically.

### 10.2 Retirement trace

```sh
make baremetal-smoke \
  BAREMETAL_PLUSARGS='+trace=/tmp/smoke.csv +max_cycles=300000'
```

Supported harness arguments are:

| Plusarg | Meaning | Default |
|---|---|---:|
| `+mem=FILE` | Required word-oriented memory image | none |
| `+test=NAME` | Name printed in diagnostics | `baremetal` |
| `+trace=FILE` | Optional full retirement CSV | disabled |
| `+max_cycles=N` | Cycle timeout | 200,000 |
| `+max_trace_events=N` | Retirement-event timeout | 100,000 |

On failure or timeout, the harness prints the most recent 256 architectural
events. Use the failing PC to inspect `NAME.dump` before opening a waveform.

### 10.3 Questa debug

```sh
make questa-baremetal-gui PROGRAM=smoke
make questa-baremetal-gui PROGRAM=trap
make questa-isa-gui ISA_TEST=rv32um-div
```

The retirement trace remains the architectural oracle; the waveform is used to
explain stage occupancy, forwarding, wait, redirect, and trap timing.

## 11. FPGA firmware initialization

Generate an image in a convenient project-local build directory:

```sh
make -C sw BUILD_DIR=../build/software all
```

Add the selected `.mem` file to the Vivado project and set the `fpga_top`
parameter `TCM_INIT_FILE` to its synthesis-visible path. The constant
`$readmemh` image is mapped into BRAM initialization attributes; the CPU begins
fetching it from address zero after reset release.

The firmware-visible mailbox address must equal `TEST_STATUS_ADDR`, and PASS
value `1` must equal `TEST_PASS_VALUE`. On the A7-Lite wrapper, a valid mailbox
store stops the heartbeat and drives sticky PASS/FAIL/DONE status. Record the
board revision, bitstream hash, firmware ELF or `.mem` hash, and observed status
when publishing hardware evidence. See
[FPGA implementation](fpga.md).

## 12. Adding a program

1. Add `sw/tests/NAME.c` or `sw/tests/NAME.S` and provide `int main(void)`.
2. Include `baremetal.h`; return zero, return a stable nonzero failure code, or
   use `BM_CHECK`/`bm_fail`.
3. Override `bm_trap_handler` only when the program deliberately expects traps.
4. Add `NAME` to `BAREMETAL_PROGRAMS` in `sw/tests/programs.mk`.
5. Run `make baremetal-NAME` and inspect `NAME.map` and `NAME.dump`.
6. Run `make test`; run `make act4` as well when architectural RTL changed.
7. For FPGA use, rebuild the `.mem`, regenerate the bitstream, and record the
   exact firmware/bitstream pairing.

Use stable, unique failure codes so a mailbox value maps directly to one source
check. Do not rely on uninitialized GPRs, TCM contents outside linked sections,
misaligned accesses, unsupported CSRs, `FENCE.I`, self-modifying code, or
features outside `rv32im_zicsr`.

## 13. Software boundaries and future work

The current environment intentionally does not provide:

- a ROM-to-RAM copy stage, external DDR initialization, or execute-in-place
  flash flow;
- interrupts, timers, nested traps, privilege transitions, SBI, or an OS ABI;
- UART/semihosting output, command-line arguments, environment variables, or a
  filesystem;
- libc, libm, libgcc integration, heap allocation, C++, TLS, atomics, or
  multithreading;
- cache maintenance, `FENCE.I`, dynamic code loading, or self-modifying code;
- secure boot, image authentication, firmware update, or persistent storage.

A future platform layer should add these as explicit hardware/software
contracts rather than silently extending this verification runtime. In
particular, external memory requires a boot/copy policy, interrupts require the
missing machine CSRs and context rules, and caches require instruction/data
coherence plus Zifencei behavior.

## 14. Release checklist for software

Before publishing a release:

1. build from a clean checkout with the documented GNU RISC-V toolchain;
2. verify ELF32, little-endian format, entry point, memory map, stack range, and
   mailbox symbol in the ELF/map output;
3. run `make test` and the applicable ACT4 regression;
4. keep generated ELF, binary, map, dump, and `.mem` files out of Git unless a
   release policy explicitly identifies an artifact;
5. record tool versions and hash every firmware image used for FPGA evidence;
6. keep README, architecture, verification, FPGA, and software claims aligned.

## 15. References

- [RISC-V ELF psABI Specification](https://riscv-non-isa.github.io/riscv-elf-psabi-doc/)
- [RV32I Base Integer Instruction Set, Version 2.1](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)
- [M Extension for Integer Multiplication and Division, Version 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/m-st-ext.html)
- [Zicsr Extension for CSR Instructions, Version 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicsr.html)
- [Machine-Level ISA, Version 1.13](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html)
