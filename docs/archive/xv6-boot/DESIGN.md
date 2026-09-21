# Booting xv6 on the teaching CPU: design and how it is judged

Delegation `codex-xv6-teaching-boot` (acked 2026-09-19). The goal is to boot the *existing* port of xv6 on
the current teaching core (RV64IMAC + S/U + Sv39, multi-cycle, one physical port, no cache) with the
accepted atomic backend and the existing SoC devices, and to show each stage separately: kernel entry, the
first user process, a real shell, and a few user programs. It is not a re-port and it does not change the
CPU.

## 1. What is isolated, and what exactly differs from the baseline

`teaching-cpu-work/xv6-sim` is the baseline and is not touched. `teaching-cpu-work/xv6-teaching` is a copy.
Two recorded differences, both build-level:

* `0002-no-pmp.patch` — `kernel/start.c`: the two PMP writes are wrapped in `#ifndef TEACHING_NO_PMP`. The
  teaching core implements no PMP at all (zero entries), where the privileged spec already gives S and U
  full access to physical memory, so removing the writes removes no permission; keeping them would be two
  illegal instructions. This is the only source change, and it is the one the contract (`cpu-atomic-prep/
  CONTRACT.md` §4) anticipated.
* `0001-teaching-build.patch` — `Makefile`: `CFLAGS += -DTEACHING_NO_PMP`, so the teaching build selects it.

Nothing else is changed: not the atomics, the timer, the page tables, `fs.img`, the user programs or any
test's semantics. The baseline's own simulation tuning (`PHYSTOP` = 16 MiB, `kfree` skipping its poison
memset while `kinit` builds the free list) is inherited as it stands, not re-tuned.

`identity.sha256` records both trees' `start.c`, `Makefile`, `kernel/kernel` and `fs.img`, the two patches,
and the simulator binary.

## 2. The machine it runs on

`RD2AtomicXv6Config`: the R-BOOT SoC with the V2 bridge, the accepted `AtomicBackend` at the coherence
manager, TSI/HTIF, the BlockDevice and the real CLINT — the same configuration the CPU-A stage accepted,
with two differences that change no behaviour:

* the per-event trace and the atomic backend's per-transaction trace are off. An OS boot runs for tens of
  millions of cycles; at roughly 80 bytes of log per cycle a trace is unusable (the first attempt produced
  450 MB for 5.8 M cycles and throttled the run). Both traces are behind a plain Scala flag that defaults
  to on, so every scored configuration keeps them.
* `+rd2_progress=N` makes the host print one line per N cycles with the CPU's PC and the number of retired
  instructions, so a long run stays diagnosable at a few dozen bytes per million cycles.

## 3. The console, and why there is only one reader

The port's console is HTIF: `kernel/htif.c` writes characters through `tohost` and polls `fromhost` for
input. On the host side that is fesvr, which already owns both. The driver (`scripts/xv6-drive.py`) never
reads the target's console input — it writes to the simulator's **stdin**, which fesvr is the only consumer
of, and reads the simulator's **stdout**, which carries the target's console characters interleaved with
the harness's own event lines. The console is what is left when the event lines are removed. So there is
exactly one reader of console input and no split stream.

## 4. Success, deadline, and how the run ends

* A **stage** passes when its evidence appears on the reconstructed console. For a command, the evidence is
  output *beyond the echo of the command itself* and a return to the prompt — matching the command text
  alone proves nothing.
* The **deadline** is a wall-clock timeout per stage. Hitting it fails that stage and the run records how
  far it got, with the first anomalous PC / cause / tval if one was seen.
* Reaching the end of the script is **not** a timeout. A shell is a system that keeps running; the driver
  stops it deliberately and records a *controlled stop* together with the stages completed and the
  simulator's real exit status. The two are never conflated.

## 5. Stages recorded

1. `xv6 kernel is booting` — kernel entry and console output.
2. `init: starting sh` or the first prompt — the first user process, which means `exec` off the real disk.
3. A real shell prompt.
4. `echo`, `ls`, `cat`, and a pipe (`echo abc | wc`) — each checked by its own output and by returning to
   the prompt.

A self-test asserts that the checker rejects a run whose key evidence is missing, so a pass cannot be
produced by a driver that simply never looked.
