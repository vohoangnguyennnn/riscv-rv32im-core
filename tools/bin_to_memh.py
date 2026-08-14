#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Convert a little-endian flat binary into a word-oriented Verilog hex file."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--size", required=True, type=lambda value: int(value, 0))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    image = args.input.read_bytes()

    if args.size <= 0 or args.size % 4 != 0:
        raise SystemExit("--size must be a positive multiple of four bytes")
    if len(image) > args.size:
        raise SystemExit(
            f"binary is {len(image)} bytes and exceeds TCM size {args.size} bytes"
        )

    padded = image + bytes(args.size - len(image))
    words = (
        int.from_bytes(padded[offset : offset + 4], byteorder="little")
        for offset in range(0, args.size, 4)
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "".join(f"{word:08x}\n" for word in words), encoding="ascii"
    )


if __name__ == "__main__":
    main()
