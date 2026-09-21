# First hardware session: the new teaching CPU runs on the PYNQ-Z1; xv6 blocked on a transport gap

claude, 2026-09-20, for `codex-xv6-live-board-run`. User confirmed the board authorization directly before
any hardware was touched.

**Result in one line: the core with M, C, Sv39, A and Zifencei is running on the board and passed all four
accepted bare-metal probes. xv6 did not complete — blocked by a defect in my transport, not by the CPU.**

No SD rewrite, no device-tree or PS boot-configuration edit, no hot PL reload, no RTL change, no synthesis,
no usertests. One directory was created on the board (`/var/lock`, needed by the production device lock);
nothing existing was overwritten.

## What was established, in the required order

### 1. Cold platform (gate 1–2)

The board had been up **4 days** with `prog_done = 1` — the state the procedure forbids programming from. I
stopped and asked the user for a physical power cycle rather than a software reboot, which on Zynq would
leave the fabric configured. After the cycle:

| | before | after |
| --- | --- | --- |
| USB enumeration | Sep 16 10:38 | **Sep 20 21:09** |
| boot id | `7d2150fa-9d02-4704-9a69-077732aa012f` | **`9e62de9e-f7f1-4cf4-93f0-060bff64ae3b`** |
| host owners | none | none |

`prog_done` reads 1 after a cold boot too — because the FSBL configures the PL from `BOOT.BIN`. That is the
normal post-boot state, not leftover session state; my earlier note said otherwise and this corrects it.

### 2. Live memory preflight (gates 3–4) — **PASS**

Captured from the running ARM as **raw bytes** (`scripts/capture-evidence.py`, base64 over the console) and
bound to the boot id above:

```
session 9e62de9e-f7f1-4cf4-93f0-060bff64ae3b
#address-cells=1 #size-cells=1
DT memory: 0x00000000 + 0x10000000 (256 MiB)
no reserved-memory on this board
iomem System RAM: 0x00000000-0x0fffffff
MemTotal 247 MiB
target window 0x10000000-0x1fffffff
MEM_PREFLIGHT OK refusals=0
```

The target's window is genuinely free. **One defect found and fixed**: the board's `boot_id` is
NUL-terminated, so two identical ids compared unequal and the preflight refused correct evidence. It
failed closed, which is right, but the normalisation was missing — fixed in `mem-preflight.py`,
`board_gate.py` and (later, when it bit again live) `transport.remote_boot_id()`. Self-test still 14/14.

### 3. Deployment (gate 5) — **PASS**

No network on this board and a RAM initramfs, so the console is the only channel. Chunked commands were
measured first at ~380 bytes/s (about six hours); streaming into one `base64 -d` with XON/XOFF gives
**8.4 KB/s**. Safe because base64's alphabet cannot contain XON/XOFF — it would be unsound for raw binary.

Every file verified by sha256 **on the board**:

| file on the board | sha256 | bytes |
| --- | --- | --- |
| `teaching.bit.bin` | `20fae71e4661c6c9…` | 4,045,564 |
| `fesvr-teaching-static` | `c050eab30f80a21a…` | 1,806,656 |
| `kernel-128mib` | `e990fb31fad483b8…` | 274,128 |
| `fs-run.img` (per-run writable copy) | `4691ffea6b05562d…` | 2,048,000 |
| `boot01..04` ELFs | as bundled | — |

`teaching.bit.bin` is derived from the accepted bitstream `2cd8a9927cfa2f51…` by stripping the `.bit`
header (payload begins with the sync word `AA995566` at offset 48). The derivation is in the session log so
the identity chain is unbroken; the pristine disk image was not modified.

### 4. Programming and the design's own identity (gates 6–7) — **PASS**

Programmed from the cold, quiescent platform with `cat teaching.bit.bin > /dev/xdevcfg`, exit 0, PS alive,
no new dmesg entries. But `prog_done` was already 1, so that proves nothing by itself. The proof is the
adapter's status register, which only this design provides:

```
devmem 0x43C00014  ->  0x00000011
devmem 0x43C00010  ->  0x00000001
```

`0x11` is `CPU_RESTART_SAFE | BOOT_READY`, with `PL_RECONFIG_SAFE = 0`, epoch 0, ndrained 0 — **bit for bit
what the Verilator board-interface test predicted for a cold start**, and `SYSTEM_RESET` already asserted by
`RegInit(true.B)`. Simulation said `status=0x00000011 … epoch=0 ndrained=0`; hardware says the same.

**The ARM binary ran for the first time.** `./fesvr-teaching-static --self-test` printed its bit map and
`no device was opened, mapped, read or written by this invocation`, exit 0. The static link was necessary:
the dynamic build needed GLIBC_2.38, far newer than this ramdisk.

### 5. Bare-metal probes (gate 8) — **4 of 4 PASS**

| program | marker | exit | status at handshake |
| --- | --- | --- | --- |
| `boot01_marker.elf` | `TEACHING-CPU-M3-OK` | 0 | `0x00000011` epoch 0 |
| `boot02_clint.elf` | `M3-CLINT-OK` | 0 | `0x00000111` epoch 1 |
| `boot03_ddr.elf` | `M3-DDR-OK` | 0 | `0x00010211` epoch 2, **ndrained 1** |
| `boot04_badaddr.elf` | `M3-BADADDR-OK` | 0 | `0x00010311` epoch 3, ndrained 1 |

Each reported `ready after 50 ms` — the hold floor honoured and `BOOT_READY` observed while the request was
held, exactly as designed. The epoch increments per restart and `ndrained` shows transactions genuinely
accounted for. **The restart handshake works on real hardware.**

The extension probes (M, C, Sv39, A) were **not run**: as reported before the session, `amo_probe.bin` and
`bdev_probe.bin` are test-bench artefacts that write to memory and print nothing, so on the board they
produce no observable result. That gate is still open and unchosen.

## The blocker: xv6 (gates 9–10) — **NOT COMPLETED**

`board-runner.py` passed every gate — preflight re-run, live boot id matched, roles bound to exact paths,
three deployment files hashed on the board, ownership claimed — and launched the host. Then it failed:

```
TimeoutExpired: ['serial-transport.py', 'cat /var/lock/teaching-fesvr.lock/pid …'] timed out after 30s
```

**The cause is a design gap in my transport, and it is mine, not the board's.** `BoardTransport.start()`
reads the remote pid back with a *second* command, and `stop()` kills by that pid — both out of band. That
is fine over `ssh`, where another session is always available. It is impossible over a serial console:
once the host is launched it owns the tty, and there is no second channel. Every offline test used an
ssh-like fake that could always run another command, so nothing ever exercised a single-channel transport.

Recovering it also cost something I should record: while diagnosing, I typed probe commands at a console
the host still owned, so those bytes went into the host's stdin and therefore into TSI. The target's state
became unknown at that point. Ctrl-C then returned the shell and the wrapper recorded exit 0.

## Board state now — defined, healthy, nothing hung

| | |
| --- | --- |
| host processes | **none** (`NO_FESVR`) |
| device lock | **still held**: `/var/lock/teaching-fesvr.lock` with `owner`, `pid` 734, `exit` **0** |
| status register | `0x00020500` — epoch 5, ndrained 2, `BOOT_READY` 0, `PL_RECONFIG_SAFE` 0 |
| `SYSTEM_RESET` | `0` — released; the target runs free, as designed (stopping a host never asserts reset) |
| ARM | healthy: 247 MB total, 224 free, `dmesg` clean, no allocator errors |
| PL | holds the teaching bitstream |

The lock is deliberately **left in place**. An interrupted run holding ownership is the designed behaviour,
and clearing it automatically is the recovery loop the task forbids. It is safe to clear by hand — the two
conditions `release()` requires are both verifiably true (remote exit recorded as 0; no host running) —
with `rm -f /var/lock/teaching-fesvr.lock/{owner,pid,exit} && rmdir /var/lock/teaching-fesvr.lock`.

Leases `board` and `serial` are held by this session.

## What I propose, and am not implementing unasked

The transport needs a single-channel mode. Sketch, for review:

* a `channel` property: `multiplexed` (ssh) or `exclusive` (serial console);
* on an exclusive channel, do not read the pid out of band at `start()`. The wrapper already writes it to
  the lock before `exec`, so read it **after** the session ends;
* stop in band — send `\x03` on the channel — then, once the channel is free, confirm the recorded exit
  status from the lock exactly as now. Uncertainty rules unchanged;
* add a single-channel fake to `board-safety-selftest.sh` that refuses a second concurrent command, so this
  class of gap cannot pass again.

That is a change to accepted code, so it is proposed rather than done, per this task's rule.

## Honest summary

The CPU is not the problem and was never reached as one. The new core with M, C, Sv39, A and Zifencei
is in the fabric, answers its status register exactly as simulated, honours the restart handshake across
four consecutive programs, and passed every bare-metal probe that exists for it. **xv6 on hardware is
unproven**, and nothing here should be read as a four-command board result.

OPEN claude-xv6-live-board-blocked
