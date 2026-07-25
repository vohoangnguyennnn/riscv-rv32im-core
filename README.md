# RV32IM 5-Stage RISC-V Core

> **Work in progress:** this project is in the early implementation stage and is
> not yet ready to run programs.

A single-issue, in-order 32-bit RISC-V CPU core written in synthesizable
SystemVerilog. The target architecture is a classic five-stage pipeline:
**IF → ID → EX → MEM → WB**.

## Planned features

- RV32I base ISA and the M extension (`MUL`, `DIV`, and related instructions)
- Data forwarding, load-use hazard detection, stalls, and pipeline flushes
- Minimal Machine mode, Zicsr instructions, exceptions, and precise traps
- Separate instruction/data memory ports backed by TCM/BRAM
- Unit tests, integration tests, and FPGA synthesis smoke tests

Cache, DDR3, MMU, S/U modes, interrupts, and superscalar execution are currently
outside the project scope.

## Repository layout

```text
core/rtl/   SystemVerilog CPU RTL
docs/       Architecture and implementation plan
refs/       Third-party reference core and ISA material
```

See [docs/rv32im-5stage-design.md](docs/rv32im-5stage-design.md) for the detailed
design decisions, module plan, verification strategy, and implementation
roadmap.

## Current status

- [x] Architecture and implementation plan
- [ ] Base RV32I pipeline
- [ ] M extension and minimal CSR/trap support
- [ ] TCM integration and verification
- [ ] FPGA synthesis and smoke test

## License

This project is released under the [MIT License](LICENSE). Content under
`refs/riscv/` comes from
[ultraembedded/riscv](https://github.com/ultraembedded/riscv) and retains its
original license.
