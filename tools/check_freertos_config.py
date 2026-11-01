#!/usr/bin/env python3
"""Check FreeRTOS configuration rebuilds and no-op builds in an isolated cache."""

from __future__ import annotations

import argparse
import subprocess
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def run_make(build_dir: Path, options: list[str], *, dry_run: bool = False) -> str:
    command = ["make", "--no-print-directory", "-C", str(REPO_ROOT / "sw")]
    if dry_run:
        command.append("-n")
    command.extend([f"BUILD_DIR={build_dir}", *options, "freertos-images"])
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"command failed: {command}\n{result.stdout}")
    return result.stdout


def check(condition: bool, description: str) -> None:
    if not condition:
        raise RuntimeError(description)


def snapshot(paths: list[Path]) -> dict[Path, int]:
    return {path: path.stat().st_mtime_ns for path in paths}


def check_noop(build_dir: Path, options: list[str], paths: list[Path]) -> None:
    before = snapshot(paths)
    dry_output = run_make(build_dir, options, dry_run=True)
    check("[CC]" not in dry_output and "[AS]" not in dry_output,
          "unchanged configuration unexpectedly schedules compilation")
    run_make(build_dir, options)
    check(snapshot(paths) == before, "unchanged configuration rewrote objects or stamp")


def check_change(build_dir: Path, options: list[str], objects: list[Path]) -> None:
    before = snapshot(objects)
    stamp = build_dir / "freertos/config.stamp"
    stamp_before = stamp.read_bytes(), stamp.stat().st_mtime_ns
    dry_output = run_make(build_dir, options, dry_run=True)
    check("[CC]" in dry_output and "[AS]" in dry_output,
          f"changed configuration did not schedule C/assembly rebuilds: {options}")
    check((stamp.read_bytes(), stamp.stat().st_mtime_ns) == stamp_before,
          "dry-run changed the configuration stamp")
    run_make(build_dir, options)
    after = snapshot(objects)
    check(all(after[path] > before[path] for path in objects),
          f"changed configuration failed to rebuild every FreeRTOS object: {options}")
    check_noop(build_dir, options, [*objects, stamp])
    print(f"[PASS] FreeRTOS rebuild and subsequent no-op: {' '.join(options) or 'defaults'}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="rv32-freertos-config-") as temporary:
        build_dir = Path(temporary)
        run_make(build_dir, [])
        objects = sorted(build_dir.rglob("*.o"))
        check(len(objects) == 8 and build_dir / "bsp/rv32_soc.o" in objects,
              "expected eight FreeRTOS objects, including the BSP")
        stamp = build_dir / "freertos/config.stamp"
        check(stamp.is_file(), "FreeRTOS configuration stamp was not generated")
        for key in ("CC=", "FREERTOS_CPPFLAGS=", "FREERTOS_PROJECT_CFLAGS=",
                    "FREERTOS_KERNEL_CFLAGS="):
            check(any(line.startswith(key) for line in stamp.read_text().splitlines()),
                  f"configuration stamp is missing {key}")

        check_noop(build_dir, [], [*objects, stamp])
        check_change(build_dir, ["FREERTOS_BLINK_PERIOD_MS=250"], objects)
        check_change(build_dir, ["FREERTOS_BLINK_PERIOD_MS=250",
                                 "FREERTOS_CPU_CLOCK_HZ=50000000"], objects)
        check_change(build_dir, [], objects)
        print("[PASS] FreeRTOS configuration stamp regression")


if __name__ == "__main__":
    main()
