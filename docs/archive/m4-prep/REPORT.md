# M4-a — board preparation for the teaching CPU

*Second submission. Codex's review of the first is `CODEX_REVIEW.md`; what changed in response, with
the commands and exit statuses, is `CORRECTIONS.md`. This report describes the state after those fixes.*

**What this milestone is, and is not.** It prepares everything needed to put the teaching CPU on the
PYNQ-Z1 and to get back off it safely. It does not build a bitstream and it does not touch hardware.
Per the delegation, **no Vivado was run, the board was not touched, the serial port was not held, and the
hardware manager was never started**. `bitstream-impl1-validated.bit`, the PS image, the SD card and the
baseline Vivado project were read only — their paths, hashes and recovery commands are recorded, and none
of them was modified. The original board checkout, the vivado-docker setup and the existing wrapper, block
design and constraints were read, not edited. Nothing in the CPU uses M or C.

## 1. What is delivered

| | file | what it establishes |
|---|---|---|
| board top | `gen-board-notrace/TeachingBoardTop.TeachingBoardConfig.v` | the board-level RTL that is delivered. `gen-board/` is the first elaboration, kept because the audit script fails on it and that is what shows the check works |
| board RTL audit | `audit/board-rtl-audit.txt`, `scripts/audit-board-rtl.py` | every board-RTL check in one re-runnable place: ports, plusargs, monitors, printfs, guards, instrumentation, ROM, reset PC |
| interface | `audit/interface-compare.txt` | 76 ports against the baseline's 76, **identical field for field** — the wrapper binds the teaching top with no edit to `rocketchip_wrapper.v` |
| reset & PlusArgs | `audit/reset-and-plusarg.md` | the reset chain traced from the wrapper to the subsystem; **0 plusarg instances** (baseline: 1) |
| synthesis guards | `audit/synthesis-guards.txt` | every simulation-only construct located and classified under this build's actual defines, against the baseline |
| wiring | `audit/board-top-wiring.txt` | every input of both children traced: none unconnected, none a stray literal, in either design |
| sim vs board | `audit/sim-vs-board.md` | 15 itemised differences between the board configuration and the M3 simulations |
| timer | `audit/mtime-and-budgets.md` | `mtime` runs at 400 kHz against a declared 1 MHz; inherited from the baseline; the board-test budgets justified |
| baseline identity | `audit/baseline-identity.txt` | read-only sha256 of the artefacts a rollback depends on |
| regression | `sim-regression/`, `audit/behaviour-equivalence.md`, `audit/sim-rtl-diff.md` | the M3 gates re-run from regenerated RTL, and the shared-file edit shown not to change behaviour |
| build inputs | `build-inputs/MANIFEST.txt`, `teaching_top_shim.v`, `teaching_project.tcl` | one pinned file list with hashes; the isolation layer; the independent project script, generated from the manifest |
| hierarchy | `scripts/check-hierarchy.py`, `scripts/check-tcl.tcl` | the design walked offline from `rocketchip_wrapper`: 126 modules, 0 unresolved, `Top` is the shim, no Rocket module present |
| build entry | `scripts/m4-build-board.sh` | dry-run only; every gate fail-closed; refuses to execute the build |
| gate self-test | `scripts/selftest.sh`, `selftest.log` | 48 cases, each asserting an exit status: every gate shown to pass on real input and fail on broken input |
| impl criteria | `scripts/check-impl-reports.py` | the resource/timing pass conditions, frozen before any number exists |
| preflight | `scripts/board-preflight.sh` | read-only gate; currently and correctly **blocks** |
| runbook | `runbook/BOARD-TEST.md` | programming, evidence, rollback, and the manual gate |
| hashes | `HASHES.txt`, `HASHES.sh` | sources → generated RTL → evidence, regenerable |

## 2. The board top, and how it reaches the board

`TeachingBoardTop` is `zynq.Top` with one substitution: the Rocket subsystem becomes the teaching one. It
instantiates the same `ZynqAdapter` at the same address, exposes the same `io_ps_axi_slave` and `io_mem_axi`
bundles, and takes its reset the same way.

It is **not** the project's top module. The board top stays `rocketchip_wrapper` — the PS block design, the
board pins, the MMCM and both AXI boundaries, baseline and unmodified. That wrapper instantiates a module
named `Top`, so the teaching project compiles a generated shim of that name which passes its 76 ports
straight through to `TeachingBoardTop`. The baseline `Top.ZynqFPGAConfig.v` is deliberately absent, and
three separate checks fail if it appears. Detail in `CORRECTIONS.md` §1.

- **Ports**: 76 vs 76, identical in direction, width and name, in the same order (`audit/interface-compare.txt`).
- **TileLink monitors**: 0, matching the baseline. `WithoutTLMonitors` is what removes them; the
  simulation configurations keep them and carry 50 monitor modules and 54 plusarg readers, 50 of which
  are the monitors' own `tilelink_timeout`. None of that reaches the board.
- **PlusArg instances**: 0. The baseline has one (`max_core_cycles`, `Top.ZynqFPGAConfig.v:100194`). The
  response intercept is removed at elaboration by `tailIntercept = false` rather than switched off, which
  matters because this build defines no `SYNTHESIS` and `plusarg_reader` would otherwise present its
  simulation branch.
- **Teaching printfs**: 0 EV lines and 0 TAILHIT lines. The board configuration sets `traceEvents = false`.
  The first elaboration did not, and carried 6 EV printfs and a TAILHIT printf whose condition was a
  constant false; both are in `gen-board/`, which `scripts/audit-board-rtl.py` rejects — the check fails on
  the old file and passes on the delivered one, so it is not vacuous.
- **Instrumentation ports**: none. `TeachingCpuZynqTop` and `TeachingCpu` have no `obs`/`halted`/`busy`/
  `axiStats` ports at all (16 ports on `TeachingCpu`, against 27 in the simulation build). What remains is
  the black box's own `dbg_*` outputs as dangling nets, with its debug *inputs* driven by explicit zeros.
- **Wiring**: every input of both child instances is connected, none resolves to a stray literal, and the
  same extraction on the baseline gives the same answer (`audit/board-top-wiring.txt`).
- **Boot ROM**: read back out of the generated RTL. The first 156 bytes are byte-identical to
  `bootrom.teaching.rv64.img`; the device tree blob sits at 0x9c as expected; everything after it is zero.
  The device tree declares memory at 0x8000_0000 + 256 MB, CLINT at 0x200_0000, ROM at 0x1_0000.
- **Reset PC**: 0x10040, the same ROM entry the simulation boots from.

## 3. What the audits found

**Reset.** `!FCLK_RESET0_N || !mmcm_locked` → the top's `reset` → `sys_reset = RegInit(true.B)` inside the
adapter → `target.reset`. The subsystem is held in reset from configuration until the PS writes bit 0 of
adapter register 0x10. The randomised-initialisation window that forced the M3 harness to hold reset with
`sys_reset || reset` exists only inside `` `ifdef RANDOMIZE_REG_INIT ``, which this build does not define.
Board reset semantics are left exactly as the baseline has them.

**Simulation-only constructs.** 4886 sites, all guarded: 4614 inside `ifdef RANDOMIZE*`, 272 inside
`ifndef SYNTHESIS`, none unguarded. The baseline has more of every kind (5682 and 417). An earlier version
of this report asserted that the 272 **are** compiled because the project defines no `SYNTHESIS`; that
inference is withdrawn — a project setting no macro says nothing about the tool's built-in macros. The
teaching project now defines `SYNTHESIS` explicitly, so those regions are excluded by construction rather
than by assumption, and `scripts/check-tcl.tcl` fails if the define disappears.

**Timer.** The RTC divider is 100 (`clint_io_rtcTick = value == 7'h63`), so on a 40 MHz board `mtime` runs
at 400 kHz while the device tree declares 1 MHz. Inherited from the baseline, not introduced here, and
`boot02_clint` does not depend on it. Recorded rather than fixed: changing `PeripheryBusKey.frequency`
would change the baseline's device tree, which is out of scope.

## 4. Regression: the shared file changed, so everything that shares it was re-run

`TeachingCpuSoc.scala` now also carries the board top and the `tailIntercept` parameter. All four M3
configurations were **regenerated from the current source**, re-verilated, and put through the full M3 gate
set — nothing was reused except the scripts.

```
M3FIX_DONE fails=0
  4 programs × 2 timing profiles: 8 runs, event gate ok, AXI gate ok
  determinism: 1802 events both times
  PROBE_DONE unrejected=0        (every mutation of a passing log rejected)
  AXI_PROBE_DONE wrong=0         (14 illegal AXI orderings rejected, 4 legal ones accepted)
  the negatives still fail for their stated reasons: tail-withheld, tail-errored, tail-delayed,
  neg-original-rom, neg-drop-first-fetch
```

Event streams were then compared against the M3-accepted round, run for run. Ten runs are byte-identical.
Five differ — the four `delay-*` runs and `neg-original-rom` — and all five depend on an uninitialised
register: `LFSR64` in rocket-chip's `Fuzzer.scala:41` is `Reg(UInt(width = wide))` with no `RegInit`, so
`--x-assign unique` gives it a different start value in every build. Pinning it with
`+verilator+rand+reset+0` and `+1` makes the M3-accepted binary and the regenerated binary produce
**identical** event streams in every case, while the two pinned values give different counts (1460 vs 1537)
— so the experiment is not vacuous. Details and logs: `audit/behaviour-equivalence.md`,
`sim-regression/xreset/`.

The generated simulation RTL does differ textually (≈5300 raw lines, 428 after normalising FIRRTL
temporaries and source annotations). `audit/sim-rtl-diff.md` characterises it: declaration reordering, plus
monitor assertion strings quoting the new line numbers. The clean configuration is the control — 428
normalised differences, and a cycle-identical event stream.

The four test ELFs hash differently between rounds. The difference is 12 bytes: gcc's temporary object
filename in the symbol table. Loadable image and full disassembly are identical.

## 5. Coverage boundaries — what is *not* verified

Stated plainly, because the board top as a whole cannot be verified at this stage:

1. **`TeachingBoardTop` has never been simulated as a whole, and this report does not claim it has.** The
   M3 evidence is about `TeachingCpuHarness`, a different top. They share the *source* of
   `TeachingCpuZynqTop`, but not its elaboration: the board's copy has no TileLink monitors, no event log
   and no observation ports. The full list is `audit/sim-vs-board.md`. Simulating the board top would need
   a PS AXI model that does not exist here.
2. **No synthesis, no place and route, no timing.** There is no bitstream, no netlist, no WNS. Nothing in
   this report should be read as a claim that the design fits the part or closes timing at 40 MHz. The
   criteria for judging that are frozen in `scripts/check-impl-reports.py`; the numbers are M4-b's.
3. **Whether the core's debug logic survives synthesis is unknown.** The Chisel-side instrumentation is
   gone from the generated RTL outright, which is more than was previously claimed. But `tcpu_core.v` is a
   black box and still drives `dbg_*` and `halted` onto nets nobody reads; synthesis would normally trim
   the logic behind them, and that is exactly the kind of thing that should be read off the post-synthesis
   netlist rather than assumed. M4-b.
4. **The PS side is untested.** `fesvr-zynq` speaks the same TSI/HTIF protocol the simulation uses, and the
   adapter register map is unchanged, so it is *expected* to drive the teaching CPU. Expected is not
   verified; the first board run is what tests it.
5. **No TileLink monitors on the board.** A protocol violation that stops a simulation is silent on
   hardware. This matches the baseline, but it means board evidence is a transcript and an exit code, which
   is weaker than an assertion, and section 5 of the runbook treats it that way.
6. **The PLIC path and the block device carry no traffic** in any configuration; they are present and
   tied off, and remain untested rather than claimed.
7. **The 400 kHz vs 1 MHz timebase is recorded, not fixed.** Any future program that converts `mtime` to
   real time will be wrong by 2.5× until someone addresses it.

## 6. What M4-b needs, in order

1. Claim the vivado lease; run `scripts/m4-build-board.sh --dry-run` first. It verifies every hash in the
   manifest, re-derives the shim and the project script to prove they are not stale, runs the RTL audit,
   parses the Tcl and closes the hierarchy — and refuses to execute the build itself.
2. Build with `vivado -mode batch -source build-inputs/teaching_project.tcl`. The project's top is
   `rocketchip_wrapper`; the baseline files are read, never written; the project directory is new and the
   script refuses to start if it exists.
3. Run `scripts/check-impl-reports.py` on the post-route reports. The criteria were fixed before any number
   existed, so they cannot be chosen to fit the result.
4. Read what became of the core's `dbg_*` and `halted` logic off the post-synthesis netlist (boundary 3).
5. Record what the build produced in `<build>/BUILD-MANIFEST.txt` — bitstream, both `.bin` images,
   timing, utilisation and DRC reports, each with a hash, plus the four `attest` lines. The preflight reads
   that file and nothing else; it does not go looking for artefacts.
6. Only then open `runbook/BOARD-TEST.md`, which starts with a manual gate and a preflight that currently
   blocks.

## 6b. One change made during this milestone

`TeachingBoardConfig` originally inherited `traceEvents = true`. Auditing the first elaboration showed what
that costs: six EV printfs, a TAILHIT printf with a constant-false condition, and the observation nets kept
alive as printf operands in a design about to be synthesised. The board configuration now sets
`traceEvents = false`. The simulation configurations keep it on, because that is where the events are read.

The edit touches a shared file, so it was checked rather than assumed: `TeachingCpuBootConfig` was
regenerated afterwards and is **byte-identical** to the RTL the regression in section 4 actually ran
(`gen-sim-recheck/simcheck.log`). The regression evidence therefore still describes the delivered source.

## 7. Reproducing this

```
scripts/selftest.sh <fresh-dir>               # 48 cases, every gate and every counterexample
./HASHES.sh                                   # regenerates HASHES.txt
scripts/audit-board-rtl.py gen-board-notrace/TeachingBoardTop.TeachingBoardConfig.v \
    --rom gen-board-notrace/rom_from_rtl.bin  # BOARD_RTL_AUDIT fails=0
scripts/audit-board-rtl.py gen-board/TeachingBoardTop.TeachingBoardConfig.v \
    --rom gen-board/rom_from_rtl.bin          # fails=2, which is how the check is shown to bite
scripts/board-preflight.sh                    # read-only; expected to report PREFLIGHT_BLOCKED today
scripts/m4-build-board.sh --dry-run           # prints the build it would run; runs nothing
scripts/check-impl-reports.py                 # with no reports: prints the criteria, verdict=PENDING, exit 2
scripts/check-hierarchy.py build-inputs/MANIFEST.txt
tclsh scripts/check-tcl.tcl build-inputs/teaching_project.tcl
```
The regression is reproduced by regenerating the four configurations with `cpu/m3-gen.sh`, rebuilding with
`cpu/m3-build-sim.sh`, and running `sim-regression/run-m3-regression.sh <new-outdir>`; the runner refuses a
non-empty output directory, so nothing here is overwritten.
