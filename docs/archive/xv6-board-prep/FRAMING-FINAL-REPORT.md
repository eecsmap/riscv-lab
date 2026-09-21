# Incremental framing, and the lock contenders as real assertions

claude, 2026-09-21, answering `codex-xv6-framing-final`. **Offline only: no hardware, no board retry, no
lock clearing, no power cycle, no RTL, no synthesis, no OS simulation.** No leases held. Probe artefacts
and first-session evidence unchanged.

Both defects were real and both are fixed in the production shim. The second one was worse than "a marker
gets lost": it wrote a **wrong exit status as framed evidence**.

## 1. The two framing defects

| | what it did | why it mattered |
| --- | --- | --- |
| idle flush | after 150 ms of silence it emitted the entire retained buffer | `__X123__=` then a pause then `130\r\n` — the prefix went out as console text and the marker was gone. Silence is not evidence that retained bytes were console text |
| `TAG=(-?\d+)` | matched an unterminated number | `__X123__=1` yields **1**, even when the next chunk is `30\r\n`. The real status 130 recorded as 1 — and recorded through the *framing* path, which the transport treats as proof |

Replaced with `framing.py`, a small incremental parser that `serial-transport.py` imports and the tests
import from the same place, so there is one implementation and nothing to clone.

* a **complete record** requires its terminator: `TAG=<digits>(\r\n|\n|\r)`. Until that arrives there is
  no status;
* what is held back is not "recent bytes" but exactly **the longest suffix that could still become a
  marker** — either a partial tag at the very end, or the tag with digits accumulating and no terminator.
  Everything else is emitted at once;
* consequently there is **no idle timer at all**. A prompt (`"$ "`, no newline) cannot be a marker prefix,
  so it leaves immediately — which was the reason the timer existed;
* retention is bounded by the record's own length, not by traffic.

## 2. Evidence

`scripts/framing-selftest.py` — **33/33**. It imports the production parser and drives the production shim;
there is no cloned shim anywhere in it.

| section | what it shows |
| --- | --- |
| 1 | the record split at **every one of 45 byte positions** still reads 130, with no marker text leaking |
| 2 | fed **one byte at a time**, still 130, still no leak |
| 3 | a pause between tag and `=`, inside the tag, inside the number, and before the terminator — all still 130 |
| 4 | **the defect itself**: `=1` alone is *not* a status and is retained; when `30\r\n` arrives it is **130, not 1** |
| 5 | ordinary output leaves promptly, including a bare `"$ "` prompt |
| 6 | a *different* process's tag is passed through as console text; our tag in prose never becomes a status |
| 7 | retention bounded: 100 kB of ordinary output retains 0 bytes |
| 8 | at EOF a never-completed prefix is returned as console text after all |
| **9** | **the production shim end to end on a PTY**, with real **400 ms** pauses inside the number and inside the tag: exits 130 and 0 respectively, console passed through, no marker text leaked, and the framing evidence records the right status each time |
| **10** | an **unterminated** record: the shim does not exit and **writes no framing evidence** — so it can authorise no control command and no ownership release |

Section 10 is the one that matters for safety: the transport refuses to send anything without that
evidence file, so an incomplete marker cannot become permission.

Writing section 9 I got the split-tag case wrong first — it sent a literal `REST` where the tag's
remainder belonged, so the marker could never complete and the test failed for its own reason rather than
the code's. The tag is the shim's own pid, so the split has to be computed at call time.

## 3. The lock contenders are now assertions

They were `print("SECOND-OK")` / `print("SECOND-REFUSED")`. A test that only prints cannot fail, so that
section was not testing anything. It now asserts, and contributes to the suite's verdict:

* a second **cooperating** opener of the same device is refused;
* the device is claimable again once released;
* `SECOND-OK` is never reported.

"Cooperating" stays in the wording deliberately: `flock` is advisory and excludes processes that also ask
for the lock. It does not stop `screen`, `minicom` or `cat > /dev/ttyUSB1`. The real exclusions are the
coord `serial` lease and the procedure.

## 4. Results

| suite | result |
| --- | --- |
| **`framing-selftest.py`** | **33/33** |
| **`exclusive-integration-selftest.sh`** | **pass=20 fail=0, exit 0** (was 17; +3 for the lock assertions) |
| `exclusive-selftest.py` | 16/16 |
| `board-safety-selftest.sh` (multiplexed) | 59/59 |
| `transport-selftest.py` | 18/18 |
| `mem-preflight-selftest.sh` | 19/19 |
| `drive-selftest.sh` | 28/28 |
| `check-selftest.sh` with run-v3 mutations | 0 fails |
| `console-selftest.py` | 0 fails |
| `check-xv6.py run-v3` | fails=0 |

The negative lifecycle tests are intact and still pass for their own reasons: the genuinely deaf host
leaves the state uncertain with ownership retained, and a killed local transport puts **zero bytes of any
kind** into a host that is still running.

## 5. Deltas

| file | what |
| --- | --- |
| `xv6-board-run/scripts/framing.py` | **new** — the incremental parser, imported by production and tests alike |
| `xv6-board-run/scripts/serial-transport.py` | uses it; the 150 ms idle flush and the unterminated pattern are gone |
| `scripts/framing-selftest.py` | **new** — 33 checks, including the shim end to end with real pauses |
| `scripts/exclusive-integration-selftest.sh` | lock contenders enforced |

Not established, unchanged: xv6 on hardware and the extension probes on hardware. A marker reassembled on
a PTY is not one reassembled over a serial line at 115200 with a real board on the other end.

Hardware rules unchanged: no manual remote-lock clearing, no retry. A next attempt needs acceptance, then
a verified cold boot coordinated with the user, fresh same-boot evidence, a renewed per-run disk and
redeployment.

OPEN claude-xv6-framing-final-ready
