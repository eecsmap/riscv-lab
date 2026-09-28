# ROI policy: what each window measures, and what is excluded from it

Fixed before any comparative run. A policy decided after seeing results is not a policy.

## Two states, reported separately, never averaged together

| state | what it means | how it is produced |
| --- | --- | --- |
| **cold** | the first pass over a working set, with nothing resident in a TLB or cache that did not have to be | the first ROI executed after reset, or after the invalidation listed below |
| **steady** | repeated passes, with whatever the structure retains | the ROI as written, whose loop count is large enough that the first pass is a small fraction |

For the baseline and fetch32 stages the distinction is vacuous — there is nothing to retain — and that is
itself the control: **if cold and steady differ on a stage with no cache and no TLB, the probe is
measuring something other than what it claims.**

## Invalidation before each ROI, recorded per sample

| stage | before a COLD ROI | before a STEADY ROI |
| --- | --- | --- |
| baseline | nothing to invalidate | — |
| fetch32 | nothing to invalidate | — |
| TLB | `sfence.vma` (conservative full flush) | nothing |
| I-cache | `fence.i` **and** `sfence.vma` | nothing |

Every sample records which of reset, `fence.i` and `sfence.vma` was actually issued. A stage that
cannot invalidate a structure it has must say so rather than report a "cold" number that is not cold.

## Window boundaries

The window is the pair of counter reads, exactly as the existing probes do it:

```
csrr t4, cycle ; csrr t5, instret ; <body> ; csrr a0, cycle ; csrr a1, instret
```

The two trailing `csrr` retire inside the window and are included in the expected count. This is the
convention `perf01`–`perf05` already use; `perf06` follows it, and its expected counts are derived from
the disassembly by `workloads/check_retirement.py` rather than by hand.

**Warm-up is not excluded anywhere.** No probe discards a first iteration, so no sample needs a
"warm-up excluded" note. If a future stage requires one, the discarded portion must be stated in cycles
and instructions, not described.

## Per-workload ROI boundaries

| workload | ROIs | deterministic retirement |
| --- | --- | --- |
| `perf01_cpi` | alu, load, store | yes, asserted by the probe |
| `perf02_sv39` | bare / megapage / 4 KiB translation | yes |
| `perf03_fetch` | insn32, insn16 | yes, `ITERS*3 + 2` |
| `perf04_where` | load_clint, load_dram | yes |
| `perf05_size` | 1/2/4/8-byte access | yes |
| `perf06_iws` | iws_resident (192 B), iws_exceeds (4140 B) | yes, 70001 and 65729, derived from the disassembly |
| `b0compute` / `b0array` / `b0file` | none — applications | **no.** A user program cannot read `mcycle` without kernel changes made for measurement convenience, so IPS and CPI are **null with that reason** and wall time is reported as a separate end-to-end metric |

## What a sample must carry

Raw log, workload ELF hash, platform clock, session id, boot id where the platform has one, the
invalidation actions taken, and the attempt's outcome including failures. Attempts are never dropped:
three successes are three successes, and any failures alongside them are part of the record.
