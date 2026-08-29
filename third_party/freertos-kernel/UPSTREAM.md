# FreeRTOS Kernel upstream provenance

- Project: FreeRTOS Kernel
- Repository: https://github.com/FreeRTOS/FreeRTOS-Kernel
- Release: `V11.3.0`
- Commit: `9b777ae5c5b8e9e456065a00294d1e5f5f9facf5`
- License: MIT (`LICENSE.md` in this directory)

This directory contains the minimal upstream subset used by the RV32IM SoC
demo: the scheduler and list implementation, public headers, and the official
GCC RISC-V machine-mode port. All imported files are copied without
modification. Project-specific configuration, startup code, chip-extension
macros, BSP code, and the demonstration application live under `sw/`.

Run `make freertos-check` to verify every imported file against the pinned
checksums in `SOURCE.sha256`.
