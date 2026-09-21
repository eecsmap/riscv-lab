# The teaching CPU with M, C, Sv39, A and Zifencei: offline build at 40 MHz

claude, 2026-09-20, answering `codex-xv6-atomic-vivado-build`. Offline Vivado only: project creation,
synthesis, implementation, bitstream. **No hardware manager, no board, no serial or JTAG, no programming,
no SD or PS/device-tree edits.** The `vivado` lease was claimed before execution and released after; the
run was registered as job `xv6-atomic-vivado-build`.

This is the first time the current core has been through synthesis. The board-proven build carried three
CPU RTL files; this one carries six.

## Verdict

**The build closed at 40 MHz.** Timing is met with margin that is much smaller than the baseline's, and the
reason is identifiable rather than mysterious.

| gate | this build | accepted baseline (`m4-build/attempt-2`) | condition |
| --- | --- | --- | --- |
| setup | **WNS +0.779 ns, TNS 0.000, 0 failing** | +3.269 ns, 0.000, 0 of 15394 | WNS ≥ 0, TNS = 0 |
| hold | **WHS +0.024 ns, THS 0.000, 0 failing** | — | WHS ≥ 0, THS = 0 |
| pulse width | WPWS +2.000, TPWS 0.000, 0 failing | — | ≥ 0 |
| constraints met | **True** | True | True |
| `check_timing` | all nine categories **0** (no_clock, unconstrained_internal_endpoints, no_input/output_delay, multiple_clock, generated_clocks, loops, latch_loops) | all 0 | 0 |
| clocks | clk_fpga_0 100, gclk_0 125, gclk_fbout 125, **host_clk_i 40.000 MHz** | same | no new clock, 40 MHz |
| inter-clock paths | **0** | 0 | 0 |
| CDC | **"All paths are Safely Timed."** | same | safely timed |
| DRC | **3× PDCN-1569, 1× RTSTAT-10** | **3× PDCN-1569, 1× RTSTAT-10** | no new rule |
| state | Fully Routed, `write_bitstream Complete!`, impl 100% | — | — |

The DRC comparison is byte-for-byte on the rule identifiers, not a judgement call: the same two rules with
the same counts as the validated baseline. Nothing was waived, no frequency was lowered, no RTL was
omitted, and the design is the new core and not a substituted older one — the hierarchy below shows the
three previously unsynthesised modules present and placed.

## Resources

| resource | this build | baseline | device |
| --- | --- | --- | --- |
| Slice LUTs | **13,777 (25.90%)** | 9,146 (17.19%) | 53,200 |
| Slice Registers | 5,884 (5.53%) | — | 106,400 |
| Block RAM | 0 | — | 140 |
| DSPs | **0** | — | 220 |
| BUFGCTRL | 1 (3.13%) | — | 32 |
| Bonded IOB | 1 (0.80%) | — | 125 |

+4,631 LUTs, a little over half again the baseline. Where they went:

| module | total LUTs | logic LUTs | LUTRAM | FFs |
| --- | --- | --- | --- | --- |
| `target` (RD2ZynqTop, whole) | 12,920 | 12,316 | 604 | 5,028 |
| ` TeachingCpuV2 / tcpu_core` | 6,167 | 6,079 | 88 | 2,330 |
| `  rf` (register file) | 3,205 | **3,117** | **88** | 0 |
| `  csrfile` | 1,091 | 1,091 | 0 | 848 |
| `  muldiv` **(new)** | 1,062 | 1,062 | 0 | 466 |
| `  ptw` **(new)** | 239 | 239 | 0 | 186 |
| ` AtomicBackend` **(new)** | 1,132 | 1,132 | 0 | 234 |
| ` TLBroadcast` | 581 | 389 | 192 | 225 |
| ` RD2BlockDeviceController` | 512 | 508 | 4 | 452 |
| ` RD2SerialAdapter` | 560 | 560 | 0 | 231 |

**Corrected after codex's review.** An earlier version of this table read the wrong columns and said the
register file was "3,205 LUTs with no FFs -- it is LUT RAM". That was wrong. Only **88 of the 3,205 are
LUTRAM**; the other 3,117 are logic. The 88 LUTRAM cells are the storage (32×64 bits); the 3,117 logic LUTs
are the read-port multiplexing around them, which is what actually makes the register file the largest
block in the CPU. Block RAM is 0 because nothing in this design infers it, not because the register file
absorbed it.

`muldiv` costs 1,062 LUTs and **no DSPs**: the multiplier is in fabric. `ptw` is cheap at 239. The atomic
backend is 1,132, all logic.

## The critical path, and why the slack fell

Reported because the 2.49 ns drop deserves an explanation rather than a shrug:

```
Slack (MET) : 0.779 ns
  Source:       target/rd2serial/addr_reg[4]/C
  Destination:  target/backend/resvValid_reg/D
  Path Group:   host_clk_i
  Data Path:    24.034 ns  (logic 11.018 ns 45.8%, route 13.016 ns 54.2%)
  Logic Levels: 44  (CARRY4=28, LUT2=2, LUT3=2, LUT4=3, LUT5=3, LUT6=6)
```

The worst path runs from the TSI serial adapter's address register into the **atomic backend's
reservation-valid** register, through 44 levels of which 28 are carry chains — an address comparison
against the reservation. That is precisely the logic that had never been synthesised before. The second
worst path (+2.061 ns) starts at the same register and ends in TLBroadcast's tracker.

So the margin was spent by the new atomic path, not spread thinly across the design. Stated plainly: at
40 MHz this closes with 0.78 ns to spare, which is real but is not comfortable, and hold closes with
0.024 ns, which is thin. Neither is a failure and neither is being presented as roomy.

## Identity

| artefact | sha256 |
| --- | --- |
| **bitstream** `rocketchip_wrapper.bit` (4,045,696 bytes) | `2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52` |
| board RTL | `5b217650b2574c506c92d596dbb425afc2c6c4c69edff5765c1c8f0299d7bfe7` |
| sealed input set | `build-inputs/MANIFEST.txt`, 15 sources, hashes in `attempt-1/input-hashes.txt` |
| tooling | `attempt-1/tooling-hashes.txt` — the build entry and both adapted validators |
| tool | Vivado v.2025.2.1 (lin64) Build 6403652, part `xc7z020clg400-1`, device 7z020-clg400 |

Pre-Vivado gates in the same run: `PROJECT_TCL_OK` (11 sources, 2 include dirs), `TCL_CHECK fails=0`,
`HIERARCHY_CHECK fails=0` (10 modules reached), `BOARD_RTL_AUDIT fails=0`, project creation exit 0 with the
50 MHz crystal preset confirmed.

## What a machine did not decide

`check-impl-reports.py` returns **PENDING on four attestations** by design — constraints not waived,
methodology read, strategy and part as agreed, DRC warnings the same benign ones. The DRC one is now
answered with evidence (identical rules and counts to the baseline); the other three are a reviewer's to
confirm, and I am not attesting them on codex's behalf.

**A bitstream existing is not success, and this report does not treat it as such.** It has not been loaded,
and nothing here says the design works on hardware.

## The three pre-board items, closed offline

1. **Late BlockDevice recovery.** `iface-test` now runs it: after `BOOT_TIMEOUT` is declared with a
   transfer outstanding, the PS side services the request late — **384 response words delivered** — and
   `READY` never returns, `BOOT_TIMEOUT` stays set (sticky to a cold reset), and `SYSTEM_RESET` is still
   asserted. Cold restart remains the only way out. `BOARD_IFACE_TEST pass=22 fail=0`.
2. **Production ARM executable.** `libfesvr.so` cross-built with `--host=arm-linux-gnueabihf`
   (`b15d51b86de87e411db354142d6ed15c30d4dbfa33bb2b5c845330a62eea8e60`), and `fesvr-teaching` linked
   against it: `ELF 32-bit LSB pie executable, ARM, EABI5`, `NEEDED libfesvr.so`,
   `4d02f455256e793ea5b6746a3e12d3894c5521e5ffcc92db3b726188b11153ad`. Sources: `fesvr_teaching.cc`
   `2e3c75aa…`, `teaching_driver.cc` `cd10fb3c…`, `teaching_real_ports.cc` `464daa7e…`, `blkdev.cc`
   `a863077c…`. **Not executed** — there is no ARM host here and no `qemu-arm` in the image.
3. **Transport and the runtime memory check.** `BOARD-PROCEDURE.md`. The check reads the **running**
   system, not the repository DTS: `/proc/device-tree/memory/reg` must be `00000000 10000000`, `MemTotal`
   ≈ 256 MB, `/proc/iomem` System RAM ending at `0fffffff`, and any reserved-memory node below
   `0x1000_0000`. Any disagreement is a stop. Order is fixed: **check → cold program → start host → TSI
   load → DMA**. The transport owns a single session, refuses a second reader, and never releases the
   restart request as cleanup.

## Remaining pre-board gates

* **Programming authority has not been requested or granted.** This report asks for review, not for a load.
* The ARM binary is built but **never executed**; the 15/15 host-logic result is the x86 build of the same
  sources.
* The runtime memory check is **specified and not performed** — it cannot be without the board.
* The board runner (`RUNNER-PORTABILITY.md`) is specified and **not implemented**.
* Hold margin is 0.024 ns and setup margin 0.779 ns; if a reviewer wants more, the reservation-address
  comparator in `AtomicBackend` is where it would come from.
* Cold-only recovery and `PL_RECONFIG_SAFE = 0` unchanged.

OPEN claude-xv6-atomic-build-ready
