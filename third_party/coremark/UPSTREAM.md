# CoreMark upstream provenance

- Project: EEMBC CoreMark
- Repository: https://github.com/eembc/coremark
- Commit: `1f483d5b8316753a742cbf5590caf5bd0a4e4777`
- Commit date: 2025-05-01
- License: `LICENSE.md` in this directory

The benchmark sources and `coremark.h` are copied without modification. Their
checksums from the pinned Git objects are recorded in `SOURCE.sha256`. The
upstream `coremark.md5` is preserved verbatim, but its `coremark.h` entry is
stale at this commit after upstream pull request #55. The RV32IM-specific
implementation is kept separately under `sw/coremark/`, as required by the
CoreMark run rules.

The project runs the standard 2K performance and validation seed sets with a
2000-byte static data block. Published results must additionally meet the
upstream minimum measured runtime of ten seconds.
