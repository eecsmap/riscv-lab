# CPU-A stage 1 — atomic backend, reservation and V2 bridge: report (after two reviews)

Claude, 2026-09-19. Delegation `codex-cpu-atomic-backend` (acked) → first review (`CODEX_REVIEW.md`:
R1/R2/R3 blocking) → `codex-cpu-atomic-backend-fixes` (acked) → second review (`CODEX_REVIEW_2.md`: R2 and
R3 accepted, 1216/1216 hashes and all 24 scenarios and 9 self-tests independently reproduced; one item
returned — the CPU request's *semantics* were not bound to the TileLink mapping) →
`codex-cpu-atomic-request-binding-fix` (acked), delivered here. This report replaces the run5 and run8
reports; every earlier run stays on disk unchanged (section 6). Deliverables: `DESIGN.md` (corrected, sections 1, 2,
5 marked), this report, the isolated Scala files in `teaching-cpu-work/fpga-zynq/common/src/main/scala/
teaching/` — `PhysPortV2.scala`, `AtomicBackend.scala`, `RD2BridgeV2.scala`, `AtomicTest.scala` (unit
harness), **new** `AtomicHub.scala` (the insertion at the coherence-manager hook), **new** `AtomicSoc.scala`
+ `atomic_soc_main.cpp` (the real-topology harness) — `scripts/atomic-run.sh`, `scripts/score.py`,
**new** `scripts/score-selftest.sh`, the run directories, `HASHES.txt`. The active CPU, the V1 bridge, the
default/RD2/teaching SoC configurations, the boot software and the rocket-chip library are untouched
(`WithAtomicHub` is mixed only into the `AtomicSoc*` configurations); nothing was synthesised.

## 1. What changed for the returned item — the CPU's request is the source of truth

Codex's counter-examples (`codex-review/fixed/wrong-request-*`): mutate only the `CPU_REQ` lines of a good
log — replace every AMO operand with `0x123456789abcdef0`, or turn every AMO code into SWAP — leave the
TileLink trace, the memory trace and the responses untouched, and the old scorer still returned
`score=0 fails=0`. It took the AMO's operation and operand from `A_ACC`, i.e. from the bridge it was meant
to be checking, so a bridge that mapped ADD to SWAP or shipped the wrong operand would have been believed.

`score.py` now **freezes the CPU request** at `CPU_REQ` (address, size, write, AMO code, `lrsc`, `wdata`,
`wmask`) and derives everything else from it:

* **Legality** from the V2 contract itself — alignment; exact byte lanes for an atomic or an SC, a non-empty
  subset of them for a plain store; the kind combination (an AMO writes and its code is known, LR reads, SC
  writes, never both, `lrsc ≠ 3`); an atomic needs size 2/3 inside the declared DRAM region. The bridge's
  printed `legal` is compared against this, never used as the truth.
* **The whole TileLink mapping** — opcode, param, size, address, operand, byte lanes — computed from the
  request (the contract's table: SWAP→Logical 3, ADD→Arithmetic 4, XOR→Logical 0, AND→Logical 2, OR→Logical 1,
  MIN/MAX/MINU/MAXU→Arithmetic 0/1/2/3; LR→Get, SC→Put with the request's data and mask) and compared field
  by field with the single `A_ACC` accepted from the announced CPU source range.
* **The model then computes from the frozen request**, not from the bridge's A: the AMO's new word, the
  returned old value, the SC decision and the memory image all follow what the CPU asked for.
* **The response must follow its transaction**: a legal DRAM request's `CPU_RESP` may not precede that
  transaction's `D_OUT`; the only exception is a request the drain discarded, which gets no response and is
  re-issued. A store or an SC must return no data at all.

Both of Codex's counter-examples are now rejected by name — `CPU txid=3 operand 0x123456789abcdef0 was
shipped as 0x0000000000000003` and `CPU txid=4 is a amo (amo code 1) and must map to TL opcode 3, the
accepted A is opcode 2` — and `score-selftest.sh` grew from 9 to **14** mutations: the two above plus a
wrong request size, wrong request lanes, and a response printed before its D.

A side effect worth naming: the early-SC negative (`faultMode 8`) used to be caught only by a coverage
minimum ("scfail 0 < required 4"). Now that the checker knows from the request that the transaction *is* an
SC, it is caught directly — `CPU txid=4 is a sc but the backend classified kind=0`, then `SC result
scfail=0, model says 1`.

**Two real defects injected in the bridge's RTL** (not log mutations), each a single fault that leaves the
design internally consistent — its A, the memory and its own response all agree, only the CPU's request
disagrees:

| Config | Defect | Rejected by |
|---|---|---|
| `AtomicNegAmoMapConfig` (`faultMode 9`) | an ADD is emitted as a Logical SWAP | `CPU txid=4 is a amo (amo code 2) and must map to TL opcode 2, the accepted A is opcode 3` (and the memory image) |
| `AtomicNegAmoOperandConfig` (`faultMode 10`) | the operand's two 32-bit halves are swapped | `CPU txid=3 operand 0x0000000000000003 was shipped as 0x0000000300000000` |
| `AtomicSocNegAmoMapConfig` (`faultMode 9`, real topology) | the same mapping defect through the hub | the same check, at the coherence-manager hook |

Effect of this plumbing on the normal path (`faultMode 0`): `run10/rtl-delta/normal-path-vs-run8.txt` diffs
the generated Verilog against run8's for six configurations. After dropping source-location comments and
collapsing temporary numbering, 8–14 lines differ per configuration: three are the AMO-param mux chain,
reordered because ADD moved to the head of the same lookup (identical keys and values), and the rest are
line numbers inside assertion message strings. The 19 positives re-ran clean on it.

## 2. What changed earlier for R1 — the verification chain binds requests, transactions and responses

* The bridge prints `CPU_REQ txid= addr= write= size= amo= lrsc= data= mask= legal=` when it accepts a CPU
  request and `CPU_RESP txid= data= err= scfail=` when the CPU takes the response; the backend prints
  `CPU_SOURCE lo= hi= clients=` once (the source range it found for the client named `teaching-phys`).
* `score.py` was rewritten as a replay of the *accepted* order with closure: the bridge's legality is
  re-derived per request (atomics only inside DRAM, size 2/3, alignment, `lrsc ≠ 3`); every legal request
  must produce exactly one `A_ACC` from the announced CPU range with matching kind and address, and an
  illegal one none; every `D_OUT` is bound to the single pending transaction (source, error, data on the
  lanes, `scfail`); every `CPU_RESP` to its open request (txid, error, data on the request's lanes,
  `scFail`, and never `scFail` on a non-SC); the manager's write sequence equals the model's; at the end no
  transaction, request or AMO is left open; the backend's counters equal the model's; a request dropped by
  the drain must be attributed (`DRAIN_DISCARD` / `LOCAL_DISCARD` / `BUFFERED_DISCARD txid=`).
* `score-selftest.sh` applies the review's three mutations and six more to a good log (missing D, wrong CPU
  data, missing CPU response, duplicate D, wrong D source, flipped error, flipped `scfail`, missing A,
  missing `CPU_SOURCE`); each must be rejected by its named check. It runs inside `atomic-run.sh`
  (`SCORE_SELFTEST_DONE mutations=9 fails=0`).
* The runner accepts a negative only when its **declared signature** appears (a scorer message or an
  assertion text); a crash, a timeout, a missing `FINISHED` or any other reason is infrastructure and fails
  the entry point.

## 3. What changed for R2 — the real insertion point and the declared DRAM region (accepted)

* `TLBroadcast` folds every client into one named `TLBroadcast`, so the backend cannot sit after the hub.
  `AtomicHub.scala` overrides `BankedL2Key.coherenceManager` to build `AtomicBackend → TLBroadcast →
  TLWidthWidget` (the default is `TLBroadcast → TLWidthWidget`). At that point the inner edge still carries
  the system-bus clients by name; the CPU is `teaching-phys`, found by name, range printed and checked.
  Proven by elaboration and by running: `AtomicSocHarness` is a `RocketSubsystem` (AXI4 memory port, error
  slave, teaching BootROM, no tiles) with the V2 bridge and two scripted masters attached with
  `sbus.fromPort` where the CPU bridge, the TSI adapter and the DMA attach in the teaching/RD2 SoC, and
  `SimAXIMem` on the memory port. The generated chain is `sbus TLXbar → AtomicBackend → TLBroadcast →
  TLWidthWidget → MemoryBus → TLToAXI4 → SimAXIMem`. The CPU is still a transaction driver (as allowed).
* The DRAM region is declared: `AtomicBackend(dramRegion)` advertises atomics only for managers entirely
  inside it that support Get+PutFull; `RD2BridgeV2(atomicRegion)` accepts an atomic only inside it *and*
  where the target advertises the operation; `lrsc = 3` and AMO-with-LR/SC are refused. The unit harness
  now has an MMIO manager (0x6000_0000) that *does* advertise atomics: the bridge refuses AMO/LR/SC to it
  with zero requests (a `VIOLATION` line would be printed if one reached the bus; none did).

## 4. What changed for R3 — backpressure, write-phase errors, drain by events (accepted)

* `V2Driver.resp.ready` can be stalled (`respStall`) or LFSR-random (`respRandom`); `TLPutter` D stalls;
  `TLDelayer` on both sides of the crossbar; `AtomicManager` D stalls. The `Bp*` configurations run the
  AMO race, both LR/SC scenarios, the errors and a drain under these; a held response (including an SC's
  `scFail`) must still match the model when the CPU finally takes it.
* A **write-only error region** (`W`, mask 0x400: reads fine, writes refused): an AMO there reads
  successfully, its Put is refused once and the AMO ends with one error response and no second Put; an SC
  there is decided "ok" (reservation valid), its Put is refused once, one error response; the scorer
  checks "no retry" and the refusal count (`--expect-wrefuse 2`).
* Drain scoring is by events: `HOLD_ASSERT < the AMO's final D_OUT ≤ DRAIN_DONE ≤ HOLD_RELEASE`, no CPU
  `A_ACC` while held, no `CPU_REQ` while held (a request in the release cycle is after the release), at
  least one attributed discard.

## 5. Results — `run10/` (`ATOMIC_RUN_DONE scenarios=27 infra=0 score_fails=0`)

Each scenario: sbt generation of its own configuration under the `fpga-zynq-build-sbt` lease, Verilator,
the run, the replay score; inputs hashed per scenario. Counts below are the scorer's model counts; the
backend's own counters must agree (checked).

| Scenario | Config | Result |
|---|---|---|
| amo-basic | `AtomicAmoBasicConfig` | 28 AMOs (× d/w, both halves, sign extension, −1), 33 CPU transactions, 30 manager writes = model |
| amo-race | `AtomicAmoRaceConfig` | 16 AMOs vs 16 external writes after each CPU A; 34 writes = model; every old value per the accepted order |
| amo-partial | `AtomicAmoPartialConfig` | 12 `.w` AMOs, 6 SC ok, 10 external transfers incl. 2-beat 16-byte Puts (beat 1 at base+8) and PutPartial masks |
| lrsc-basic | `AtomicLrscBasicConfig` | 5 SC ok / 7 SC fail: consume, newer LR, own store, trap pulse, plain reads keep, `.w` halves |
| lrsc-race | `AtomicLrscRaceConfig` (latency 30, stall 12) | 4 kills, 4 SC fail, 2 SC ok; writes offered during the LR are accepted after its D and kill the reservation before the SC |
| errors | `AtomicErrorsConfig` | 9 local refusals (ROM ×3, 2-byte, misaligned, MMIO ×3, `lrsc=3`), 3 manager refusals (1 store into E, the AMO's Put and the SC's Put into W), 1 SC fail (LR into E), no Put after a read error, 2 memory writes = model |
| progress | `AtomicProgressConfig` | 32 SC ok around 30 external writes, 66 CPU transactions |
| drain-getd / drain-putd / drain-resp | soft reset in GetD / PutD / Resp | 7 AMOs (one drained and re-issued), attribution `DRAIN_DISCARD txid=`, ordering by events |
| bp-amo / bp-lrsc / bp-lrsc-basic / bp-errors / bp-drain | the `Bp*` configs (delayers, D stalls, stalled/random `resp.ready`) | the same model counts as their base scenarios, clean |
| soc-amo-race / soc-lrsc-race / soc-partial / soc-errors | `AtomicSoc*Config` — the real topology (§3), `--soc` scoring | 16 AMOs / 4 kills + 4 SC fail + 2 SC ok / 12 AMOs + 6 SC ok with 2-beat Puts / 10 local refusals (incl. the unmapped MMIO load) + 3 SC ok; every LR/AMO/load value equals the replay of the accepted order through TLBroadcast, the width widget, TLToAXI4 and SimAXIMem |

Negatives — each accepted only by its declared signature (`atomic-run.sh` prints the matching line):

| Negative | Defect | Declared signature (matched) |
|---|---|---|
| neg-readerr-writes | `faultReadErrWrites` (the automata behaviour) | `AMO Put issued after its Get returned an error` |
| neg-no-kill | `faultNoKill` | `SC result scfail=0, model says 1` |
| neg-wrong-source | `faultWrongSource` (a typed source id) | `the backend classified source 2 cpu=0, the announced CPU range is [2,3)` (the run also aborts on the mark assertion; that abort is *not* what counts) |
| neg-sc-early | bridge `faultMode 8` (the SC decided at the bridge) | `SC result scfail=0, model says 1` — now reached through the request binding (`CPU txid=4 is a sc but the backend classified kind=0`), no longer through a coverage minimum |
| neg-amo-map | bridge `faultMode 9`: an ADD emitted as a Logical SWAP | `CPU txid=4 is a amo (amo code 2) and must map to TL opcode 2, the accepted A is opcode 3` |
| neg-amo-operand | bridge `faultMode 10`: the operand's halves swapped | `CPU txid=3 operand 0x0000000000000003 was shipped as 0x0000000300000000` |
| soc-neg-no-kill | `faultNoKill` in the real topology | `SC result scfail=0, model says 1` |
| soc-neg-amo-map | `faultMode 9` in the real topology | the same mapping check, through the hub |

The scorer against mutated logs, inside the same entry point: `SCORE_SELFTEST_DONE mutations=14 fails=0`.

Unchanged paths, measured in the previous round on the unchanged simulators (regression only — not evidence
for the new path): the four M3 boot programs on the CPU-SV39 SoC simulator (`m3-boot-gate-fixed/`,
`RD2_BOOT_GATE_DONE programs=4 fails=0 infra=0`); the V1 bridge 13-case regression, production
`ReqRespToTL` and the RD1 bridge (`v1-regress13-fixed/`, `RD1_REGRESS13_DONE production=0 rd1bridge=0`).
They were not re-run for this round: neither touches `RD2BridgeV2`, and the only RTL edit here is the
negative-control plumbing, whose effect on the normal path is the diff in `run10/rtl-delta/`.

## 6. Runs that failed, kept

* `run1/`, `run2-aborted-loop/`, `run3/`, `run4/`, `run5/` — the pre-review runs (run5 = the reviewed
  delivery); `codex-review/` — Codex's replay and mutations.
* `run6/` — the first full run after the fixes (`score_fails=7`): the drain scenarios flagged a `CPU_REQ`
  in the same cycle as `HOLD_RELEASE` (event order within a cycle, scorer fixed); the errors scenarios
  flagged legal loads to the ROM/MMIO managers that never pass the backend (they hang off the crossbar —
  scorer taught that only DRAM passes the hook, in both harnesses); the unmapped MMIO load refused locally
  in the subsystem; and **a real finding**: the 2-beat Puts. `SimAXIMem` lands beat 1 at base+8, while the
  scorer *and* the unit harness's `AtomicManager` wrote every beat to the base address — they agreed with
  each other and were both wrong; the unit runs could not see it. Both fixed (`aBeat` in the manager; the
  scorer's `A_BEAT` at base + 8·n); the SoC logs then replay clean and the unit runs were repeated.
* `run7-aborted-fwdref/` — a Scala forward reference in that manager fix (aborted at the first generation).
* `run8/` — the delivery Codex reviewed the second time: 24 scenarios clean, but two of its counter-examples
  (mutating only `CPU_REQ`) passed the scorer. The whole set was re-run after the request binding went in.
* `run9/` — the first run with the request binding: every scenario behaved as intended, but the runner
  refused to count `neg-amo-map` and `soc-neg-amo-map` (`score_fails=2`) because the signature I declared for
  them was written in the wrong direction — "must map to opcode 3, accepted A is opcode 2", which is the
  *log-mutation* case; the injected RTL defect says the opposite ("amo code 2 … must map to opcode 2, the
  accepted A is opcode 3"). The rule worked as designed: a wrong expectation fails the entry point instead
  of quietly passing. The signature was corrected and the full set re-run as `run10/`.

## 7. Not claimed

For an address no manager covers in the subsystem harness (the unmapped MMIO probe), whether the bridge
refuses locally depends on manager coverage, which the checker does not model; there the printed `legal` is
taken as given and only the structural rules are enforced (a refused request issues nothing and is answered
with `error`; an accepted one has exactly one transaction and one response). Everything else — alignment,
lanes, kind combinations, the DRAM region — is re-derived.

The core's AMO/LR/SC instructions, exceptions, `misa.A`; the R-BOOT configuration with the hub (the
RD2/teaching SoC configurations do not include `WithAtomicHub`); the source mapping *after* the hub is
unchanged and untested beyond what the SoC runs exercise; xv6; synthesis. The PS's own DDR accesses stay
outside any hardware serialisation. MMIO and ROM atomics are unsupported (refused at the bridge).
