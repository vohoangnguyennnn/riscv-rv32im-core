#!/usr/bin/env python3
"""Convert an ELF32 little-endian RISC-V executable to sparse word memh.

The loader intentionally has no third-party Python dependency. It copies every
PT_LOAD segment according to its physical address and models p_memsz padding as
zero, matching a bare-metal ELF loader and the RTL TCM's little-endian words.
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path


ELF_HEADER = struct.Struct("<16sHHIIIIIHHHHHH")
PROGRAM_HEADER = struct.Struct("<IIIIIIII")
PT_LOAD = 1
EM_RISCV = 243


class ElfError(ValueError):
    """Raised when an input cannot be represented by the simulation TCM."""


def load_elf(path: Path, base: int, size: int) -> tuple[bytearray, set[int]]:
    raw = path.read_bytes()
    if len(raw) < ELF_HEADER.size:
        raise ElfError("file is shorter than an ELF32 header")

    header = ELF_HEADER.unpack_from(raw)
    ident = header[0]
    e_type, e_machine, _e_version, e_entry = header[1:5]
    e_phoff, _e_shoff, _e_flags = header[5:8]
    _e_ehsize, e_phentsize, e_phnum = header[8:11]

    if ident[:4] != b"\x7fELF":
        raise ElfError("not an ELF file")
    if ident[4] != 1 or ident[5] != 1 or ident[6] != 1:
        raise ElfError("ACT4 requires ELF32, little-endian, version 1")
    if e_type != 2:
        raise ElfError(f"expected ET_EXEC (2), found e_type={e_type}")
    if e_machine != EM_RISCV:
        raise ElfError(f"expected EM_RISCV ({EM_RISCV}), found {e_machine}")
    if e_entry != base:
        raise ElfError(f"entry point 0x{e_entry:08x} does not match TCM base 0x{base:08x}")
    if e_phentsize < PROGRAM_HEADER.size:
        raise ElfError(f"program-header size {e_phentsize} is too small")
    if e_phoff + e_phentsize * e_phnum > len(raw):
        raise ElfError("program-header table extends beyond end of file")

    memory = bytearray(size)
    touched_words: set[int] = set()
    load_count = 0

    for index in range(e_phnum):
        offset = e_phoff + index * e_phentsize
        fields = PROGRAM_HEADER.unpack_from(raw, offset)
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz = fields[:6]
        if p_type != PT_LOAD:
            continue

        load_count += 1
        address = p_paddr
        if p_filesz > p_memsz:
            raise ElfError(f"PT_LOAD[{index}] has p_filesz > p_memsz")
        if p_offset + p_filesz > len(raw):
            raise ElfError(f"PT_LOAD[{index}] data extends beyond end of file")
        if address < base or address + p_memsz > base + size:
            raise ElfError(
                f"PT_LOAD[{index}] 0x{address:08x}..0x{address + p_memsz:08x} "
                f"is outside TCM 0x{base:08x}..0x{base + size:08x}"
            )

        start = address - base
        memory[start : start + p_filesz] = raw[p_offset : p_offset + p_filesz]
        if p_memsz:
            first_word = start // 4
            last_word = (start + p_memsz - 1) // 4
            touched_words.update(range(first_word, last_word + 1))

        # ACT4 links virtual and physical addresses identically. Reject an
        # unexpected split instead of silently constructing a different image.
        if p_vaddr != p_paddr:
            raise ElfError(
                f"PT_LOAD[{index}] has different virtual/physical addresses "
                f"0x{p_vaddr:08x}/0x{p_paddr:08x}"
            )

    if load_count == 0:
        raise ElfError("ELF has no PT_LOAD segment")
    return memory, touched_words


def write_memh(path: Path, memory: bytearray, touched_words: set[int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    previous = -2
    with path.open("w", encoding="ascii", newline="\n") as stream:
        stream.write("// ELF32 little-endian PT_LOAD image; addresses are word indices\n")
        for word_index in sorted(touched_words):
            if word_index != previous + 1:
                stream.write(f"@{word_index:x}\n")
            start = word_index * 4
            word = int.from_bytes(memory[start : start + 4], "little")
            stream.write(f"{word:08x}\n")
            previous = word_index


def parse_int(value: str) -> int:
    return int(value, 0)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="input ELF32 RISC-V executable")
    parser.add_argument("output", type=Path, help="output word-oriented Verilog hex")
    parser.add_argument("--base", type=parse_int, default=0, help="TCM base address")
    parser.add_argument("--size", type=parse_int, default=1024 * 1024, help="TCM size in bytes")
    args = parser.parse_args()

    if args.base < 0 or args.size <= 0 or args.base % 4 or args.size % 4:
        parser.error("--base and --size must describe a positive, word-aligned region")

    try:
        memory, touched_words = load_elf(args.input, args.base, args.size - 4)
        write_memh(args.output, memory, touched_words)
    except (OSError, ElfError) as error:
        print(f"elf_to_memh: {args.input}: {error}", file=sys.stderr)
        return 1

    print(
        f"elf_to_memh: {args.input.name} -> {args.output} "
        f"({len(touched_words)} initialized words)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
