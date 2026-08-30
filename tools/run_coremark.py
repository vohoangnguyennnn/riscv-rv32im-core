#!/usr/bin/env python3
"""Run the RV32IM CoreMark ports and render a validated Markdown report."""

from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path


UPSTREAM_COMMIT = "1f483d5b8316753a742cbf5590caf5bd0a4e4777"
RUNS = ("coremark_performance", "coremark_validation")
COREMARK_RE = re.compile(r"^COREMARK (?P<fields>.+)$", re.MULTILINE)
PERF_RE = re.compile(r"^PERF (?P<fields>.+)$", re.MULTILINE)
HEX_FIELDS = {"seedcrc", "crclist", "crcmatrix", "crcstate", "crcfinal"}
EXPECTED = {
    0: {"seedcrc": 0xE9F5, "crclist": 0xE714, "crcmatrix": 0x1FD7, "crcstate": 0x8E3A},
    1: {"seedcrc": 0x18F2, "crclist": 0xE3C1, "crcmatrix": 0x0747, "crcstate": 0x8D84},
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sim", type=Path, required=True)
    parser.add_argument("--image-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--compiler", default="riscv64-unknown-elf-gcc")
    parser.add_argument("--max-cycles", type=int, default=2_000_000_000)
    parser.add_argument("--max-trace-events", type=int, default=2_000_000_000)
    return parser.parse_args()


def parse_fields(record: str, hex_fields: set[str]) -> dict[str, int | str]:
    fields: dict[str, int | str] = {}
    for item in record.split():
        key, value = item.split("=", 1)
        if key == "benchmark":
            fields[key] = value
        else:
            fields[key] = int(value, 16 if key in hex_fields else 10)
    return fields


def run_one(
    sim: Path,
    image_dir: Path,
    name: str,
    max_cycles: int,
    max_trace_events: int,
) -> dict[str, dict[str, int | str]]:
    command = [
        str(sim),
        f"+test={name}",
        f"+mem={image_dir / (name + '.mem')}",
        "+coremark",
        "+perf",
        f"+max_cycles={max_cycles}",
        f"+max_trace_events={max_trace_events}",
    ]
    print(f"[RUN]   {name}", flush=True)
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"{name}: simulator exited with status {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    coremark_match = COREMARK_RE.search(result.stdout)
    perf_match = PERF_RE.search(result.stdout)
    if coremark_match is None or perf_match is None:
        raise RuntimeError(f"{name}: missing COREMARK/PERF record\n{result.stdout}")

    coremark = parse_fields(coremark_match.group("fields"), HEX_FIELDS)
    perf = parse_fields(perf_match.group("fields"), set())
    validate(name, coremark)
    return {"coremark": coremark, "perf": perf}


def validate(name: str, row: dict[str, int | str]) -> None:
    run_type = int(row["run_type"])
    expected_type = 0 if name.endswith("performance") else 1
    if run_type != expected_type:
        raise RuntimeError(f"{name}: run_type={run_type}, expected {expected_type}")
    if int(row["valid"]) != 1 or int(row["errors"]) != 0:
        raise RuntimeError(f"{name}: CoreMark did not validate: {row}")
    for field, expected in EXPECTED[run_type].items():
        actual = int(row[field])
        if actual != expected:
            raise RuntimeError(
                f"{name}: {field}=0x{actual:04x}, expected 0x{expected:04x}"
            )

    clock_hz = int(row["clock_hz"])
    cycles = int(row["cycles"])
    if clock_hz != 75_000_000 or cycles < 10 * clock_hz:
        raise RuntimeError(f"{name}: timed run is shorter than ten seconds")


def compiler_version(compiler: str) -> str:
    try:
        result = subprocess.run(
            [compiler, "-dumpfullversion", "-dumpversion"],
            check=True,
            text=True,
            capture_output=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return compiler
    version = result.stdout.strip().splitlines()[0]
    return f"{compiler} {version}"


def stall_breakdown(perf: dict[str, int | str]) -> str:
    cycles = int(perf["cycles"])
    return ", ".join(
        (
            f"load-use {100 * int(perf['load_use']) / cycles:.1f}%",
            f"CSR {100 * int(perf['csr']) / cycles:.1f}%",
            f"MDU {100 * int(perf['mdu']) / cycles:.1f}%",
            f"memory {100 * int(perf['memory']) / cycles:.1f}%",
            f"redirects {int(perf['redirects'])}",
            f"squashed {int(perf['squashed'])}",
        )
    )


def render(
    rows: list[dict[str, dict[str, int | str]]], compiler: str
) -> str:
    lines = [
        "# CoreMark on RV32IM",
        "",
        "CoreMark 1.0 is built as a single-context, 2K, freestanding RV32IM/Zicsr workload.",
        "Both the performance seeds and validation seeds are run for at least ten measured seconds;",
        "the Verilator harness checks the standard intermediate CRCs before accepting PASS.",
        "",
        f"- Upstream commit: `{UPSTREAM_COMMIT}`",
        f"- Compiler: `{compiler}`",
        "- Common compile flags: `-O2 -std=gnu11 -march=rv32im_zicsr -mabi=ilp32 -mcmodel=medlow -mstrict-align -mno-relax -ffreestanding -fno-common -fno-pic -ffunction-sections -fdata-sections -g3`",
        "- CoreMark defines: `TOTAL_DATA_SIZE=2000`, `ITERATIONS=0`, and the standard performance/validation seed selector",
        "- Memory: 64 KiB single-cycle TCM; architectural clock: 75 MHz",
        "- Contexts/data size: 1 / 2000 bytes",
        "- Scope: RTL simulation result; not an EEMBC-certified submission",
        "",
        "| Run | Iterations | ROI instructions | ROI cycles | Time (s) | CPI | IPC | CoreMark/MHz | CRC validation |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---|",
    ]

    for item in rows:
        row = item["coremark"]
        run_type = int(row["run_type"])
        label = "Performance" if run_type == 0 else "Validation"
        iterations = int(row["iterations"])
        instructions = int(row["instructions"])
        cycles = int(row["cycles"])
        clock_hz = int(row["clock_hz"])
        seconds = cycles / clock_hz
        cpi = cycles / instructions
        ipc = instructions / cycles
        score = iterations * 1_000_000 / cycles
        lines.append(
            f"| {label} | {iterations:,} | {instructions:,} | {cycles:,} | "
            f"{seconds:.3f} | {cpi:.3f} | {ipc:.3f} | {score:.3f} | PASS |"
        )

    performance = rows[0]["coremark"]
    performance_score = (
        int(performance["iterations"]) * 1_000_000 / int(performance["cycles"])
    )
    lines.extend(
        (
            "",
            f"**Headline result: {performance_score:.3f} CoreMark/MHz at 75 MHz.**",
            "",
            "The ROI counters use `mcycle`/`minstret` around CoreMark's timed region.",
            "The following diagnostic counters cover the complete process (startup, automatic",
            "iteration calibration, timed region, validation, and termination), so they are useful",
            "for pipeline bottleneck analysis but are not used to calculate the CoreMark score.",
            "",
            "| Run | Full-run instructions | Full-run cycles | CPI | IPC | Stall breakdown |",
            "|---|---:|---:|---:|---:|---|",
        )
    )
    for item in rows:
        row = item["coremark"]
        perf = item["perf"]
        label = "Performance" if int(row["run_type"]) == 0 else "Validation"
        instructions = int(perf["instructions"])
        cycles = int(perf["cycles"])
        lines.append(
            f"| {label} | {instructions:,} | {cycles:,} | "
            f"{cycles / instructions:.3f} | {instructions / cycles:.3f} | "
            f"{stall_breakdown(perf)} |"
        )
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    args = parse_args()
    rows = [
        run_one(
            args.sim,
            args.image_dir,
            name,
            args.max_cycles,
            args.max_trace_events,
        )
        for name in RUNS
    ]
    report = render(rows, compiler_version(args.compiler))
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(report, encoding="utf-8")
    print(report, end="")


if __name__ == "__main__":
    main()
