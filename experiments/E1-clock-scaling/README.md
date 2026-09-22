# E1 — clock scaling: how much of a memory round-trip is fixed time?

**Status: build complete, not accepted, no board access.** Per `codex-b0-e1-opt01-authorization` §2, board
installation is conditional on B0's microbenchmark identity review and acceptance of this build, and on a
coordinated physical cold cycle.

## The question

B0 measures one DRAM round-trip at roughly 18 cycles but cannot say how it divides between

* **design-clock cycles** — core FSM, fabric adapter, AXI interconnect, the PL side of S_AXI_HP0, all of
  which run on `host_clk` (RTL fact: `rocketchip_wrapper.v` drives both `.clock` and the block design's
  `.ext_clk_in` from the MMCM output), and
* **fixed nanoseconds** inside the PS — clock-domain crossing, DDR controller scheduling, DDR3 latency.

B0 can only bracket the benefit of raising the clock at **1.08×–1.25×**. A second frequency turns the
bracket into a number.

## This build

One constant changed against the frozen B0 inputs, and nothing else:

```
boards/pynq-z1/frozen/clocking.vh:  `define RC_CLK_DIVIDE  25.0  ->  40.0
```

125 MHz on pin H16 × 8.0 / 40.0 = **25 MHz**, confirmed by the build's own constraint report
(`host_clk_i` period 40.000 ns). All 15 frozen inputs were hash-verified before copying; `INPUTS.json`
records every one, and `BUILD.json` records the delta, tool identity, timing, checks and output hashes.

| | |
| --- | --- |
| WNS | **+13.396 ns** on a 40 ns period, TNS 0, **0 of 20392** setup endpoints failing |
| WHS | +0.064 ns, THS 0, 0 hold failures |
| DRC / CDC / methodology | no critical warnings or errors |
| bitstream | `df043a1def284fd4…` — a **new configuration identity**, not the accepted one |

I predicted +15.8 ns earlier by extrapolating linearly from the 40 MHz build's WNS. The actual figure is
**+13.4 ns**, wrong by 2.4 ns. Timing does not scale that way, and nothing here says whether 50 MHz is
reachable — that would need its own build.

## The model, and what two points can and cannot do

```
L(f) = N_cycles + T_fixed · f
```

This is an **empirical two-point model**. Linearity is the assumption under test, not a result:
CDC quantisation, DDR controller scheduling and a changed implementation — re-synthesis moves placement
and routing, and the MMCM divider is fixed at synthesis so the frequency cannot be changed without it —
can each violate it. **Two points cannot detect curvature.** What they can do is reject the two extreme
hypotheses:

| if CPI32 at 25 MHz is | then |
| --- | --- |
| ≈ 40.3 cycles, unchanged | the path is essentially synchronous; `T_fixed` ≈ 0 |
| ≈ 25 cycles (0.625×) | the path is essentially fixed time; raising the clock buys nothing |

**Built-in control:** the CLINT load never leaves the fabric, so its *cycle* cost should be unchanged. If
it moves, something other than the clock changed and the DRAM figures from this build are not
interpretable. Cross-frequency ratios will be reported in **both cycles and nanoseconds**, and the
existing comparison guards in `benchmarks/tools/gen_comparisons.py` stay enabled — a 25 MHz row and a
40 MHz row are different configured frequencies, and `ratio()` already refuses to divide them silently.

## What happens on the board, when authorised

Coordinated cold cycle → install this bitstream → eight startup probes → `perf03` and `perf04`, ≥5 bounded
samples, unchanged probe ELF identities → **second coordinated cold cycle** → restore the accepted 40 MHz
bitstream → re-run the eight gates. Restoration is required, and is not authority for unsafe recovery: on
any failed gate, stop, preserve evidence, and report the actual remaining board state.
