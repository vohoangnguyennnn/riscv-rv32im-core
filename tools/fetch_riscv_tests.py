#!/usr/bin/env python3
"""Restore omitted riscv-tests instruction bodies at the documented commit."""

from pathlib import Path
import shutil
import subprocess
import tempfile


UPSTREAM = "https://github.com/riscv-software-src/riscv-tests.git"
COMMIT = "447a5fcb8253627ddb5f6a226f64e43463afcdd5"
ISA_DIR = Path(__file__).resolve().parents[1] / "third_party/riscv-tests/isa"
SHARED_DIRS = ("rv64ui", "rv64um")


def tree_contents(directory: Path) -> dict[str, bytes]:
    files = {}
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"refusing symlink in source tree: {path}")
        if path.is_file():
            files[path.relative_to(directory).as_posix()] = path.read_bytes()
    return files


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="rv32im-riscv-tests-") as temporary:
        checkout = Path(temporary)
        subprocess.run(["git", "init", "--quiet", str(checkout)], check=True)
        subprocess.run(
            ["git", "-C", str(checkout), "fetch", "--quiet", "--depth=1", UPSTREAM, COMMIT],
            check=True,
        )
        revision = subprocess.check_output(
            ["git", "-C", str(checkout), "rev-parse", "FETCH_HEAD"], text=True
        ).strip()
        if revision != COMMIT:
            raise ValueError(f"upstream revision mismatch: {revision}")
        subprocess.run(
            ["git", "-C", str(checkout), "checkout", "--quiet", "--detach", COMMIT],
            check=True,
        )

        # Validate both destinations before writing either. Never replace local edits.
        for name in SHARED_DIRS:
            destination = ISA_DIR / name
            if destination.is_symlink():
                raise ValueError(f"refusing destination symlink: {destination}")
            if destination.exists() and (
                not destination.is_dir()
                or tree_contents(destination) != tree_contents(checkout / "isa" / name)
            ):
                raise ValueError(f"{destination} differs from {COMMIT}; preserve or move it before retrying")

        for name in SHARED_DIRS:
            destination = ISA_DIR / name
            if not destination.exists():
                shutil.copytree(checkout / "isa" / name, destination)
        print(f"[PASS] riscv-tests shared sources match {COMMIT}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"riscv-tests bootstrap failed: {error}") from error
