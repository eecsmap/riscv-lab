# MC-PERF — fixed-workload 1-core vs 2-core measurement: REPORT (rev. 3: board results; rev. 2 = mtime time base)

**Rev. 3 (2026-09-28, user authorised '交换并授权')**: the board measurement was executed per PLAN §5 — see §6 and RESULTS.md.

Revision 2 answers `codex-mc-perf-timebase-fix`: the kernel-tick time base of rev. 1 is withdrawn (see §2); timing now reads the
shared CLINT mtime through a new read-only syscall; the judge, plan and evidence below are the rev. 2 versions. Rev. 1's three short
simulations (`runs/sim-*`) are kept as functional evidence only.

Tasks `codex-mc-fixed-work-prep` and `codex-mc-perf-timebase-fix`. Everything here is offline: no board, serial, programming, push or tag. The board procedure
in PLAN.md §5 is a proposal that needs the user's hand-back and authorisation again.

## 0. What M5 did and did not show (as Codex asked to be restated)
On hardware, MC-M5 verified two harts through the six bare-metal gates (boot of hart 1 via the ROM IPI, per-hart CLINT, LR/SC and
AMO contention with observed SC failures on both harts, peripheral bus, cross-hart fence.i, 100 000-iteration long run with equal
sums) and, under xv6, `hart 1 starting` plus the completion of concurrent programs (m3par2, m3fs). The board has **no per-hart user
retire counters** (HARTS/HARTS_USER lines are simulator-main output), so M5 **did not measure any dual-core speed-up**, and the
completion of concurrent programs is not one. This preparation is what would measure it.

## 1. Deliverables
| file | content |
|---|---|
| `PLAN.md` | configurations, workloads, timing base/resolution/overhead, metrics, proposed 2-cold-cycle board procedure with time estimates |
| `sw/xv6/user/perflib.h`, `perfcompute.c`, `perfarray.c`, `mtimetest.c` | the two benchmarks and the time-base smoke test (isolated copy of the M4 xv6 tree) |
| `sw/xv6/kernel/{syscall.h,syscall.c,sysproc.c}`, `user/{user.h,usys.pl}` | the read-only `mtime()` syscall (SYS 25): `return *(volatile uint64 *)CLINT_MTIME;` — one aligned 64-bit S-mode load through the existing `kvmmap(CLINT_BASE, 0x10000)`; `timervec`, interrupts and scheduling untouched; nothing mapped to user space; no RTL. Full diff: `sw/out/xv6-m4-to-perf.patch` (3 kernel files, 2 user headers, Makefile, 4 new user files) |
| `tests/build-sw.sh` → `sw/out/` | the MEASUREMENT kernel `kernel-deploy-128` **133f5b72…** (128 MiB, both board configurations run this same file) and `kernel-deploy-4` **d713744a…** (sim); **not** byte-identical to the accepted 33021237… (adds `sys_mtime`; 8,851 differing disassembly lines because every address after the syscall table shifts); `fs-perf.img` **d558e444…**; hashes frozen in `sw/out/sha256.txt` |
| `tools/` | isolated copies of the M4/M5 runner and console driver with profiles `perf-short` (sim: `mtimetest`, `perfcompute 20000`, `perfarray 1`) and `perf-board` (`mtimetest`, then 3 × each benchmark at full size) |
| `tests/run-xv6.sh` | the M4 sim entry (fresh disk copy per run, decimal range plusargs) pointed at this tree |
| `tests/perf_check.py` | the judge (§3); `tests/perf-check-selftest.sh` its 23-case mutation self-test (`runs/perf-check-selftest-tb.txt`) |
| `runs/tb-dual-short`, `runs/tb-single-short` | rev. 2 short-simulation evidence (§4); `runs/sim-*` = rev. 1 functional evidence (kernel-tick version, kept, not used for timing) |

## 2. Design summary
- **Fixed total work, 4 independent address spaces**: parent forks 4 children; compute = 4 × 2,000,000 chained-LCG iterations
  (the accepted m3par mix; no explicit data-array access — instruction fetch, stack and page-table traffic remain); array = 4 × 128
  passes over a private 128 KiB array, stride 7 (b0array's pattern), plus one initialising pass per child (inside the region, not
  counted as updates). Children return checksums through a pipe; the parent waits for all four and is the only writer.
- **Timing inside the program**: `mtime()` before the first fork and after the last `wait()`; boot, `exec` of the benchmark and all
  console output are outside the region; fork/exit/pipe/wait are inside.
- **Time base (rev. 2)**: the shared CLINT `mtime`, free-running at core clock / 100 (`int_rtc_tick = value == 7'h63` in the generated
  Verilog; the same `rtcTick` feeds the CLINT in both builds) → **400 kHz at 40 MHz, 2.5 µs/unit**. Read by `sys_mtime` (§1).
  **Why the rev. 1 kernel tick was wrong** (Codex): `timervec` rearms `mtimecmp` from the *current* mtime, so a late timer interrupt
  is absorbed and `ticks` counts services rendered, not time elapsed; under load it under-reads, and differently so with two harts.
  The rev. 1 "±1 tick, ≤ 1 %" bound is withdrawn. `uptime()` is still printed as `ticks=` for diagnosis; the judge only requires
  `ticks ≤ dmtime/25000 + 1`.
- **Overhead**: `readcost` = two back-to-back `mtime()` calls (trap + aligned MMIO load + return); printed per run and by
  `mtimetest` (8 consecutive reads). Values from the simulation are in §4; the judge refuses > 100,000 units.
- **Same everything on both boards**: the same measurement kernel file (133f5b72…), programs, disk image (fresh copy per boot),
  128 MiB, 40 MHz, per-core TLB + I-cache (79a114ae… single, 43e5b414… dual).

## 3. The judge (`perf_check.py`, rev. 2)
Layers: runner exit 0 and deliberate stop; production `check-xv6 --require-commands`; per perf run: exactly one summary line, `ok=1`,
`children=4`, size = the profile's expected size, `mt1 ≥ mt0`, `dmtime == mt1 − mt0`, **dmtime ≥ --min-dmtime** (2,000,000 units =
5 s on the board), `ticks ≤ dmtime/25000 + 1`, `readcost ≤ 100,000`, `PERF-DONE ok=1`, child lines 0..3 exactly once, none MISSING,
**every checksum equals the value recomputed in Python** (the compute reference reproduces the accepted m3par2 checksums); across
runs, each run's `mt0 ≥` the previous run's `mt1` (one monotonic shared counter). `mtimetest`: 8 reads monotonic, the child's read within
the parent's `[p0, p1]` (one time base across processes/harts), `ticks ≤ (p1−p0)/25000 + 1`, spin checksum correct. `--mtime-hz`
(default 400000) converts to seconds and work/s.
Self-test (`perf-check-selftest.sh`): positive PASS + 22 mutations refused, each for its own reason (matched only in `FAIL:` reason
lines): ok=0, children=3, child missing / duplicated / MISSING, wrong compute and array checksum, too-short / inconsistent / backwards
dmtime, ticks exceeding the hardware delta, huge read cost, runs out of order, mtimetest non-monotonic / child outside / ticks / spin
checksum / segment missing, wrong size, no DONE, runner rc, stop record.

## 4. Short-simulation evidence (rev. 2; Verilator, `perf-short` = `mtimetest`, `perfcompute 20000`, `perfarray 1`)
| run | sim | wall | HARTS | mtimetest | compute (80,000 iters) | array (65,536 updates + 65,536 init) | judge |
|---|---|---|---|---|---|---|---|
| `runs/tb-dual-short` | N=2 (`m3/runs/sim-dual`) | 1351 s | n=2 | 8 reads monotonic, deltas 135–136 units; child read within parent's [p0, p1]; spin 100k = 127,773 units (128 cycles/iter) | dmtime **93,304** (readcost 134, ticks 4) | dmtime **158,021** (readcost 136, ticks 7) | PASS |
| `runs/tb-single-short` | N=1 (`m3/runs/sim-single`) | 1180 s | n=1 | 8 reads monotonic, deltas 132–133; child within [p0, p1]; spin 100k = 133,902 units (134 cycles/iter) | dmtime **167,357** (readcost 132, ticks 6) | dmtime **262,904** (readcost 131, ticks 10) | PASS |

- **Correctness**: all 8 child checksums identical between N=1 and N=2 and to the rev. 1 runs, and equal to the Python references.
- **Monotonic + shared**: 8 consecutive parent reads never decrease; a child (on N=2 usually on the other hart) reads a value between the
  parent's before/after reads; the two perf runs are ordered (`mt0` of array > `mt1` of compute). One time base, not per-hart.
- **Correspondence with simulator cycles**: mtime × 100 must trail the simulator's cycle count: dual final `mt1` 1,754,916 × 100 =
  175.49 M cycles vs `CYCLES total` 177.11 M (the parent's output and the host stop come after mt1); single 2,002,218 × 100 = 200.22 M vs
  201.98 M. Consistent with mtime = cycles / 100. The single-process spin of 100,000 LCG iterations costs 128–134 cycles/iteration.
- **Read cost**: one `mtime()` syscall round trip = 131–136 mtime units ≈ **13,300 cycles ≈ 333 µs at 40 MHz** (trap, syscall dispatch,
  aligned MMIO load through the TLB, return). Twice the observed simulation cost is below 1.4 × 10⁻⁴ of a 2,000,000-unit region; this is an estimate, not a bound on board latency. Report the measured board readcost/region ratio as well.
- **Tick diagnostic**: ticks 4/6/7/10 against dmtime/25000 = 3.7/6.7/6.3/10.5 — within the under-count rule; the kernel tick is not
  used for any number.
- **Not a speed-up measurement**: the sim regions (0.23–0.66 s of simulated time) are below the board minimum by design (a board-sized
  run would take hours of simulation); the ratios seen here (compute 1.79, array 1.66) are quoted for calibration only and are not S2.
  The runner: each command in its own prompt segment, deliberate stop, host exit 0 (`check-xv6 --require-commands` fails=0).

## 5. Honest notes
- The rev. 1 tick-based timing was wrong for the reason Codex gave (`timervec` rearms from the current mtime; `ticks` under-counts under
  load). Rev. 1's three sims (`runs/sim-*`) remain as functional evidence of the workloads; their tick numbers are not used.
- The measurement kernel differs from the accepted M5 deployment kernel by the one syscall (and the address shift it causes); both
  configurations must run **133f5b72…**; the "same kernel byte-identical to 33021237…" statement of rev. 1 is withdrawn.
- The judge crashed (division by zero) on a zero-length region when the self-test's `dmtime-short` mutation was first run; fixed, the
  mutation is now refused for its own reason (23/23). Earlier self-test defects (a no-op array mutation; reason matched in the directory
  name) were fixed in rev. 1 and remain fixed.
- The sim's `spin100k` differs between N=1 and N=2 (134 vs 128 cycles/iteration) although it is a single process: the simulator's
  environment (the second hart's idle loop and the shared backend) is not identical; nothing is concluded from it.
- Calibration for board sizes is coarse and the simulator's memory is not the PS DDR; fork/initialisation are fixed costs inside the
  region; no board time is predicted, only that every board run should exceed the 5 s minimum by ≥ 5×.
- On a single-core board the same NCPU=8 kernel never sees hart 1; `ncpus_started` stays 1 (no validation syscalls in this kernel).
- Offline only: no board, serial, programming, push or tag; production scripts, frozen images and shared trees untouched.

## 6. Board measurement (rev. 3) — see RESULTS.md for the table
Procedure as PLAN §5, tooling = the accepted M5 scripts re-pointed at the perf artefact set (`board/`, isolated; production
`ips-precycle.sh/ips-record-power-cycle.sh/ips-install.sh cache` used unchanged with `IPS_OUT`/`IPS_SESSION` redirected into `perf/`).
1. Boot #1 (user power cycle attested 04:18:01Z): `m5-install.sh dual` — cold boot a1b62d8e…, preflight OK, 10 artefacts verified,
   payload 43e5b414… programmed and re-hashed, **6/6 dual gates**; then `perf-board` on the same boot (`session-dual-…/xv6-perf-board-…`):
   10/10 stages, deliberate stop, judge PASS. Wall 126 s for the run.
2. Boot #2 (attested 04:59:46Z): production `ips-install.sh cache` — cold boot e6930db4…, preflight OK, 13 artefacts verified, payload
   **79a114ae…** programmed and re-hashed, **8/8 gates**, perf02/03/04/06 3/3 each (this is the restore); then `perf-single-run.sh`
   deployed the measurement kernel + a fresh disk copy and ran `perf-board`: 10/10 stages, judge PASS. Wall 229 s. Post-state PD=1,
   no host, no lock; **the board ends in the user's configuration**; no third cycle.
3. Results: **S2 = 2.035 (compute), 1.975 (array)**; E2 = 1.018 / 0.988; 1-core spread ≤ 0.04 %, 2-core ≤ 1.6 %. Resources +55 % LUT.

Observations, stated as observations:
- S2 slightly above 2 for compute is not a measurement artefact of the time base (same counter, same kernel, three consistent runs);
  the plausible cause is that on one hart every timer interrupt and every HTIF console poll (`clockintr` → `htif_poll`, one host round trip
  per tick) is charged to the only hart, while on two harts children on hart 1 run without them. The single-process `spin100k` in
  `mtimetest` shows the same direction (141 vs 132 cycles/iteration, 7 %). Not investigated further; not claimed as a hardware property.
- `readcost` differs between the boards (190 vs 214 units) and from the simulator (135): the syscall's MMIO load goes to the CLINT through
  the backend; the difference is real but ≤ 0.06 % of any region here.
- The array workload's S2 (1.975) is below compute's: four children × 128 KiB share one serial atomic backend and the PS DDR through
  one port; the ~1.5 % faster first 2-core array run is within what page allocation order can do; not decomposed further.
- Nothing here is a general "2× speed-up" claim: two workloads, one size each, 3 repetitions, both embarrassingly parallel by
  construction (4 independent address spaces, no sharing inside the timed region beyond fork/exit/pipe/wait and the kernel).
