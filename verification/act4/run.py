#!/usr/bin/env python3
"""Run ACT4 self-checking ELF files on the RTL bare-metal harness."""

from __future__ import annotations

import argparse
import fnmatch
import subprocess
import sys
import time
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools"))

from elf_to_memh import ElfError, load_elf, write_memh  # noqa: E402


def select_elfs(elf_dir: Path, patterns: list[str]) -> list[Path]:
    candidates = sorted(elf_dir.rglob("*.elf"))
    if not patterns:
        return candidates

    selected: list[Path] = []
    for elf in candidates:
        relative = elf.relative_to(elf_dir).with_suffix("").as_posix()
        if any(
            fnmatch.fnmatch(relative, pattern)
            or fnmatch.fnmatch(elf.stem, pattern)
            or pattern in relative
            for pattern in patterns
        ):
            selected.append(elf)
    return selected


def run_one(
    sim: Path,
    elf: Path,
    elf_dir: Path,
    artifact_dir: Path,
    max_cycles: int,
    max_trace_events: int,
) -> tuple[bool, float, str]:
    test_id = elf.relative_to(elf_dir).with_suffix("").as_posix()
    artifact_stem = test_id.replace("/", "__")
    memh = artifact_dir / f"{artifact_stem}.mem"
    log = artifact_dir / f"{artifact_stem}.log"

    try:
        memory, touched_words = load_elf(elf, base=0, size=1024 * 1024 - 4)
        write_memh(memh, memory, touched_words)
    except (OSError, ElfError) as error:
        return False, 0.0, f"ELF conversion failed: {error}"

    command = [
        str(sim),
        f"+test={test_id}",
        f"+mem={memh}",
        f"+max_cycles={max_cycles}",
        f"+max_trace_events={max_trace_events}",
    ]
    started = time.monotonic()
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    elapsed = time.monotonic() - started
    log.write_text(result.stdout, encoding="utf-8")

    passed = result.returncode == 0 and "tb_baremetal: PASS" in result.stdout
    if passed:
        return True, elapsed, result.stdout

    # Produce an instruction-level CSV automatically for the failing case.
    trace = artifact_dir / f"{artifact_stem}.trace.csv"
    trace_command = [*command, f"+trace={trace}"]
    traced = subprocess.run(
        trace_command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    log.write_text(
        result.stdout + "\n--- diagnostic rerun with retirement trace ---\n" + traced.stdout,
        encoding="utf-8",
    )
    return False, elapsed, traced.stdout or result.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sim", type=Path, required=True, help="tb_baremetal ACT4 simulator")
    parser.add_argument("--elf-dir", type=Path, required=True, help="ACT4 generated elfs directory")
    parser.add_argument("--artifact-dir", type=Path, required=True, help="memh/log/trace output directory")
    parser.add_argument(
        "--test",
        action="append",
        default=[],
        help="substring or glob matched against test basename/relative path; repeatable",
    )
    parser.add_argument("--max-cycles", type=int, default=1_000_000)
    parser.add_argument("--max-trace-events", type=int, default=500_000)
    parser.add_argument(
        "--expected-count",
        type=int,
        default=47,
        help="required ELF count for an unfiltered ACT4 4.0.0 I/M run",
    )
    args = parser.parse_args()

    if not args.sim.is_file():
        parser.error(f"simulator does not exist: {args.sim}")
    if not args.elf_dir.is_dir():
        parser.error(f"ELF directory does not exist: {args.elf_dir}")
    if args.max_cycles <= 0 or args.max_trace_events <= 0:
        parser.error("cycle and trace limits must be positive")

    elfs = select_elfs(args.elf_dir, args.test)
    if not elfs:
        parser.error(f"no ACT4 ELF matched {args.test or ['*']} below {args.elf_dir}")
    if not args.test and len(elfs) != args.expected_count:
        parser.error(
            f"expected {args.expected_count} ACT4 I/M ELFs, found {len(elfs)}; "
            "regenerate from the pinned ACT4 release"
        )

    args.artifact_dir.mkdir(parents=True, exist_ok=True)
    print(f"[ACT4] running {len(elfs)} self-checking ELF(s) on RTL")

    failures: list[str] = []
    suite_started = time.monotonic()
    for index, elf in enumerate(elfs, start=1):
        test_id = elf.relative_to(args.elf_dir).with_suffix("").as_posix()
        passed, elapsed, output = run_one(
            args.sim,
            elf,
            args.elf_dir,
            args.artifact_dir,
            args.max_cycles,
            args.max_trace_events,
        )
        status = "PASS" if passed else "FAIL"
        print(f"[{status}] {index:02d}/{len(elfs):02d} {test_id} ({elapsed:.2f}s)")
        if not passed:
            failures.append(test_id)
            lines = output.rstrip().splitlines()
            print("\n".join(lines[-80:]), file=sys.stderr)

    elapsed = time.monotonic() - suite_started
    passed_count = len(elfs) - len(failures)
    print(
        f"[ACT4] summary: {passed_count}/{len(elfs)} passed, "
        f"{len(failures)} failed ({elapsed:.2f}s)"
    )
    if failures:
        print(f"[ACT4] failing tests: {', '.join(failures)}", file=sys.stderr)
        print(f"[ACT4] diagnostics: {args.artifact_dir}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
