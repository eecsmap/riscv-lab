# Repository packaging validation — 2026-09-21

Performed by Codex in the new repository, without hardware access or modifying the original workspace.

- `make check`: exit 0. 413 imported-file hash records matched; recorded xv6 session check returned
  segments=5, prompts=5, stages=7, fails=0. Original memory-map evidence passed for the recorded boot id.
- Framing tests: 33 passed; transport tests: 40 passed; memory-preflight tests: 19 passed. These are
  offline tests, not 92 new CPU/board tests.
- `make board-project`: exit 0. All 15 frozen inputs verified; Tcl lists 11 Verilog sources and two
  include directories. No Vivado invocation or newly built bitstream is claimed.
- `make xv6 TOOLPREFIX=...`: exit 0 using RISC-V GCC 13.2.0 (`gc891d8dc23e`). The root entry point
  explicitly sets `TEACHING_SIM_MEM_MIB=128` and forces rebuilding, because the imported source's
  default is 16 MiB for simulation. The initial default-parameter build was different, as expected;
  it was not accepted or published as the board kernel.
- Final rebuilt kernel SHA-256:
  `e990fb31fad483b805aaeae77ecaebb3111abcec012d70447c620c9e9b289c2c`.
- Final rebuilt filesystem SHA-256:
  `4691ffea6b05562d33a599a3406ab3b6d69e6c2444addb08838f1ef6f97527b7`.
- Both match the original accepted board artifacts byte-for-byte. The release still preserves the
  original artifacts, not replacements. All 15 packaged binary checksums passed.
- Targeted scan found no private-key headers or GitHub/AWS token patterns in the source snapshot.
  This is a basic check, not a guarantee that historical records contain no sensitive information;
  publication is private as requested.

No new RTL simulation, full ISA suite, usertests, live board session, Chisel regeneration or ARM-host
rebuild was run during packaging. The performance-probe proposal remains separate and unaccepted.
