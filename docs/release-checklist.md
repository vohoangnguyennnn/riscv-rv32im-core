# Release checklist

Use this checklist when publishing a stable GitHub release. A release means the
documented RV32IM simulation scope is reproducible; it does not imply official
RISC-V certification or support for features listed outside the design scope.

## 1. Freeze and verify

- Confirm `git status --short` contains only intentional source/documentation
  changes. Do not commit Vivado projects, logs, waveforms, generated binaries,
  caches, or local IDE metadata.
- Run `make -j"$(nproc)" test` from a clean checkout.
- Run `make act4` when the ACT4 network/tool dependencies are available.
- For an FPGA release, rerun synthesis and implementation against the exact
  part and speed grade printed on the board. Archive the raw reports outside
  Git and copy only reviewed summary metrics into the release notes.
- Program the board with `smoke.mem`; record the LED/DONE result and the tested
  board revision. Simulation and timing closure alone are not an on-board test.

## 2. Review the public package

- Check `README.md`, `LICENSE`, third-party license notices, source manifests,
  memory map, FPGA pin constraints, and all commands shown in the docs.
- Check that no credentials, absolute developer paths, proprietary tool files,
  or large generated artifacts are staged: `git diff --cached --check` and
  `git diff --cached --stat`.
- Review the exact package with `git status --short` and `git diff --cached`.

## 3. Publish

Use a focused release commit and an annotated semantic-version tag. Until the
hardware scope and compatibility policy are frozen, `v0.x.y` is appropriate.

```sh
git add .
git diff --cached --check
git diff --cached --stat
git commit -m "release: prepare v0.1.0"
git push origin main
git tag -a v0.1.0 -m "RV32IM core v0.1.0"
git push origin v0.1.0
```

Wait for both GitHub Actions workflows to pass before creating the GitHub
Release from the tag. Release notes should state:

- supported ISA and explicitly excluded features;
- RTL, bare-metal, `riscv-tests`, and ACT4 result counts;
- simulator, compiler, ACT4/Sail, Vivado, board, and FPGA-part versions;
- timing WNS/WHS, DRC status, utilization, and whether an on-board smoke test
  was actually performed;
- known limitations and changes since the previous tag.

## 4. GitHub repository settings

- Add the topics `riscv`, `rv32im`, `systemverilog`, `cpu`, `fpga`, and
  `verilator`, plus a concise repository description.
- Require the RTL and ACT4 checks on `main` after their first successful runs.
- Disable force pushes and branch deletion on `main`.
- Enable Issues only if the project will actively accept bug reports.
