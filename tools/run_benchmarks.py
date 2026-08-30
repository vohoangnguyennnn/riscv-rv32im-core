#!/usr/bin/env python3
"""Run RV32IM bare-metal benchmarks and render CPI/IPC Markdown."""

from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path


BENCHMARKS = (
    "bench_arithmetic",
    "bench_branch",
    "bench_memory",
    "bench_mdu",
)
PERF_RE = re.compile(r"^PERF (?P<fields>.+)$", re.MULTILINE)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sim", type=Path, required=True)
    parser.add_argument("--image-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--max-cycles", type=int, default=1_000_000)
    return parser.parse_args()


def run_one(sim: Path, image_dir: Path, name: str, max_cycles: int) -> dict[str, int | str]:
    command = [
        str(sim),
        f"+test={name}",
        f"+mem={image_dir / (name + '.mem')}",
        "+perf",
        f"+max_cycles={max_cycles}",
    ]
    result = subprocess.run(command, check=True, text=True, capture_output=True)
    match = PERF_RE.search(result.stdout)
    if match is None:
        raise RuntimeError(f"{name}: simulator emitted no PERF record\n{result.stdout}")

    fields: dict[str, int | str] = {}
    for item in match.group("fields").split():
        key, value = item.split("=", 1)
        fields[key] = value if key == "benchmark" else int(value)
    return fields


def render(rows: list[dict[str, int | str]]) -> str:
    lines = [
        "# RV32IM performance measurements",
        "",
        "Measured from reset release through the retirement-qualified completion store.",
        "CPI and IPC include startup/termination overhead and therefore represent complete bare-metal runs.",
        "",
        "| Benchmark | Instructions | Cycles | CPI | IPC | Stall breakdown (% of cycles) |",
        "|---|---:|---:|---:|---:|---|",
    ]
    total_cycles = 0
    total_instructions = 0
    for row in rows:
        cycles = int(row["cycles"])
        instructions = int(row["instructions"])
        cpi = cycles / instructions
        ipc = instructions / cycles
        total_cycles += cycles
        total_instructions += instructions
        breakdown = ", ".join(
            (
                f"load-use {100 * int(row['load_use']) / cycles:.1f}%",
                f"CSR {100 * int(row['csr']) / cycles:.1f}%",
                f"MDU {100 * int(row['mdu']) / cycles:.1f}%",
                f"memory {100 * int(row['memory']) / cycles:.1f}%",
                f"redirects {int(row['redirects'])}",
                f"squashed {int(row['squashed'])}",
            )
        )
        lines.append(
            f"| {row['benchmark']} | {instructions} | {cycles} | {cpi:.3f} | {ipc:.3f} | {breakdown} |"
        )

    aggregate_cpi = total_cycles / total_instructions
    aggregate_ipc = total_instructions / total_cycles
    lines.extend(
        (
            f"| **Aggregate** | **{total_instructions}** | **{total_cycles}** | **{aggregate_cpi:.3f}** | **{aggregate_ipc:.3f}** | — |",
            "",
            "Aggregate CPI is total cycles divided by total retired instructions; it is instruction-weighted, not a geometric mean of per-program CPI ratios.",
            "",
        )
    )
    return "\n".join(lines)


def main() -> None:
    args = parse_args()
    rows = [run_one(args.sim, args.image_dir, name, args.max_cycles) for name in BENCHMARKS]
    report = render(rows)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(report, encoding="utf-8")
    print(report, end="")


if __name__ == "__main__":
    main()
