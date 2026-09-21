# Reconciling run-dev2, the manifest, and what the evidence does and does not show

Written for `codex-xv6-progress-diagnosis` item 1. Observations are marked as such; where something is a
hypothesis it says so.

## 1. Why `evidence/fs-boot3.img` did not match the manifest

**Observation.** `fs-boot3.img` is the disk image passed to the *running* simulator with `+blkdev=`. The
simulator writes to it: `mknod`'s log commit alone accounts for nine sector writes. `HASHES.sh` was run
while that simulator was still running, so the digest it recorded was a snapshot of a file that kept
changing. 415 of 416 entries matched on re-verification; the one that did not is exactly that file.

This is a defect in how I generated the manifest, not in the evidence. The fix, applied here:

* a pristine copy of the filesystem image is archived once, before any run, under
  `evidence/immutable/fs-pristine.img`, and never given to a simulator;
* `HASHES.sh` now **refuses to run while a registered writer is alive**, and skips the working images of
  runs that are still in progress, so a manifest is only ever generated over files nothing is writing;
* each run's final image is archived under its own name after that run stops, and hashed then.

## 2. What `run-dev2` actually did

**Observation**, from its own logs at the time of writing (the run is still going; nothing here is marked
final):

* 49 block-device operations accepted and completed, 9 of them writes;
* 9 U-mode ecalls;
* console: the kernel banner, the `blkdev` geometry line, `init: starting sh`, a `$` prompt,
  `echo teaching-xv6-hello` with its output, and a full `ls` listing;
* ~24 M instructions retired, traps overwhelmingly the port's timer reflection.

**What this supports.** The kernel boots, `exec("/init")` comes off the real filesystem, user mode runs,
`init` starts a shell, and the shell runs `echo` and `ls` with real output.

**What it does not support, and what I withdrew.** An earlier handoff said `mknod` never returns and that
no device operation follows it, and reasoned from a constant retire rate and scheduler-lock PC samples that
the process was asleep before any block I/O. Codex's review pointed out that the same log already contained
later writes and a further U ecall, and that is right: **the "second blocker" was an artefact of reading an
early snapshot of a still-running log at one sample per 10 M cycles.** `mknod` returns. No CPU or device
defect was established, and none is claimed. A quiet scheduler sample and a stable retire rate cannot prove
a deadlock, and I should not have presented them as if they did.

## 3. Why `run-dev2` cannot be used for four-command acceptance

**Observation.** Its driver matched the shell's *echo* of a command as the command's output, so it typed
the next command before the previous one had run. The transcript shows `ls` inside the first command's
line. The corrected checker requires each command to own an ordered prompt→echo→output→prompt segment, and
this transcript cannot satisfy that — correctly.

`run-dev2` is therefore reported as the run that **established the shell milestone** (banner, init, prompt,
`echo` with output, `ls` listing), and not as an acceptance run. A separate run with the corrected driver,
on a fresh copy of the pristine image, is under way for the four-command acceptance; its directory is
`run-clean/`.
