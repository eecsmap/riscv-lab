# M2-3 coverage corrections: interrupts delivered while enabled, and a store counted exactly once

Delegation: `codex-m2-3-coverage-corrections`, after the M2-3 review returned two blocking coverage gaps.
Accepted runs: `run-a` (the new coverage) and `gate` (the full M2-3 gate re-run under the same sources).
Independent re-derivation: `src/check-m2-3-fixes.py` and `src/check-m2-3.py`.
`../m2-3/src`, `../m2-3/run-b` and the earlier evidence are untouched.

## What was actually wrong

**The five injection points were not five in-flight interrupt tests.** Every one of them fired before the
program had set `mstatus.MIE`, so all five accepted at the same cycle and the same `mepc`. They demonstrated
"pending while masked, taken once enabled" — worth having, but not the property the points existed to test.
The injector armed on the first matching moment, and the startup code supplies plenty of those.

The fire records in this run make the old behaviour visible rather than arguing about it. The six re-run
semantics cases that do not require enablement report `enabled=0` at cycle 6, `pc=0x80000000`: they inject
during the very first instruction of the startup code. Three others — `sem-redirect`, `sem-syncfirst`,
`sem-storeexact` — report `enabled=1`, so those three were genuine enabled deliveries all along.

**"Exactly once" for a store was inferred, not measured.** `i09` checked the final value, the interrupt count
and the global `req == resp`. A store repeated with the same value to the same address, with its response
still paired, passes all three. The comment claiming it was measured went beyond the evidence.

## The corrected boundary matrix

The injector now fires only when three things hold: the program has armed it, the CSR file reports that
`mstatus.MIE` and the line's enable are genuinely in effect, and the chosen microarchitectural moment has
occurred. Arming takes effect only once the core is back at a fetch boundary, so the arming store's own
request, response wait and writeback can never be the moment that gets injected into.

`j01_enabled_boundary` sets the enables, reads them back to prove they took, arms, and then executes one
named load — `target_insn` — which has a fetch phase, a data phase and a writeback. Each fire is recorded
with its cycle, the PC it was aimed at, the core state, the real enable bit, and the handshake context.

| point | cycle | state | pc | handshake | mepc |
|---|---|---|---|---|---|
| fetch request awaiting ready | 341 | IF_WAIT | `target_insn` | req_valid=1 req_ready=0 | `after_target` |
| fetch response outstanding | 343 | IF_WAIT | `target_insn` | req_valid=0 outstanding=1 | `after_target` |
| data request awaiting ready | 346 | MEM_WAIT | `target_insn` | req_valid=1 req_ready=0 | `after_target` |
| data response outstanding | 348 | MEM_WAIT | `target_insn` | req_valid=0 outstanding=1 | `after_target` |
| writeback, updates scheduled | 350 | WB | `target_insn` | idle | `after_target` |
| architectural boundary, updates landing | 351 | ARCH | `after_target` | idle | `after_target` |

Six distinct cycles, each with `enabled=1`. In every case the target load completed with the right value and
retired, and `mepc` is the instruction after it — never the instruction that was in flight.

The last two rows are the distinction the review asked to be made explicit. `S_WB` is where the register-file
and CSR write enables are *scheduled*; `S_ARCH` is where they are high and the values *land*, on that cycle's
closing edge. The PC has already advanced by `S_ARCH`, which is why the fire is recorded against
`after_target` there. They are separate injection points and neither stands in for the other.

The checker verifies the state, the enable, the PC, the handshake context, the retirement and the `mepc` for
each row separately, and requires the six cycles to be distinct — six moments, not one moment counted six
times. Aggregate hit counts are no longer used as evidence of anything.

## Exactly once, measured

`j02_store_once` runs a fixed 50 iterations of load-increment-store at a named address, so the expected
transaction counts are static and do not depend on when the interrupt arrives. The harness counts, for that
one address, requests, write requests, and the write side effects the memory model actually applied.

| run | interrupt arrives | req | write req | applied writes | verdict |
|---|---|---|---|---|---|
| `watch-clean` | during the store's request phase | 102 | 51 | 51 | pass |
| `watch-resp` | awaiting the store's response | 102 | 51 | 51 | pass |
| `watch-slow` | same, on a slow bus | 102 | 51 | 51 | pass |
| `watch-dup` | same as clean, with the side effect duplicated | 102 | 51 | **102** | exit 21 |

102 requests is 50 loads plus 50 stores in the loop, plus the initial store and the final checking load;
51 write requests and 51 applied writes are those 50 stores plus the initial one.

The duplicate is the point. Under `watch-dup` the memory model applies the watched write twice with the same
value, so: the final value is unchanged, the program still reports a pass, the interrupt count is unchanged,
and the global `req == resp` still holds — the bus totals are byte-for-byte identical to the clean run. The
only thing that sees it is the model's own write counter. The checker asserts all of that, so a future
version of this test cannot quietly go back to inferring exactness from the final value.

## Regression

The full M2-3 gate was re-run under these sources into `gate/`: `M2_3_DONE fails=0`, and `check-m2-3.py`
reports 0 findings, including the cross-milestone check that retirement counts still match the accepted M2-2
evidence (84 / 75 / 94 / 79). The synchronous-exception-first, MRET re-entry and branch-target cases are
re-run unchanged and still pass; the masking test is kept exactly as it was, because masked-pending is a real
property and this work does not replace it.

`check-m2-3-fixes.py` reports 0 findings on `run-a` and 157 on the old `../m2-3/run-b`, where none of the
fire records or watched-address counts exist.

## Also corrected

The comments in `tcpu_csr.v` and `tcpu_core.v` that still described CSR and register-file updates as landing
in the same cycle as `S_WB` were wrong in the way the review described. They now say what the hardware does:
the enables are registered in `S_WB`, they are high during `S_ARCH`, and the values land on that cycle's
closing edge. "Atomic" is a claim about the values — the write and the destination value derive from one
combinational read — not about the cycle they are scheduled in.

The over-claim in the M2-3 report about five in-flight injection points, and the `i09` comment about exactly
once being measured, are superseded by this document rather than edited out of the old one.

## Evidence

    run-a/   the new coverage: fire records, watched-address counts, logs, exit codes, ELFs, symbols, hashes
    gate/    the full M2-3 gate re-run under the same sources
    src/     sources, tests and all four scripts, with SRC.sha256

Identity chain: `src/SRC.sha256` -> `run-a/source.sha256` and `gate/source.sha256` (both verified equal to
the snapshot and to each other) -> `sim.sha256` -> `elf.sha256`. Tool versions in `tools.txt`.

    teaching-cpu-work/cpu/run-m2-3-fixes.sh <newdir>
    teaching-cpu-work/cpu/check-m2-3-fixes.py <newdir>

## What this still does not show

- The test interrupt controller remains a harness model: nothing here tests CLINT or PLIC wiring, and no
  claim is made that the original BootROM or `hello` will run.
- No asynchronous input, no M or C extension, no S/U, no MMU, no PMP, no delegation.
- The ELF is still pre-loaded through a backdoor port, not booted from ROM.
- Not connected to the M1 bridge or the SoC; nothing has been near a board.
