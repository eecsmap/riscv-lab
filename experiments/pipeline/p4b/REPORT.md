# PIPE-P4b REPORT — dual-pipeline PYNQ-Z1 offline implementation at 40 MHz

Task `codex-pipe-p4b-offline-40mhz`. Branch/worktree `pipe-dual`, local commits only. Offline: no board, serial,
JTAG or programming; the user's single-pipeline image and disks are untouched. No push/tag.

**Status: routed, 40 MHz closed, bitstream built (not programmed).** Every acceptance item passed offline.

| stage | label | result |
|---|---|---|
| elaboration | generated | `RD2BoardTop.RD2PipeDualBoardConfig.v` `75e4374b…`: two `tcpu_core_pipe` (HART_ID 0 and 1), no `tcpu_core` |
| synthesis | synthesis-only | `synth_design Complete!`, 0 black boxes |
| place & route | **routed** | WNS **+0.641 ns**, TNS 0, WHS **+0.028 ns**, THS 0, 47,425 endpoints, 0 failing; 41,746 nets fully routed, 0 routing errors |
| gate | routed | setup/hold met, routed, 0 DRC errors → bitstream allowed (`results/attempt-1/gate.txt`) |
| bitstream | **bitstream** | `rocketchip_wrapper.bit` `646d88b73b908ad7…`, payload `.bit.bin` `f330769dac6172da…` (not programmed) |

## 1. Pinning
* Commits: `3464940` (RD2PipeDualBoardConfig + gen-p4b.sh), `bf61588` (board tooling), `f1dff88` (generation
  evidence), `aa24497` (validator self-test fix; **the RTL commit the build extracted** and the frozen scripts), and
  this report's commit. P4a acceptance anchor: `5a5dd0e` + `1cd67b1` (closeout note `53d8745`).
* **Frozen execution**: every job ran scripts extracted by `git archive` from a named commit into
  `runs/frozen-<commit>/` (generation from `3464940`, the build and self-test from `aa24497`); no live script was
  executed or edited while a job ran.
* Build (`results/attempt-1/`): `source-MANIFEST.txt` (20 sealed sources: the board RTL; the shim generated from it,
  76 ports identical to the baseline `Top`; exactly the 11 `SOURCES.pipe` files extracted from `aa24497`; the
  baseline wrapper, `base.xdc`, block design Tcl, support files), `input-hashes.txt`, `tooling-hashes.txt`,
  `environment.txt` (Vivado **2025.2.1**, image `vivado-env:2025.2`, part **xc7z020clg400-1**, 4 jobs),
  `source-set.txt` (what Vivado compiled), `outputs.sha256`; `bit2bin.py` first reproduced the accepted M4 payload.
* Reproduce: `bash <frozen>/experiments/pipeline/p4b/scripts/build-board-p4b.sh <new attempt dir> aa24497
  runs/gen-1/after-RD2PipeDualBoardConfig/RD2BoardTop.RD2PipeDualBoardConfig.v --with-vivado`.

## 2. Configuration and generation (`results/gen-1/`)
* `RD2PipeDualBoardConfig` = `RD2DualBoardConfig` (no TileLink monitors, no event/atomic/BDEV traces, no bus
  instrumentation, numCores 2) with `coreImpl = "pipeline"`, generated as `RD2BoardTop`.
* Fresh elaboration before (`53d8745`) / after: the twelve existing configurations (multicycle 1/2 in Xv6Fast, Boot,
  Board; V1 RD2Boot; pipeline 1 in three shapes; pipeline 2 Xv6Fast and Boot) are **raw-identical** (an added class
  only); the five refusals still refuse.
* Against the accepted multicycle dual board shape: 128 modules each, 126 identical; only `TeachingCpuV2` and
  `TeachingCpuV2_1` differ (the core instances). The harness → board differences of pipeline/2 (vs
  RD2PipeDualXv6FastConfig) are exactly multicycle/2's own (70 identical, 44 differing, 40 / 14 only-in), apart from
  the two hart wrappers.
* Validators (`tools/`, copies of P3a's): the hierarchy reaches both hart wrappers and every pipeline module and no
  multicycle module; the audit requires exactly two `tcpu_core_pipe` with RESET_PC 0x10040, MISA_A / M / C / SU = 1,
  HART_ID 0 and 1, nothing else passed, no `tcpu_core`, all fault/knob defaults 0, no plusarg readers, monitors or
  trace printfs, the boot ROM equal to the teaching image. Self-test (`results/selftest-validators-1.txt`): seven
  mutants each refused for its own reason, including both harts HART_ID 0 (`HART_ID parameters ['0', '0']`).
  Recorded: the first run of this self-test failed on my own layout mistake and a mutant pattern loose enough to
  match a section header; both fixed in `aa24497` before the build.

## 3. Timing (routed)
| build | WNS | TNS | WHS | THS | endpoints | freshly built here |
|---|---|---|---|---|---|---|
| **pipeline × 2 (this)** | **+0.641 ns** | 0 | **+0.028 ns** | 0 | 47,425 | yes |
| pipeline × 1 (P3a) | +0.440 ns | 0 | +0.020 ns | 0 | 29,147 | archived |
| multicycle × 2 (M4) | +0.396 ns | 0 | +0.035 ns | 0 | 37,958 | archived |
| multicycle × 1, cache | +0.424 ns | 0 | +0.036 ns | 0 | 24,530 | archived |

* Clock: `host_clk_i` 25.000 ns (40 MHz) from the baseline MMCM; constraints unchanged; the only exceptions are the
  IP's own three `src_arst` false paths; `check_timing` reports 0 unconstrained / unclocked items.
* Worst setup: `target/rd2serial/addr_reg` → `target/backend/resvValid_1_reg`, +0.641 ns, 50 levels — the shared
  SoC's serial-address → reservation compare, the same path class that is worst in all four builds. Worst inside a
  pipeline hart: `harts_1/cpu/core/mem_addr` → `preq_wmask` reset, +1.407 ns, 17 levels.
* Worst hold: +0.028 ns, `harts_1/cpu/core/g_sv39.walk/walker/a_reg` → `req_addr_reg` (inside the walker), then
  +0.034 ns in hart 0's MEM → WB register. Met; thin, as in every build here (+0.020 to +0.036 ns).
* DRC: 3 × PDCN-1569, 1 × RTSTAT-10 (warnings); methodology: 3 × LUTAR-1; critical warnings: 4, the PS preset's
  PSU-1 / PSU-2 DDR DQS notes — identical in kind and count to all three archived builds. No new warning class.
* Build duration: ≈ 13 min for the whole job (Vivado project + synthesis + route + bitstream 777 s).

## 4. Resources (routed; `results/compare-1.txt`)
Device xc7z020: 53,200 LUT (17,400 usable as LUTRAM), 106,400 FF, 13,300 slices, 140 BRAM tiles, 220 DSP.

| build | LUT | LUTRAM | FF | slices | BRAM | DSP |
|---|---:|---:|---:|---:|---:|---:|
| multicycle × 1 (cache) | 14,554 (27.4%) | 963 | 7,011 (6.6%) | 4,508 (33.9%) | 0 | 0 |
| multicycle × 2 | 22,631 (42.5%) | 1,265 | 11,181 (10.5%) | 7,087 (53.3%) | 0 | 0 |
| pipeline × 1 | 18,208 (34.2%) | 963 | 9,154 (8.6%) | 5,449 (41.0%) | 0 | 0 |
| **pipeline × 2** | **29,490 (55.4%)** | **1,263** | **15,481 (14.5%)** | **8,622 (64.8%)** | 0 | 0 |

| build | per hart LUT / FF | outside the harts LUT / FF |
|---|---|---|
| multicycle × 1 | 7,399 / 3,460 | 7,155 / 3,551 |
| multicycle × 2 | 7,396 / 3,460 and 7,329 / 3,446 | 7,906 / 4,275 |
| pipeline × 1 | 10,826 / 5,604 | 7,382 / 3,550 |
| **pipeline × 2** | **10,829 / 5,604 and 10,598 / 5,602** | **8,063 / 4,275** |

* Pipeline × 2 vs multicycle × 2: +6,859 LUT (+30%), +4,300 FF (+38%), all in the two harts (the rest differs by
  157 LUT, 0 FF). Pipeline × 2 vs pipeline × 1: +11,282 LUT, +6,327 FF (the second hart plus the second hart's
  bridge/port/CLINT/PLIC share, as in multicycle).
* Headroom: 45% of the LUTs, 85% of the FFs, 35% of the slices, all BRAM and DSP remain.
* Hierarchical numbers are attribution after cross-boundary optimisation, not isolated feature costs.

## 5. Scope
Same memory system and policy as every build compared here: one physical port and one outstanding request per hart,
the shared serial atomic backend, private 8-entry TLB and 1 KiB I-cache per hart, no D-cache, 40 MHz, the same
PS/AXI wrapper and constraints. Offline closure only: nothing about board operation or board speed is claimed.

## 6. Not done
Board takeover, cold cycle, install and the four-configuration fixed-work board measurement (a separate assignment).
