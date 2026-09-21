# Review correction: session 2's "remote exit confirmed: yes" is invalid evidence

claude, 2026-09-21, under `codex-xv6-production-entry-fix`.

**`run-1/stages.txt` and `run-1/console.txt` are NOT modified by this correction**, and must not be. They
are what the run actually recorded, and a record that is rewritten after the fact stops being evidence.
This file sits beside them and says what the record is worth.

    run-1/stages.txt  md5 acb376231e06e6ca2315398a47a71b9f
    run-1/console.txt md5 728cd874d64366e5917d0187af691b67

## The two lines that must not be read as evidence

```
# host exit: 595
# remote exit confirmed: yes
```

**Neither is a fact about the board.** `595` was not read from the board's `exit` record at all. The run's
shim had crashed with

```
File "/usr/lib/python3/dist-packages/serial/serialposix.py", line 595, in read
```

and the transport's `_last_int()` took *the last integer anywhere in the console stream*, which was the
line number in that traceback. `remote exit confirmed: yes` then followed mechanically from having got a
number, not from the board having recorded one.

So, for session 2:

| line | status |
| --- | --- |
| `# host exit: 595` | **invalid.** 595 is a Python source line number from our own crashed shim |
| `# remote exit confirmed: yes` | **invalid.** No exit status was ever read from the board |
| `# stop: uncertain-lock-state` | valid, and the only reason the run was not reported as a success |
| stages `ok` up to `shell prompt 87.0s` | valid — the kernel banner, init and the prompt were observed |
| stage `FAILED 103.4 command echo` | valid |

The host's true exit status on the board in session 2 is **unknown and unknowable from this evidence**.
It was never read. Nothing in this directory establishes that the fesvr host terminated.

## What still stands

The hardware results in `logs/` are unaffected — they are marker-and-exit-status records from probe
binaries, read directly, with no control-reply path involved: the four M3 probes and the four extension
probes (`TEACHING-EXT-{M,C,A,SV39}-OK`, RC=0), the `0x00000011` cold-start status word, and the xv6 boot
timings above.

## Why it cannot recur

`_last_int()` no longer exists. Control replies are now delimited by a per-read nonce assembled on the
board, must be a bare integer, and must be in range (pid positive, shell status 0..255). A traceback, a
bare number, console furniture, a failed control command, a timeout and two replies from two writers are
each refused rather than turned into a value — including this exact traceback, which is now a test case in
`transport-selftest.py`. A failed control command can no longer produce `confirmed: yes`.

See `../xv6-board-prep/PRODUCTION-ENTRY-REPORT.md` for the defect this run exposed and the fix.
