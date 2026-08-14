# Pinned riscv-tests snapshot

This directory vendors the RV32I/RV32M assembly sources and scalar test macros
needed by this project's offline ISA regression.

- Upstream: <https://github.com/riscv-software-src/riscv-tests>
- Commit: `447a5fcb8253627ddb5f6a226f64e43463afcdd5`
- Snapshot date: 2026-08-03
- License: BSD 3-Clause; see `LICENSE` in this directory

The upstream physical test environment is not used because it assumes
privilege levels and CSRs outside this core's documented M-mode-only scope.
`sw/isa/env/riscv_test.h` supplies the small target-specific environment while
leaving the upstream self-checking instruction bodies and test macros intact.

The source snapshot includes `fence_i` and `ma_data` for provenance and easier
upstream comparison. They are intentionally excluded from the enabled manifest:

- `fence_i` tests Zifencei, which is outside RV32IM.
- `ma_data` requires successful misaligned memory accesses. This core's
  documented execution environment instead raises precise misalignment traps,
  which is permitted by the unprivileged ISA.
