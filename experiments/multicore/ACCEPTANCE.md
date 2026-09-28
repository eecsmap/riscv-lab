# Archive verification — Codex, 2026-09-28

This commit archives the accepted milestone; it does not claim new hardware tests.

- Clean isolated worktree based on hardware commit `565d33f`; existing development
  branches, tags, and shared worktrees were not switched or modified.
- Source build using `build-software.sh 128` completed with exit 0 using the lab
  RISC-V toolchain. Despite relocation, both outputs reproduced the measured
  images byte for byte:
  - kernel: `133f5b72290781ad47d766beeede7d7a07d9af63985caeb34c669dfeba67081c`
  - filesystem: `d558e4444abcea6046147d85b81e538ecf604049b6d8ab15552f9a3d32bf688c`
- The Makefile packaging change replaces the old destructive remove/restore of
  validation programs with a conditional list. No runtime kernel/RTL change was
  needed for archival. TEACHING_VALIDATION is off in the reproduced images.
- Archived board records rechecked with the relocated performance checker:
  single and dual each pass all six workload runs. Checksums are recomputed by
  the checker, not accepted solely from success strings.
- Earlier independent reviews: M3 checker 15/15; drain checker 16/16;
  final performance timebase checker 23/23; M4 routed reports and sealed
  inputs examined; board performance medians independently recalculated.
- Large build outputs remain in the original lab workspace, unmodified. The
  selected archive is approximately 4 MB, not the complete simulation scratch.
- No push, programming, board access, deletion or cleanup was performed.

Known limits and reproducibility commands are in README.md. Historic report
claims are superseded by its scope notes and the recorded Codex decisions.
