# Executing DEPLOY-AND-RESTORE.md

`DEPLOY-AND-RESTORE.md` is the procedure. These scripts are that procedure made executable, so the
user's power-cycle window is spent measuring rather than improvising.

**Nothing here has touched the board.** Both rehearsals run against recording stand-ins and open no
device.

| script | when |
| --- | --- |
| `e1-precycle.sh <phase>` | **before** the user powers down. Claims the leases, checks every local artefact and both payload hashes, asks the board whether it has `timeout`, and pins the current boot id |
| `e1-record-power-cycle.sh <phase>` | **the user runs this** after physically removing and restoring power |
| `e1-install.sh` | after the first cold cycle — steps 1–7 |
| `e1-restore.sh` | after the second cold cycle — steps 8–12 |
| `rehearsal.sh` | offline: the gate FUNCTIONS refuse, 27 checks |
| `entrypoint-rehearsal.sh` | offline: the REAL scripts stop, 29 checks |
| `gen-markers.sh` | regenerates `markers.tsv` from the ELFs that will be deployed |

## What the first version got wrong

Codex reviewed it and did not clear it for hardware. Four findings, all real, all fixed here.

**1. Failures did not stop the entrypoints.** The scripts used `set -u` only, and the cold-cycle gate
was called as `NEWBID=$(verify_cold_cycle ...)`. `die` calls `exit`, and inside a command substitution
that exits the *subshell*: the parent carried on with the refusal message captured as the boot id and
went on to program the FPGA. Demonstrated before fixing:

```
REFUSE: the boot id is UNCHANGED
PARENT CONTINUED. NEWBID='REFUSE: the boot id is UNCHANGED'
...and would now program the FPGA
script rc=0
```

No gate returns its value through `$( )` any more; they write to a file the caller names. The 20-check
library rehearsal had passed throughout, because a function exiting correctly says nothing about whether
its caller stopped.

**2. Board access preceded the lease claims.** Leases are now claimed before any transport call,
including in `e1-precycle.sh`; a partial claim releases what was taken and refuses; only leases we
actually hold are released.

**3. The memory evidence chain was missing.** The install called `mem-preflight.py --evidence-dir`,
a flag the real CLI does not have, against a directory nothing filled. `capture_evidence.py` now
collects this boot's evidence in the layout the preflight requires — the three device-tree files are raw
bytes, so they cross the text console as `od -An -tx1` and are reassembled — the live boot id is checked
against the capture, and the verdict is taken from the preflight's **exit status**, not from grepping an
accumulating log. Restore runs the same chain.

**4. Validation was too weak to mean anything.** Now: every artefact is uploaded through `send-file.py`,
which verifies each sha256 *on the board*; executable mode is set as its own step (the historical
procedure does this and the first draft omitted it); each startup gate must print its **exact completion
marker** as well as exit 0, the markers being read out of the ELFs themselves by `gen-markers.sh`; and
each perf sample is judged by the production `probe_parse`, which checks the marker, the exit status and
the retired-instruction window. `RC=0` is not a result — a corrupted sample with a valid marker and
`RC=0` is still rejected because its window retired 153 instructions instead of 30002.

## The boot id does not prove a power cycle

Codex's answer to the question I asked, and it is right: a pinned boot id proves a **new Linux boot**.
A warm `reboot` changes the boot id, resets uptime and clears the RAM initramfs just as well, and leaves
the PL configured. Nothing reachable from this host distinguishes them.

So power removal is **attested by the user** through `e1-record-power-cycle.sh`, and is labelled as
attested — not measured — everywhere it is used. The boot evidence is still required, and is still
necessary-but-not-sufficient. A record older than the pin is refused, because it attests to an earlier
cycle.

## A shortfall is a failed measurement, not an abandoned restoration

Fewer usable samples than the policy requires exits 40 and says so. Restoration is still required and
still authorised; failure is not permission to hot-reload or to clear an unknown lock.

## One refusal, one exit code

| code | meaning |
| --- | --- |
| 10 | the boot id did not change, or could not be read: **no reboot** |
| 11 | uptime is not near zero |
| 12 | `/root/xv6run` is not empty — not a fresh RAM initramfs |
| 13 | a host is running, or an ownership lock is present (**never cleared by hand**) |
| 14 | no user-attested record that power was physically removed |
| 20 | an artefact hashed wrong **on the board**, or an upload failed |
| 21 | programming failed, or did not leave `prog_done=1` |
| 30 | a startup gate failed, or exited 0 without its marker |
| 40 | fewer usable samples than the policy requires — the measurement FAILED |
| 50 | nothing was pinned to compare against |
| 60 | a lease was refused |
| 61 | memory evidence could not be captured, or the preflight refused |
| 62 | the transport failed; the board's state is unknown |

## The rehearsals, and what they were checked against

`entrypoint-rehearsal.sh` runs the **actual** `e1-install.sh` and `e1-restore.sh` against recording
stand-ins and asserts, for every induced failure, that **zero** subsequent deploy, program and probe
operations were issued — read off a recording of everything the script actually asked for.

| mutant | result |
| --- | --- |
| the original condition: `set -u` only **and** the `$( )` form | **caught** — install ran on past the refused gate and died later at 61 instead of 10 |
| `set -e` removed, correct structural form kept | **29/29 still pass** — the protection is structural, not `set -e` |
| the boot-id comparison removed | caught |
| a failing gate skipped instead of stopping | caught, and **with the wrong reason** — an exit-code-only test would have accepted it |
| `tail -1` → `head -1` in the response parse | caught by the wrapped-echo decoy |

The positive path matters as much: install deploys 12 artefacts, programs the PL **exactly once**, runs
18 probes (8 gates + 2 × 5 samples) and reports `E1_INSTALL_DONE`; restore deploys 10, programs once,
re-runs the 8 gates and takes no samples.

Two defects in my own test harness came out of writing this: `grep -c` prints `0` **and exits 1**, so
`|| echo 0` made every count read `"0\n0"`; and `artefacts.sh` reassigned `SEND` unconditionally after
`lib-e1.sh` had made it overridable, so the rehearsal called the real `send-file.py`, which opened the
serial device and hung. The hang is how it was found.
