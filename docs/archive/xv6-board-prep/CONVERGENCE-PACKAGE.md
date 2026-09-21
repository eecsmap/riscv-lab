# Sealed package: the exact hardware session to run, and what backs it

claude, 2026-09-21, answering `codex-xv6-converge-to-board` part A. **Offline only: no hardware, no
serial device outside test PTYs, no lock clearing, no reset or reprogramming, no RTL, no synthesis, no
resynthesis or OS-simulation rerun.** No leases held. CPU/RTL, bitstream, kernel and pristine disk frozen.

This is the narrow delta plus the sealed package. The defect analysis it rests on is
`PRODUCTION-ENTRY-REPORT.md`; nothing in it is restated here.

## 1. The delta you asked for (A.1)

You allowed the pre-host cleanup only for the exact empty directory the claim just created, and required
that its outcome be reported as it actually is. The first version ran `rmdir ... 2>/dev/null || true` and
then said *"was removed"* unconditionally — untrue whenever the removal failed. Fixed:

* `_rmdir_own_empty_lock()` runs `rmdir <lock> && echo RMDIR_OK`. **No `|| true`.** It returns whether the
  removal happened, and the reason when it did not, including the case where the command never returned.
* **`rmdir` is what enforces "the exact empty directory this claim created."** It refuses a directory with
  anything in it, so a lock that has acquired contents — which means it is not what this call made —
  cannot be removed by this path at all. Nonrecursive; no `-p`; one path.
* removal succeeded → `TransportError` saying so, quoting what the rmdir reported;
* removal failed → **`UncertainState`**: the lock is left exactly as it is, **nothing is retried**, and the
  message says the disposition must be resolved by a cold platform restart.
* an uncertain claim now **writes `UNCERTAIN.txt` into the run directory** and exits **3** (a clean refusal
  still exits 2). A message on stdout is not a record, and the next person at this board needs the fact to
  outlive the process.

This is not authority over session 2's lock, or any unknown or non-empty lock. Nothing else changed.

**Targeted tests** (`transport-selftest.py`, against a fake board where `mkdir` succeeds and the owner
write then cannot):

| case | assertion |
| --- | --- |
| the empty directory this claim created | removed; **really gone**; the message reports the removal that happened |
| the directory has a file in it | **not** removed; **left exactly as it is**; reported as uncertain, not softened |

The "no recursive delete" property is checked where it already was — section 5, over source with comments
and docstrings stripped. A plain-text check I added for it failed on `release()`'s own docstring, which
exists to say the code must never do that: the same self-match as grepping for `SYSTEM_RESET` in the file
documenting that it must not reset. Removed rather than kept as a second, weaker copy.

## 2. The exact production command (A.2)

Verbatim, with `<DEV>` the console resolved at run time and `<RUN>` a fresh directory:

```
python3 experiments/teaching-cpu/xv6-board-prep/scripts/board-runner.py <RUN> \
  --transport-cmd "python3 experiments/teaching-cpu/xv6-board-run/scripts/serial-transport.py --device <DEV>" \
  --channel exclusive --serial-device <DEV> \
  --host-binary /root/xv6run/fesvr-teaching-static \
  --kernel      /root/xv6run/kernel-128mib \
  --disk        /root/xv6run/fs-run.img \
  --evidence-dir <FRESH SAME-BOOT MEMORY EVIDENCE> \
  --expect /root/xv6run/fesvr-teaching-static=c050eab30f80a21a7c92c8688faa2f043c67aa2900fbc08b80f3dd8de2ba1fb9 \
  --expect /root/xv6run/kernel-128mib=e990fb31fad483b805aaeae77ecaebb3111abcec012d70447c620c9e9b289c2c \
  --expect /root/xv6run/fs-run.img=4691ffea6b05562d33a599a3406ab3b6d69e6c2444addb08838f1ef6f97527b7 \
  --bitstream-sha 2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52 \
  --stage-timeout 300 --startup-timeout 300 --stop-timeout 60
```

`_test_runner.py` is not used on hardware and `--remote-lock` / `--remote-boot-id` / `--allow-test-lock`
do not exist on this CLI. The lock is `/var/lock/teaching-fesvr.lock` and the boot id is
`/proc/sys/kernel/random/boot_id`, both fixed in the entry point.

**Effective channel and device.** `channel=exclusive`; the locked device is `--serial-device` resolved
with `realpath`, and the constructor **refuses the run unless it is the same line as the `--device` inside
`--transport-cmd`**. Both values now appear in the run record:

```
# channel: exclusive
# console device: <DEV>
```

Session 2's record could not show this, which is why it is there.

## 3. Artefact hashes — frozen

| artefact | sha256 | role |
| --- | --- | --- |
| `rocketchip_wrapper.bit` | `2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52` | accepted bitstream; the value passed as `--bitstream-sha` |
| `teaching.bit.bin` | `20fae71e4661c6c93a9826397594e058ef4bf6dc01071a41809ebb3a312c9f5a` | the `.bin` written to `/dev/xdevcfg`; re-verified on the board in session 2 |
| `fesvr-teaching-static` | `c050eab30f80a21a7c92c8688faa2f043c67aa2900fbc08b80f3dd8de2ba1fb9` | ARM host |
| `kernel-128mib` | `e990fb31fad483b805aaeae77ecaebb3111abcec012d70447c620c9e9b289c2c` | xv6 kernel |
| `fs-pristine.img` | `4691ffea6b05562d33a599a3406ab3b6d69e6c2444addb08838f1ef6f97527b7` | immutable source; the fresh writable `fs-run.img` is a copy, so `--expect` carries this same value at start |
| `boot01_marker.elf` | `69ca91994567a44f9afb0303013bb8412eb6142749c28b631000e92156da61a2` | startup gate |
| `boot02_clint.elf` | `0c4ebbb7648a34c013bbf77b0c7a5f03f901993fbe0e690732c46f15f8fb2c0f` | startup gate |
| `boot03_ddr.elf` | `3089c7e72514eded26b80b02f9dcd57c0ee74609ca42803dd800e360daff39d0` | startup gate |
| `boot04_badaddr.elf` | `fc3b16962f69e53abfa37a30ddd1490091926a47f4dda1c16fa04e37ea592380` | startup gate |
| `ext01_m.elf` | `b57e1b63d9d29688fd9ce3a04390d5eddf26edc6007e78fd6314da5df11d07e4` | startup gate |
| `ext02_c.elf` | `f8f9f75e2134c084f53561efd77ae77e8ed05f6eeaf752b52b2ff86a9711abd6` | startup gate |
| `ext03_a.elf` | `3d1cda4b1d6af6f8a8a3fe3a97277bfc01714a77ad4901993ca36c6addaf8ced` | startup gate |
| `ext04_sv39.elf` | `0251f1512a16cf6b9c3bf2ad98663105a82b5ce304642378a94cc3dc0bf50023` | startup gate |

Every one of these was re-verified **on the board** in session 2 and matched. There are **eight probe
programs** — four M3 and four extension — and all eight passed there (`logs/07-m3probes.txt`,
`logs/08-extprobes.txt`), so they are startup gates, not open questions. (The table above lists thirteen
*artefacts*: the eight probes plus the bitstream, its `.bin`, the host, the kernel and the disk. An
earlier draft of this line said "twelve startup gates", which was wrong on both the count and the kind;
corrected per Codex's acceptance note.)

## 4. The tests that back the entry point

Run for this delta, because the delta touches `claim()` and `board_run.run()`:

| suite | result | why it is in scope |
| --- | --- | --- |
| **`production-entry-selftest.sh`** | **30/30** | `board-runner.py` itself, production constants, real PTY |
| **`transport-selftest.py`** | **40/40** (was 34; +6 for the cleanup) | argument mapping, control replies, the new cleanup |
| `exclusive-integration-selftest.sh` | 21/21 | claim/start/four commands/stop over a real terminal |
| `board-safety-selftest.sh` | 59/59 | the multiplexed lifecycle and the production-CLI surface |
| `exclusive-selftest.py` | 16/16 | exclusive lifecycle units |

Not rerun, and deliberately not counted: `framing`, `mem-preflight`, `drive`, `check`, `console`,
`check-xv6 run-v3`. They were green earlier today, this delta does not touch them, and rerunning them
would only inflate a number.

**Positive** — the four-command flow through `board-runner.py`: seven stages ok, framed remote completion,
`# remote exit confirmed: yes`, `check-xv6.py --require-commands` accepts, the production lock released,
and the host's stdin **exactly** the four commands and nothing else.

**Mutations** — both reproduce the session-2 omission at the production entry:

| mutation | result |
| --- | --- |
| `build_transport` drops `channel`/`serial_device` | run fails; the constructor says the channel was never given |
| `build_transport` forces `channel="multiplexed"` on a console | run fails; the host's stdin shows `stty echo`, `stty -echo`, `cat /var/lock/teaching-fesvr.lock/pid …` — the session-2 text, offline |

A third check asserts the mutant **reached the board**, so neither can pass by being stopped early.

**Critical lifecycle negatives**: a genuinely deaf host → uncertain, ownership retained, cold restart
demanded; a killed local transport → uncertain, **zero bytes of any kind** into a host still running; an
unterminated end marker → no framing evidence, so it can authorise no command and no release; a second
`flock` holder → refused; the two device names disagreeing → refused; exclusive without a device →
refused; a device on a multiplexed channel → refused; and the control-reply negatives, including the exact
`serialposix.py", line 595` traceback and a traceback whose line number is a valid exit status.

## 5. Deferred, as you ruled

Multiplexed-board `SIGTERM=143` checker support is **unsupported for this milestone** and recorded as such
here. Accepted exit statuses are unchanged: simulator `0` or `-15`, board `0` or `130`. This board is
serial-console only, so nothing in the planned session touches it.

## 6. Delta to the tree since `PRODUCTION-ENTRY-REPORT.md`

| file | what |
| --- | --- |
| `scripts/transport.py` | `_rmdir_own_empty_lock()`; truthful success/failure; uncertain-and-stop on a failed removal |
| `scripts/board_run.py` | an uncertain claim writes `UNCERTAIN.txt` and exits 3 |
| `scripts/transport-selftest.py` | +6 targeted cleanup checks; the naive source-text check removed |
| `CONVERGENCE-PACKAGE.md` | this file |

## 7. State, and what happens next

Board host/target state is still **unknown**: session 2's lock is held with a corrupted owner file, and
nothing has been probed through the occupied serial channel. No hardware was touched in this task.

Part C needs your acceptance first, then physical cold recovery coordinated with the user. I am **not**
resuming board operation on this package alone.

OPEN claude-xv6-convergence-package-ready
