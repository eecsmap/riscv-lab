# Executing DEPLOY-AND-RESTORE.md

`DEPLOY-AND-RESTORE.md` is the procedure. These scripts are that procedure made executable, so the
user's power-cycle window is spent measuring rather than improvising.

**Nothing here has touched the board.** The rehearsal runs entirely against a scripted fake.

| script | when |
| --- | --- |
| `e1-precycle.sh install` | **before** the user powers down. Checks every local artefact and both payload hashes, asks the board whether it has `timeout`, and **pins the current boot id to a file** |
| `e1-install.sh` | after the first cold cycle — steps 1–7 |
| `e1-precycle.sh restore` | before the second power-down; pins again |
| `e1-restore.sh` | after the second cold cycle — steps 8–12 |
| `rehearsal.sh` | any time, offline: proves the gates refuse |

## Why the boot id is pinned to a file

The rule is that a power cycle is verified and never assumed. "Verified" has to mean compared against
something recorded *before* the power-down — a boot id recited in conversation, or written in a coord
note, is not evidence. With no pin, `verify_cold_cycle` refuses (exit 50) rather than proceeding.

## One refusal, one exit code

| code | meaning |
| --- | --- |
| 10 | the boot id did not change, or could not be read: **no power cycle** |
| 11 | uptime is not near zero |
| 12 | `/root/xv6run` is not empty — not a fresh RAM initramfs |
| 13 | a host is running, or an ownership lock is present (**never cleared by hand**) |
| 20 | an artefact hashed wrong **on the board** |
| 21 | `prog_done` is not 1 after programming |
| 30 | a startup probe failed — the session stops, it is not skipped or retried |
| 40 | fewer samples than the policy requires |
| 50 | nothing was pinned to compare against |

## The rehearsal, and why it can fail

`rehearsal.sh` is **20 checks**, each asserting the exit code *and* that the refusal names its own
reason, plus positives proving the same gates let a healthy board through — a gate that always refused
would otherwise pass every negative.

It was checked against deliberate defects:

| mutant | caught as |
| --- | --- |
| the boot-id comparison removed | `exit 0, wanted 10` |
| a failing startup gate **skipped** instead of stopping | still refused, but **with the wrong reason** (`only 7 of 8 gates ran`) — an exit-code-only test would have passed it |
| `tail -1` → `head -1` in the response parse | the wrapped-echo decoy is read as the answer |

## Two defects found while writing this, both before any hardware

* the probe invocation was written `+payload=x.elf` from memory; the run-2/run-3 logs record
  `./fesvr-teaching-static ./x.elf`. It would have failed inside the power-cycle window;
* `perf03_fetch`/`perf04_where` live in `probes/build-perf`, and the E1 payload under `build/reports` —
  neither was where the first draft looked. The preflight now checks all of it **before** the power-down.

A third was found by the fake: the shim echoes each command, and the terminal **wraps** that echo, so a
line beginning `BID=` can come from the question rather than the answer. Every response parse is
"last `KEY=value`", and section 7 pins that with a decoy.
