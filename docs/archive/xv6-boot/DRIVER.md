# The xv6 driver and checker: what they promise, and how that is tested

Codex's `codex-xv6-driver-closeout` found that the delivered `scripts/xv6-drive.py` did not do what the
previous handoff claimed. All four findings were correct. This file states the contract the two scripts now
hold to, and points at the test that proves each clause, so the claim can be checked without an hours-long
run.

## The console reconstruction

The simulator writes the target's console characters and the harness's own event lines to one stdout. The
console is what is left after the event lines are removed, and the driver must preserve its line structure,
because the checker segments the transcript on the shell prompt and then requires each command's output to
appear inside that command's own segment. A transcript with the newlines removed cannot be segmented at all.

Two cases have to be told apart, and `pump()` now does:

* a stdout line that contains an event is a console **fragment** followed by that event. The newline that
  ended the stdout line belongs to the event line, not to the target, so the fragment is appended with no
  newline of its own.
* a stdout line with no event in it is console text that really did end with a newline, so the newline is
  kept -- including for empty lines, which are what separate an echoed command from its output.

These compose: if the target prints `xv6 kernel is booting\n` and an event is emitted between the text and
the newline, the stream carries `xv6 kernel is bootingEVH 7 ...\n` and then an empty line, which
reconstructs to exactly `xv6 kernel is booting\n`.

A third case had never been handled and the fake simulator exposed it: **a shell prompt ends in `$ ` with no
newline after it**, so the line holding it stays in the read buffer indefinitely. The old driver only ever
matched completed lines, so it could only see a prompt when an event line happened to come along and
terminate it -- the real runs worked by luck, and the fake, which emits no events while idling at a prompt,
timed out waiting for a prompt that was sitting in the buffer. `text()` now offers the unterminated tail for
matching, with any partial event line trimmed off it, while `console.txt` still only receives text that has
been committed by a newline or by EOF.

## The ending

`pump()` no longer returns as soon as `poll()` reports an exit: it reads to EOF first and flushes the last
partial line, because the simulator writes its tally as it goes down and that tail was being dropped. The
`finally` path pumps while it waits for the process, so output produced in response to the SIGTERM is
captured too.

`stages.txt` ends with a record whose **values** the checker validates, not merely their presence:

| field | meaning |
| --- | --- |
| `# driver: v2` | the transcript format. Earlier drivers joined console lines; the checker rejects them rather than mis-segmenting them silently. |
| `# simulator exit: N` | must be `0`, or `-15` for the driver's own SIGTERM. A crash or a forced kill is rejected. |
| `# stop: deliberate-stop-after-all-commands` | the one acceptable ending, and only when every stage passed. A shell does not terminate on its own, so the driver stopping a healthy simulator is a result, not a timeout. |
| `# stop: stopped-after-failed-command:<name>` | a command failed; the driver stopped there. |
| `# stop: simulator-exited-during-command:<name>` / `simulator-exited-on-its-own:<code>` | the simulator ended by itself, which is never the intended ending. |
| `# stop: no-shell-prompt` | the run never got that far. |
| `# signalled: SIGKILL` | the simulator refused SIGTERM, so its tail is not trustworthy; rejected. |

An empty, unrecognised, or duplicated field is rejected. The last clause matters because a transcript with
two contradictory `# stop:` lines would otherwise be read as whichever one came first.

A failed command now **stops the run**. Typing the next command into a shell whose state is unknown -- a
command that never returned leaves the input stream ambiguous -- produces output that cannot be attributed
to anything, which is how a later command's text came to satisfy an earlier command's pattern in the
counterexample Codex built.

## The tests

`scripts/drive-selftest.sh <fresh dir>` runs the real driver against `scripts/fakesim.py`, a stand-in that
reproduces only the properties that matter: chunked writes that do not line up with lines, event lines wedged
into the middle of console lines, an echo of whatever is typed at it, and output written at the moment it is
terminated. It logs every line it is sent, which is how "a failed command prevents later input" is proved
rather than asserted. 27 checks, in four groups:

1. a healthy run -- newlines kept (banner as its own line, empty lines survive), event text excluded from
   the console but kept in `run.log`, the tail written at SIGTERM drained, all four commands typed, the
   checker accepts it;
2. a command that fails -- the driver exits 1, **only `echo` and `ls` were ever typed**, the ending names
   the failed command, the checker rejects it and says which command;
3. a simulator that dies on its own -- the output written just before it exits is still captured, the ending
   reports the unexpected exit, the checker rejects it;
4. eight transcripts with a **passing console and a bad ending** -- an exit-on-its-own label, an empty label,
   an unrecognised label, a failed-command label, a crash exit status, a SIGKILL, an older driver version,
   and a deliberate-stop label contradicted by a failed stage. Every one is rejected.

`scripts/check-selftest.sh <fresh dir>` still runs the synthetic console negatives independently of any run.
Recorded output: `evidence/driver-selftest-v2.txt` (27/27) and `evidence/check-selftest-v2.txt`.

## Status of the real runs

* `run-dev2` -- finished, **old driver**. Archive evidence only; its console has no newlines.
* `run-clean` -- still running, started 00:56 with the **old driver**. Its transcript is format-incompatible
  and the checker rejects it by design. It is **not acceptance-ready** and is being left to finish untouched
  rather than being claimed as a result.
* `run-v2` -- started 01:59 with the corrected driver, its own copy of `evidence/immutable/fs-pristine.img`
  (`4691ffea...`), kernel `6ad5c233...`, simulator `fa8c59db...`. This is the run that four-command
  acceptance depends on.
