# xv6 runs on the teaching CPU, on the PYNQ-Z1, with all four commands

claude, 2026-09-21, executing `codex-xv6-converge-to-board` part C under the existing user authorization,
after Codex's acceptance in `CODEX_CONVERGENCE_ACCEPTANCE.md`. The user performed the physical power
cycle; everything else below is mine.

**The milestone is met in one hardware session.** xv6 booted on the teaching core, reached an interactive
shell, ran `echo`, `ls`, `cat README` and `echo abc | wc` with correct output for each, terminated with a
framed remote exit read back from the board, released its lock, and left the ARM healthy.

```
XV6_CHECK segments=5 prompts=5 stages=7 console_bytes=3387 fails=0
BOARD_RUN stages=7 failed=0 host_exit=0 (deliberate-stop-after-all-commands)
```

## 1. Cold start, verified on six signals before anything was claimed

Cold recovery is a precondition, never inferred. The board was not probed beforehand — session 2's host
might still have owned the serial line, and sending anything to an unknown owner is how session 2 was
contaminated. The pre-cycle record (`PRE-CYCLE-STATE.md`) is host-side only.

| signal | session 2 | after the power cycle |
| --- | --- | --- |
| USB re-enumeration | ttyUSB0 02:56, ttyUSB1 03:17 | **both 06:32** |
| boot id | `50271db5-f010-409d-bfd9-98a367280bc2` | **`ebeab8a6-0ac9-474a-84c3-bd6e0b357d3b`** (third distinct) |
| uptime | — | **22.44 s** |
| `/root/xv6run` | 12 files | **0 entries** |
| `/var/lock/teaching-fesvr.lock` | held, corrupted owner | **`NO_LOCK`** |
| fesvr processes | unknown | **0** |

Session 2's stale lock is gone **because the platform lost power**, which is the only permitted way for it
to go. Nothing was cleared by hand. The board's clock reads from the epoch (no RTC), corroborating uptime.

## 2. The session, in order

| step | result |
| --- | --- |
| memory evidence | captured over the console, bound to `ebeab8a6-…`; digest `ae1898787833944a…` |
| preflight | `MEM_PREFLIGHT OK refusals=0` — DT memory 256 MiB @ 0x0, target window `0x10000000–0x1fffffff` |
| deployment | `DEPLOY_OK`, 12 files, 16m55s, 8.4 KB/s; `fs-pristine.img` → `/root/xv6run/fs-run.img` as the fresh writable copy |
| hashes on the board | **all 12 diffed against the frozen manifest: exact match**, no eyeballing |
| PL programming | from cold/quiescent, `PROG_RC=0`, `prog_done=1`, dmesg clean |
| adapter status | **`0x00000011`** — `cpu_restart_safe=1 pl_reconfig_safe=0 boot_ready=1 epoch=0`, and `0x43C00010=1`. The cold-start signature, matching simulation |
| ARM self-test | `TEACHING_HOST_SELFTEST`, "no device was opened, mapped, read or written", rc 0 |
| **startup gates** | `boot01_marker` `boot02_clint` `boot03_ddr` `boot04_badaddr` **4/4 rc 0**; `ext01_m` `ext02_c` `ext03_a` `ext04_sv39` **4/4 rc 0**. Eight probe programs, bounded timeout each |
| **xv6** | below |

## 3. The run itself

The **exact** command in `CONVERGENCE-PACKAGE.md`, unmodified: `board-runner.py`, `--channel exclusive`,
`--serial-device /dev/ttyUSB1`, the three `--expect` hashes and `--bitstream-sha`. `_test_runner.py` was
not used and cannot be reached from this CLI.

| stage | t |
| --- | --- |
| kernel banner | 5.4 s |
| init started / first prompt | 73.8 s |
| shell prompt | 86.2 s |
| `echo teaching-xv6-hello` | **ok** 96.4 s |
| `ls` | **ok** 247.4 s |
| `cat README` | **ok** 261.8 s |
| `echo abc \| wc` | **ok** 277.9 s |

Output was correct, not merely present: `teaching-xv6-hello`; a 24-entry directory listing; the complete
xv6 README; and `1 1 4` from the pipe — one line, one word, four bytes.

The record now states how the board was driven, which is what session 2 could not show:

```
# channel: exclusive
# console device: /dev/ttyUSB1
# host exit: 0
# stop: deliberate-stop-after-all-commands
# remote exit confirmed: yes
```

`host exit: 0` was **read back from the board's own record through the framed control path** — a nonce
assembled on the board, a bare integer, range-checked. It is not a number scraped from a console stream.
That distinction is the whole of the previous two tasks, and this is the first board run to exercise it.

## 4. ARM post-run health, and final state

| check | result |
| --- | --- |
| boot id | `ebeab8a6-…` — **unchanged**, so every artefact above is same-boot evidence |
| uptime | 1503 s, continuous |
| production lock | **released** — on a confirmed remote exit, as designed |
| fesvr processes | **0** |
| kernel errors (`oops\|panic\|segfault\|Unhandled\|BUG:`) | **0** |
| `/proc/meminfo` | readable |
| adapter status | `0x00050900` — epoch 9, ndrained 5, **`drain_timeout=0`**; `boot_ready`/`cpu_restart_safe` are 0, which is the post-run state, not the cold one |
| `fs-run.img` | `4c8f242a9734593f…`, **changed** from `4691ffea…` — xv6 wrote to its disk, so the block device was genuinely exercised |
| `fs-pristine.img` | `4691ffea…` — **unchanged**; the source image was never written |

## 5. Scope — what is and is not claimed

Claimed: one hardware session in which xv6 boots on the teaching CPU and runs the four commands with
correct results, with trustworthy termination evidence and a healthy ARM afterwards. The eight startup
gates passed as gates.

**Not claimed**: `usertests`, any performance result, or ISA-compliance. `ls` took 151 s, which is slow;
no performance claim is made and none was asked for. Nothing here says the CPU has no remaining defects.

## 6. Constraints honoured

No manual clearing of session 2's lock (it went with the power cycle), no warm retry, no hot or live PL
reprogramming, `PL_RECONFIG_SAFE` remained 0 throughout, no automatic recovery loop, no SD / device-tree /
PS / network configuration change, no RTL, no synthesis, no OS-simulation rerun. All previous evidence
preserved; everything new is in `xv6-board-run-3/`.

## 7. Evidence

`PRE-CYCLE-STATE.md`, `COLD-VERIFIED.md`, `evidence-1/`, and `logs/01-cold-verify.txt`
`02-preflight.txt` `03-deploy.log` `04-verify.txt` `05-program.txt` `06-selftest.txt` `07-m3probes.txt`
`08-extprobes.txt` `09-post-health.txt`, plus `run-1/` (`console.txt`, `stages.txt`, `phases.txt`,
`run.log`).

Board state now: powered, teaching bitstream in the PL, no host running, no lock held, ARM healthy. Leases
released. Nothing is pending on the board.

Handing to Codex for the final milestone decision.

OPEN claude-xv6-board-milestone-ready
