# CPU-A stage 1 — the atomic/reservation backend and the V2 bridge: design

Delegation `codex-cpu-atomic-backend` (first review 2026-09-19, `CODEX_REVIEW.md`, R1–R3) and its fix
delegation `codex-cpu-atomic-backend-fixes`; contract `cpu-atomic-prep/CONTRACT.md` as ruled in
`cpu-atomic-prep/CODEX_DECISIONS.md` (A1–A6 and the six semantic corrections). This stage adds isolated
Scala modules, a unit harness and a real-topology harness; the active CPU, the V1 bridge, the default
configurations and the boot software are untouched. Sections 1, 2 and 5 were corrected after the review;
the corrections are marked.

## 1. Where the backend sits (corrected, R2)

The subsystem's *coherence manager* is the hook between the system bus and the memory bus
(`BankedL2Key.coherenceManager`); the default builds `TLBroadcast → TLWidthWidget` there. `TLBroadcast`'s
`clientFn` folds every system-bus client into one client named `TLBroadcast` (`rocket-chip/tilelink/
Broadcast.scala`), so anything placed *after* the hub cannot tell the CPU from the TSI adapter or the DMA.
The backend therefore sits **before** the hub, as the first element of the coherence manager:

```
CPU ──PhysPortV2──> RD2BridgeV2 ──TL──> [RD2Watch/Throttle] ──> sbus TLXbar <── TSI SerialAdapter
                                                                        <── BlockDevice DMA
   sbus ──> **AtomicBackend** ──> TLBroadcast ──> TLWidthWidget ──> MemoryBus ──> TLToAXI4 ──> AXI4 HP0 / SimAXIMem
   RD2BridgeV2 ══ side-band (mark / resv_clear / sc_result) ══ AtomicBackend
```
`WithAtomicHub` (`AtomicHub.scala`) overrides only that hook; every other configuration keeps the default
chain. At this point the inner edge still carries the system-bus clients by name, so the CPU is found as the
client named `teaching-phys` (the bridge's own name) and its source range is printed once (`CPU_SOURCE lo=
hi= clients=`); the scorer re-derives every `cpu=` classification from that announcement. The path from the
hook to DRAM is the generated one (TLBroadcast, width widget, memory bus, TLToAXI4); only DRAM traffic
passes the hook — the ROM, the error slave and MMIO are served from the system/peripheral bus and never see
the backend, which is exactly the ruled "DRAM only" boundary.

The DRAM region is **declared**, not inferred: the backend advertises atomics only for managers that lie
entirely inside `dramRegion` (from `ExtMem`) and support Get + PutFull, and the bridge accepts an atomic
only if the address is inside its own `atomicRegion` (the same `ExtMem` range) *and* the target advertises
`Arithmetic`/`Logical` for that size. Capability alone is not a whitelist (R2): the unit harness's MMIO
manager advertises atomics and the bridge still refuses AMO/LR/SC to it (`VIOLATION` if one ever reached
the bus). `lrsc = 3` is reserved and refused.

The PS's own DDR accesses stay outside any hardware serialisation (a platform rule).

## 2. AtomicBackend (TL adapter node, ours)

* **Advertises** `supportsArithmetic/Logical = TransferSizes(4, 8)` for DRAM managers only (section 1).
* **Strictly serial**: one transaction at a time, of any kind, from any master; `in.a.ready` is high only in
  `IDLE` (a multi-beat Put is one transaction, `IDLE → PASS` until its last A beat and its D). Transactions
  complete (final D) in the order they were accepted. Performance is not a goal. **Consequence for the
  wording (corrected)**: while an LR's read is pending no other transaction is *accepted*; an external write
  arriving then is *offered* (its `a.valid` is high and waits), is accepted after the LR's D, and kills the
  reservation at *its* acceptance — before the SC can be accepted. The "write during the LR" races in the
  scenarios are races between an offered write and the CPU's SC, and the scorer judges them by the order
  actually accepted (`A_ACC` order), not by an assumed one.
* **State table**

| State | Entry | Action | Exit |
|---|---|---|---|
| IDLE | — | accept one A; classify: PLAIN (Get/PutFull/PutPartial), AMO (Arithmetic/Logical), SC (a Put carrying the CPU mark `sc`), LR-Get (a Get carrying the CPU mark `lr`) | PLAIN/LR → PASS; AMO → GET; SC → SC_CHECK |
| PASS | plain or LR | forward the A beats to `out.a`; forward `out.d` to `in.d` unchanged | last D beat → IDLE (an LR whose D has `error` clears the reservation) |
| GET | AMO accepted | issue `Get(addr, size)` on `out.a` with the AMO's source | D returns: `error` → RESP_ERR; else latch old data → PUT |
| PUT | old data | compute `new = op(old, operand)` on the request's byte lanes (sign-extended operands for signed min/max, `.w` on the addressed half); issue `PutFull(addr, size, new)` | AccessAck → RESP_OK (with the Put's `error` if any) |
| RESP_OK / RESP_ERR | — | one `AccessAckData` to `in.d` with the AMO's source/size: data = old (RESP_OK) or 0, `error` = Put error / 1 | `in.d.fire` → IDLE |
| SC_CHECK | marked Put | if the reservation is valid and its word matches → forward the Put (`PASS`), `sc_result = ok` with its D; else **drop** it and synthesise `AccessAck(source, size)` on `in.d`, `sc_result = fail` | IDLE; the reservation is cleared in both cases |

  The read-error rule is in `GET`: an error on the Get ends the AMO with one error response and **no Put**
  (*ruled 1*). A Put-phase error (a write-only fault, R3) is reported once in the final response; no retry,
  no second Put.
* **Reservation** (one, for the CPU source): `{valid, word[31:3]}`.

| Event | Effect |
|---|---|
| CPU LR accepted (marked Get) | `valid ← 1, word ← addr[31:3]` (a candidate from the moment of acceptance) |
| any write-class A (Put*/Arithmetic/Logical) from a **non-CPU** source whose byte range `[addr, addr+2^size)` overlaps the word — evaluated at *its* acceptance (which, by seriality, is after the LR's D) | `valid ← 0` |
| CPU Put/AMO to the word (a marked SC or a plain store) | `valid ← 0` (an SC to any address also clears it) |
| LR's D returns `error` | `valid ← 0` |
| side-band `resv_clear` (core trap or reset, forwarded by the bridge) | `valid ← 0` |
| node reset | `valid ← 0` |
| plain Gets from anyone, page-table reads, fetches | no effect |

* **Side-band** (bridge ↔ backend, same clock domain, transaction-bound) — **corrected**: `mark` is a depth-1
  *registered* queue the bridge pushes **when it accepts the CPU's request** (`phys.req.fire && legal`) for
  an LR or SC (`{lr, sc}`), not at the TileLink A handshake: with one outstanding CPU request the marked A is
  the next A the bridge offers, and the mark is visible one cycle later at the latest, before that A can be
  accepted (the first attempt, pushing at the A handshake through the combinational crossbar, made the mark
  invisible in the same cycle, and a flow-through queue closed a combinational loop — `REPORT.md` 2b). The
  backend pops it when it accepts an A from the CPU's source. Asserted: the queue never overflows, a CPU A
  with a mark present is the marked one, a CPU A without a mark is plain, the queue is empty whenever the
  CPU has nothing outstanding. `sc_result`: `Valid(fail)` in the cycle the SC's D is handed to the inner
  side; the bridge binds it to its one outstanding SC and holds it in its buffered response until the CPU
  takes it (R3: return backpressure).
* **Events printed** (one line each, `AT <cycle> TAG k=v …`): `CPU_SOURCE`, `A_ACC src= cpu= op= param= addr=
  size= data= mask= kind=`, `A_BEAT`, `AMO_START/AMO_GET/AMO_PUT data=`, `D_OUT src= data= err= kind= [scfail=]`,
  `RESV set word=` / `RESV kill word= why=`, `SC_FAIL`, `SC_OK`.

## 3. PhysPortV2 and RD2BridgeV2

`PhysReqV2 = PhysReq + amo[3:0] + lrsc[1:0]`; `PhysRespV2 = PhysResp + sc_fail`; plus `resv_clear` (core →
bridge, level pulse). A V1 request is a V2 request with `amo = 0, lrsc = 0`. AMO codes: 1 SWAP, 2 ADD, 3 XOR,
4 AND, 5 OR, 6 MIN, 7 MAX, 8 MINU, 9 MAXU → TL `Logical(SWAP/XOR/OR/AND)` and `Arithmetic(ADD/MIN/MAX/MINU/
MAXU)`; the operand travels in `wdata` on the address's lanes with `wmask` = those lanes.

Bridge legality (before any TL request; `error` back otherwise, nothing on the bus): AMO/LR/SC ⇒ `size ∈
{2,3}`, aligned, `wmask` = exactly the lanes, address inside the declared `atomicRegion`, target advertises
`Arithmetic`/`Logical` for the size, `lrsc ≠ 3`, not AMO-and-LR/SC together; anything else is the V1 rule.
The bridge issues Get (LR) / Put (SC) with the mark, `Arithmetic/Logical` for AMOs, returns `rdata` = the
D's data (old value) for an AMO/LR, `sc_fail` from `sc_result` for an SC, `error` from the D, and prints
`CPU_REQ txid= addr= write= size= amo= lrsc= data= mask= legal=` / `CPU_RESP txid= data= err= scfail=` so the
scorer can bind every CPU request to its one TileLink transaction and its one response (R1). The drain
contract is the RD1 one, unchanged: an AMO is one request with one final D — nothing is released on the
read half; a request dropped by the drain is attributed (`DRAIN_DISCARD` / `LOCAL_DISCARD` /
`BUFFERED_DISCARD txid=`).

## 4. The unit harness

`AtomicHarness`: `mgr := delayer := backend := xbar := delayer := {bridgeV2, putter0, putter1}`, plus a
read-only ROM without atomics and an MMIO manager *with* atomics (the bridge must still refuse it).
* `AtomicManager`: 512 × 64-bit words with real storage (masks applied), programmable latency, A stalls and
  D stalls, an error region (reads and writes fail) and a **write-only error region** (reads fine, writes
  refused: the AMO's Put half and an SC's write fail once) — `MGR_WRITE/MGR_REFUSE/MGR_D` lines.
* `TLPutter`: a scripted TileLink client issuing Get / PutFull / PutPartial (single- and 2-beat) at cycles
  or on triggers ("after the n-th CPU A", "while the CPU's transaction is outstanding"), with optional D
  stalls.
* `V2Driver`: a scripted CPU stand-in on the V2 port; `resp.ready` fixed, stalled or LFSR-random (R3); under
  `cpuResetHold` it drops its in-flight step and re-issues it, as a CPU under reset does.
* `TLDelayer` on both sides of the crossbar (`delayQ` configurations) so A and D see independent delays.
* `score.py` replays the *accepted* order (R1): `CPU_REQ` **freezes the CPU's request semantics** — address,
  size, write, AMO code, `lrsc`, `wdata`, `wmask` — and everything downstream is derived from it:
  * **legality** from the V2 contract itself (alignment; exact lanes for an atomic or an SC, a non-empty
    subset for a plain store; the kind combination — an AMO writes and its code is known, LR reads, SC
    writes, never both, `lrsc ≠ 3`; an atomic needs size 2/3 inside the declared DRAM region). The bridge's
    printed `legal` is *checked* against this, never used as the truth.
  * **the TileLink mapping**: opcode, param, size, address, operand and byte lanes are computed from the
    request (AMO code → `Arithmetic`/`Logical` + param per the contract's table: SWAP→Logical 3, ADD→
    Arithmetic 4, XOR→Logical 0, AND→Logical 2, OR→Logical 1, MIN/MAX/MINU/MAXU→Arithmetic 0/1/2/3; LR→Get,
    SC→Put with the request's data and mask) and compared field by field with the single `A_ACC` the backend
    accepted from the announced CPU source range. **The model then computes from the frozen request**, so a
    bridge that maps ADD to SWAP or swaps the operand's halves is rejected even when its A, the memory and
    its own response agree with each other (R1 second round).
  * every `D_OUT` bound to the pending transaction (source, error, data, `scfail`); every `CPU_RESP` to the
    open request (txid, error, data on the request's lanes, `scFail`, no data at all for a store or an SC)
    and **after that transaction's D** — the only exception is a request the drain discarded, which gets no
    response and is re-issued; memory write sequence equal to the manager's; end closure (no pending D, no
    open request, no open AMO); the backend's own counters must agree; drain ordering from events
    (`HOLD_ASSERT < AMO final D ≤ DRAIN_DONE ≤ HOLD_RELEASE`, no CPU A while held, at least one attributed
    discard).

  `score-selftest.sh` mutates a good log fourteen ways and requires each to be rejected by its named check:
  missing D, wrong CPU data, missing CPU response, duplicate D, wrong D source, flipped error, flipped
  `scfail`, missing A, missing `CPU_SOURCE`, and five that change **only the request** while the bus trace,
  the memory and the answers stay identical — wrong operand, every AMO turned into SWAP, wrong size, wrong
  lanes, and a response printed before its D.

Negatives are separate variants, each rejected only by a *declared* signature (a crash, a timeout or a
missing `FINISHED` is infrastructure, never a detection): `faultReadErrWrites` (the automata behaviour),
`faultNoKill` (external writes do not clear the reservation), `faultWrongSource` (the CPU identified by a
typed source id), bridge `faultMode 8` (the SC decided at the bridge), and two **request-semantics** faults
injected in the bridge's RTL, each a single defect that leaves the design internally consistent:
`faultMode 9` — an ADD is emitted as a Logical SWAP (opcode and param wrong, everything else right) — and
`faultMode 10` — the operand's two 32-bit halves are swapped on the way out (the classic lane slip). Both
are caught by the mapping comparison and, independently, by the memory image the model computes from the
request.

## 5. The real-topology harness (R2)

`AtomicSocHarness` (`AtomicSoc.scala`): a `RocketSubsystem` with the AXI4 memory port, the error slave, the
teaching BootROM, `WithAtomicHub`, no tiles; the V2 bridge and two `TLPutter`s attached with `sbus.fromPort`
exactly where the CPU bridge, the TSI adapter and the block-device DMA attach in the teaching/RD2 SoC; the
same `V2Driver` and scripts; `SimAXIMem` on the memory port; the same event lines. No CPU instruction runs
here — that is the next stage — but the chain under test is the generated one: `sbus TLXbar → AtomicBackend
→ TLBroadcast → TLWidthWidget → MemoryBus → TLToAXI4 → SimAXIMem`. The scorer's `--soc` mode knows there is
no scripted manager (SimAXIMem answers; its `AccessAck` data is don't-care and not compared, as TileLink
says), no error regions inside DRAM, and that legal requests outside DRAM (a ROM read, an MMIO access to
nothing → the error slave) never produce an `A_ACC` at the hook.

## 6. Not in this stage

The core's AMO/LR/SC instructions, exceptions and `misa.A`; the R-BOOT SoC configuration with the hub (the
teaching/RD2 configurations are unchanged); xv6; synthesis. The PS side stays a platform rule.
