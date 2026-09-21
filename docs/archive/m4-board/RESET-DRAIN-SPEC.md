# Reset and transaction drain — specification, third draft

*Revised again after Codex's RD1 review. The bridge-local part of this specification is now implemented and
exercised: `experiments/teaching-cpu/reset-drain/rd1/`. The SoC-wide parts below (§5 domains beyond the
bridge, §7 `PL_RECONFIG_SAFE`, the serial adapter and block device) remain **proposal, not frozen**.*

Supersedes the design sketch in `.coord/proposals/claude-m4c-reset-drain-design.md` (kept verbatim; this
document states where it was wrong). Written against Codex's eight required revisions. **Nothing here is
implemented**: no RTL changed, no Vivado run, no board touched. The M4-c result stands as accepted — under
its stated condition, attempt-2 plus a ≥50 ms `SYSTEM_RESET` hold before each run — and this document does
not remove that condition.

Everything in §1 is read out of the source or the generated board RTL
(`m4-prep/gen-board-orphanfix/TeachingBoardTop.TeachingBoardConfig.v`), with citations. Everything from §2
on is proposal.

---

## 1. What the hardware actually does today

### 1.1 There is exactly one reset domain

All 17 children of `TeachingCpuZynqTop` take the module's own `reset` input:

```
cpu bridge adapter(SerialAdapter) controller(BlockDeviceController) clint plic error debug_1
sbus pbus mbus bh(TLBroadcast) Queue Queue_1     ← all .reset(<net>), every net = reset
bootrom ww int_bus                               ← no reset port (combinational)
```

and `TeachingBoardTop` drives it from the adapter register:
`assign target_reset = adapter_io_sys_reset` (`TeachingCpuSoc.scala:296`+, generated RTL).
So a PS write of `0x43C00010` bit 0 resets **the CPU, the bridge, the whole TileLink fabric, the
TL→AXI adapters, the serial adapter, the block-device controller, the CLINT and the PLIC, together**.

That single fact is the root cause. The rest of §1 is what it costs.

### 1.2 The memory path, and who else is on it

```
bridge ──► coupler_from_port_named_teachingcpu (TLBuffer_2: pass-through, 0 regs; TLFIFOFixer_1)
        ──► sbus xbar ──► master_splitter ──► coupler_to_mbus ──► mbus xbar
        ──► coupler_to_memory_controller (TLWidthWidget_1 ─ TLToAXI4 ─ AXI4IdIndexer ─ AXI4UserYanker)
        ──► mem_axi4 ──► rocketchip_wrapper ──► PS HP0 ──► DDR
```

`SystemBus` has **three** masters coupled in, not one:
`coupler_from_port_named_teachingcpu`, `coupler_from_port_named_serialadapter`,
`coupler_from_port_named_blkdevcontroller`. The CPU bridge being idle says nothing about the other two.

### 1.3 State that a soft reset destroys, per module

| module | state it holds | on `sys_reset` today | consequence |
|---|---|---|---|
| `ReqRespToTL` (bridge) | `state`, held `req` payload, `rdata/err` | cleared to `sIdle` | `tl.a.valid := state === sA` (`ReqRespToTL.scala:69`) — an **already asserted A.valid is withdrawn**, which TileLink forbids; and the D for an already-fired A is no longer accepted |
| `SerialAdapter` | `state = RegInit(s_cmd)` (`SerialAdapter.scala:52`) | cleared to `s_cmd` | `mem.a.valid := state.isOneOf(s_write_data, s_read_req)` (:78) — same irrevocability violation; `mem.d.ready := state.isOneOf(s_write_ack, s_read_data)` (:82) — its outstanding D is never accepted. **A second, independent orphan source** |
| `BlockDeviceController` | trackers, frontend, two TLBuffers | cleared | same class; unused in these tests but present in the design |
| `TLToAXI4` | `doneAW`, `r_holds_d`, `reg_error`, `idCount`, `queue_arw` | cleared | a Put whose AW was issued but whose W beats were not yet all sent is **truncated**: the AXI slave keeps waiting for `WLAST` |
| `AXI4UserYanker` | per-id queues carrying TL `source`/`size` in `user` | cleared | a returning R has **no** queue entry: `assert(!out.r.valid || r_valid)` fires in simulation; on hardware the source/size bits are simply wrong, so the beat is routed to the wrong client or dropped |
| `TLFIFOFixer_1` | `flight` vector (`FIFOFixer.scala:72`) | RegInit → cleared (optimised away in this elaboration) | ordering bookkeeping lost |
| `CLINT` | `time` (reset to 0), `ipi_0` (reset to 0), **`timecmp_0` — no reset at all** | partially cleared | already the current semantics; `boot02_clint` opens by pushing `mtimecmp` out of reach precisely because it is not reset |
| `TLPLIC` | `pending_*` | reset to 0 | — |

### 1.4 Why a single refusing master blocks everyone

`TLToAXI4` merges R and B into one D channel:

```scala
out.r.ready := in.d.ready
out.b.ready := in.d.ready && !r_wins          // ToAXI4.scala:189-191
```

`in.d.ready` is the *arbitrated* TL D readiness. A client that will not take its D therefore stalls the
single D path, and with it **every other client's responses**. That is the mechanism behind the observed
"next program produces nothing": the serial adapter's ELF-load Put never gets its AccessAck.

**Evidence status.** This chain is read from the RTL, not from a bus trace: there is no cycle-level
observability on the board. What was measured is the *behaviour* (`DIAGNOSIS.md` §4): 7/10, 5/10 and 8/12
hangs without a reset hold, 0/22 with it. The chain is the best-supported explanation, and it is labelled
as an explanation, not as a captured trace.

### 1.5 A second failure mode, worse than the orphan, that §1.3 exposes

A soft reset **between AW and the last W beat** would leave the PS AXI slave waiting for `WLAST` from a
master that no longer exists, and no drain inside the PL could supply it. This is a risk the current
structure permits; it is **not** a diagnosis of the session-3 wedge, for which no trace exists. It is listed
because a design that claims safety must prevent it, not because it was observed.

---

## 2. Definitions

* **Cold reset** — `!FCLK_RESET0_N || !mmcm_locked`, or PL reconfiguration. Everything is destroyed,
  including records of transactions the PS still has outstanding. Nothing in the PL can make this safe;
  only *not doing it while transactions are in flight* can.
* **Soft reset** — a PS write of `0x10` bit 0. The subject of this specification.
* **Epoch** — a counter, in the cold-reset domain, incremented when a soft reset is released. Every
  transaction record carries the epoch it was accepted in.
* **txid** — a monotonic transaction number in the cold-reset domain, never reset by a soft reset, unique
  per accepted CPU request.
* **Safety** — no transaction is delivered to the wrong requester, completed twice, or left half-issued on
  a protocol channel.
* **Liveness** — the drain terminates. Safety is required unconditionally; liveness is *conditional* on
  every accepted transaction eventually being answered, which the PL cannot guarantee by itself (§6).

---

## 3. The bridge, state by state (revision 1)

The sketch said "`outstanding` is one bit because the port is single-outstanding". That was wrong in the
way Codex identified: `A.fire` is not the only thing that creates work.

### 3.1 Pending work

```
pendingA     := state === sA                 // A.valid is (or is about to be) asserted, not yet accepted
outstanding  := A fired and its D has not returned
pendingWork  := pendingA || outstanding
```

`pendingA` is as un-revocable as `outstanding`: once `tl.a.valid` has been high for a cycle, TileLink
requires valid and payload to stay stable until `a.ready`. A soft reset may not clear `state`, `req`, or
the A payload while `pendingA` holds.

This is a statement about the TL A channel specifically, and about the CPU-facing port where
PHYSICAL_PORT_V1 froze the same rule ("valid and payload stable until the handshake"). It is not a claim
that every channel in the system behaves alike: what the PS AXI side does with a half-issued burst is a
separate question, treated in §4.

### 3.2 Rule table

`R` = soft reset level is asserted this cycle. `drainReq` is **sticky**: set by any cycle with `R`, cleared
only when `pendingWork` falls. A one-cycle pulse therefore cannot be missed — this is the answer to
"禁止短 reset 脉冲漏记 drain".

| bridge state at the cycle `R` first appears | TL-side action | CPU-side action | drain complete when |
|---|---|---|---|
| `sIdle` | none | `req.ready := 0` | immediately (`pendingWork = 0`) |
| `sIllegal` (rejected locally, no A) | none | discard the pending response | immediately |
| `sA`, `a.valid` asserted, `a.ready` low | **hold** `a.valid` and payload until `a.fire` | `req.ready := 0` | after `a.fire` **and** its `d.fire` |
| `sA` and `a.fire` this cycle | transaction becomes outstanding | — | after its `d.fire` |
| `sA` and `a.fire` and `d.fire` same cycle (zero-latency manager) | completes | — | immediately |
| `sD` (outstanding) | keep `d.ready` high | — | after `d.fire` |
| `sResp` / `sDup` (response held for the CPU) | none | **withdraw** the response; the CPU is being reset and must not consume it | immediately |
| `sDiscard` | keep `d.ready` high | — | after `d.fire` |

Responses that arrive while `drainReq` is set are **discarded**, counted in `nDrained`, and never written
to `rdata`/`err`. The CPU cannot observe them because it is held in reset until drain completes (§3.4).

### 3.3 Same-cycle event priority

When several of these coincide, in this order (highest first):

1. `d.fire` — retires `outstanding`.
2. `a.fire` — converts `pendingA` into `outstanding`.
3. `R` (level) — sets `drainReq` and forces `req.ready := 0`.
4. `req.fire` — **cannot** occur while `drainReq || R`, because `req.ready` is already 0 in that cycle;
   `req.ready := (state === sIdle) && !drainReq && !R`.

So `reset` coincident with `req`, with `A`, with `D`, or with `A`+`D` all have defined outcomes, and none
of them can strand work or accept new work.

### 3.4 Release

```
cpu_reset_internal := sys_reset || drainReq
```

The CPU leaves reset only when the drain is complete. Consequently a new `A` cannot be issued while an old
`D` is outstanding — the illegal interleaving is **unreachable by construction**, which is what an
assertion should say rather than a test trying to provoke it (Codex's point 7).

---

## 4. Writes

The bridge issues single-beat Puts (64-bit beat, `size ≤ 3`), so there is no multi-beat TL Put from it.
Multi-beat behaviour lives in `TLToAXI4` and on the AXI side, and it is where the damage is:

| situation | today | required |
|---|---|---|
| AW issued, W not yet sent | reset truncates the W stream; slave waits for `WLAST` forever | the fabric is not reset (§5), so the W stream completes |
| W sent, AW not yet issued | `doneAW` cleared; AW may never be issued | same |
| B outstanding | `in.d.ready` gone; B blocks the shared D path | B accepted and discarded by the drain |
| write already applied in DDR, B delayed | indistinguishable from "not applied" | the drain must not re-issue; the write stays applied exactly once |

**Exactly-once is not provable from the final memory value.** The verification matrix (§8) therefore counts
*write-apply events at the target address in the memory model*, tagged with the AXI `id` and the txid, and
requires exactly one apply per accepted write, at most one B per AW, and no B delivered to a later epoch's
request.

---

## 5. Reset domains, revised

The sketch's D0/D1 split was under-specified and self-contradictory (Codex's point 5). Revised:

### 5.1 D0 — not affected by the soft reset

Everything that must survive in order to *finish* an accepted transaction:

* the TileLink fabric: `sbus`, `mbus`, `pbus`, their xbars, splitter, couplers, `TLFIFOFixer_1`;
* the memory coupler: `TLWidthWidget_1`, `TLToAXI4`, `AXI4IdIndexer`, `AXI4UserYanker`;
* the **TL-side** of every master: the bridge's `state`/`req`/`outstanding`, the `SerialAdapter`'s
  transaction state, the `BlockDeviceController`'s trackers;
* the new bookkeeping: `epoch`, `txid`, `nDrained`, and the memory-port outstanding counter (§5.4).

D0 is reset by the cold reset only. It is **not** "never reset": PL reconfiguration or loss of MMCM lock
destroys it, which is exactly why §7 forbids reconfiguring unless the port is idle.

### 5.2 D1 — two separate things, not one

The first draft wrote `d1_reset := sys_reset && drained`, which conflates two requirements that have
opposite timing, and misses a case Codex named: a short pulse that has already been released.

* **The CPU is held immediately.** `cpuResetHold` rises the cycle `softReset` is sampled and does not
  depend on the drain at all. Holding the CPU is what stops new work from being created.
* **Peripherals are reset only after the drain**, and only once, through an explicit
  `RESET_APPLY` phase — never while they still owe a response.
* **`resetPending` is sticky.** A one-cycle pulse that has already returned to 0 still latches it; the
  phase machine then runs drain → apply → release on its own. `sys_reset` being low again is not a reason
  to skip any of it. The RD1 implementation does exactly this and the `single-pulse` and `multi-pulse`
  scenarios exercise it.

So the sequence is: `softReset` sampled → hold CPU → drain (bounded only by the transactions themselves)
→ `RESET_APPLY` for at least one full cycle → release, and only then does the epoch advance. Peripherals
that can be mid-transaction (CLINT, PLIC, serial adapter, block device frontend) take their reset in the
`RESET_APPLY` phase.

### 5.3 The serial adapter

Its TL side moves to D0 and gains the same drain rule as the bridge. The fallback — refusing the soft
reset while TSI is mid-transaction — is *not* chosen as the primary design because it makes the PS-visible
behaviour of a register write depend on hardware state. Either way, the current behaviour (assert, clear
state, abandon the transaction) is not acceptable.

**Explicitly withdrawn assumption.** The first draft said "fesvr is idle when it writes 0x10, so the serial
adapter has nothing in flight". That is an assumption about a piece of host software, not a hardware
guarantee, and the design must not rest on it. It is now an assertion in the verification matrix instead
(`TSI-inflight`, §8), and the design is required to be correct when it is false.

### 5.4 Memory-port outstanding counter (new, D0)

At the `mem_axi4` boundary: `arOutstanding` (AR fired, `RLAST` not returned) and `awOutstanding`
(AW or W started, B not returned). These are the only place where "the PS has nothing pending on this
design" is observable, and they are what `PL_RECONFIG_SAFE` is built from.

---

## 6. Liveness, timeouts, and what the PL cannot promise

The first draft asserted that DDR always answers in microseconds and that unmapped addresses are rejected
before `A`. Both were stated without evidence. Corrected:

* **Addresses no manager claims** are rejected locally, before any `A` (`legal` → `sIllegal`,
  `ReqRespToTL.scala:56-64`), so they never become outstanding. This holds by source. It is a different
  thing from an address that *is* mapped — the error device at 0x3000, or a manager that does not support
  the requested size — where a perfectly real TL transaction happens and a real D comes back carrying
  `error`. Those are outstanding work and must be drained like any other; only the first kind never exists.
* **DDR answering**: the PS HP port's behaviour is not guaranteed by anything in this repository. If a
  response never comes, the drain does not terminate.

Therefore: **the drain is safe but not live.** A timeout may *report* and must **never** force-clear
`pendingWork`, because clearing it is precisely how an orphan is created. On timeout:

* `QUIESCENT.timeout` is set and stays set until cold reset;
* the CPU stays in reset;
* `PL_RECONFIG_SAFE` reads 0 — so the procedure forbids reconfiguration, which is the one action that
  would turn a stalled transaction into an unrecoverable board.

---

## 7. Software interface

### 7.1 Two different questions

| name | meaning | sufficient for |
|---|---|---|
| `CPU_RESTART_SAFE` | the bridge has no `pendingWork`, the CPU is held in reset, D1 reset has been applied | restarting the teaching CPU, i.e. what `fesvr` does |
| `PL_RECONFIG_SAFE` | a **sustained quiesce lock**, not a momentary reading — see below | writing `/dev/xdevcfg` |

`PL_RECONFIG_SAFE` cannot be a snapshot of "everything looks idle right now", because anything that is
still allowed to start new work can make it false again between the read and the reconfiguration. It has to
be a *lock*:

1. software sets a `QUIESCE_REQ` bit;
2. from that cycle the design **refuses to enqueue new work**: the serial adapter stops accepting TSI
   commands, the block-device controller stops accepting new requests, the CPU stays in reset;
3. work already accepted is finished — including the serial and block-device FIFOs that already hold
   commands, which must drain or be explicitly abandoned with a recorded event;
4. only when every master's TL side is idle **and** the memory port has nothing outstanding does
   `PL_RECONFIG_SAFE` read 1, and it stays 1 because (2) is still in force;
5. clearing `QUIESCE_REQ` is the only way to start work again.

AW/W accounting cannot be "count AW, count W". A write is outstanding from the first of (AW, first W) until
its B, and a burst is only complete when `WLAST` has been sent *and* the B returned; a partially issued
burst is the dangerous state. The counter therefore tracks **burst pairing**: an entry is opened by AW or by
the first W of a new burst, and closed only by B, with a separate flag for "W stream not yet finished".
Any VALID still waiting for its READY on any channel counts as outstanding, because it is not revocable.

`concurrency = 1` on the adapter register file bounds the PS's slave-side traffic to one transaction, which
is what lets the poll read itself be excluded — but that is a statement about the register file, not a
proof that the whole PL is idle, and the first draft leaned on it too heavily.

`CPU_RESTART_SAFE` does **not** imply `PL_RECONFIG_SAFE`. The first draft conflated them; that was the
substance of Codex's point 3.

The PS's own poll read is unavoidably in flight while it reads the register — that single transaction is
excluded by construction (it completes before the PS acts on the value). No other slave-side transaction
may be in flight; the adapter's register file is single-outstanding by `concurrency = 1`
(`ZynqAdapter.scala:95`), which makes that checkable rather than assumed.

### 7.2 Register (teaching configuration only)

New read-only word at `0x14`, added **behind a feature gate** so the Rocket configuration's register map
and connections are untouched:

```scala
case class ZynqAdapterParams(quiescentStatus: Boolean = false)   // default: today's behaviour
0x14 -> (if (p(ZynqAdapterKey).quiescentStatus) Seq(RegField.r(32, quiescent)) else Nil)
```

| bit | name | meaning |
|---|---|---|
| 0 | `CPU_RESTART_SAFE` | as §7.1 |
| 1 | `PL_RECONFIG_SAFE` | as §7.1 |
| 2 | `DRAINING` | a drain is in progress |
| 3 | `TIMEOUT` | sticky; a drain exceeded its bound |
| 15:8 | `EPOCH` | low 8 bits |
| 31:16 | `NDRAINED` | low 16 bits, saturating |

*Read semantics*: a snapshot of the cycle the read is answered; all bits from the same cycle. Bits 0–2 are
level, bit 3 is sticky until cold reset. *Cold-reset value*: `0x0000_0002` — nothing in flight, nothing
draining, epoch 0. *Software ordering*: write `0x10`=1 → poll `0x14` until the needed bit is set (bounded,
with a host-side timeout) → act. The bit is computed from the hardware conditions in §7.1, not from the
bridge's debug booleans; the debug counters stay what they are, a diagnostic.

---

## 8. Directed verification matrix

Two mechanisms, both simulation-only and elaborated away in `TeachingBoardConfig` (the board-RTL audit
gains a counter assertion for them, as it has for the tail intercept):

* **reset injection** — `teach_reset_at` / `teach_reset_len`, driven through the same adapter register the
  PS uses;
* **response steering** — an `AXI4ResponseHold` between the memory port and `SimAXIMem` which can hold a
  *specific* R or B until a named event (not merely a cycle number), so a response can be made to land in
  a chosen bridge state.

Every injector emits a `HIT` event naming the epoch, txid and the state it landed in. **A test whose
injector never reports a hit fails**, whatever else happened — this closes "定 cycle 延迟" into
"事件定向注入并断言命中".

### 8.1 Identification

Events carry `(epoch, txid)`. Checker rules:

1. every `RESP(e,t)` matches exactly one earlier `REQ(e,t)` — one-to-one, including the first response of
   an epoch matching the first request of that epoch (no `seq >` threshold anywhere);
2. every `REQ(e,t)` is eventually accounted for as exactly one of: `RESP(e,t)` delivered to the CPU,
   `DRAIN(e,t)` discarded by the bridge, or outstanding at end of test (a failure unless the test is the
   timeout case);
3. AXI completion, bridge discard and CPU delivery are three distinct event classes and are counted
   separately;
4. writes: exactly one apply per accepted write at the target address, ≤ 1 B per AW, no B crossing epochs.

### 8.2 Cases

| # | case | injection | old design expected | new design expected |
|---|---|---|---|---|
| 1 | `R-idle` | reset with a read outstanding; R lands while bridge idle | passes (this is what the orphan fix already handles) — **reported as a pass, not forced to fail** | passes; `nDrained = 1` |
| 2 | `R-newA` | R held until the bridge would have issued the next A | **fails**: D delivered against a different txid | passes; assertion "no A while `pendingWork`" never fires; new A only after drain |
| 3 | `R-newD` | R held until the bridge is in `sD` for a new request | **fails**: wrong `RESP(e,t)` pairing | passes |
| 4 | `stalled-A` | reset while `a.valid` high and `a.ready` low | **fails**: `a.valid` withdrawn (TL monitor assertion) | passes; A completes, then drains |
| 5 | `same-cycle` | reset in the same cycle as `req.fire` / `a.fire` / `d.fire` / `a.fire`+`d.fire` | mixed; report honestly per sub-case | all four defined per §3.3 |
| 6 | `short-pulse` | 1-cycle reset pulse with work in flight | may pass by luck — reported as found | `drainReq` sticky: always drains |
| 7 | `W-AW-only` | reset after AW, before W | **fails**: truncated W stream, slave stalls | passes; W completes |
| 8 | `W-W-only` | reset after W, before AW | **fails** | passes |
| 9 | `W-B-late` | B held past the reset | **fails**: B blocks the shared D | passes; B drained, write applied exactly once |
| 10 | `multi-pulse` | 20 fesvr-style 1/0 pulses while the CPU spins on DDR fetches | hangs (matches the board: 20/32) | 20/20 complete |
| 11 | `TSI-inflight` | reset while the serial adapter has a Put outstanding | **fails**: adapter abandons it; D orphaned | passes; adapter drains |
| 12 | `bdev-inflight` | same for the block device controller | **fails** | passes |
| 13 | `never-answers` | a response that never returns | hangs silently | `TIMEOUT` set, CPU stays in reset, `PL_RECONFIG_SAFE = 0`, no force-clear |
| 14 | `reconfig-model` | assert `PL_RECONFIG_SAFE`, then model reconfiguration by dropping the PL state | — | no PS-side transaction is left outstanding at the moment the bit reads 1 |

Cases 1, 5 and 6 are marked explicitly as "the old design may legitimately pass" — per Codex's point 8, a
negative control that passes is reported as a pass, not bent into a failure.

---

## 9. Changes this would require

| file | change | shared? |
|---|---|---|
| `ReqRespToTL.scala` | `pendingA`/`outstanding`/`drainReq`, rule table §3.2, priority §3.3, `nDrained`, epoch/txid tagging | teaching only |
| `TeachingCpuSoc.scala` | D0/D1 split (`withClockAndReset`), `cpu_reset_internal`, `d1_reset`, memory-port counters, injectors behind `cfg.testReset` | teaching only |
| `SerialAdapter` usage | TL side into D0 + drain; ideally by wrapping rather than editing testchipip | **shared** — wrap, do not edit |
| `ZynqAdapter.scala` | `0x14` behind `ZynqAdapterParams(quiescentStatus)`, default off | **shared** — gated, Rocket path unchanged |
| checkers | epoch/txid one-to-one rules, write-apply counting, injector-hit assertions | teaching only |
| board-RTL audit | assert zero `testReset` logic in `TeachingBoardConfig` | teaching only |

Then: M3 gates on four configurations, the bridge's 13 cases, the new matrix, board-RTL audit, a rebuilt
bitstream, and only then a board session — each as a separately authorised step.

## 10. Assumptions still unverified

1. The PS HP port always eventually answers. Not guaranteed anywhere in this repository; §6 makes the
   design safe without it, not live.
2. The observed hangs are the orphan chain of §1.4. That remains a **hypothesis supported by code
   reading** plus the hold/no-hold statistics; the board cannot produce a cycle-level bus trace, so it is
   not confirmed. The write-truncation mechanism in §1.5 is a **risk the code permits**, not a diagnosis of
   what happened in session 3: nothing was captured that identifies it as the cause of that particular
   wedge, and it should not be quoted as if it were.
3. `concurrency = 1` on the adapter register file means at most one PS slave transaction in flight. Read
   from `ZynqAdapter.scala:95`; not independently tested.
4. Wrapping `SerialAdapter` without editing testchipip is achievable. Needs a construction check before it
   is promised.
5. Whether `TLFIFOFixer_1`'s `flight` state, optimised away in this elaboration, reappears under a
   different configuration and needs the same treatment.

## 11. Not proposed

A fixed-cycle reset stretch as a substitute for the protocol (rejected by Codex, and rightly: it would
re-create orphans with a different timing). Any change to the CPU's architectural behaviour, the physical
port contract, the baseline wrapper, project or bitstream. Any removal of the current 50 ms operating
condition before the above is built and verified.
