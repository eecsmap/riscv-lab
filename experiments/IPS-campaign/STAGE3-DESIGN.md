# Stage 3 design — the instruction cache, written before the implementation

Required by `codex-ips-four-stage-campaign`, the same way stage 2's was. Nothing in `rtl/` has been
changed for stage 3 when this is written; `ips-cache` does not exist yet.

Frozen geometry: **1 KiB, direct mapped, 16-byte lines, physically tagged, blocking, sequential refill
over the existing interface.** 64 lines. Instruction side only — no D-cache, no write-back, no
prefetcher, no extra outstanding requests, no change to atomic or data-memory ordering.

## Where it sits, and why that is the only safe place

**After translation and after the permission check.** The cache is indexed and tagged by *physical*
address, and a lookup happens only once `tcpu_xlate` has returned a PA with no fault.

This is not a preference. A virtually-indexed lookup that raced the translation would have to decide
what to do about a page that turns out to be unmapped, unreadable or not executable — and the only
answers are to fetch something it was not allowed to fetch, or to unwind. Putting it behind
`tcpu_xlate` means a line is only ever filled from an address the architecture has already agreed the
instruction stream may read. That is what *"cache only validated executable RAM accesses after
translation/permission checks"* has to mean in a design with one memory port.

Consequence, stated plainly: a hit still costs a translation. The TLB is what makes that cheap, which
is why the stages are in this order.

## What is cacheable

| range | cacheable | why |
| --- | --- | --- |
| DRAM, `0x8000_0000`+ (through the adapter's window) | **yes** | ordinary memory |
| CLINT, `0x0200_0000`–`0x0200_ffff` | **no** | `mtime` changes without anyone writing it; a cached copy would be a stale clock |
| everything else | **no** | the default is *not cacheable*, so a region nobody thought about is not silently cached |

A non-cacheable address is passed straight through as the single access it already was. **No line is
read.** That is the whole of *"bypass without speculative line reads or side effects"*: a 16-byte
refill next to an MMIO register could touch a neighbouring register with a side effect, and a refill
that crosses into an adjacent page could generate a transaction to a page the access was never
permitted.

**A refill never crosses a line boundary**, and a 16-byte line inside a 4 KiB page cannot cross into
the next page — so *"no new transactions to adjacent inaccessible pages"* follows from the geometry
rather than from a check that could be wrong.

## Line and tag

| field | width | note |
| --- | --- | --- |
| `valid` | 1 | per line |
| `tag` | PA[31:10] | 22 bits: physical, above the 64-line index |
| index | PA[9:4] | 64 lines |
| offset | PA[3:0] | 16 bytes |
| data | 128 bits | two 64-bit beats, filled sequentially |

Direct mapped, so there is no replacement policy to choose: index decides, and a conflict evicts.
That is deliberate for a first cache — the eviction pattern is then a property of the addresses alone,
which a measurement can reason about.

## Refill, and what must never become visible

Blocking: a miss stalls the fetch until the line is present. Two sequential 64-bit reads at
`{tag,index,4'b0000}` and `+8`.

* **A failed refill leaves NO valid line.** `valid` is written on the *last* beat, and only if no beat
  reported an error. A partially filled line that was marked valid would serve half a line of
  whatever the bus returned.
* **The faulting access keeps its own fault.** If a refill beat errors, the instruction access raises
  the access fault it would have raised without a cache, with the same `tval` — the cache changes when
  memory is read, never what a fault means.
* **`fence.i` invalidates every line**, in one cycle, and an in-flight refill started before the
  `fence.i` is **abandoned**: its beats are consumed and discarded rather than written. Otherwise a
  refill issued before a self-modifying store could land after it and make a stale instruction
  visible — which is precisely the case `fence.i` exists to prevent.
* **Reset invalidates every line.** So does the host loading a new program: the harness holds the CPU
  in reset while it writes memory, and reset is what clears the cache, so an image loaded over a
  previous one cannot be executed from stale lines. The test below proves that rather than assuming it.

## The disabled configuration

`ICACHE_BYTES = 0` removes it: every fetch goes to memory as it does on `ips-tlb`, and the campaign
will require **identical cycle counts** on the frozen probe set between the disabled cache and the TLB
stage. That is the same test `TLB_ENTRIES=0` gets in stage 2.

## What must be observable

No hardware counter exists. `EVA:AR` in the harness trace counts external AXI reads exactly, and
`trace_aggregate.py` already aggregates it — the same mechanism stage 1 needed and stage 2 uses for
walks. So:

* `perf06_iws`'s **resident** ROI (192 bytes, 0.19x of 1 KiB) must show **far fewer** external reads
  than on `ips-tlb`;
* its **exceeds** ROI (4140 bytes, 4.04x) must still be **correct**, and is expected to show little or
  no saving — a direct-mapped 1 KiB cache conflicts on every pass through it. If it shows a large
  saving, the probe is not doing what it claims and the number is not a cache result.

The two ROIs were measured identical on `ips-baseline` and on `ips-fetch32` — 19.02 and 11.00 CPI
alike — so any divergence at this stage is attributable to the cache and to nothing else. That control
is why `perf06` was written in stage 0 rather than here.

## Tests that must fail for the right reason

Named before the implementation exists:

| mutant | must be caught by |
| --- | --- |
| a line is marked valid on the first beat | a refill whose second beat errors, followed by a fetch from that line |
| `fence.i` does not invalidate | a self-modifying-code probe: write an instruction, `fence.i`, execute it |
| an in-flight refill survives `fence.i` | the same probe with the store timed inside the refill window |
| MMIO is cached | a loop reading `mtime` through the fetch path is not applicable; instead a **cacheability** unit test on the decode, plus `perf04`'s CLINT ROI showing no change |
| the cache is indexed before the permission check | an unmapped page adjacent to a resident line, fetched after a `sfence.vma` |
| reset does not invalidate | two programs loaded in succession, the second at the same addresses with different instructions |

## Status

**Design only.** No RTL written, no branch created.
