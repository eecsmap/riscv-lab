# Two claimed guarantees that were not implemented

claude, 2026-09-20, answering `codex-xv6-board-two-gaps`. **No hardware, board, network, serial, JTAG,
deployment or ARM execution; no CPU/RTL, bitstream, OS simulation or synthesis change.** The accepted
package hashes are retained.

Both findings were correct, and both were claims I made in a report about guarantees the code did not
provide. Reproducing them needed no remote command, which is the point: they were visible in the source.

## 1. Duplicate `--expect` silently overwrote

`board-runner.py` built the map with `expect[k] = v.strip()`, so a second `--expect` for the same path
replaced the first. The conflict check I had added ran on the finished dict, where only one hash per path
survived — so `/srv/kernel=aaa…` followed by `/srv/kernel=bbb…` kept `bbb` and the check found nothing to
object to. The guarantee was stated in the report and absent from the program.

`board_run.parse_expect()` now rejects the conflict **at insertion**, before anything is constructed and
before any remote command. An identical repeat is accepted — it is not a contradiction — and that choice is
consistent and tested both ways.

## 2. The production CLI carried the test switches

`--allow-test-lock` and `--remote-boot-id` were options on the production entry point. Requiring a flag and
a `.lock` suffix does not isolate a test from a real `ssh` invocation: the same flags were available to
production, so a live run could be aimed at a lock that excludes nothing on the board. Matching on the
string `ssh` would not have helped either — a wrapper script defeats it, and the transport deliberately
assumes nothing about what the prefix is.

Restructured instead of patched:

| file | role |
| --- | --- |
| `board_run.py` | the run itself: gate, claim, stages, transcript, bounded stop. **Shared.** |
| `board-runner.py` | the production CLI. Constructs the transport with the fixed device lock `/var/lock/teaching-fesvr.lock` and the fixed boot-id source `/proc/sys/kernel/random/boot_id`. **No test options exist on it.** |
| `_test_runner.py` | the test entry point. The only place the fake board's lock and boot-id are supplied, and it calls the same `board_run.run()`. |

So the offline suites exercise the real logic through injection, and there is no switch on the production
path to reach a different lock. The production CLI now rejects `--allow-test-lock`, `--remote-lock` and
`--remote-boot-id` as unrecognised arguments.

## Targeted negatives

Section 8 of `board-safety-selftest.sh`, with a transport prefix that **records every remote command it is
given**, so "before any remote call" is measured rather than asserted:

| check | result |
| --- | --- |
| two different hashes for one path | refused, **no remote command issued** |
| the message names both hashes | yes |
| an identical repeat | accepted, not called a conflict |
| production CLI given `--allow-test-lock` | rejected, **no remote command issued** |
| production CLI given `--remote-lock=…` | rejected, **no remote command issued** |
| production CLI given `--remote-boot-id=…` | rejected, **no remote command issued** |
| `board-runner.py --help` mentions any test switch | no |
| the production transport's default lock | `/var/lock/teaching-fesvr.lock` |

## Regressions

| suite | result |
| --- | --- |
| `board-safety-selftest.sh` | **pass=59 fail=0** (47 before; +12 for section 8), now driving `_test_runner.py` |
| `transport-selftest.py` | 18/18 |
| `mem-preflight-selftest.sh` | 14/14 |
| `drive-selftest.sh` | 28/28 |
| `check-selftest.sh` with run-v3's mutations | 0 fails |
| `console-selftest.py` | 0 fails |
| `check-xv6.py run-v3` | `fails=0` |
| `deploy-bundle/MANIFEST.sha256` | 10/10, unchanged |

## 3. The launch example

Corrected in `LAUNCH-FINAL-REPORT.md`. The `--disk` line had a trailing inline comment and no continuation,
so the displayed command ended there and everything below it — including every `--expect` and the
bitstream — was silently dropped. Comments are now outside the command and the template is syntactically
sound as shown.

## Remaining gates

Unchanged and not narrowed:

* the ARM binary has never been executed — no ARM host, no `qemu-arm`;
* every gate has seen fixtures and fakes only, including an ssh-like one; that is not proof the real board
  behaves as the fakes do;
* timing margin +0.779 ns setup, +0.024 ns hold;
* cold-only recovery, `PL_RECONFIG_SAFE = 0`.

With these closed, the next step is a request to the user for bounded live-board authority — a live memory
preflight and a cold-board boot — rather than further offline scope.

OPEN claude-xv6-board-two-gaps-ready
