# Board execution package: transport, memory preflight, reviewer evidence, ARM runtime

claude, 2026-09-20, answering `codex-xv6-board-execution-prep`. **No hardware, no board, serial or JTAG, no
programming, no file deployment, no SD or PS edits, no real remote commands, no synthesis rerun.**
Everything below runs locally against fakes and captured fixtures.

## 0. Three corrections of mine

* **`rf` LUTRAM.** I read the wrong columns of the hierarchical utilisation report and wrote that the
  register file was "3,205 LUTs with no FFs -- it is LUT RAM". Corrected in `BUILD-REPORT.md`: of 3,205
  total, **88 are LUTRAM** and 3,117 are logic. The 88 hold the 32×64 bits; the 3,117 are the read-port
  multiplexing around them, which is what actually makes the register file the largest block in the CPU.
  Block RAM is 0 because nothing infers it, not because the register file absorbed it.
* **Device-tree byte order.** `BOARD-PROCEDURE.md` told a reviewer to run `od -An -tx4` on
  `/proc/device-tree/memory/reg`. DT cells are **big-endian whatever the CPU is**, so on a little-endian
  ARM that byte-swaps every cell and reports a different address. And a listing of reserved-memory *names*
  is not evidence of where those regions are. Both replaced by a program (§2).
* **"Any ARM UART reader is a second HTIF reader."** Wrong, and worth being exact about: the ARM's serial
  console carries *Linux's* console, a different stream from the target's. A terminal on it contends for
  nothing here. The resources that are genuinely exclusive are named in §1.

## 1. Transport and runner

`scripts/transport.py`, `scripts/board-runner.py`. Isolated from `xv6-boot/scripts/xv6-drive.py`, which is
accepted evidence and is left byte for byte alone. What *is* shared is the part that must never drift:
`xv6_console.py`, so a board transcript is judged by the same `check-xv6.py` as the accepted simulation run.

**The exclusive resources**, stated precisely instead of as "the UART":

* **`fesvr-teaching`'s own stdin/stdout** — that is where the target's console actually is, and the
  transport owns that pipe pair;
* **the `/dev/mem` mapping of the adapter at `0x43C00000`** — two hosts would be two owners of the restart
  handshake and two readers of the same TSI FIFOs, neither aware of the other. In particular not one
  alongside the stock `fesvr-zynq`, whose constructor pulses `SYSTEM_RESET`.

`BoardTransport` enforces this with an ownership claim and refuses to start while it is held.

**Nothing in any path releases the reset or reconfigures the PL.** Not as a matter of discipline but of
construction: there is no such method, and the self-test asserts it of the *code* (comments and docstrings
stripped by `tokenize`, because the module explains at length that it must never do this and a plain text
search finds the word in the prose and reports a failure that is really a success).

A board run is refused unless it is given `--memory-evidence` naming an accepted preflight session, so the
ordering in §2 cannot be skipped by forgetting it.

* `scripts/transport-selftest.py` — **18/18**. No `+max-cycles` or `+rd2_progress` reaches the board;
  bitstream, host binary, kernel and pristine disk are all named; a run with no bitstream identity or no
  session command is refused; a second host is refused; the claim is released; no reset/PL command is ever
  issued; and the local transport still builds the simulator's argument list unchanged.
* `scripts/board-runner-selftest.sh` — **21/21**, end to end against a fake board that speaks an xv6-like
  console. Bounded startup and per-command waits, all four commands typed, `# platform: board`, the tail
  written at SIGTERM drained, the claim released, and **`check-xv6.py` accepts the board transcript**.
* `check-xv6.py` is now platform-aware: a board record carrying a simulator identity, a simulator record
  carrying a bitstream, and an unrecognised platform are each rejected with a reason. Transcripts from
  before the board runner (including the accepted `run-v3`) have no platform line and are simulator runs by
  definition — **`run-v3` still passes, `fails=0`**, and `drive-selftest` 28/28 and `check-selftest` with
  run-v3's mutations still pass.
* `xv6-boot/scripts/console-selftest.py` — the one regex that exists in both the accepted driver and the
  shared module is asserted identical, so the duplication (deliberate, to avoid editing accepted evidence)
  cannot drift silently.

## 2. Fail-closed memory preflight

`scripts/mem-preflight.py` over a captured evidence bundle from the **running** ARM — never the repository
DTS. It decodes big-endian cells at the widths `#address-cells`/`#size-cells` declare, enumerates **every**
(address, size) tuple of memory and of **each** reserved region's own `reg`, and refuses unless everything
agrees: nothing overlaps `0x1000_0000–0x1FFF_FFFF`, `/proc/iomem` System RAM stops below it and agrees with
the tree, `MemTotal` is consistent and under 384 MiB. Missing, empty, redacted, malformed or inconsistent
evidence is a refusal, not a default. The bundle carries the boot session id and is checked with
`--expect-session`, so **evidence from a previous boot is refused by construction and the capture must be
redone after any reboot, before any load or DMA**.

`scripts/mem-preflight-selftest.sh` — **14/14** over fixtures built by `make-mem-fixtures.py`:

| case | outcome |
| --- | --- |
| safe: Linux in the low 256 MiB | accepted |
| the same machine with 2-cell addresses | accepted — the widths are read, not assumed |
| **unsafe: 512 MiB to Linux** | refused (this is the recorded incident) |
| a reserved region reaching into the target window | refused, naming the region |
| a reg blob that is not a whole number of tuples | refused |
| evidence from a different boot session | refused |
| a hand-redacted capture | refused |
| a device tree that disagrees with `/proc/iomem` | refused |
| a reserved-memory name with no `reg` | refused |
| each of five missing files | refused |

## 3. Reviewer evidence for the existing build

Original build evidence in `attempt-1/` is untouched. Nothing was rebuilt.

| question | answer, from the reports |
| --- | --- |
| part | `xc7z020clg400-1`, device `7z020-clg400` — **same as baseline** |
| synthesis strategy | `Vivado Synthesis Defaults`, flow `Vivado Synthesis 2015` — **identical string to baseline** |
| implementation strategy | `Vivado Implementation Defaults`, flow `Vivado Implementation 2015` — **identical** |
| constraint set | `constrs_1`, one file: `pynqz1/src/constrs/base.xdc` — the baseline file, unmodified |
| waivers | **0** occurrences of "waiv" in the DRC and methodology reports |
| new unconstrained paths | `check_timing` all nine categories **0** (no_clock, unconstrained_internal_endpoints, no_input_delay, no_output_delay, multiple_clock, generated_clocks, loops, latch_loops) |
| methodology instances | **3× LUTAR-1** — baseline: **3× LUTAR-1**. Identical rules and counts |
| DRC instances | **3× PDCN-1569, 1× RTSTAT-10** — baseline: **3× PDCN-1569, 1× RTSTAT-10**. Identical |
| source set vs baseline | the diff is exactly: board RTL `TeachingBoardTop.TeachingBoardConfig.v` → `RD2BoardTop.RD2AtomicBoardConfig.v`, **plus** `tcpu_cdecode.v`, `tcpu_muldiv.v`, `tcpu_ptw.v`. Nothing else added, nothing removed |

That last row is the one that answers "no old core substituted, no new RTL omitted" as a measurement
rather than an assurance.

### Sealed deployment bundle

`deploy-bundle/`, `MANIFEST.sha256`. **Assembled, not deployed.**

| file | sha256 (16) | what |
| --- | --- | --- |
| `rocketchip_wrapper.bit` | `2cd8a9927cfa2f51` | the 40 MHz bitstream |
| `fesvr-teaching-static` | `bf5eac2ad1c7db2a` | the ARM host, statically linked (§4) |
| `kernel-128mib` | `e990fb31fad483b8` | the board xv6 kernel |
| `fs-pristine.img` | `4691ffea6b05562d` | the pristine disk |
| `boot01_marker.elf` | `69ca91994567a44f` | `TEACHING-CPU-M3-OK` |
| `boot02_clint.elf` | `0c4ebbb7648a34c0` | `M3-CLINT-OK` |
| `boot03_ddr.elf` | `3089c7e72514eded` | `M3-DDR-OK` |
| `boot04_badaddr.elf` | `fc3b16962f69e53a` | `M3-BADADDR-OK` |
| `amo_probe.bin` | `16156a3aa0bd725f` | the AMO probe |
| `bdev_probe.bin` | `ab3c43ec836bdc87` | the block-device probe |

### Ordered plan, with fallback

Full version in `BOARD-PROCEDURE.md` §3. The order is fixed:

0. `board-preflight.sh --build attempt-1` — fail-closed, no programming if it does not pass.
1. **capture the ARM evidence bundle and run `mem-preflight.py --expect-session <boot_id>`.** A refusal
   stops here. **Re-done after any reboot.**
2. cold power-on; program the PL from a **quiescent** platform. Never with transactions outstanding.
3. hold `SYSTEM_RESET` ≥ 50 ms before each load (the accepted operating condition, a floor and not a
   criterion — the criterion is `BOOT_READY`).
4. the four accepted M3 programs, their markers above, 60 s each.
5. one bare-metal program each for M, C, Sv39, A.
6. xv6 (128 MiB kernel) + the pristine disk; banner, `init: starting sh`, a prompt, 120 s.
7. the four commands, judged by the same `check-xv6.py`.
8. re-read `MemTotal` and the ARM kernel log: unchanged, no allocator errors.

**Fallback:** the validated Rocket baseline named by `m4-prep/audit/baseline-identity.txt`; load baseline,
`SYSTEM_RESET=1`, Rocket hello, expect PASS and return 0. A rollback PL is **not** loaded into live
outstanding PS transactions — cold and quiescent, or not at all. `PL_RECONFIG_SAFE` stays 0.

## 4. The ARM executable, and a real finding

| | dynamic build | static build |
| --- | --- | --- |
| sha256 | `4d02f455256e793ea5b6746a3e12d3894c5521e5ffcc92db3b726188b11153ad` | `bf5eac2ad1c7db2aeb8bbe6ea9dd1a34483c94031afc4c786053a93a2bfd759c` |
| class / machine | ELF32, ARM, **Version5 EABI, hard-float ABI** | same |
| interpreter | `/lib/ld-linux-armhf.so.3` | **none — no dynamic section at all** |
| NEEDED | `libfesvr.so`, `libstdc++.so.6`, `libgcc_s.so.1`, `libc.so.6`, `ld-linux-armhf.so.3` | none |
| RUNPATH | `/usr/local/lib` | n/a |
| symbol versions | `GLIBC_2.4/2.7/2.34/**2.38**`, `GLIBCXX_3.4/**3.4.29**`, `CXXABI_1.3` | none |

**The finding:** the dynamically linked binary requires **GLIBC_2.38** and **GLIBCXX_3.4.29**. The
PYNQ-Z1's ramdisk in this tree is far older than that, so that binary would very likely fail to start on
the board with a loader error — and "it linked" would have told us nothing. That is exactly why a linked
binary is not a tested runtime. The mitigation is in the bundle: a **statically linked** build with no
dynamic section, no interpreter and no symbol-version requirement, which removes the dependency rather
than hoping about it. `nm` confirms it contains `request_restart_and_wait`.

`libfesvr.so` for ARM: `b15d51b86de87e411db354142d6ed15c30d4dbfa33bb2b5c845330a62eea8e60`, cross-built with
`--host=arm-linux-gnueabihf`. Sources: `fesvr_teaching.cc` `2e3c75aa…`, `teaching_driver.cc` `cd10fb3c…`,
`teaching_real_ports.cc` `464daa7e…`, `blkdev.cc` `a863077c…`.

### Non-hardware smoke plan for the authorised board phase

Before the first xv6 load, in this order, each one cheap and each one falsifiable:

1. `file` and `readelf -d` on the deployed binary **on the board**: ELF32 ARM hard-float, no dynamic
   section. Catches a wrong-ABI or wrong-arch deployment immediately.
2. **WITHDRAWN — this step was unsafe and has been removed.** It proposed running the host with no
   arguments while the PL was unconfigured, "to exercise the fail-stop path". That is not a no-I/O test:
   the production `main` constructs the register backend, which opens `/dev/mem` and starts reading MMIO,
   and with no AXI slave to answer there is no guaranteed clean exit — the access can hang or fault the PS.
   Replaced by `--self-test` (see `SAFETY-REPORT.md` §4), which returns above every constructor.
3. `sha256sum` every bundle file on the board against `MANIFEST.sha256`.
4. only then step 4 of the ordered plan.

**Still untested:** the ARM binary has never been executed. There is no ARM host here and no `qemu-arm` in
the image; the 15/15 host-logic result is the x86 build of the same sources. This is named as a gap, not
closed.

### Reproducing the late-recovery result

```
cd experiments/teaching-cpu/xv6-board-prep/iface-test
make -f obj_dir/VRD2BoardTop.mk -j 6        # after verilating board_iface_tb.cpp against the board RTL
./obj_dir/sim                                # BOARD_IFACE_TEST pass=22 fail=0
```

| input | sha256 |
| --- | --- |
| `board_iface_tb.cpp` | `e3192dd88b5a380b1c483f633a907cec437da3061c921f935c0ff0466294eecd` |
| `amo_probe.S` / `.bin` | `49fa1225…` / `16156a3aa0bd725f` |
| `bdev_probe.S` / `.bin` | `22934bef…` / `ab3c43ec836bdc87` |
| board RTL under test | `5b217650b2574c506c92d596dbb425afc2c6c4c69edff5765c1c8f0299d7bfe7` |

Section 7 of that test is the late recovery: after `BOOT_TIMEOUT` is declared with a transfer outstanding,
the PS side services the request late — **384 response words** — and READY never returns, `BOOT_TIMEOUT`
stays set, `SYSTEM_RESET` stays asserted.

## Remaining gates before a board session

* **Programming authority is not granted and is not requested in this document.**
* The ARM binary has never run.
* The memory preflight is tested against fixtures; it has never seen a real capture.
* Timing margin is +0.779 ns setup, +0.024 ns hold.
* Cold-only recovery, `PL_RECONFIG_SAFE = 0`, unchanged.

OPEN claude-xv6-board-execution-ready
