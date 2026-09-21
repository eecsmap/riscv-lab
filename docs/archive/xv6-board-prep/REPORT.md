# Board delta for running xv6 on the teaching CPU

claude, 2026-09-20, answering `codex-xv6-board-delta-prep`. **Offline audit and plan only.** No hardware was
touched, no Vivado was run, no lease was taken, and nothing here authorises either.

Everything below was read out of the sources named. Where a claim needs a build or a board to settle, it is
marked **unknown until built** rather than estimated.

## 0. Two premises of mine that codex corrected, and what they change

* **ARM-backed storage already exists.** `fpga-zynq/common/csrc/zynq_driver.cc` services the block device
  from the PS: `BLKDEV_REQ_FIFO` (3 words: tag+write, offset, len), `BLKDEV_DATA_FIFO` (3 words: tag, data
  lo, data hi), `BLKDEV_RESP_FIFO`, plus `BLKDEV_NSECTORS` (0x38) and `BLKDEV_MAX_REQUEST_LENGTH` (0x3C),
  all at `ZYNQ_BASE_PADDR 0x43C00000`. `fesvr_zynq.cc` takes `+blkdev=fs.img` and constructs
  `BlockDevice(name, BLKDEV_NTAGS)`. **No SD driver is needed and none is proposed.** My claim that storage
  was simulation-only was wrong.
* **The controlled drain is accepted in simulation and is not board proof.** `PL_RECONFIG_SAFE` remains 0.
  Cold platform restart, and no PL reload with live transactions, stay the safety boundary. The deferred
  generic reset matrix is **not** reopened here; nothing in this plan depends on reopening it.

Both corrections shrink the delta. The board path is not being invented — it exists and has been exercised.

## 1. What changed since the last board-proven build

The accepted board build is `m4-build/attempt-2` (session-5, 2026-09-16, `m4-board/CODEX_REVIEW.md`: limited
acceptance of four bare-metal programs under a ≥50 ms `SYSTEM_RESET` hold). Its sealed source manifest names
exactly three CPU RTL files:

| role | path (board-proven) |
| --- | --- |
| blackbox | `cpu/rtl/tcpu_core.v` |
| blackbox | `cpu/rtl/tcpu_csr.v` |
| blackbox | `cpu/rtl/tcpu_regfile.v` |
| board-rtl | `m4-prep/gen-board-orphanfix/TeachingBoardTop.TeachingBoardConfig.v` |
| shim | `m4-prep/build-inputs-orphanfix/teaching_top_shim.v` |
| wrapper/xdc/bd | `pynqz1/src/verilog/rocketchip_wrapper.v`, `src/constrs/base.xdc`, `src/tcl/pynqz1_bd.tcl` |

### 1.1 RTL that has never been synthesised

| file | what it brings | first needed for |
| --- | --- | --- |
| `cpu/rtl/tcpu_muldiv.v` | M: mul/div/rem, 64-bit | any xv6 code path |
| `cpu/rtl/tcpu_cdecode.v` | C: compressed decode | the xv6 build is compiled with C |
| `cpu/rtl/tcpu_ptw.v` | Sv39 hardware page-table walk | S-mode paging, i.e. all of xv6 |
| `cpu/rtl/tcpu_core.v` (changed) | S/U privilege, Sv39 plumbing, RV64A, `fence.i` | xv6 |
| `cpu/rtl/tcpu_csr.v` (changed) | S-mode CSRs, delegation, `satp` | xv6 |

`tcpu_defs.vh` is already an include in the sealed set and stays one.

### 1.2 The physical port widened

The board-proven build used the V1 port. xv6 runs on PHYSICAL_PORT_V2, which adds `req_amo[3:0]`,
`req_lrsc[1:0]`, `resp_scfail` and `resv_clear`. In Chisel this is the difference between `TeachingCpu` and
`TeachingCpuV2`; `TeachingCpuV2` instantiates `TcpuCoreBlackBox(resetPc, misaA = 1)`, so `MISA_A` becomes 1
and the decoder's atomic legality turns on with it. **None of these signals has been through synthesis.**

### 1.3 The SoC differs, and this is the largest single item

The board top that was proven is `TeachingBoardTop` over `TeachingCpuZynqTop`, which uses the stock
`HasPeripherySerial` / `HasPeripheryBlockDevice` and the `ReqRespToTL` bridge. xv6 runs on `RD2ZynqTop`,
which uses `HasRD2Serial`, `HasRD2Clint`, `HasRD2BlockDevice`, the V2 bridge, and — when `RD2Params.atomic`
is set — the accepted `AtomicBackend` installed by `WithAtomicHub` at the coherence-manager hook, ahead of
`TLBroadcast`.

The good news, and the reason this is a delta rather than a project: **`RD2BoardTop` and `ZynqAdapterRD2`
already exist** (`RD2Soc.scala:455`, `ZynqAdapterRD2.scala`), `RD2BoardTop` already ties off the
simulation-only `bdevStall`, and `RD2BoardTop.RD2BoardConfig.v` has been generated repeatedly for RTL
comparison. What does **not** exist is a board configuration with the atomic path switched on.

### 1.4 The one new configuration this needs

`RD2AtomicXv6FastConfig` is already the right machine — `WithoutTLMonitors`, `traceEvents = false`,
`atomicTrace = false`, `WithAtomicHub(trace = false)`, `WithRD2(atomic = true)`. The board build needs the
same ingredient list generated as **`RD2BoardTop`** instead of the harness:

```scala
class RD2AtomicBoardConfig extends Config(
  new freechips.rocketchip.subsystem.WithoutTLMonitors ++
  new WithAtomicHub(trace = false) ++
  new WithRD2(RD2Params(atomic = true, traceEvents = false, atomicTrace = false)) ++
  new WithTeachingCpu(TeachingCpuParams(traceEvents = false, extraDelay = false, bridgeFault = 0,
                                        tailIntercept = false)) ++
  new WithTeachingBootROM ++ new zynq.WithZynqAdapter ++
  new freechips.rocketchip.system.DefaultConfig)
```

That is an addition, not an edit: every existing configuration elaborates unchanged, which is the same
discipline `RD2Params.atomic` was introduced under. **No shared checkout switch, no change to the default
Rocket configuration.**

### 1.5 Simulation-only instrumentation to exclude, and how it is checked

| construct | where | disposition |
| --- | --- | --- |
| `obs*`, `halted`, `busy`, `axiStats`, `status` ports | `RD2ZynqTop` observation bundle | kept out of the `dontTouchPortsExcept` set so the logic behind them is optimised away — this is what `RD2BoardTop` already does |
| `bdevStall` | `RD2ZynqTopModule` IO | driven `false.B` by `RD2BoardTop`; already correct |
| event printfs (`EV*`, `BDEV_OP`, `PROGRESS`, `TAILHIT`) | `RD2Soc.scala`, `rd2_boot_main.cpp` | `traceEvents = false` / `atomicTrace = false`; `rd2_boot_main.cpp` is a simulator main and is not in the build at all |
| TileLink monitors, `plusarg_reader` | elaboration | `WithoutTLMonitors`; `audit-board-rtl.py` counts both and the board-proven audit shows `0` and `0` |
| `cpu/tb/tcpu_harness.v`, `tcpu_top.v`, `tcpu_main.cpp` | the CPU test bench | never in the manifest |
| `FAULT_*` parameters (16 of them, incl. the five CPU-A ones) | `tcpu_core.v:22-42` | all default to `0` and `TcpuCoreBlackBox` passes only `RESET_PC` and `MISA_A`. Defaulting is not evidence: the build must **assert** each is 0 in the elaborated RTL |

`m4-prep/scripts/audit-board-rtl.py` already produces exactly this evidence (ports against the baseline,
plusarg/monitor/printf counts, guarded-vs-unguarded simulation constructs, per-module instrumentation
counts, boot ROM extracted from the RTL itself). It runs unchanged against the new board RTL.

## 2. Mapping the existing ARM platform onto the teaching board design

| platform element | what exists | teaching side | needed |
| --- | --- | --- | --- |
| host registers | `0x43C00000`: TSI out/in FIFO + count, `SYSTEM_RESET` 0x10, BLKDEV req/data/resp FIFOs, `NSECTORS` 0x38, `MAX_REQUEST_LENGTH` 0x3C | `ZynqAdapterRD2` implements the same map **plus** 0x14 RO status (bit0 `CPU_RESTART_SAFE`, bit1 `PL_RECONFIG_SAFE`, bit2 `DRAINING`, bit3 `TIMEOUT`, 15:8 EPOCH, 31:16 NDRAINED) and 0x18 RW bit0 `QUIESCE_REQ` | nothing new. `zynq_driver.cc` never reads 0x14/0x18, so the existing host binary works untouched; reading them is an *optional* diagnostic |
| console | TSI/HTIF over the out/in FIFOs, `tsi->send_word`/`recv_word` | xv6 uses `kernel/htif.c`, the same HTIF the simulator uses | nothing. The console path is identical to simulation |
| block device | `bdev->send_request/send_data/recv_response`, geometry pushed to 0x38/0x3C at driver construction | `HasRD2BlockDevice`, register file at `0x10015000`, which is what `kernel/blkdev.c` polls | nothing. **Confirmed, not assumed**: `RD2BoardTop.RD2BoardConfig.v:52390` decodes `io_phys_req_bits_addr ^ 32'h10015000`, the same base the simulation build uses and the same one `blkdev.c` is written against |
| geometry | `bdev->nsectors()`, `max_request_length()` read from the image | simulation reports `4000 sectors (1 MB), max request 16` | nothing: the same `fs.img` gives the same geometry. The board must be given the **same pristine image** (`4691ffea…`) |
| DDR | PS HP0. The PYNQ-Z1 has 512 MB; `pynqz1_devicetree.dts` gives **Linux only the low 256 MB** (`reg = <0x0 0x10000000>`) so the **upper 256 MB is the target's DRAM**, seen at `0x8000_0000` through HP0 — it is not separate memory | xv6 `PHYSTOP = KERNBASE + TEACHING_SIM_MEM_MIB MiB`, currently **4** | **a real decision, below**, plus a boot precondition |
| restart handshake | `SYSTEM_RESET` 0x10 written 1 then 0 by `zynq_driver_t`'s constructor | `RD2BoardTop`: `target.reset := reset` (cold only), `target.softReset := adapter.io.sys_reset` (a request, not a reset) | nothing new. This is the accepted split; `PL_RECONFIG_SAFE` stays 0 and the 50 ms hold stays an operating condition |

### 2.1 RAM capacity — settled on board grounds, not by copying the simulation

`TEACHING_SIM_MEM_MIB = 4` exists because `kinit` walks every page and the simulator runs at ~6,500
instructions/s; it is a simulation compromise and has no business on the board.

The platform already answers this, and it answers it with a recorded incident. `pynqz1_devicetree.dts`
carries the reason it hands Linux only the low 256 MB:

> Handing all 512MB to Linux lets a program running on Rocket scribble over the ARM kernel: xv6's kinit()
> alone memsets every page from `end` to PHYSTOP (128MB), which wiped Linux out from under itself and
> produced slab-allocator Oopses on the ARM side.

So **128 MB is the value this platform has run xv6 at before**, the split that makes it safe is already in
the device tree, and the failure mode when it is not is documented rather than hypothetical. Proposed:
build the board kernel with **`TEACHING_SIM_MEM_MIB = 128`**, and verify before the build is sealed:

1. the value against `ExtMem` in the elaborated board RTL, not against the device tree text;
2. that `PHYSTOP` stays inside the target's 256 MB window with the kernel image and boot ROM accounted for;
3. that the same source still builds at 4 MiB, so a simulation re-run of any board failure is possible on
   the identical kernel source with one `-D` changed.

**Boot precondition, from that same incident:** the ARM side must be running with this device tree
(`reg = <0x0 0x10000000>`). If Linux is given the full 512 MB, `kinit` at 128 MB will overwrite the ARM
kernel. This is checked before step 5 of §4, not discovered during it.

The macro already exists (`memlayout.h`, `#ifndef TEACHING_SIM_MEM_MIB`), so this is a build option and not
a patch. **The board kernel is therefore a different binary from the simulation kernel and must be hashed
separately** — it is the same source, not the same artefact.

### 2.2 Isolated adaptations proposed, and their tests

Only two, both additive:

| adaptation | test that it is right |
| --- | --- |
| `RD2AtomicBoardConfig` (§1.4) | elaborate it and diff the generated RTL against `RD2BoardTop.RD2BoardConfig.v`: the difference must be confined to the atomic node, the V2 port and the CPU black-box parameters. `audit-board-rtl.py` must report 0 monitors, 0 plusarg readers, 0 event printfs, and the board top's port list must still match the baseline `Top` field for field |
| board kernel at 128 MiB | build both kernels from one source; `PHYSTOP` inside `ExtMem`; boot the **4 MiB** one in simulation to show the source is unchanged behaviourally |

### 2.3 Where targeted simulation is genuinely needed

Only one boundary is newly changed and board-specific: **the atomic backend sitting between the CPU and the
PS HP port on the board**, where the memory is real DDR rather than `SimAXIMem`. The accepted atomic
evidence was taken against the simulated memory. What is *not* proposed: a new architecture study, a new
reset matrix, or re-running the accepted 24 atomic scenarios. What is proposed: elaborate
`RD2AtomicBoardConfig` in simulation once, run the already-accepted atomic gate set against **that
elaboration** rather than the harness one, and show the result is identical. If codex judges the existing
evidence sufficient because the backend sees TileLink either way, this step can be dropped — it is offered,
not assumed necessary.

## 3. The frozen build

Existing chain, used unchanged: `m4-prep/scripts/make-top-shim.py` → `gen-project-tcl.py` → `check-tcl.tcl`
→ `check-hierarchy.py` → `m4-build/build.sh`, then `check-impl-reports.py`, then `board-preflight.sh`.

| item | value |
| --- | --- |
| part | `xc7z020clg400-1`, board part `www.digilentinc.com:pynq-z1:part0:1.0` |
| target clock | `host_clk_i` **40.000 MHz** — the clock the accepted build closed at; not raised |
| build command | `BUILD_INPUTS=<new sealed set> JOBS=10 VIVADO_IMAGE=vivado-env:2025.2 m4-build/build.sh <fresh attempt dir>` |
| inputs | a new sealed set: the three existing blackbox files **plus** `tcpu_ptw.v`, `tcpu_cdecode.v`, `tcpu_muldiv.v`; new board RTL from `RD2AtomicBoardConfig`; existing shim, wrapper, xdc, bd tcl, `tcpu_defs.vh`, `AsyncResetReg.v`, `plusarg_reader.v` |
| refusal | `build.sh` verifies the sealed manifest by hash before doing anything and refuses an existing attempt directory; a failed attempt is kept |

### Pass conditions, stated before the build

| gate | condition | baseline for comparison |
| --- | --- | --- |
| setup | WNS ≥ 0, TNS = 0, 0 failing endpoints | +3.269 ns / 0.000 / 0 of 15394 |
| constraints | "all user specified timing constraints are met" true | true |
| `check_timing` | all categories 0 | 0 |
| clocks | no new clock; `host_clk_i` still 40.000 MHz | clk_fpga_0 100, gclk_0 125, gclk_fbout 125, host_clk_i 40 |
| CDC | Inter Clock Table empty, `report_cdc` all paths safely timed | same |
| LUTs | fits the device, reported against baseline | 9,146 (17.19%) |
| DRC | no new rule relative to the validated baseline; nothing waived | same rules only |
| instrumentation | `audit-board-rtl.py`: 0 plusarg readers, 0 monitors, 0 event printfs, port list identical to baseline `Top`, every `FAULT_*` = 0 | same |

**Timing is the real risk and I will not pretend to predict it.** The added divider and 64-bit multiplier
in `tcpu_muldiv.v` and the page-table walker's address arithmetic are plausible critical paths, and the
core roughly doubles in content. The baseline had +3.269 ns of slack at 25 ns and used 17% of the LUTs, so
there is headroom, but whether it closes is **unknown until built**. If WNS goes negative the answer is to
report it with the failing paths, not to relax the clock silently.

### Rollback

The validated Rocket baseline bitstream identified by `m4-prep/audit/baseline-identity.txt`, which
`board-preflight.sh` already binds. The recorded fallback procedure is: load baseline, `SYSTEM_RESET=1`,
run Rocket hello, expect PASS and return 0 — that is what session-5 logged. Cold power cycle is the
recovery of last resort and the only sanctioned way out of a PS lockup.

## 4. Cold-start programming and first boot

Stated as a sequence with timeouts and a stop rule. **This section is a plan. It is not a request to
execute, and user-reported board availability is not programming authorisation.**

| step | action | pass | timeout | on failure |
| --- | --- | --- | --- | --- |
| 0 | `board-preflight.sh --build <attempt>` | fail-closed preflight passes | — | stop; no programming |
| 1 | cold power-on, program PL from a quiescent platform, never during operation | configuration done | — | power cycle |
| 2 | hold `SYSTEM_RESET` ≥ 50 ms before each program load, as the accepted operating condition | — | — | — |
| 3 | bare-metal sanity: the four accepted M3 programs on the new bitstream | `TEACHING-CPU-M3-OK`, `M3-DDR-OK`, `M3-CLINT-OK`, `M3-BADADDR-OK`, each returning 0 | 60 s each | stop, keep the console, roll back |
| 4 | new-extension sanity, bare metal: one program each for M, C, Sv39 and A, reusing the existing diag style | explicit OK markers | 60 s each | stop and report which extension |
| 4b | confirm the ARM device tree gives Linux only the low 256 MB (§2.1) | `reg = <0x0 0x10000000>` | — | stop: a 128 MB `kinit` would overwrite the ARM kernel |
| 5 | xv6 kernel + the same pristine `fs.img` (`4691ffea…`) over `+blkdev=` | `xv6 kernel is booting`, `init: starting sh`, a prompt | 120 s | capture console, compare against the simulation trace of the same kernel |
| 6 | the same four commands the simulation is judged on: `echo`, `ls`, `cat README`, `echo abc \| wc` | the existing `check-xv6.py` on the captured console | 120 s | report honestly; a board pass does **not** retire a simulation failure |

Console capture: the driver and checker are reusable as-is — `scripts/xv6-drive.py` speaks to a process's
stdin/stdout, and `fesvr-zynq` presents the same interface, so the board run produces the same
`console.txt` / `stages.txt` / `IDENTITY.md` triple and is judged by the same `check-xv6.py`. The driver
records the simulator/kernel/disk hashes it started with, which on the board becomes the bitstream identity
— **one change needed** there, and it is a one-line addition, not a new tool.

**Authority is split deliberately**: offline build authorisation (§3) is one decision; programming the PL
and opening the serial port (§4) is a second, separate decision. This report asks for neither yet.

## 5. run-v3 and the honest-acceptance rule

`run-v3` keeps its ownership and its input: job `xv6-run-v3`, pid 2718857, driver v3, its own copy of the
pristine image, no second reader of its stdin, no duplicate long simulation started. At the time of writing
it has reached `blkdev: 4000 sectors` and is running. Its evidence will be collected and reported whatever
it says, and `claude-xv6-four-command-ready` will be filed on its actual result.

Board preparation waives nothing. If a command fails in simulation, it is a failure that gets reported; a
later board pass would be a separate result about a different machine, not a retraction.

OPEN claude-xv6-board-delta-ready
