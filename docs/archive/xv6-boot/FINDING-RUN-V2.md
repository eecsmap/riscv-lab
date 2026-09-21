# run-v2 was aborted by a driver false negative, not by an xv6 failure

Reported by claude, 2026-09-20, under `CODEX_DRIVER_ACCEPTANCE.md`'s instruction to preserve the first
causal evidence when a command fails rather than to adjust the success criteria. The criteria are unchanged.

## What the record says

```
ok	4.0	kernel banner
ok	3501.4	init started / first prompt
ok	4049.2	shell prompt
ok	4485.4	command echo
FAILED	10953.8	command ls
# driver: v2
# simulator exit: 0
# stop: stopped-after-failed-command:ls
```

## What actually happened

`ls` succeeded. `run-v2/console.txt` holds the complete listing in `ls`'s own prompt segment -- 24 lines,
`README 2 2 2441` among them. The driver's *inline* check disagreed with the checker because the two
attributed output differently:

* the checker segments the console on the prompt and reads the body of the segment whose echoed line is
  exactly `ls`. That segment contains README, so the checker calls it a pass;
* the driver used `text().rsplit(cmd, 1)[-1]` -- the text after the **last** occurrence of the substring
  `ls` anywhere in the console. A real xv6 listing contains an entry for the `ls` binary itself, so the
  split landed inside `ls`'s own output at `ls             2 10 38960` and examined only the tail, which
  begins at `mkdir` and naturally does not contain README.

Replaying the corrected attribution over the preserved console:

```
echo : segment 0,  1 output lines, pattern satisfied = True
ls   : segment 1, 24 output lines, pattern satisfied = True
cat  : never ran (no segment echoing exactly 'cat README')
pipe : never ran (no segment echoing exactly 'echo abc | wc')
```

`cat` and `pipe` never ran because the driver -- correctly, given what it believed -- stopped at the first
failed command. So this run proves `echo` and `ls` on the teaching CPU and proves nothing either way about
`cat` and the pipe.

## The fix

The defect is that the driver and the checker each had their own idea of what a command's output is. A
better heuristic in the driver would not have fixed that. `scripts/xv6_console.py` now holds the one
implementation -- `segments()`, `command_output()`, `output_matches()`, the `EXPECTED` command table and the
`STAGES` list -- and both programs import it. They can no longer disagree.

`scripts/fakesim.py` now prints a listing that contains entries named `ls`, `echo`, `cat` and `wc`, which is
what defeats substring attribution; `drive-selftest.sh` asserts that `ls` is attributed to `ls` and not to
the `ls` entry inside its own listing. 28 checks, 28 pass. Had the fake's listing been realistic in the
first place, this would have cost minutes instead of three hours.

## Provenance, also corrected

`archive-run.sh` first wrote the *current* hashes of the driver and checker into `run-v2/IDENTITY.md`. Those
sources had been edited since the run, so the entry described what they had become, not what produced the
transcript. The driver now records its own hash, the shared module's, the simulator's, the kernel's and the
disk's into `stages.txt` **when it starts**, and the archive prefers those. `run-v2/IDENTITY.md` was
regenerated and now says plainly that the run predates this and omits the two hashes rather than asserting
wrong ones.

## Status

`run-v2` is kept as failed-run evidence and is not offered for acceptance. `run-v3` started 05:07 under job
`xv6-run-v3` with driver v3 and its own copy of the pristine image (`4691ffea...`).
