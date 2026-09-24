# Stage 2 design — the TLB, written before the implementation

Required by `codex-ips-four-stage-campaign`: *"Document entry fields, replacement, supported page sizes
and permission check location before implementation."* Nothing in `rtl/` has been changed when this is
written.

Branch `ips-tlb`, from `ips-fetch32`. Frozen geometry: **8 entries, fully associative, shared between
instruction and data accesses.** No sweep.

## What the baseline does, and therefore what must not change

`tcpu_ptw.v` walks Sv39 serially: one 8-byte PTE read per level over the core's single physical port,
which the core hands to the walker while `busy`. Its verdict on a leaf is **not** a property of the
PTE alone. It is computed from the PTE bits *and* from the access:

```
perm_rwx = fetch ? X : load ? (R | (MXR & X)) : AMO ? (R & W) : W
perm_u   = (priv == U) ? U : fetch ? !U : (!U | SUM)
perm_ad  = A && (store/AMO -> D)
```

`acc_type`, `eff_priv`, `SUM` and `MXR` all vary from one access to the next against the same page.

**Therefore the TLB caches the PTE, never the verdict.** An entry stores the permission bits and the
identical expression is evaluated on every hit, with that access's own type, privilege, SUM and MXR.
There is no path on which a hit skips a permission check — that is the whole of "do not bypass
permissions", and it is the one thing a targeted test must be able to catch.

## Entry fields

| field | width | why |
| --- | --- | --- |
| `valid` | 1 | |
| `vpn` | 27 | `va[38:12]`; the comparison is masked by `level` |
| `level` | 2 | 0 = 4 KiB, 1 = 2 MiB, 2 = 1 GiB. Needed to rebuild the PA exactly as `leaf_pa` does, and to mask the tag compare |
| `ppn` | 44 | the leaf PTE's PPN, unmodified |
| `r w x u a d` | 6 | the PTE permission bits, **re-evaluated per access**, never pre-judged |

No ASID field and no G bit: see invalidation below. Nothing derived is stored — no pre-computed PA, no
pre-computed verdict — so there is nothing that can go stale independently of the PTE bits it came from.

## Page sizes

All three the walker supports: 4 KiB, 2 MiB (level 1), 1 GiB (level 2).

A superpage entry matches on the bits above its own boundary and supplies the rest from the virtual
address, exactly as `leaf_pa` does:

| level | tag compared | PA |
| --- | --- | --- |
| 0 | `vpn[26:0]` | `{ppn, va[11:0]}` |
| 1 | `vpn[26:9]` | `{ppn[43:9], va[20:0]}` |
| 2 | `vpn[26:18]` | `{ppn[43:18], va[29:0]}` |

`misaligned_super` is checked by the walker before an entry is ever filled, so a misaligned superpage
faults and is never cached.

## Replacement

**Round-robin over the 8 entries**, a 3-bit counter advanced on each fill.

Not pseudo-LRU: this is a teaching core and a measurement platform, and round-robin is deterministic —
the same program produces the same fills in the same order, which is what makes a cycle count
reproducible and a regression legible. The cost is that a pathological access pattern evicts a hot
entry; with 8 fully associative entries and the workloads frozen for this campaign, that is a trade
worth stating rather than hiding.

## Where the permission check happens

In the core, on the hit path, using the **same expressions** as `tcpu_ptw.v` — not a copy that can
drift, but the identical logic factored so both use it. A hit therefore produces one of:

* a physical address, when the check passes;
* a **page fault of the access's class** (12 fetch / 13 load / 15 store-AMO), when it does not —
  the same cause the walker would have raised, with the same `tval`.

A/D is part of that check: A/D are software-managed here, so an entry with `A=0`, or `D=0` for a store,
**faults on every hit**. It is not refilled and not repaired, because that is what the walker does.

## Invalidation

**Conservative full flush.** Every `sfence.vma`, whatever its `rs1`/`rs2`, and every write to `satp`,
invalidate all 8 entries in one cycle.

* **ASID**: not stored. A `satp` write changes the address space and flushes everything, so an entry
  can never outlive the address space it was filled in.
* **Global (G)**: not stored and not honoured as an optimisation. Flushing everything is strictly more
  conservative than preserving global entries would be.
* **Reset**: all entries invalid.
* **A failed walk fills nothing.** Only a walk that produced a PA is cached.

This is more flushing than the architecture requires. It is the right default for a first TLB: the
failure mode of over-flushing is a slower machine, and the failure mode of under-flushing is a wrong
one.

## The disabled configuration

A parameter reduces the TLB to zero entries, in which case every access walks and the core is
**architecturally equivalent to `ips-fetch32`**. That is a test, not a feature: the campaign will run
the fetch32 probe set against the disabled configuration and require identical cycle counts.

## What must be observable

The design has no hardware counter for walks. The harness's per-event trace has one: a PTE read is a
`REQ` the walker issues, and `trace_aggregate.py` already counts `EV:REQ` and `EVA:AR` exactly. So
"fewer walks on repeated hits, and a re-walk after invalidation" is measured from the trace rather than
asserted — the same mechanism stage 3 will use for external instruction reads.

## Tests that must fail for the right reason

Written before the implementation, so they cannot be shaped to it:

| mutant | must be caught by |
| --- | --- |
| a hit skips the permission re-check | a U-page accessed from S without SUM, hitting after a legitimate S access to the same page |
| a hit ignores A/D | a store to an entry with `D=0` that faulted on the walk |
| `sfence.vma` does not flush | a page-table edit followed by `sfence.vma`, then an access that must see the new mapping |
| a `satp` write does not flush | the same VA mapped differently in two address spaces |
| a superpage entry compares the full VPN | two 4 KiB pages inside one 2 MiB superpage |
| a failed walk fills an entry | a faulting access repeated — the second must fault for the same reason, not hit |

## Implementation

| file | what |
| --- | --- |
| `rtl/cpu/tcpu_permcheck.v` | **new** — the Sv39 leaf permission check, in one place |
| `rtl/cpu/tcpu_tlb.v` | **new** — 8 entries, fully associative, round-robin, `ENTRIES=0` disables |
| `rtl/cpu/tcpu_xlate.v` | **new** — the TLB in front of the walker, presenting the **walker's own interface** |
| `rtl/cpu/tcpu_ptw.v` | uses `tcpu_permcheck`; exposes the leaf PTE it used, written only on a successful walk |
| `rtl/cpu/tcpu_core.v` | instantiates `tcpu_xlate`, adds `TLB_ENTRIES` and the flush condition |

**`S_XLATE` in the core is unchanged.** It still pulses `start`, waits for `done`, and reads
`fault`/`cause`/`pa`; a hit simply answers in one cycle without touching the memory port. That keeps
the stage's blast radius at the translation unit rather than the state machine.

The extraction of `tcpu_permcheck` from `tcpu_ptw` was proved **exhaustively equivalent over all 4096
inputs** — `tests/tlb-tb/permcheck_equiv_tb.v`, whose reference is a transcription of the original
expression and must never be edited to match the module. A mutated module is caught at input 12.

## Component tests — PASSED

`tests/run-tlb-tb.sh <outdir>`: **31 checks, 0 fails**, covering 4 KiB / 2 MiB / 1 GiB matching,
the permission bits coming back rather than a verdict, flush, round-robin eviction order, the disabled
configuration, and the permission truth table including SUM, MXR and A/D.

Checked against five mutants, each caught by the right test:

| mutant | caught by |
| --- | --- |
| the A/D check dropped | store with `D=0`, store with `A=0`, load with `A=0` |
| SUM allowed to permit a fetch | "S never executes a U page" |
| a superpage compares the full VPN | a 4 KiB page 1.3 MiB inside a 2 MiB entry |
| flush does not clear | a previously hitting address after flush |
| replacement always writes entry 0 | twelve checks, starting with the superpage cases |

## Targeted probe — built

`workloads/tlb01_sfence.S`, built by `workloads/build-tlb01.sh`, which checks the disassembly actually
contains `sfence.vma`, a `satp` write, an `stvec` write and `sret` rather than trusting the source.

Each case is built so only a defect in the **hit path** can pass it:

* **A** — a page is cached by a successful load, its PTE is edited to drop W, `sfence.vma` is issued,
  and a store must now fault. A flush that did nothing leaves a stale entry that still says W.
* **B** — a page with `A=1, D=0` is cached by a successful **load**; a **store** must then fault. The
  walker cannot catch this: the walk already happened and already passed, for a load.
* **C** — `satp` is pointed at a second root table where the alias is **invalid**, with no
  `sfence.vma`. An access must fault; a stale entry from the first address space would hit.

## Status

**IMPLEMENTED**, component-level **SIM-VERIFIED**. The SoC regression, the targeted probe's execution,
the disabled-configuration equivalence and the walk-count observation have not been run — one heavy
simulation at a time, and the stage 1 xv6 run holds that slot.
