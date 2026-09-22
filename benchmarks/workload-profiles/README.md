# Workload profiles — a proposed delta to the frozen xv6 driver and checker

**The delta is NOT applied.** `xv6-workload-profiles.patch` is a proposal, and the four files it touches
are provenance-frozen. Per `codex-b0-e1-opt01-authorization` §1 — *"If changing frozen tools is actually
necessary, propose the exact delta first, not bypass their provenance gate"* — this is that proposal,
with the tests that show it does what it claims.

Nothing here changes the repository's frozen files and `make check` is unaffected.

## Why a delta rather than a separate runner

`EXPECTED` is a module-level constant in `xv6_console.py`, imported and iterated directly by both
`board_run.py` and `check-xv6.py`. A separate runner under `benchmarks/` could not reach it without
either monkey-patching at runtime or **copying the command loop** — and a copied loop that drifts from
the production one is exactly how `_test_runner.py` came to exercise a construction production never
performed, which is the bug that cost hardware session 2.

So the proposal is to make the production code take a **named profile**, defaulting to what it does now.

## The delta: 4 files, 64 added or removed lines

| file | change |
| --- | --- |
| `xv6_console.py` | add `PROFILES` (with `'default': EXPECTED`) and `profile(name)`. **`EXPECTED` and `STAGES` are not modified**, so an unnamed run is byte-for-byte what it was |
| `board_run.py` | iterate `profile(a.workload or 'default')` instead of `EXPECTED`; write `# workload:` into `stages.txt` |
| `board-runner.py` | one option, `--workload`, defaulting to `default` |
| `check-xv6.py` | read the workload **out of the record being checked** and look up the same profile |

### The two properties that matter

**One definition, shared.** The driver decides what to send and the checker decides what to accept from
the *same* profile entry. They cannot diverge, because there is only one table.

**No escape hatch.** The interface takes a **name**. Commands live only in `PROFILES`, and an unknown
name is refused — by the driver at launch and by the checker when it reads the record. There is no way
to pass an arbitrary shell command, and no blanket "marker seen" acceptance: each entry carries an
explicit expected-output regex, and for the application workloads that regex is a **checksum**.

All production lifecycle gates are untouched: identity, memory preflight, ownership, framing, bounded
timeout, remote exit and ARM health are all outside this delta.

## Corrections after review (R1)

Codex found that the first draft validated the profile **only inside the post-boot command loop**, so an
unknown name would have constructed a transport, taken a lease and a remote lock, and **launched a host**
before raising. The tests checked `profile()` and the checker, not the pre-launch refusal the README
claimed. Three fixes:

* **`board-runner.py` validates immediately after `parse_args`** — before the expectations are parsed,
  before a transport exists, before any lease, lock, remote command or host launch;
* **`board_run.run()` validates at the shared entry** and passes the resolved profile into the loop, so
  non-CLI callers get the same refusal;
* `UnknownProfile` is a typed exception converted to a **clear refusal and exit 2**, never a traceback;
* the checker **refuses duplicate or conflicting `# workload:` headers** instead of silently taking the
  first.

## Tests

### `cli_selftest.sh` — the ACTUAL production entry, 17 checks, 0 failures

| | |
| --- | --- |
| **zero remote or host calls** | an unknown name against a *recording* transport leaves its log **empty**; no lock taken, no output directory created, exit 2, no traceback |
| **driver → board → checker** | a real `b0apps` run through the production CLI against a PTY board: six stages ok, the record names the workload, the host received **exactly** the three commands in order, and the **patched checker accepts the real transcript** |
| a wrong checksum from the board | fails the run **and** is refused by the checker |
| duplicate workload headers | refused, naming the problem |

### `profile_selftest.py` — 18 checks, 0 failures

It applies the patch to a **scratch copy**, never to the repository.

Both suites use only in-repository paths.

| | |
| --- | --- |
| default unchanged | `profile('default')` is the original `EXPECTED`, still the four accepted commands in order, with the original `STAGES` |
| **the regression that matters** | the **accepted board transcript** (`evidence/xv6-board-run-3/run-1`) still checks clean through the *patched* checker |
| named profile | drives `b0compute`/`b0array`/`b0file`, stage names derived from the same definition, each with an explicit checksum |
| no escape hatch | an arbitrary command string and an unknown name are both refused |
| negatives | wrong checksum, truncated output, a timed-out stage, a missing command stage, a record naming an unknown profile, and a four-command transcript presented as `b0apps` — each refused |

Each negative asserts **the reason**, not merely a non-zero exit. An earlier draft placed the profile
lookup above the import, so the checker died with `NameError`; every negative "passed" on that crash.
`refused()` now fails a test that exits non-zero by crashing.

## Applying it, when reviewed

`apply-profile-delta.sh --dry-run` shows exactly what would change and touches nothing:

```
  tools/xv6-boot/scripts/xv6_console.py   d879f46dfac22323 -> 86e4b94e63a26322
  tools/xv6-boot/scripts/check-xv6.py     ced6ea10ce59fd9e -> 97fd56af4dfb84c5
  tools/board/scripts/board_run.py        1639fea593c5d93f -> bbe4b30bed2802c6
  tools/board/scripts/board-runner.py     e5a08cd52d585bde -> c81d02cae721acf4
  4 of 413 provenance entries would change
```

`--apply` does it in the order Codex required: **first** preserve the original manifest verbatim in
`provenance-history.json` — all 413 entries, plus each changed file's original hash, the patch's own
hash, the commit it was applied at, and the reason — **then** patch, **then** update those four hashes
and record the resulting ones. **No entry is deleted and no file is exempted from hash verification.**
The history file is written once and refuses to overwrite itself.

**It has not been applied.** That is a decision for the provenance gate's owner.

## What this does not do

It runs nothing on hardware. The three application workloads remain **unexecuted**, and their metrics
stay `null` — see `benchmarks/baselines/B0/REPORT.md`. Applying this delta is a decision for the
provenance gate's owner, not something to be assumed by merging.
