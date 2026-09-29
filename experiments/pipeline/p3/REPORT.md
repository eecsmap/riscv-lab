# PIPE-P3a REPORT — offline single-pipeline PYNQ-Z1 implementation at 40 MHz

Task `codex-pipe-p3-offline-40mhz`. Worktree `worktrees/pipe-single`, branch `pipe-single`, local commits only. No
board, JTAG, serial, power, network, push or tag action; the bitstream was built and **not programmed**. The board
stays in the user's dual-multicycle interactive session.

**Status: routed and bitstream built, 40 MHz closed.** Every gate of the task passed offline; the board comparison
is prepared (§7) and needs a separate review and authorisation.

| stage | label | result |
|---|---|---|
| elaboration | generated | `RD2BoardTop.RD2PipeBoardConfig.v` `ec2a7311…`, one `tcpu_core_pipe`, no `tcpu_core` |
| synthesis | synthesis-only numbers are not used below except where named | `synth_design Complete!`, 0 black boxes |
| place & route | **routed** | WNS **+0.440 ns**, TNS 0, WHS **+0.020 ns**, THS 0, 29,147 endpoints, 0 failing; 26,071 nets fully routed, 0 routing errors |
| gate | routed | setup/hold met, routed, 0 DRC errors → bitstream allowed (`results/attempt-1/gate.txt`) |
| bitstream | **bitstream** | `rocketchip_wrapper.bit` `b687f77f6b7cc69a…`, payload `.bit.bin` `5f97d4abf2778c1a…` (not programmed) |

## 1. Anchors
* P2b accepted by Codex at `8e099a5` (production core/SoC `0b225e0`), 2026-09-29 17:30Z; independent evidence in
  `experiments/pipeline-review-p2b-*` (Codex). The generated SoC Verilog Codex reused was gen-3 (P2b).
* P3a commits: `6dd0914` (RD2PipeBoardConfig + gen/compare scripts), `8bb91cf` (board-build tooling), `94d67c6`
  (validator self-test; **the RTL commit the build extracted**), and this report's commit.
* The pipeline RTL is unchanged since `35c05eb` (P2b checkpoint 3); P3a changed no RTL, shared or pipeline.

## 2. Configuration and re-elaboration (`scripts/gen-p3.sh`, `runs/gen-1`, `results/gen-1/`)
* `RD2PipeBoardConfig` = `RD2AtomicBoardConfig` (the accepted single multicycle board shape: no TileLink monitors,
  no event/atomic/BDEV traces, no bus instrumentation) with `coreImpl = "pipeline"`, generated as `RD2BoardTop`.
  Pipeline × 2 stays refused (`MC1UnsupportedPipelineConfig`, re-checked in this run).
* Re-elaborated from the pinned scala (`6dd0914`), fresh private commons (`judge-gen.txt`: JUDGE_GEN PASS):
  * the seven existing configurations are identical before (`8e099a5`) and after — raw identical this time, since
    the only scala change is an added class;
  * the fresh `RD2PipeXv6FastConfig` equals the accepted gen-3 one module for module (151/151 identical,
    `cmp-gen3-vs-fresh.txt`);
  * the five refusals refuse with their messages.
* **Board RTL vs the accepted multicycle board shape** (`cmp-vs-atomic-board.txt`): 126 modules each; 125 identical;
  `TeachingCpuV2` differs in exactly one line pair — `tcpu_core #(.RESET_PC(65600), .MISA_A(1), .HART_ID(0))` →
  `tcpu_core_pipe #(.MISA_A(1), .PIPE_EXT_SU(1), .PIPE_EXT_M(1), .HART_ID(0), .RESET_PC(65600), .PIPE_EXT_C(1))`.
  The wrapper's pipeline-only `isFetch` terms are removed by elaboration here: the board shape reads no observation.
* **Board RTL vs the accepted P2b integration (gen-3)** (`cmp-vs-gen3.txt`): the intended harness → board
  differences — 39 simulation-only modules gone (AXI4RAM, the simulated block device and serial drivers, …), 14
  board modules added (`RD2BoardTop`, `ZynqAdapterRD2*`, queues), 42 modules changed. They are **exactly** the
  differences the multicycle core's own harness → board step has (`cmp-multi-xv6fast-vs-board.txt` vs
  `cmp-pipe-xv6fast-vs-board.txt`: the same 70 identical / 42 differing / 39 / 14 modules; only `TeachingCpuV2`'s
  changed-line count differs, 30 vs 36, the dropped `isFetch` terms).

## 3. The build, pinned (`scripts/build-board-p3.sh`, `runs/attempt-1`, `results/attempt-1/`)
The accepted M4 flow (m4-prep `gen-project-tcl.py` + `check-tcl.tcl`, validators, Vivado batch in
`vivado-env:2025.2`, Vivado **2025.2.1**, part **xc7z020clg400-1**, board `pynq-z1`, top `rocketchip_wrapper`,
4 jobs), with pipeline-owned copies where the inputs differ:
* `source-MANIFEST.txt`: 20 sealed sources — the board RTL above; the shim generated from it (76 ports, identical
  to the baseline `Top`); **exactly the 11 files of `rtl/cpu/pipeline/SOURCES.pipe`, extracted from commit
  `94d67c6`** into the attempt (no directory glob, no multicycle file) with `tcpu_defs.vh` in an include-only dir;
  the BASELINE wrapper, `base.xdc`, block design Tcl and support files, unchanged. `input-hashes.txt`,
  `tooling-hashes.txt` (every script used), `environment.txt`, `source-set.txt` (what Vivado actually compiled).
* Validators (`tools/`, copies of the M4 ones): the hierarchy closes from `rocketchip_wrapper` and reaches every
  pipeline module, and **no multicycle module (`tcpu_core`, `tcpu_xlate`, `tcpu_tlb`, `tcpu_ifill`) is reached or
  in the list**; the board-RTL audit requires one `tcpu_core_pipe` with `RESET_PC` 0x10040, `MISA_A` 1,
  `PIPE_EXT_M/C/SU` 1, `HART_ID` 0 and **nothing else passed**, no `tcpu_core`, all 27 fault/knob parameters
  defaulting to 0, no plusarg readers, TL monitors or trace printfs, the V2 port connected, the boot ROM equal to the
  teaching image and to the accepted M4 extraction. Self-test (`results/selftest-validators-1.txt`): six mutants
  (the multicycle core file added, `tcpu_tlb2.v` dropped, the multicycle board RTL, `.PIPE_FAULT(4)` passed,
  `PIPE_EXT_C(0)`, a knob default of 4) each refused for its own reason.
* `tools/run_impl_p3.tcl` (copy of the accepted `run_impl.tcl`): implementation stops after `route_design`; the
  routed design is gated (setup and hold met, every net routed, no DRC error); only then `write_bitstream`. No
  debug or negative-control variant is in this build. Payload: the accepted `bit2bin.py`, first self-checked by
  reproducing the accepted M4 payload `43e5b414…` byte for byte.
* Old configurations and artifacts: untouched (the M4/IPS builds are only read).

## 4. Timing (routed, `results/attempt-1/post_route_*.rpt`)
| build | clock | WNS | TNS | WHS | THS | endpoints |
|---|---|---|---|---|---|---|
| **single pipeline** (this) | `host_clk_i` 25.000 ns = 40 MHz | **+0.440 ns** | 0 | **+0.020 ns** | 0 | 29,147 |
| single multicycle, cache (accepted, bit `e546c0dd…`) | same | +0.424 ns | 0 | +0.036 ns | 0 | 24,530 |
| dual multicycle (accepted M4, bit `4ecccd05…`) | same | +0.396 ns | 0 | +0.035 ns | 0 | 37,958 |

* Constraints: the baseline `base.xdc` and block design, unchanged; the clock was not lowered. The only timing
  exceptions are the IP's own three `src_arst` false paths (`post_route_exceptions.rpt`) — no false path or
  multicycle exception was added.
* `check_timing`: 0 unclocked register pins, 0 pins unconstrained for max delay, 0 input/output ports without
  delay, 0 multiple-clock pins, 0 unconnected generated clocks — as both accepted builds.
* **Critical setup path** (`post_route_critical_setup.rpt`): +0.440 ns, `target/rd2serial/addr_reg` →
  `target/backend/resvValid_0_reg`, 48 logic levels (28 CARRY4) — **in the shared SoC** (serial adapter address →
  atomic backend reservation compare), the same path class that is worst in both accepted builds (+0.424 / +0.396
  ns). The next ones: the V2 bridge's `state` → `applied` reset (+1.867 ns). **The worst path inside the pipeline**:
  `core/ex_insn` → the walker's `cause` register enable, +1.914 ns, 28 levels (EX decode → MEM/walker start).
* **Hold**: worst +0.020 ns in the PS AXI interconnect's protocol converter (baseline block-design IP), then
  +0.037 ns into the I-cache LUTRAM write port from `core/ic_fill_data`. Met, but thinner than the baselines'
  +0.036 / +0.035; recorded, not argued away.
* DRC: 3 × PDCN-1569, 1 × RTSTAT-10 (warnings); methodology: 3 × LUTAR-1 (warnings); 4 critical warnings, all the
  PS preset's PSU-1/PSU-2 DDR DQS skew notes — **identical** in kind and count to both accepted builds. No new
  error or unexplained warning class.

## 5. Resources (routed, `results/compare-1.txt`, `scripts/p3-compare.py`)
Full system (the whole `rocketchip_wrapper`, PS interconnect included):

| build | LUT | of which LUTRAM | FF | BRAM | DSP |
|---|---|---|---|---|---|
| **single pipeline** | **18,208** | 963 | **9,154** | 0 | 0 |
| single multicycle (cache) | 14,554 | 963 | 7,011 | 0 | 0 |
| dual multicycle | 22,631 | 1,265 | 11,181 | 0 | 0 |

Per hart (the `TeachingCpuV2` instance) and the rest of the design:

| | single pipeline | single multicycle (cache) | dual multicycle, per hart |
|---|---|---|---|
| hart | **10,826 LUT / 5,604 FF** | 7,399 LUT / 3,460 FF | 7,396 / 3,460 and 7,329 / 3,446 |
| everything outside the hart(s) | 7,382 LUT / 3,550 FF | 7,155 LUT / 3,551 FF | 7,906 LUT / 4,275 FF |

So the single-pipeline system is +3,654 LUT (+25 %) / +2,143 FF (+31 %) over the single multicycle system, of which
the hart accounts for +3,427 LUT / +2,144 FF; it is 4,423 LUT smaller than the dual multicycle system.

Inside the hart (attribution after cross-boundary optimisation — **not** isolated feature costs):

| block | pipeline | multicycle (cache) |
|---|---|---|
| core logic of its own | `tcpu_core_pipe` 3,329 LUT / 3,381 FF | `tcpu_core` 439 / 838 |
| CSR (shared `tcpu_csr`) | 1,731 / 848 | 1,164 / 848 |
| mul/div (shared `tcpu_muldiv`) | 1,696 / 466 | 1,112 / 466 |
| TLB | `tcpu_tlb2` (2 lookup ports) 789 / 643 | `tcpu_tlb` 413 / 643 (inside `tcpu_xlate` 720 / 987) |
| walker | `tcpu_ptw_wrap` 791 / 202 (walker 691 / 170) | `tcpu_ptw` 291 / 212 |
| I-cache (shared `tcpu_icache`, 1 KiB) | 2,265 / 64, 200 LUTRAM | 337 / 64, 200 LUTRAM (fill engine `tcpu_ifill` 746 / 257 besides) |
| register file (shared `tcpu_regfile`) | 245, 88 LUTRAM | 2,904, 88 LUTRAM |

The same shared modules land at different sizes because the tool moves logic across boundaries. Most likely (not
verified cell by cell): the register file's read multiplexing is attributed to the multicycle's `rf` but mostly to
the pipeline core's own logic, which has more read paths and forwarding; and the pipeline's fetch word/parcel
selection is attributed to `icache`. Only the
full-system and whole-hart numbers are comparable; the block rows show where the tool placed logic.

## 6. What the comparison is and is not
* Same memory system and policy for the primary comparison: one physical port, one outstanding request, the shared
  serial atomic backend, 8-entry TLB, 1 KiB I-cache, no D-cache, 40 MHz, the same PS/AXI wrapper and constraints.
* **Front-end redesign and pipelining are combined in this implementation**: the pipeline has its own fetch engine
  and extractor (and a second TLB lookup port) where the multicycle core has `tcpu_ifill`. A controlled
  front-end-only comparison is future work; nothing above attributes a cost to one of them.
* No board, frequency beyond 40 MHz, power or performance claim. Simulation cycle counts (P2b) are not board
  performance.

## 7. Board comparison checklist — PREPARED, NOT EXECUTED (needs Codex review and the user's authorisation)
Preconditions: the user hands the board back (it is in the user's dual-multicycle interactive session) and
authorises the cold power cycles and programming; the user states which image the board must end in (the dual
payload `43e5b414…` currently loaded, or the single cache payload `79a114ae…`); leases `board`/`serial` taken by the
scripts themselves (not pre-claimed by hand — the M5 gotcha), `mkdir -p /var/lock` on the cold RAM root.
1. **Identity and cold cycle #1**: record pre-state (boot id, PL `prog_done`, `/root/xv6run` contents); the user
   attests the power cycle; new boot id, uptime ≤ 600 s, no host, no lock; production `mem-preflight`.
2. **Install**: an isolated copy of the M5 install script with the pipeline payload `5f97d4ab…` (bit `b687f77f…`),
   re-hashed after transfer and after programming (`prog_done`), host `fesvr-teaching-static` `c050eab3…`.
3. **Correctness gates on hardware**: the single-core bare-metal gate set of the cache stage (8 programs, exact
   completion markers), then xv6 `m4smoke` (kernel-dual-128mib `33021237…`, fresh `fs-dual-deploy.img` `d8e50269…`),
   judge `m5_xv6_check.py`. Regexes use `\r?\n` (serial CRLF).
4. **Fixed work on the same boot**: measurement kernel `133f5b72…` (128 MiB), fresh `fs-perf.img` `d558e444…`,
   profile `perf-board` (mtimetest, 3 × perfcompute 2,000,000, 3 × perfarray 128), judge `perf_check.py` with its
   defaults (`--mtime-hz 400000`, `--min-dmtime 2000000`); child checksums must equal the multicycle's.
5. **Time base**: mtime = core clock / 100, so 400 kHz only if the fabric really runs at 40 MHz: check the
   mtimetest spin rate against the simulator's cycles/iteration and the multicycle board's, and report the
   frequency as measured, not assumed.
6. **Comparison**: T_pipe vs the accepted single multicycle T1 (compute 26.588 s, array 40.548 s, `perf/RESULTS.md`),
   same kernel and disk; report ratios per workload with ranges, no threshold, no generalisation.
7. **Rollback / cold cycle #2**: the production restore for the image the user names (`ips-install.sh cache` for
   `79a114ae…`, or the M5 dual install for `43e5b414…`), with its gates re-verified; the board ends in the user's
   configuration.

## 8. Not done / open
* No board step (by design). The payload is not in any deploy directory used by the board scripts.
* The hold margin (+0.020 ns, in the PS interconnect IP) is thinner than the baselines' but met; no action taken.
* A front-end-only controlled build (§6) and anything dual-pipeline: not in scope.

## 9. Commands
```sh
P=experiments/pipeline/p3
bash $P/scripts/gen-p3.sh 8e099a5 $P/runs/gen-N                         # re-elaborate, judge, compare
bash $P/scripts/build-board-p3.sh $P/runs/attempt-N <rtl commit> $P/runs/gen-N/gen/after-RD2PipeBoardConfig/RD2BoardTop.RD2PipeBoardConfig.v            # validators only
bash $P/scripts/build-board-p3.sh $P/runs/attempt-N <rtl commit> <board rtl> --with-vivado   # + Vivado (coord vivado lease, coord job)
bash $P/scripts/selftest-validators.sh $P/runs/attempt-N $P/runs/gen-N
python3 $P/scripts/p3-compare.py pipeline=$P/runs/attempt-N/reports cache=<cache reports> dual=<M4 reports>
```
