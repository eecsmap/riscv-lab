# mc-v1-dual: accepted dual-multicycle milestone

The local milestone includes the hardware history through `565d33f`, the xv6
adaptations, fixed-work benchmarks, selected raw board evidence, and routed
reports. It is not a new synthesis or board run. No remote publication is implied.

## Results and scope

PYNQ-Z1, 40 MHz, RV64 multicycle, fetch32, private 8-entry TLB / 1 KiB I-cache,
no D-cache, one physical req/resp port per hart, shared serial atomic backend.
`NUM_CORES=1|2`; pipeline and four-core configurations are not implemented.

| Four-process fixed work (three samples each) | Single median | Dual median | Speedup |
|---|---:|---:|---:|
| 8,000,000 compute iterations | 26.588 s | 13.064 s | 2.035x |
| 8,388,608 private-array updates | 40.548 s | 20.530 s | 1.975x |

The result is workload-specific, not a general 2x claim. The slight >2x compute
result is observed; its cause has not been experimentally isolated. Repeated
samples alone cannot exclude systematic bias. Timing uses shared hardware mtime,
400 kHz, not xv6 software ticks. Both configurations used the same kernel/disk.

Routed resources: single 14,554 LUT / 7,011 FF; dual 22,631 LUT / 11,181 FF;
BRAM/DSP zero. Dual WNS +0.396 ns, WHS +0.035 ns at 40 MHz.

Dual bare-metal gates, xv6 boot, concurrent computation/file I/O, single-core
regressions, and measurement were accepted. Historical SU/M/C baseline failures
remain documented: this is not a claim of complete ISA conformance. Board xv6
has no per-hart user-retirement counters. Simulation low-address retirement is
a proxy, not a privilege-mode count. No cpustat feature is included.

## Sources and reproducibility

- Hardware: repository `rtl/cpu/` and `soc/scala/teaching/`, including
  `TeachingHart`, `AtomicBackend`, `RD2DualBoardConfig` / `RD2BoardTop`.
- `software/xv6/`: measurement kernel (+read-only mtime syscall), benchmarks,
  hart0-only HTIF polling, no-device PLIC contract, validation-only pin/getcpu
  behind `TEACHING_VALIDATION`. Default filesystem excludes validation programs.
- `archive/m3/software/` and `archive/m4/software/`: source-only snapshots for
  earlier validation and deployment kernels. Retained licenses apply.
- `archive/*/`: historical reports and tests, kept as provenance. Absolute
  `/home/engineer/fpga` paths are historical lab dependencies, not portable
  standalone entrypoints. Do not blindly execute archived build/board scripts;
  some remove their output directories. Large generated RTL, binaries, Vivado
  projects and simulation scratch remain outside Git, with their original hashes.
- `evidence/route/`: routed reports and source hash manifest (historical paths).
- `archive/perf/sessions/`: original single/dual board records and recovery.
  Internal manifests describe original lab trees, not this selected archive.

With the RISC-V newlib toolchain on PATH, from the repository root:

```sh
bash experiments/multicore/build-software.sh 128
# Use 4 instead of 128 for the bounded simulator memory layout.
```

The new build goes into a fresh ignored `build/` directory. Relocation can change
ELF debug paths; byte identity of a relocated kernel is not promised. The board
measurement kernel hash is in `evidence/measured-software.sha256`; it differs
from the older deployment kernel `33021237…`. Do not substitute kernels silently.

Re-evaluate archived board evidence without touching hardware:

```sh
P=experiments/multicore/archive/perf
S=$P/sessions/session-restore-cache-20260928T050004Z/xv6-perf-board-20260928T051330Z
D=$P/sessions/session-dual-20260928T041829Z/xv6-perf-board-20260928T043607Z
python3 "$P/tests/perf_check.py" "$S"
python3 "$P/tests/perf_check.py" "$D"
python3 "$P/tests/perf_summary.py" "$S" "$D"
```

## Release and next phase

Local branch `mc-v1-closeout`, annotated tag `mc-v1-dual`. Earlier `ips-v1-*`
tags and all development branches remain unchanged. Compare cumulative hardware
with `git diff ips-v1-icache mc-v1-dual -- rtl soc`.

Hardware access still requires user handback and coordination leases. The latest
lab handoff (2026-09-28 07:38 UTC) says the user has the **dual** interactive
configuration; older measurement records end with single-core restoration and
are not a current board-state claim.

Next: a separate single-core pipeline design/verification contract, keeping
core implementation and hart count orthogonal. Do not mix pipeline edits into
this frozen milestone. Pipeline RTL and new board sessions are not part of this tag.
