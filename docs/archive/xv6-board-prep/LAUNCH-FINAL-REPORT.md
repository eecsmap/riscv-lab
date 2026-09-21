# Launch binding finalised: exact paths, real SSH serialisation, a restricted lock, a resealed bundle

claude, 2026-09-20, answering `codex-xv6-board-launch-finalize`. **No hardware, board, serial, JTAG or
network; no programming, no deployment, no SD/PS mutation, no ARM execution, no synthesis rerun, no new OS
simulation.** CPU/RTL, the accepted bitstream and the accepted xv6 simulation are untouched.

All four defects were real. The second one is the interesting one: it could only have been caught the way
Codex caught it.

## 1. Roles bound to exact paths

The gate required only that the expectation map was non-empty and then matched by **basename**, so a run
could start with a `MISSING` identity, or a same-named file from another directory could stand in for the
approved one.

`check_roles()` now requires an approved hash for the **exact path** of each of the three roles — host
binary, kernel, writable disk — validates every hash against `^[0-9a-f]{64}$`, rejects the same path
approved twice with different hashes, and rejects two roles pointing at one file. The identity map is keyed
by full path (`remote path /srv/kernel`), and the runner indexes it by the path it actually named, with no
`MISSING` default to fall back on: the gate has already refused anything absent, so a lookup failure would
be a bug rather than a condition.

Negatives, each launching **zero** hosts: host binary omitted, kernel omitted, disk omitted, only unrelated
paths approved, a hash that is not a sha256, and a same-basename file from another directory approved
instead of the real one.

## 2. Real SSH serialisation

The transport built `prefix + ["sh", "-c", script]`. Under a fake that preserves argv this works. Under
**real ssh it does not**: ssh joins its command arguments with spaces and hands the result to the remote
login shell, so the three words are re-parsed and the `sh -c` grouping is gone — the script's first word
becomes the command. The old tests could not see this because the fake preserved argv.

The contract is now stated in the module and enforced:

> the prefix is invoked with exactly **one** further argument, which is a complete shell command, and is
> expected to execute it with a shell on the board.

`ssh host` satisfies that. The prefix itself is parsed with `shlex.split`, so `--transport-cmd 'ssh -p 2222
pynq'` means what it looks like. Every embedded path goes through `remote_quote()`, and the inner
`sh -c '...'` is quoted with `shlex.quote` as a unit.

Rather than attempt to carry arbitrary paths through a remote shell, `remote_quote` **refuses early** what
it cannot carry unambiguously: anything outside `[A-Za-z0-9_@%+=:,./-]`. Whitespace, quotes, `;`, `$(...)`
and newlines are each refused with a reason, rather than quoted and hoped about.

The test suite now contains a fake that **joins its arguments and runs them through a shell**, exactly as
ssh does, and the procedure's own invocation is run through it end to end: the run completes and the same
`check-xv6.py` accepts the transcript.

## 3. The device lock

`release()` was `rm -rf $lock` — an unrestricted recursive delete on the board, aimed by a command-line
option. It now:

* verifies an **ownership token** written at claim time (a lock this process did not take is not ours to
  release);
* removes the three files it created, **by name**, then `rmdir`s the empty directory — so a wrong or
  over-broad path cannot become a recursive delete of something else;
* **fails closed**: if the token does not match or the cleanup does not complete, `UncertainState` is
  raised, ownership is **not** dropped, and the run records the uncertainty.

There is now one production lock, `/var/lock/teaching-fesvr.lock`. A different path requires an explicit
`allow_test_lock=True`, and even then over-broad paths such as `/`, `/tmp` and `/tmp/x` are refused.

**Corrected after review:** this was originally surfaced as `--allow-test-lock` on the production CLI,
which meant the switch that lets a test aim at a fake board was equally available to a real `ssh` run. The
test-only knobs now live only in `_test_runner.py`; see `TWO-GAPS-REPORT.md`.

The destructive-path checks run against a **recording fake** that captures the commands without executing
them; nothing is deleted from a real filesystem to prove this.

## 4. Bundle resealed

| | sha256 |
| --- | --- |
| `fesvr-teaching-static`, **previous** (no `--self-test`) | `bf5eac2ad1c7db2aeb8bbe6ea9dd1a34483c94031afc4c786053a93a2bfd759c` |
| `fesvr-teaching-static`, **current** (with the no-I/O `--self-test`) | `c050eab30f80a21a7c92c8688faa2f043c67aa2900fbc08b80f3dd8de2ba1fb9` |

The old manifest is kept as `deploy-bundle/MANIFEST.sha256.prev-2026-09-20`; the new one verifies 10/10.
The transition is the addition of the `--self-test` / `--version` mode that returns above every
constructor, and nothing else.

```
16156a3aa0bd725f  amo_probe.bin          ab3c43ec836bdc87  bdev_probe.bin
69ca91994567a44f  boot01_marker.elf      0c4ebbb7648a34c0  boot02_clint.elf
3089c7e72514eded  boot03_ddr.elf         fc3b16962f69e53a  boot04_badaddr.elf
c050eab30f80a21a  fesvr-teaching-static  4691ffea6b05562d  fs-pristine.img
e990fb31fad483b8  kernel-128mib          2cd8a9927cfa2f51  rocketchip_wrapper.bit
```

### The launch invocation, corrected

Every role by full path, a shell-executing prefix, the production lock, and the bitstream named:

Comments are kept outside the command, so the template can be pasted as it stands:

```
board-runner.py <outdir> \
  --transport-cmd 'ssh pynq' \
  --host-binary   /opt/teaching/fesvr-teaching-static \
  --kernel        /opt/teaching/kernel-128mib \
  --disk          /var/tmp/fs-run.img \
  --evidence-dir  /var/tmp/arm-evidence \
  --expect /opt/teaching/fesvr-teaching-static=c050eab30f80a21a7c92c8688faa2f043c67aa2900fbc08b80f3dd8de2ba1fb9 \
  --expect /opt/teaching/kernel-128mib=e990fb31fad483b805aaeae77ecaebb3111abcec012d70447c620c9e9b289c2c \
  --expect /var/tmp/fs-run.img=<sha256 of the writable copy as deployed> \
  --bitstream-sha 2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52
```

* `--disk` is the per-run **writable copy**; the source image stays immutable.
* `--evidence-dir` is the bundle captured from **this** boot of the ARM.
* an earlier version of this template broke here: the `--disk` line carried a trailing comment and no
  continuation, so everything below it was silently dropped from the command.

There is no `--remote-lock` and no `--allow-test-lock` to pass: the production CLI has no such
options at all (see the report below).

## Regression evidence

| suite | result |
| --- | --- |
| `board-safety-selftest.sh` | **pass=47 fail=0** at the time of this report; **59/59** after the follow-up in `TWO-GAPS-REPORT.md` |
| `transport-selftest.py` | **18/18**, rewritten for the new API |
| `mem-preflight-selftest.sh` | 14/14 |
| `drive-selftest.sh` | 28/28 |
| `check-selftest.sh` with run-v3's mutations | 0 fails |
| `console-selftest.py` | 0 fails |
| `check-xv6.py run-v3` | `fails=0` — the accepted simulation still checks clean |

One more of my own errors, found while writing the "no reset call" check: it identified docstrings by
looking at the token before them, which is wrong after `def f():` (the preceding significant token is `:`),
so the module's own prose about never writing `SYSTEM_RESET` was being read as code and reported a failure
that was really a success. Docstrings are now identified through the AST.

## Remaining gates

* **Programming authority is not granted and is not requested here.**
* The ARM binary has never been executed — no ARM host, no `qemu-arm`.
* The gates have seen fixtures and fakes, including an ssh-like one. That is not proof the real board
  behaves as the fakes do.
* Timing margin +0.779 ns setup, +0.024 ns hold.
* Cold-only recovery, `PL_RECONFIG_SAFE = 0`.

The intended next phase, on closure, is an explicitly authorised live memory preflight and cold-board boot.

OPEN claude-xv6-board-launch-final-ready
