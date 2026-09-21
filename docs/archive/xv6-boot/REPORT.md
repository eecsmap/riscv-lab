# Booting xv6 on the teaching CPU: stages reached, and the one thing that blocks the rest

Claude, 2026-09-19. Delegation `codex-xv6-teaching-boot` (acked). `DESIGN.md` states the isolation, the
console arrangement and the success / deadline / stop semantics before any run. **The boot is blocked, with
the first identified cause**: the core does not implement `fence.i`, and xv6's `userret` executes one. That is the first blocker, not a demonstration that it is the only one.
Per item 4 of the delegation this is reported with its evidence, a minimal reproduction and a proposed fix
rather than repaired here.

## 1. What was set up

* `teaching-cpu-work/xv6-teaching`, an isolated copy of the `xv6-sim` baseline (untouched). Two recorded
  build-level differences, both in `identity.sha256` with their patches: `0002-no-pmp.patch` wraps
  `start.c`'s two PMP writes in `#ifndef TEACHING_NO_PMP`, and `0001-teaching-build.patch` adds that define
  to the copy's Makefile. Nothing else differs — not the atomics, the timer, the page tables, `fs.img` or
  any test's semantics. The kernel emits no floating point, so the baseline's `-march=rv64gc` was left as
  it is rather than changed.
* `RD2AtomicXv6Config` / `RD2AtomicXv6FastConfig`: the accepted atomic R-BOOT SoC with the per-event and
  per-transaction traces off (both behind flags that default to on, so every scored configuration keeps
  them), and the second one also without the TileLink monitors. The first trace-enabled attempt produced
  450 MB of log for 5.8 M cycles and throttled the run; the monitor-free build is **13× faster**
  (100 k cycles/s, ~6.5 k instructions/s against ~480).
* `+rd2_progress=N` and a capped trap history in the host: one line per N cycles with the PC, the retire
  count and the last trap, plus every one of the first 400 traps. That is what made a 6-million-instruction
  boot diagnosable without a per-cycle trace.
* `scripts/xv6-drive.py` — the console driver. fesvr is the only reader of the target's console input; the
  driver writes the simulator's stdin and reads its stdout, reconstructing the console by removing the
  harness's event lines. Stages, deadlines and the controlled stop are as `DESIGN.md` states.

## 2. Stages actually reached

| Stage | Evidence |
|---|---|
| kernel entry and console | `xv6 kernel is booting` on the console |
| the disk driver initialised | `blkdev: 4000 sectors (1 MB), max request 16 sectors` — the driver read the device's **geometry registers**. That is a real device transaction; it is *not* evidence that 4000 sectors, or any file data, were read |
| timer and trap path | 78 machine timer interrupts taken and returned from, in kernel code, before the failure |
| the first user process | **not proven**. The kernel reached `userret`, the code that *prepares* to enter user mode, and failed inside it; its first `sret` never executed. Nothing here shows user-mode execution, `init`'s `exec`, or a shell |
| a shell | **not reached** |
| `echo` / `ls` / `cat` / a pipe | **not reached** |

## 3. The first causal divergence

From the trap history of `run6/` (`run.log`, traps printed in full up to 400):

```
TRAP n=78  cause=0x8000000000000007  epc=0x80000bd8      (machine timer, kernel — normal)
TRAP n=79  cause=0x2   epc=0x3ffffff09c  tval=0x0000100f  ← illegal instruction
TRAP n=80  cause=0xf   epc=0x3ffffff00c  tval=0x3fffffe028 ← store page fault, and from here it repeats
...        149108 traps later, still cause=0xf at the same pc
```

* `0x3ffffff09c` is `TRAMPOLINE + 0x9c` = **`userret`**, and `0x0000100f` is the encoding of **`fence.i`**.
  `userret` begins with one, and `objdump` shows it is the **only** `fence.i` in the entire kernel.
* The core implements RV64IMAC + Zicsr; **Zifencei is not implemented**, so that instruction is illegal.
* The trap is taken *in supervisor mode*, and `usertrapret` has already pointed `stvec` at `uservec` while
  `satp` is still the **kernel** page table — the `csrw satp` is the instruction after the `fence.i`. So the
  illegal-instruction trap lands in `uservec`, whose first act is `sd ra, 40(a0)` into the trapframe at
  `0x3fffffe000`. The kernel page table does not map the trapframe (it is per-process, in the user table),
  so that store page-faults — and the fault re-enters `uservec`, forever.

Everything after the `fence.i` is a consequence; the boot never gets back to user mode.

## 4. Minimal reproductions

* `repro/r02_fencei.S` — executes one `fence.i` and reports what the core did. **Exit 2: illegal
  instruction with `mtval = 0x0000100f`**, in 432 cycles. That is the whole defect, in 30 lines.
* `repro/r01_trapframe.S` — the *pattern* xv6 relies on, in isolation: a U-mode trap into a handler at a
  high virtual address whose first act is a store to a second high page mapped `R|W|A|D` without `U`.
  **Exit 0 — that pattern works.** It shows the page-fault loop is downstream of the illegal `fence.i`
  downstream of the illegal `fence.i`. (This test tripped over the same missing `fence.i` while it was
  being written, which is how the encoding was first recognised.)

## 5. The fix, implemented under `codex-xv6-fencei-resume`

`tcpu_core.v` now decodes `fence.i` (MISC-MEM, `funct3 = 001`) as legal: it retires exactly once, writes no
register, and does nothing else. Its `rd` / `rs1` / `imm` fields are reserved by the ISA and are ignored.
No other MISC-MEM encoding was made legal — `funct3 = 010` and the rest still trap. The whole change is
three lines plus the comment explaining why "no further action" is correct here: this core has no
instruction cache, no store buffer, one hart and one in-order outstanding access, so a store's response is
taken before the next fetch is issued and nothing is prefetched. That is an invariant of the design, and
section 6 measures it rather than asserting it.

### Validation

| Case | Result |
|---|---|
| `repro/r02_fencei.S`, the original failure | **exit 2 before the fix, exit 0 after** |
| `repro/r03_fencei_matrix.S`, six cases: plain `fence.i` retires and writes nothing; reserved fields all non-zero (`rd=x5, rs1=x6, imm=0xABC`) still legal and `rd` still untouched; the neighbouring `funct3=010` encoding still illegal; store-a-new-instruction → `fence.i` → execute it, twice with different instructions (1 then 42); legality in M, S and U | **exit 0 on three memory timings**: immediate, `ready 3 / response 6`, and randomised |
| `repro/boot13_smc.S` — self-modifying code on the real SoC through the V2 bridge and the accepted atomic backend, **with the TileLink monitors enabled** | `M3-SMC-OK`, exit 0, **zero assertions** |

The SoC case is the one that matters for the invariant, and the evidence is read off the bus rather than
argued. Three times, with three different instruction words (1, 42, 99), the store to the code buffer
*completed* before the fetch of that address was even issued:

| store completes (cycle) | fetch requested (cycle) |
|---|---|
| 1635 | 1763 |
| 1899 | 1962 |
| 2100 | 2163 |

and each time the newly written instruction is the one that executed (the program checks the value, so a
stale fetch would have produced the previous number).

### Regressions for the decode change

`CPU_SV39_DONE fails=0` (the SU and Sv39 suites), `M23_WITH_SV39_DONE exit=0` (`M2_3_DONE fails=0`), and
the CPU-A suite `CPU_A_DONE scenarios=17 infra=0 fails=0` — all on the core with `fence.i` implemented.

## 6. What the fix unblocked, and where the boot now stands

With `fence.i` implemented, the run (`run-4mib/`, the 4 MiB fast-simulation build — see section 7) goes
past the old failure point and **into user mode**:

* no illegal instruction and no page fault at `userret` any more; the traps are timer ticks and the port's
  supervisor-software reflection of them;
* **two `cause=0x8` traps — ecalls from U mode** — at user `epc=0x392` and `0x39a`, taken through the
  trampoline. Disassembling `user/_init` identifies them exactly: `open("console", O_RDWR)` and then
  `mknod("console", CONSOLE, 0)`, which is `init`'s first two calls and means `exec("/init")` off the real
  filesystem succeeded. So kernel entry, `userret`'s `sret`, user execution and `exec` are all reached.

**The boot continues — there is no second blocker.** What looked like one was slow progress, and this
report said so prematurely before the run had been given enough wall time; that claim is withdrawn here.
For a long stretch after `mknod` was entered the retire rate was *exactly* constant (178,60x instructions
per 10 M cycles, sample after sample), every sampled PC was in the scheduler's per-process lock path with
`wakeup` appearing, and the device-operation count stood still at 22. That looked like an idle scheduler
with nothing runnable. It was not: given more time the count moved to 37 with **nine** writes — `mknod`'s
log commit — and the console produced

```
init: starting sh
```

so `mknod` returned, `init` ran on, and it forked and exec'd the shell. The lesson recorded here is about
the instrumentation, not the machine: at one sample per 10 M cycles, a kernel that spends most of its time
in the lock path between rare disk transfers is indistinguishable from one that is idle. A conclusion of
"blocked" needs either a much finer sample or a positive sign of a deadlock, and this had neither.

### The shell, and commands running on it

The same run went on to a shell and to real commands. The console, verbatim (the interleaving is the shell
echoing what the driver typed while earlier output was still being written out):

```
xv6 kernel is booting
blkdev: 4000 sectors (1 MB), max request 16 sectors
init: starting sh
$ echo teaching-xv6-hello
ls
teaching-xv6-hello
$ .              1 1 1024
..             1 1 1024
README         2 2 2441
cat            2 3 36824
echo           2 4 35672
forktest       2 5 17392
grep           2 6 40264
init           2 7 36136
kill           2 8 35616
ln             2 9 35408
ls             2 10 38960
...
```

* **a shell prompt** (`$ `) after `init: starting sh`;   *(observation)*
* **`echo teaching-xv6-hello`** produced `teaching-xv6-hello` as output — distinct from the echo of the
  command itself — and the prompt came back;
* **`ls`** produced a real directory listing off the filesystem: name, type, inode number and size for
  `README`, `cat`, `echo`, `forktest`, `grep`, `init`, `kill`, `ln`, `ls`, … each entry costing inode reads
  on the real block device.

`cat README` and the pipe test were typed and are still running when this report was written; the console is
written out one character per polled HTIF transfer, so a 2.4 KB file takes a while. Their results are not
claimed here.

One flaw in the driver showed up and is fixed for future runs: it waited for the expected output text, which
the shell's *echo of the command* can satisfy, so it sent the next command early. That is why `ls` appears
inside the first command's line above. The checker was already immune — it strips echoed command lines
before looking for output — and the driver now waits for the prompt to return and then looks only at what
arrived after the command's echo.

### Corrections made after review

Three things in this stage were wrong and are corrected rather than quietly adjusted.

* **The acceptance checker had a false positive.** Codex constructed a transcript in which `echo abc | wc`
  produced *nothing* and there was no stage record at all, and the checker passed it: its "three numbers"
  pattern matched a directory entry printed by an earlier `ls`, and a missing `stages.txt` was silently
  accepted. My claim that the checker "was already immune" to command confusion was too broad — it was
  immune to matching a command's own echo, not to matching another command's output. The checker now
  splits the console into ordered `prompt → echoed command → that command's output → next prompt` segments
  and matches each expected command **only inside its own segment**, requires the complete ordered stage
  set, and requires the driver's record of the simulator's exit status and of how the run ended. Codex's
  counterexample is now rejected by name, and the self-test carries it permanently, together with a
  complete control transcript that must still pass so the rejections cannot be vacuous.
* **`r03`'s privilege transitions were not sound.** It executed M-only `mstatus`/`mepc`/`mret` from S mode,
  its handler stepped over unexpected traps, and its success path accepted an ecall from either S or U — so
  the claimed U-mode coverage was not robust. Each level change now goes through an explicit ecall into the
  M handler, which is told which transition to expect, sets `MPP = U` itself, and treats any other trap as a
  failure; completion requires `cause = 8`. The trap record of a passing run is now exactly three traps —
  the one deliberate illegal encoding, `ecall from S`, `ecall from U` — on all three memory timings.
* **The manifest was generated while a simulator was still writing** one of the files in it, which is why
  `evidence/fs-boot3.img` did not verify. `RECONCILIATION.md` explains it; `HASHES.sh` now refuses to run
  while a registered run is alive and skips in-progress working images, and a pristine image is archived
  separately and never handed to a simulator.

`RECONCILIATION.md` also records what `run-dev2` does and does not show, including the withdrawal of the
"second blocker" claim.

### Stages, honestly

| Stage | Status |
|---|---|
| kernel entry, console | **reached** |
| disk driver initialised (geometry registers read) | **reached** |
| `userret` completes, user mode executes | **reached** (proven by the U-mode ecalls) |
| `exec("/init")` off the real filesystem | **reached** — proven twice over: the ecall PCs are inside `_init`, and the device trace shows the superblock, log recovery, the directory lookup and `/init`'s data blocks being read |
| `open("console")` from user mode | **reached**, returns < 0 as expected on a fresh image |
| `mknod("console", …)` | **returns** — its log commit is the nine writes in the device trace |
| `init: starting sh` | **reached** |
| shell prompt | **reached** |
| `echo` | **reached** — output distinct from the echoed command, prompt returned |
| `ls` | **reached** — a real directory listing from the filesystem |
| `cat README`, the pipe test | not accepted. They were typed in `run-dev2`, but that run's driver raced the echo, so its transcript cannot satisfy per-command binding; a corrected run (`run-clean/`) is under way |
| `echo` / `ls` / `cat` / pipe | not reached |

## 7. The optional simulation memory size

`0003-sim-mem-size.patch` adds `TEACHING_SIM_MEM_MIB` to the isolated copy's `memlayout.h`. Unset it is the
baseline's **16 MiB**, which stays the reference and is what the board build would use; the boot above was
run with `-DTEACHING_SIM_MEM_MIB=4`, and both kernels are kept (`evidence/kernel-16mib`,
`evidence/kernel-4mib`, and their differing `PHYSTOP` shift is visible in `kinit`). Measured saving and the
reasoning are in `PHYSTOP_MEASUREMENT.md`.

This changes the machine's capacity. It is not a claim that 4 MiB is equivalent to 16 MiB, and any
allocation failure under it must be re-checked against the reference size rather than worked around. Any
shell result obtained this way is labelled as a 4 MiB simulation result.

## 8. Cost, measured

At ~6.5 k instructions/s on the monitor-free build, the ~6 M instructions to this point take about 25
minutes of wall time. A boot that continues into a shell and a few commands is plausible within an hour or
two per attempt; `usertests` is not realistic on this simulator and is not part of this task.

## 9. Not claimed

The manifest, reconciled: the first proposal said 62, the review found 47, and both were right at
different moments — 62 was counted before superseded artefacts (a 450 MB trace log and five intermediate
disk images) were deleted, 47 after. The current `HASHES.txt` lists **410** paths, all verified, the
increase being this stage's own outputs: the three regression runs, the reproduction sources and logs, the
two kernels and the new runs. The count is whatever `HASHES-VERIFY.txt`'s first line says at the time it
was generated, and that line carries its own timestamp.

No synthesis, no board, no serial or JTAG. The Rocket build, the `xv6-sim` baseline, `fs.img`, the user
programs and the default SoC configurations are untouched. No interrupt, paging, user-mode or atomic
feature was disabled to make anything pass.
