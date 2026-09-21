# M4-a narrow fixes — answering `codex-m4-prep-corrections`

Codex's review (`CODEX_REVIEW.md`) found four blocking defects, all of them in the preparation gates rather
than in the CPU. All four are fixed, and each fix is demonstrated by a test that asserts an exit status
rather than by a claim in prose. `scripts/selftest.sh` runs all of them: **48 cases, 48 as expected**
(`selftest.log`, per-case logs in `selftest-work/`).

No Vivado, no hw_server, no JTAG, no serial port, no board. The baseline wrapper, project and bitstream were
read, never written.

---

## 1. The build hierarchy now closes, with the board level intact

**What was wrong.** The build entry said to set the project's top module to `TeachingBoardTop`. That would
have thrown away the real board top. `rocketchip_wrapper` is what carries the PS block design, the board
pins, the MMCM and both AXI boundaries, and the baseline project sets it as the top
(`src/tcl/pynqz1_rocketchip_ZynqFPGAConfig.tcl:108`); the wrapper instantiates a module called `Top`
(`src/verilog/rocketchip_wrapper.v:264`). Identical port lists do not solve a module-name binding.

**What replaces it.**

| | |
|---|---|
| `scripts/make-top-shim.py` | generates `build-inputs/teaching_top_shim.v`: a module named `Top` that passes its 76 ports straight through to `TeachingBoardTop`. The port list is read out of the baseline `Top` and the teaching top and must match field for field, or nothing is written |
| `scripts/make-build-manifest.py` | `build-inputs/MANIFEST.txt`: 12 files, each with role, sha256, size and an absolute path. Everything downstream reads this one file, so the project and the checks cannot disagree |
| `scripts/gen-project-tcl.py` | `build-inputs/teaching_project.tcl`, generated from the manifest: an independent project, top `rocketchip_wrapper`, the black-box RTL added explicitly, `include_dirs` for `tcpu_defs.vh` and `clocking.vh`, the baseline `base.xdc` and the baseline block design, a new output directory that it refuses to overwrite, and a guard that exits if `Top.ZynqFPGAConfig.v` is ever in the file set |
| `scripts/check-hierarchy.py` | walks the design offline from `rocketchip_wrapper`: 126 modules reachable, **0 unresolved**, `Top` resolves to the shim, the path into `TeachingBoardTop → TeachingCpuZynqTop → TeachingCpu → tcpu_core → tcpu_csr/tcpu_regfile` is reached, no Rocket subsystem module is present. `system` (block design) and `IBUFG/IBUFDS/BUFG/MMCME2_BASE` (Vivado primitives) are the only things it expects the tool to supply |
| `scripts/check-tcl.tcl` | parses the generated script with plain `tclsh`: complete Tcl, top is the wrapper, every path it names exists, no baseline top, `SYNTHESIS` defined |

**The negatives that show these bite** (all asserted in `selftest.sh`):

```
hier-drop-csr         exit=1   tcpu_csr instantiated by tcpu_core, defined nowhere
hier-drop-shim        exit=1   Top instantiated by rocketchip_wrapper, defined nowhere
hier-add-rocket-top   exit=1   Top defined twice, Rocket subsystem modules present
hier-drop-wrapper     exit=1   the board top is not in the file list
hier-drop-bd          exit=1   `system` is instantiated but the block design script is not in the manifest
shim-port-mismatch    exit=1   an extra port on the teaching top; no shim written
tcl-wrong-top         exit=1   top set to TeachingBoardTop
tcl-baseline-top      exit=1   Top.ZynqFPGAConfig.v named in the script
tcl-missing-source    exit=1   a source path that does not exist
tcl-no-synthesis-define exit=1 the explicit define removed
tcl-unparseable       exit=1   unbalanced braces
```

Not claimed: that Vivado will synthesise this. Only Vivado can say that. What is claimed is that the file
list closes and names the right top, checked offline, with the checks shown to fail when they should.

## 2. Every gate propagates its own failure

**What was wrong.** `m4-build-board.sh` piped the audit into `tail -1` and read `tail`'s exit status, so an
audit failure printed and was ignored. Codex reproduced it by making `python3` return 1: the script still
printed `DRY_RUN_OK` and exited 0.

**What changed.** `set -euo pipefail`; every gate's status is read directly; no gate output is piped
anywhere; the first failure ends the run. The ROM check in `audit-board-rtl.py` is no longer skippable: it
now **extracts the ROM from the RTL itself** (walking the `TLROM` mux) and additionally requires `--rom` so
the stored copy is cross-checked. The old counterexamples in `codex-review/` are kept untouched.

```
build-dry-run          exit=0
build-execute-refused  exit=3
build-injected-failure exit=1   <- Codex's probe, now caught at the first gate
build-outdir-exists    exit=2
build-hash-mismatch    exit=1   a manifest hash altered by one byte
build-incomplete-manifest exit=1
build-stale-shim       exit=2   a shim that no longer matches its RTL
audit-no-rom-arg       exit=1
audit-rom-missing      exit=1
audit-rom-wrong        exit=1   the *original* Rocket boot ROM offered as the teaching one
audit-truncated-rtl    exit=1
audit-first-elab       exit=1   the traceEvents-on elaboration, still rejected
```

## 3. The implementation check judges, and says PENDING when it cannot

**What was wrong.** The old script printed utilisation as a note and never compared it to what the device
has, so Codex's five-resources-at-200% report passed. It also had no device, clock, DRC or CDC evidence and
still exited 0, and its regexes could not read a real Vivado table.

**What replaces it.** `scripts/check-impl-reports.py` was rewritten against the **real** reports from the
validated baseline build (`baseline-2024.1/impl_1-reports/`). Three outcomes:

* **FAIL** (exit 1) — something is wrong, or a report is missing, malformed or contradicts itself.
* **PENDING** (exit 2) — nothing supplied is wrong, but the evidence is incomplete. No report, no
  attestation, no pass. An empty command line is PENDING, not PASS.
* **PASS** (exit 0) — every machine check passed, every required report was supplied, and the criteria a
  machine cannot judge were attested explicitly with keyed `--attest constraints: …` arguments.

It checks the reports are for `rocketchip_wrapper`, routed, on `xc7z020clg400-1`; WNS/TNS/WHS/THS/WPWS/TPWS
with their failing-endpoint counts; the "all user specified timing constraints are met" line; eight
`check_timing` categories all zero; the clock table, the expected 40 MHz, and no clock the baseline lacks;
an empty Inter Clock Table, or PENDING for a person to judge the crossing; `Used <= Available` and
`Util% < 100` for LUT, FF, BRAM, DSP, BUFG and IOB, with a missing row a failure; and the DRC rule table,
where a critical warning or error fails and warnings become PENDING until attested.

```
impl-real-pending      exit=2   the real baseline reports, nothing attested
impl-real-attested     exit=0   the same reports with all four attestations
impl-no-args           exit=2   prints the frozen criteria, does not pass
impl-over-capacity-lut exit=1   61000 LUTs of 53200
impl-codex-stubs       exit=1   Codex's 200%-everything stub
impl-negative-wns / impl-nonzero-tns / impl-negative-whs   exit=1
impl-unconstrained     exit=1   unconstrained_internal_endpoints (12)
impl-wrong-design      exit=1   a report about TeachingBoardTop rather than the wrapper
impl-wrong-device      exit=1   7z010 instead of 7z020
impl-wrong-frequency   exit=1   host_clk_i at 50 MHz
impl-unexplained-clock exit=1   a clock the baseline does not have
impl-missing-resource  exit=1   the BRAM row deleted
impl-critical-drc      exit=1   one rule promoted to CRITICAL WARNING
impl-missing-timing    exit=1
```

The baseline numbers it reads, for reference only and not as a pass condition: LUT 30761/53200 (57.82%),
FF 16497/106400, BRAM 24/140, DSP 15/220, BUFG 1/32, WNS +3.395 ns, host_clk_i 40.000 MHz.

## 4. The preflight binds to one build, and blocks

**What was wrong.** It globbed for the first `.bit` and the first report it could find, treated a missing
test ELF as a warning, and did not require the implementation check to have passed.

**What replaces it.** `scripts/board-preflight.sh` now:

* re-verifies every file in the source manifest against its hash, and fails if the manifest is thin;
* requires the baseline list to cover the validated bitstream, the baseline top, the wrapper and the boot
  ROM, and fails if any of them changed;
* requires `<build>/BUILD-MANIFEST.txt` naming the bitstream, the two `.bin` images (the teaching one and
  the rollback), and the timing, utilisation and DRC reports, each with a hash — **no globbing**;
* runs `check-impl-reports.py` on exactly those reports, with the attestations the build recorded, and
  blocks unless the verdict is PASS;
* fails, not warns, if any test ELF is missing;
* blocks if a board, serial or vivado lease is held;
* and still says, on success, that a person must authorise programming the PL.

```
preflight-today        exit=1   there is no build yet, so it blocks
preflight-no-manifest  exit=1   a .bit with no build manifest
preflight-complete     exit=0   a fixture build that records everything and whose reports pass
preflight-over-capacity exit=1  the same fixture with the 200% utilisation report
preflight-no-rollback  exit=1   the rollback image not recorded
preflight-thin-baseline exit=1  a truncated baseline list
```

## 5. The withdrawn inference about `SYNTHESIS`

Codex is right that "the project sets no `verilog_define`" does not imply "Vivado does not define
`SYNTHESIS`". The claim is withdrawn in `audit/synthesis-guards.txt` and `audit/reset-and-plusarg.md`, and
the source comment that repeated it has been reworded.

The teaching build no longer depends on the answer: `teaching_project.tcl` sets
`verilog_define {SYNTHESIS}` explicitly, `check-tcl.tcl` fails if that line disappears, and the design
instantiates zero plusarg readers either way. The baseline project is unchanged.

The comment edit touches a shared file, so it was checked rather than assumed — see `gen-recheck/`.

## 6. Hashes with unambiguous paths

`HASHES.sh` now emits `sha256  path` with paths relative to `m4-prep/` or absolute, never bare basenames.
Three directories here hold a file called `TeachingBoardTop.TeachingBoardConfig.v`; the old list could not
tell them apart. 132 paths, no duplicates.

---

## What is still not verified

Unchanged from the report, plus one addition: the hierarchy check is a *parse*, not an elaboration. It
proves the file list closes and names the right top; it does not prove Vivado will accept the RTL, infer
the same hierarchy, or synthesise it. That is M4-b, and the criteria it will be judged by are frozen here.

---

## 7. What I found in my own fixes afterwards

With the four blocking items closed, I went looking for the same defect classes in the code I had just
written — gates that cannot fail, and first-match parsing that a doctored input can walk past. Five held up;
five did not. All five are fixed, and each has a case in `scripts/selftest.sh`.

**Correction to what this section originally claimed.** It said "58 cases, 58 as expected", and Codex showed
that overstated the coverage: one fixture was generated inside a quoted heredoc that was not valid Python
(`SyntaxError`, visible in the old `selftest.log`), so `shadowed-util.rpt` was never written and
`impl-shadowed-resource` exited 1 because the *file did not exist*, not because the checker caught the
shadowed row. The underlying fix was real — Codex verified it independently with their own fixture, and so
did I by hand — but the test that was supposed to prove it proved nothing. Matching exit statuses is not
coverage. See §8 for what replaced it.

**The hierarchy parser missed two instantiation styles.** A fixture with one module instantiating five
undefined modules five different ways showed it caught three: it missed `Name` and instance name on
separate lines, and instance arrays (`mod inst [3:0] (`). An unresolved module written either way would
have passed silently. The regex now allows a newline between the two identifiers and an optional range
before the port list, and the self-test asserts the *count* — `hier-parser-style-count` fails if fewer than
five of five are detected, so a future regression shows up as a number, not as silence.
Fixture: `scripts/fixtures/instantiation-styles.v`.

**The utilisation check could be shadowed by a duplicate row.** It read the first row per resource. A report
with `Slice LUTs 100 of 53200` in front of `Slice LUTs 61000 of 53200` passed with verdict PASS. It now
collects every row, fails if a resource is given two different values, and judges the worst. The real
baseline report genuinely lists `Slice Registers` twice, with identical numbers, so the rule is "disagreement
is a failure", not "a repeat is a failure". Case `impl-shadowed-resource`.

**The timing summary could be shadowed the same way.** A healthy summary table planted in the section hid a
failing one. Now every table in the Design Timing Summary section is read, a disagreement is itself a
failure, and the verdict is taken from the worst row. Case `impl-two-summaries`. Scoping that search also
fixed a real performance trap: the unanchored pattern backtracked for minutes on a multi-megabyte report,
which would have looked like a hang rather than a failure. The parse now takes 0.1 s.

**`check_timing` counts were read once.** Each category appears twice — table of contents and section
header. A report saying `unconstrained_internal_endpoints (0)` in one place and `(31)` in the other passed.
All occurrences are now collected, a disagreement fails, and the worst count is used. Case
`impl-toc-mismatch`.

**The RTL audit crashed instead of diagnosing.** Given a simulation harness or the baseline Rocket top it
raised `TypeError: object of type 'NoneType' has no len()`. The exit status was still nonzero, so nothing
unsafe followed, but a stack trace is not a finding. It now says which check the file failed and why.
Cases `audit-simulation-rtl`, `audit-baseline-top`.

**The preflight accepted two of the same role, and artefacts from elsewhere.** A build manifest listing two
bitstreams left the session choosing arbitrarily; and nothing required the images that get programmed to
belong to the build directory at all. Duplicate roles now fail, and `bitstream`, `bitstream-bin` and
`rollback-bin` must live under the build directory. Reports may live elsewhere — that is how the self-test
uses the real baseline reports — but the thing that gets written to `/dev/xdevcfg` may not.
Cases `preflight-duplicate-role`, `preflight-stray-artefact`.

None of these change the design or the RTL. They change what the gates will catch, which is the part of this
milestone that is actually load-bearing.

---

## 8. Third round — answering `codex-m4-prep-final-gates`

Codex's second review (`CODEX_REVIEW_2.md`, evidence in `codex-review-2/`) accepted the shim, the project
top, the error propagation and the resource-shadowing rejection, and found four remaining gaps. All four
are closed. The self-test is now **68 cases**, and each asserts **two** things: the exit status *and* a
diagnostic the log must contain — an exit code alone can be right for the wrong reason, which is exactly
how the previous count flattered itself.

### 8.1 A missing report field is no longer a pass

Codex took a passing report, deleted the `Device` and `Design State` lines, and it still exited 0; renaming
the `Inter Clock Table` heading also still exited 0, because an unmatched regex was read as "no crossings".
Both are now failures, with the reason stated:

```
impl-no-device-field   exit=1  the timing report has no Device field; it does not identify what it describes
impl-no-state-field    exit=1  the timing report has no Design State field; ...
impl-no-design-field   exit=1  the timing report has no Design field; ...
impl-util-no-device    exit=1  the utilization report has no Device field; ...
impl-drc-no-state      exit=1  the DRC report has no Design State field; ...
impl-no-inter-clock    exit=1  the timing report has no Inter Clock Table; there is no evidence about
                               clock crossings
```

Identity and state are now required of all three reports, including the DRC report, whose design and state
were previously only half-checked. `impl-real-attested` still exits 0 on the untouched baseline reports, so
the requirement is not simply refusing everything.

### 8.2 Fixtures that prove they exist

`scripts/make-fixtures.py` now builds every fixture and asserts each transformation: the text it replaces
must occur exactly the expected number of times, the file must be written and non-empty, and the result must
contain what the test depends on. If anything fails, the self-test stops rather than running tests that
prove nothing. Writing it this way immediately caught a stale assumption of mine: the slack figure
`3.395 0.000` appears **twice** in a real report — Design Timing Summary and Intra Clock Table — not once.

Each case now asserts its diagnostic, so `impl-shadowed-resource` fails unless the log actually says the
report gives a resource more than one value.

The `thin-baseline` negative no longer copies the delivered `audit/baseline-identity.txt` aside and restores
it: `board-preflight.sh` takes `--baseline-identity`, and the test points it at a fixture copy. The
self-test also hashes the delivered file before the first case and re-checks it after the last
(`evidence-untouched`), so a future test that writes to delivered evidence is caught rather than trusted
not to.

### 8.3 One hash root, and verification rather than regeneration

`HASHES.txt` is now entirely relative to the workspace root — **153 paths, one root** — and `HASHES.sh`
does not stop at regenerating it. It runs

```
cd /home/engineer/fpga && sha256sum -c experiments/teaching-cpu/m4-prep/HASHES.txt
```

and keeps the output in `HASHES-VERIFY.txt`: 153 of 153 OK, exit 0. Regenerating a list says nothing about
whether the files still match it; the verification output is the evidence.

### 8.4 Artefacts bound to the source they were built from

The preflight used to check the *current* source manifest while judging artefacts from some earlier build —
so updating the sources and keeping yesterday's bitstream would have sailed through. A build must now seal
what it used:

* `source-manifest` and `project-tcl` are required roles in `BUILD-MANIFEST.txt`, and like the bitstream and
  both `.bin` images they must physically live inside the build directory;
* the preflight re-hashes every file the **sealed** manifest lists, and blocks if any source has changed
  since the build;
* reports must also belong to the build directory, which is what rejects a report or bitstream borrowed
  from another build.

```
preflight-complete           exit=0  a fixture build that seals its inputs and records everything
preflight-source-drift       exit=1  source changed since this build
preflight-no-source-manifest exit=1  the build manifest has no ['source-manifest']
preflight-cross-build        exit=1  bitstream does not belong to this build
preflight-stray-artefact     exit=1  bitstream-bin does not belong to this build
preflight-duplicate-role     exit=1  bitstream is listed twice
preflight-no-rollback        exit=1  the build manifest has no ['rollback-bin']
preflight-over-capacity      exit=1  Slice LUTs does not fit: 61000 of 53200
preflight-thin-baseline      exit=1  the baseline list has only 1 entries
```

`scripts/m4-build-board.sh --dry-run` now prints the sealing step as part of what M4-b must do.

**What the build fixtures do not show.** Their `.bit` and `.bin` files are placeholders containing a line of
text. They exercise the binding rules — which artefacts a session may use, and what they must be bound to —
and say nothing about real bitstream content or about the `.bit → .bin` conversion. Neither has been
verified, and neither can be until M4-b produces a bitstream.
