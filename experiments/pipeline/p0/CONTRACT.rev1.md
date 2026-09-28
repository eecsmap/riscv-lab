# PIPE-P0 CONTRACT — a five-stage in-order pipeline behind the accepted TeachingHart interface

Task `codex-pipe-p0-contract`. Read-only audit of tag `mc-v1-dual` (93b8117, worktree `pipe-single`); no RTL is changed by
this package. Anchors are `file:line` in that tree. Where this document decides something, it says **DECISION**; where it
needs Codex's ruling, it says **RULING REQUESTED** and the choice is listed again in §9.

## 0. What is fixed, and by whom
| fixed | where | consequence for the pipeline |
|---|---|---|
| the core's port list (module `tcpu_core`, 61 ports) | `soc/scala/teaching/TeachingCpuBlackBox.scala:10-72` (`desiredName = "tcpu_core"`, `:71`), `rtl/cpu/tcpu_core.v:48-104` | the pipeline is a second Verilog implementation of the SAME module name and port list; nothing in Scala changes for it |
| PHYSICAL_PORT_V2: valid irrevocable, payload held, response no earlier than the next cycle, ONE request in flight per hart, wdata/wmask with the request, no CPU transaction id | `experiments/teaching-cpu/PHYSICAL_PORT_V1.md`, `PhysPortV2.scala:1-44`, M0 CONTRACT C2 (`experiments/multicore/archive/m0/CONTRACT.md:55-63`); enforced by the bridge `RD2BridgeV2.scala:84` (`req.ready := state === sIdle`), `:133`, `:168-201` | §4 |
| the stable observation bundle: one commit OR one trap per cycle, never both; `pc`; `isFetch` while the outstanding request is a fetch; `halted` | `TeachingCpuBlackBox.scala:214-232` (TeachingCpuObs), `RD2Soc.scala:361-374` (busy = reqValid ‖ outstanding ‖ awaitingRetire) | §3.5, §6.3 |
| implementation state stays private | `TeachingCpuImplObs` (`TeachingCpuBlackBox.scala:233-236`), lint `archive/m1/tests/lint-stable-obs.sh` | the pipeline publishes NO stage state through `dbg_state`/`dbg_redirect`; they are driven constant (§6.3) |
| the atomic side-band: `resv_clear` pulse on trap or reset, marks pushed by the bridge on acceptance | `tcpu_core.v:179-184`, `RD2BridgeV2.scala:136-149`, `AtomicBackend.scala:8-15` | §5.4 |
| CORE_IMPL × NUM_CORES matrix, refused not substituted | `RD2Soc.scala:54-58,119-122` | §6 |
| fetch32 / 8-entry TLB / 1 KiB I-cache capacities, 40 MHz, no D-cache, no branch prediction, no second outstanding request | task text | §2, §7 |

## 1. Stage split and control (item 1)
**DECISION: IF, ID, EX, MEM, WB, in order, one instruction per stage, no prediction (fall-through fetch only).** The
front end is internally two steps (IF-T translate, IF-C cache), but IF-T runs on the *next* PC while IF-C serves the current
one, so the pipeline still presents five architectural stages; the redirect penalty counts both.

| stage | does | produces (carried down) |
|---|---|---|
| IF | translate the fetch VA (TLB lookup, combinational as `tcpu_xlate.v:49-58` does today; miss → walker), then I-cache lookup on the PA (`tcpu_ifill`/`tcpu_icache` geometry unchanged); a miss goes to the port through the core's request arbiter (§4.2) | `pc`, `epoch`, the raw parcel/word, `len` (2/4, from the parcel as `tcpu_core.v:207-215`), fetch fault flag+cause+tval (insn access 1 / insn page fault 12 / misaligned 0 for `pc[0]`) |
| ID | decode (`tcpu_cdecode` for C exactly as `tcpu_core.v:222-225`), read rs1/rs2 (with WB bypass, §2.2), legality (`tcpu_core.v:288-391`, unchanged expressions), CSR address/privilege legality (`tcpu_csr.v:130-148`), interrupt attachment (§3.2) | decoded fields, immediates, `illegal`, `ecall/ebreak/xret/fence/fence.i/sfence/wfi/csr` class flags |
| EX | ALU (`tcpu_core.v:241-286`), branch decision + target (`:393-416`), address generation + misalignment (`:418-439`), MUL/DIV start (structural stall, §2.4), redirect decision | result or address, `branch_taken`, `npc`, misaligned flag+cause, `mem class` (load / store / LR / SC / AMO) |
| MEM | data translation (TLB lookup; miss → walker; effective privilege `MPRV ? MPP : priv` as `:493-495`), issue exactly one V2 request through the arbiter, wait for the response, format load data (`:441-459`), SC result, bus error → access fault 5/7 | value to write, `mem fault flag+cause+tval` |
| WB | **the single commit point**: register write, CSR read-modify-write (§2.5), trap entry, xRET, `commit_*`/`trap_*` outputs, `resv_clear` | — |

**Valid/stall/bubble/flush, priority (highest first):**
1. **reset / soft-reset hold** (`cpuResetHold`, `TeachingHart.scala:78`): every stage invalid, epoch reset, no request issued; an outstanding request cannot exist across a hold because the bridge discards it (`RD2BridgeV2.scala:155-165,175,187`) — the pipeline's port state machine is reset with the core, as today.
2. **trap taken at WB** (exception or attached interrupt): flush IF/ID/EX/MEM, `pc ← trap vector`, epoch++.
3. **serialising instruction at WB** (xRET, CSR write, sfence.vma, fence.i, wfi, fence): flush younger, `pc ← npc` (xRET: xepc; else pc+len), epoch++ (§2.5).
4. **redirect from EX** (taken branch, JAL, JALR): flush IF/ID, `pc ← target`, epoch++.
5. **stall from MEM** (request not yet issued or response outstanding, translation walk in progress): MEM and everything older than it hold; IF/ID/EX hold (in-order, no buffering between stages).
6. **stall from EX** (MUL/DIV busy; load-use interlock, §2.3; serialising instruction waiting for the pipeline to drain, §2.5): EX and younger hold; MEM/WB proceed.
7. **stall from IF** (cache miss outstanding, walk in progress, arbiter busy with MEM): IF holds; ID and younger proceed, a bubble enters ID.
A stage that is stalled keeps its valid and payload; a stage that is flushed drops valid. A flush never touches a request already accepted by the port (§4.3).

**Variable-length C instructions and page crossing.** As today, a 4-byte-aligned PC fetches one 32-bit word (`tcpu_core.v:607-613`
OPT01) and a 2-byte-aligned 32-bit instruction fetches two parcels, the second translated on its own (`:639-664,698-708`).
**DECISION:** IF keeps that behaviour exactly (no line-straddling prefetch): a straddling instruction costs a second IF pass;
its exception ownership is unchanged — `epc = pc` of the instruction, `tval = pc + 2` for a second-parcel fault (`:646-647`,
`:657-658`). `insn_len` is decided from the first parcel and drives pc+len and link values (`:196-206`).

**No external reader of the FSM.** The pipeline has no `state`; `dbg_state`/`dbg_redirect` are constants (§6.3); anything a
test needs is derived from the stable bundle and the port, as `RD2Soc.scala:361-374` already does.

## 2. Data hazards, redirects, CSR serialisation, M (item 2)
### 2.1 RAW forwarding
EX reads rs1/rs2 from: EX/MEM result (an ALU result of the instruction now in MEM), MEM/WB value (a load's or ALU's value of the
instruction now in WB), then the register file. `x0` is never forwarded and never written (`tcpu_regfile.v:21-24`: reads return 0;
the pipeline compares `rs != 0` before matching, and a producer with `rd == 0` never asserts a forward). Forwarding compares the
5-bit register numbers of *valid* producers only; a flushed producer forwards nothing.
### 2.2 Register file, same-cycle read/write
`tcpu_regfile.v:22-24` is write-on-edge / asynchronous read: a read in the write cycle returns the OLD value. **DECISION:** ID
bypasses WB (compare rs against WB.rd with WB.we) so the register file module is reused unchanged.
### 2.3 Load-use
A load's value exists only in WB (its response arrives in MEM). A consumer entering EX while its producer is in MEM as a load
stalls in EX until the producer reaches WB (1 bubble in the ideal case; in practice the load waits for its response anyway, §7).
LR and AMO results are loads for this rule; SC's result (0/1) too.
### 2.4 M extension
`tcpu_muldiv.v` is reused as is: 64 iterations + 1 assembly cycle, `start` accepted only when idle (`tcpu_muldiv.v:104-118`). **DECISION:** EX
starts it and stalls (structural) until `done`; younger instructions wait; older ones complete. No pipelining of the unit, no
early-out. An interrupt is not attached to an instruction whose MUL/DIV is running (it is past ID); it attaches to the next
instruction at ID (§3.2), as the multicycle core defers it past `S_MUL` (`tcpu_core.v:795-797`).
### 2.5 CSR and other serialising instructions
**DECISION: serialise by draining.** A CSR instruction (any of the six forms), ECALL/EBREAK, MRET/SRET, SFENCE.VMA, FENCE.I, FENCE,
WFI waits in EX until MEM and WB are empty (no outstanding request), executes its CSR read-modify-write **in WB** with the same
single-cycle atomicity the multicycle core has (`tcpu_core.v:481-486, 805-823`: read value and write land on one edge, software
write to a counter wins over the increment), and then flushes everything younger and refetches from pc+len (or xepc). Consequences,
all as today: an enable-changing CSR write or an xRET is never followed by an already-fetched instruction (`:116-118`); `satp`
writes and `sfence.vma` flush the TLB (`:497-511`, same condition `csr_we_r && csr == 0x180`); `fence.i` invalidates the I-cache
(`:162-163`) — and, because the drain guarantees no fetch refill is in flight at that moment, the `killed` guard in `tcpu_ifill.v:85,123,136`
stays a guard, not a dependency. Cost: ~4 cycles per serialising instruction (§7); xv6 executes few.
### 2.6 Branch / jump redirect
Resolved in EX from forwarded operands; `npc` and the misaligned-target trap (`tcpu_core.v:411-416`, only for a *taken* target) as today.
Redirect kills IF and ID (2 instructions) and restarts IF at the target: penalty 2 cycles + 1 for IF-T, i.e. **3 cycles** (§7).

## 3. Precise retirement and exceptions (item 3)
### 3.1 One commit point
Only the instruction in WB commits or traps; one per cycle, never both (`TeachingCpuObs` invariant, `tcpu_core.v:71`). An
instruction reaching WB with an exception flag traps: no register write, no CSR write, no memory effect from it — every
architectural side effect of an instruction is performed in WB or, for memory, in MEM under §3.3.
### 3.2 Exception and interrupt ownership and priority
Each instruction carries at most one synchronous cause, the first found in pipeline order (this is also program-order for one
instruction): IF: `pc[0]` misaligned (0) → fetch access (1) / fetch page fault (12) [incl. second parcel, tval = pc+2] → ID: illegal
(2, tval = raw insn), ECALL (8/9/11), EBREAK (3, tval = pc), privilege-illegal xRET/SFENCE (`:362-365`) → EX: taken-target misaligned
(0, tval = target), load/store/AMO misaligned (4/6, before any request, `:714-718`) → MEM: page fault 13/15 (walker or TLB hit
permission check), PA above 32 bits → access fault 5/7, bus error → 5/7 (`:779-782`). LR is load-class, SC/AMO store-class (`:422-423`).
**Interrupts** (`csr_irq_pending`, `tcpu_csr.v:182-198`): sampled at ID. When pending, the instruction *entering* ID is marked
"interrupt" with `epc = its pc`, its own fetch fault (if any) is dropped (interrupts win over that instruction's synchronous
causes, RISC-V priority), it carries no other effect, and it traps when it reaches WB — by which time every older instruction
has committed and no request is outstanding (§3.3). Between two instructions the multicycle core samples in `S_IF_REQ` after
`S_ARCH` (`tcpu_core.v:470-479, 589-598`); the pipeline's rule is the same boundary expressed per instruction. `trap_interrupt`, `cause`
(`irq_cause`), `tval = 0` as `tcpu_core.v:594-597`. A pending interrupt while MEM holds an outstanding request is never taken early
(no `EARLY_IRQ` behaviour); a stale-enable decision cannot occur because enables change only in WB and ID samples after
the WB flush (the serialisation in §2.5 refetches).
### 3.3 Memory effects only from a safe position
**DECISION:** MEM issues a request (load, store, LR, SC, AMO, or an MMIO access of any class) only when **WB holds no trapping
instruction and no interrupt-marked instruction is older** — in a 5-stage in-order pipeline that means: the instruction in WB
(if any) has `trap = 0`, and the instruction in MEM itself is not interrupt-marked. Since everything older than MEM is in WB and
commits this cycle, an issued request belongs to an instruction that will retire unless *its own* response errors — and that
error becomes its own precise access fault, reported at its WB with the same cause/tval as `tcpu_core.v:779-782`. A store therefore issues
exactly once and only when it will commit or fault on its own; `i09_store_exact`/`j02_store_once` (`tests/cpu/tests2`) stay valid.
The response is awaited in MEM: **no store buffer, no early retirement of stores** (a store's bus error must be precise); this
keeps the SoC's `awaitingRetire` accounting (`RD2Soc.scala:371-374`: a data response is not finished until its instruction
retires) exactly true.
### 3.4 CSR side effects
CSR writes, `mepc/mcause/mtval/mstatus` updates at trap entry, xRET state changes, `minstret` increment (`tcpu_csr.v:214-252`,
`retire` input) happen only in WB. `mcycle` free-runs. A flushed instruction updates nothing.
### 3.5 Observation outputs
`commit_*` exactly as the multicycle core populates them in `S_WB` (`tcpu_core.v:805-823`: pc, raw parcel/word, len, rd valid = we && rd≠0,
rd data); `trap_*` as in `S_TRAP` (`tcpu_core.v:835-846`). `halted` only under the test option. `isFetch` (`dbg_req_is_fetch`) is 1 while
the request the port holds is an instruction fetch or a fetch-side PTE read is NOT counted (today `tcpu_core.v:463-465` excludes walker reads);
**DECISION:** keep that: fetch = a fetch or refill request; walker reads and data are not fetches.

## 4. The physical port stays V2, one in flight (item 4)
### 4.1 Unchanged rules
Valid irrevocable with payload held until `req_ready` (`tcpu_core.v:617,699,777` style holding registers); response consumed the cycle
it arrives (`resp_ready = 1`, `:461`); `req_write`, `size`, `wdata` on the address's lanes, `wmask` exact for AMO/SC (`RD2BridgeV2.scala:86-101`
legality) — the pipeline reuses the same formatting expressions (`tcpu_core.v:437-439, 676-681, 731-740`). No transaction id is added: the
bridge is `IdRange(0,1)` (`:32`) and the backend binds by client name.
### 4.2 One arbiter, one outstanding request, priority MEM > IF
**DECISION:** the core has ONE holding register for the outstanding request and one arbiter: the walker (either side), MEM, and an
I-cache refill/uncached fetch all go through it; at most one is accepted until its response returns. Priority: the walker of an
already-issued translation (it owns the port until `done`, as `tcpu_ptw.v:6-8` requires), then MEM, then IF. I-cache **hits** do not
use the port (`tcpu_ifill.v:93-99`), which is the only way IF and MEM overlap (§7).
### 4.3 Flush versus an outstanding request: epoch
A request already accepted is never withdrawn. **DECISION:** the front end carries a 1-bit epoch per fetch request; a redirect or
flush increments the front-end epoch; a response whose epoch ≠ current is consumed and **discarded** (its data and its `error`
alike). With one outstanding request, "stale" is exactly "issued before the last flush", so a single flag suffices, but the epoch
is kept as a bit to make the scoreboard obvious. A refill that completes stale still fills the line (a valid line for its PA; the
same rule as `tcpu_ifill.v:150-153` with `killed` (`:85`) only from fence.i). A data request can never be stale: it is issued only under §3.3.
### 4.4 Walker side effects and speculation
A/D bits are software-managed: the walker never writes memory (`tcpu_ptw.v:1-8`, `cpu-sv39/DESIGN.md`), so a walk has no
architectural side effect beyond its PTE *reads*. A walk started for a wrong-path fetch completes (it owns the port), its fault is
discarded with the fetch, and its TLB fill is harmless (bits, not verdicts; permission re-checked on every use, `tcpu_xlate.v:7-10`).
**DECISION (speculative access rule):** the front end may issue a *speculative* port request (a fetch behind an unresolved branch
or behind an instruction that may still trap) only to a **cacheable RAM physical address** (`tcpu_cacheable.v`) — for a refill this
is already implied; for a PTE read the walker's next PTE address must be cacheable RAM, otherwise IF waits until it is
non-speculative (EX/MEM/WB empty of branches and trap-capable instructions). An **uncached (MMIO) fetch** is issued only
non-speculatively. This is stricter than the multicycle core (which is never speculative) and is the whole of "no predicted fetch
touches MMIO".

## 5. TLB, I-cache, walker sharing; ordering of satp/sfence/fence.i/trap/reservation (item 5)
### 5.1 What is shared inside the core
| unit | today | pipeline |
|---|---|---|
| TLB (8 entries, PTE bits, full flush) `tcpu_tlb.v` | one lookup port, used by fetch and data serially | **DECISION:** the same module with **two combinational lookup ports** (IF and MEM in the same cycle; 8 entries, the array is not duplicated), one fill port from the single walker. Capacity, replacement (round-robin), flush policy unchanged (`tcpu_tlb.v:96-111`) |
| walker `tcpu_ptw.v` | one | one; requests serialised through the arbiter (§4.2); MEM's translation miss has priority over IF's |
| permission check `tcpu_permcheck.v` | evaluated on every hit with the access's own type/priv/SUM/MXR | same, per port |
| I-cache `tcpu_icache.v` + fill `tcpu_ifill.v` | in front of the port | fetch side only; hit = 1 cycle after lookup as today (`tcpu_ifill.v:125-131`); refill 2 beats unchanged; cacheability decision unchanged |
| CSR file, regfile, muldiv, cdecode | — | reused unchanged (§6.1) |
### 5.2 Ordering
| event | when it takes effect | what it flushes |
|---|---|---|
| `satp` write (any write, `csr_we_r && csr==0x180`) | WB of the CSR instruction | TLB (all), pipeline younger than WB, refetch pc+4 under the new satp |
| `sfence.vma` (any rs1/rs2) | WB | TLB (all), younger instructions (they may have been fetched under a stale translation) |
| `fence.i` | WB | I-cache (all), younger instructions; the drain of §2.5 guarantees no refill in flight |
| `fence` | WB (a no-op: one in-flight, in-order; `tcpu_core.v:329-334`) | younger instructions (kept uniform with the other serialisers; cheap) |
| trap / xRET | WB | younger; `resv_clear` pulses in the trap cycle (§5.4) |
| interrupt | attached at ID, taken at WB | younger |
### 5.3 MMIO
Data MMIO accesses are ordinary MEM requests under §3.3 (never speculative). Fetch from MMIO: §4.4. The cacheability decision
(`tcpu_cacheable.v`) is the one and only classifier.
### 5.4 Reservations
`resv_clear` = `rst || (trap taken this cycle in WB)` — the pipeline's equivalent of `tcpu_core.v:184`. The core still has at most one
request outstanding and takes no trap while its own LR is in flight (the LR is in MEM; a trap can only come from WB, which is older
and committing) — the same argument as the comment at `:182-183`. The backend's cross-hart rules are untouched.

## 6. Configuration and directory structure: CORE_IMPL ⟂ NUM_CORES (item 6)
### 6.1 Files
```
rtl/cpu/                     shared, byte-identical to mc-v1-dual: tcpu_csr.v tcpu_regfile.v tcpu_muldiv.v tcpu_cdecode.v
                             tcpu_ptw.v tcpu_tlb.v(+2nd lookup port, §5.1) tcpu_xlate.v tcpu_permcheck.v tcpu_icache.v
                             tcpu_ifill.v tcpu_cacheable.v tcpu_defs.vh
rtl/cpu/tcpu_core.v          the multicycle core, UNCHANGED (its hash stays the accepted one)
rtl/cpu/pipeline/tcpu_core.v the pipeline: module tcpu_core, the SAME port list and parameter names that exist today
                             (fault-injection parameters it cannot honour are refused at elaboration: a non-zero value
                             for a knob the pipeline does not implement is a compile error, not a silent 0)
```
**DECISION:** the choice is made in ONE place per build flow — the Verilog file list: `tools/xv6-boot/scripts/rd2-build-sim-fast.sh:12`
(`VSRCS`), the core harness runners (`archive/m1/tests/core-suites/run-cpu-*-rtl.sh`, e.g. `run-cpu-c-rtl.sh:44`, which already take the RTL directory as a
parameter), and the board manifest (`tools/board/scripts/make-build-manifest-atomic.py`, `audit-board-rtl-atomic.py`). Each takes
`CORE_IMPL` and picks `rtl/cpu/tcpu_core.v` or `rtl/cpu/pipeline/tcpu_core.v`, never both.
### 6.2 Scala
`RD2Params.coreImpl` (`RD2Soc.scala:58`) gains the value `"pipeline"`; the `require` at `:119` accepts `multicycle | pipeline` and still
refuses anything else by name. Nothing else in Scala changes: `TeachingHart`, `TeachingCpuV2`, the bridge, the backend and
`NUM_CORES ∈ {1,2}` are orthogonal to the core implementation because the BlackBox is by name and port list only.
**Silent-fallback guard (RULING REQUESTED, recommended):** the core gets one new constant output `dbg_impl[1:0]` (1 = multicycle,
2 = pipeline) in *both* implementations; `TeachingCpuV2` exposes it in `TeachingCpuImplObs` (implementation detail, lint-excluded),
and the simulation mains assert on the first cycle that it equals the configured `coreImpl`; the board audit script checks the
file hash by `CORE_IMPL`. A Scala config that says `pipeline` built against the multicycle file list fails in the first cycle.
### 6.3 Observation bundle
Unchanged ports. The pipeline drives `dbg_state = 0`, `dbg_redirect = 0` (constants; nothing outside the wrapper reads them —
`lint-stable-obs.sh` is re-run as a gate). `TeachingCpuImplObs` stays private.
### 6.4 Not silently different
Fault-injection parameters listed at `tcpu_core.v:20-47` that name a multicycle-only mechanism (`EARLY_IRQ`, `STALE_MIE`,
`REQ_WITHDRAW`, …) either get a pipeline-specific meaning (documented in TESTPLAN N-list) or are refused when non-zero.

## 7. Throughput ceiling before any CPI promise (item 7)
Facts (audited): I-cache hit answers **1 cycle** after the lookup handshake (`tcpu_ifill.v:125-131`); TLB hit answers 1 cycle after
`start` (`tcpu_xlate.v:138-145,153-159`); the bridge's fastest response is **2 cycles** after `req.fire` (`RD2BridgeV2.scala`: fire →
`sA` → same-cycle D → `sResp`); simulator memory (`CYCLES`/probe evidence): `perf02 bare_alu` **6.00 CPI** and `bare_load` **8.34 CPI** on
the cache stage (`IPS-campaign/FINAL-COMPARISON.md:5-6`) — i.e. a load costs ≈ 2.3 cycles beyond the ALU path in simulation;
on the board one DRAM round trip is **≈ 18 cycles** (`riscv-lab/experiments/E1-clock-scaling/README.md:9`).

Multicycle path today (cache stage, TLB hit): IF_REQ + IF_WAIT(2) + XLATE-hit(2, under Sv39) + EXEC + WB + ARCH = 6 (bare) / 8 (Sv39)
cycles per ALU instruction, matching the measured 6.00 / 8.00 (`FINAL-COMPARISON.md:5,7`).

Pipeline hand-count (per instruction, steady state, I-cache and TLB hits):
| class | ideal cycles | note |
|---|---|---|
| ALU / LUI / AUIPC | **1** | forwarding covers back-to-back RAW |
| taken branch / JAL / JALR | 1 + **3** | redirect from EX; no prediction (task: none) |
| not-taken branch | 1 | |
| load-use | +1 bubble | on top of the load's own wait |
| load / LR / AMO (RAM) | 1 + T_mem | T_mem = response latency: **≥ 2** (bridge floor), **≈ 3** simulator, **≈ 18–20** board (DRAM); no D-cache, so every one |
| store / SC | 1 + T_mem | the response is awaited (§3.3) |
| I-cache miss | + 2 beats + T_mem each ≈ 2·T_mem + 3 | 16-byte line, two 8-byte reads (`tcpu_ifill.v:13,140-157`) |
| TLB miss | + 3 PTE reads ≈ 3·T_mem + 6 | plus the access itself |
| MUL/DIV | 1 + **65** | `tcpu_muldiv.v:119-126` |
| CSR / xRET / fences / ecall | ≈ **4–5** | drain + refetch (§2.5) |
| straddling 32-bit C-mode instruction | + 1 IF pass | as today |

With the port unchanged, **IF and MEM overlap only when IF hits the cache**; a fetch miss and a data access serialise on the one
outstanding request. So the ceiling is set by memory-instruction density and T_mem, not by the number of stages:
- **simulator** (T_mem ≈ 3): a mix of 65 % ALU / 10 % branches (½ taken) / 25 % loads+stores → CPI ≈ 0.65·1 + 0.10·(1+1.5) + 0.25·(1+3) ≈ **1.9**
  (versus ≈ 8–9 today on the same mix: 0.75·8 + 0.25·11): ≈ 4.5×.
- **board** (T_mem ≈ 18): the same mix → CPI ≈ 0.65 + 0.25 + 0.25·19 ≈ **5.7** (versus ≈ 0.75·8 + 0.25·26 ≈ 12.5 today): ≈ **2.2×**.
  The remaining time is DRAM latency on every load/store; only a D-cache or multiple outstanding requests would change that, and both
  are excluded by the task as separate design choices.
**DECISION on the CPI target:** *P1 gate (bare RV64I, I-cache hits, simulator memory profile)*: ≤ 2.0 CPI on the perf02 `bare_alu`
ROI and ≤ 4.5 on `bare_load`; *P3 board target*: ≥ 2× the multicycle IPS on the fixed-work `perfcompute`/`perfarray` (MUL-heavy,
so compute is dominated by the 65-cycle unit and will show less than 2×; that is stated now, not discovered later). No "from 6 to
1.x" is promised; 1.x is reachable only on ALU-only ROIs with cache hits, which `perf02 bare_alu` measures, and that number will be
reported separately from the workload CPI. The front-end change that makes 1-cycle hits possible is the arbiter of §4.2 (I-cache hit
path decoupled from the port), which is an internal design choice and does not alter the external contract.

## 8. Phases (proposal; Codex decides in §9)
- **P1** RV64I + Zicsr-minimal (mret, mepc/mcause/mtval, mstatus.MIE) pipeline in the standalone harness: forwarding, load-use,
  redirects, precise exceptions (illegal/misaligned/access), interrupts at ID, epoch discard, arbiter; commit-stream equality
  against the multicycle core over the same programs under three delay profiles; TESTPLAN P1.
- **P2** M, C (two-parcel, straddle), full CSR/S/U/delegation, Sv39 (dual-port TLB, walker sharing, speculative-access rule), A
  (LR/SC/AMO through the V2 port + backend), fence.i/sfence ordering; every existing stage suite re-run through the RTL-directory
  runners; single-core xv6 in the RD2 sim with `m3_check.py`; TESTPLAN P2.
- **P3** 40 MHz offline implementation (`build-board.sh` flow with CORE_IMPL) and, after separate authorisation, board same-workload
  comparison (M5/perf tooling, profile `perf-board`, also `perf02` ROIs); TESTPLAN P3.
- **P4** NUM_CORES=2 with the pipeline core: M2b dual gates, M3 dual xv6, fixed-work S2; TESTPLAN P4.
Reason for the split: P1 fixes the control skeleton where every later feature hangs; M/C/CSR/VM/A are each a stall or a flush rule
on that skeleton and are cheaper to add one at a time against the existing suites than to re-derive the skeleton later.

## 9. Rulings requested (with the recommended answer)
| # | question | recommended |
|---|---|---|
| R1 | Serialise CSR/xRET/fences by draining and refetching (§2.5) rather than tracking CSR side effects per stage | **drain**: simpler, matches today's atomicity, cost negligible in xv6 |
| R2 | Stores await their response in MEM (no store buffer) (§3.3) | **await**: precise store faults, SoC `awaitingRetire` stays exact |
| R3 | Speculative port requests only to cacheable RAM; MMIO fetch non-speculative (§4.4) | **yes** |
| R4 | TLB: same 8 entries with two lookup ports, one walker (§5.1) — not split I/D TLBs | **shared dual-port** (keeps "same capacity" comparable) |
| R5 | `dbg_impl` constant + first-cycle assertion as the anti-fallback guard (§6.2) | **yes** |
| R6 | CPI gates in §7 (P1: ≤2.0 bare_alu / ≤4.5 bare_load in the simulator profile; P3: ≥2× IPS on fixed work, MUL-heavy caveat) | **adopt as gates, not as promises of 1.x** |
| R7 | Phase split P1–P4 as §8 | **adopt** |
| R8 | Configuration boundary §10: status levels + refuse-below-implemented; preset/config object after P2 | **adopt** |

## 10. Future configuration boundary (codex-pipe-config-direction; not implemented in P0 or P1)
Goal later: Chipyard-style composition by switches. P0 only fixes where each switch is wired and how its status is stated, so that
no combination is ever claimed or silently substituted. Current names follow `docs/FEATURES.md` (main 11c283b).

| switch | wiring point today | values that exist | pipeline impact |
|---|---|---|---|
| CORE_IMPL | `RD2Params.coreImpl` (`RD2Soc.scala:58`, refused at `:119`) + Verilog file list (§6.1) | `multicycle` | adds `pipeline` (§6.2); guard `dbg_impl` (R5) |
| NUM_CORES | `RD2Params.numCores` (`RD2Soc.scala:57`, refused at `:121`) | 1, 2 | orthogonal: `TeachingHart` instantiates the BlackBox by name (§0) |
| fetch policy | inside the core: OPT01 aligned 32-bit fetch (`tcpu_core.v:607-613`); tags `ips-v1-baseline`/`ips-v1-fetch32` keep the before/after | fetch32 only (no switch) | the pipeline implements fetch32 behaviour (§1); a parcel-only fetch is NOT offered as a switch in P1–P4 |
| TLB_ENTRIES | `tcpu_core` Verilog parameter (`tcpu_core.v:15`), not passed by `TcpuCoreBlackBox` (default 8) | 0, 8 at core level | the pipeline takes the same parameter name; 0 must mean "no TLB" with identical architecture |
| ICACHE_BYTES | `tcpu_core` Verilog parameter (`tcpu_core.v:16`), not passed by the BlackBox (default 1024) | 0, 1024 at core level | same name and meaning in the pipeline |

**Status levels (to be used verbatim in every later report and in a future config table):** *expressible* (a parameter or
config value exists) < *implemented* (RTL for it exists and elaborates) < *simulated* (its gates passed in simulation) < *board-proven*
(its gates passed on hardware after a cold cycle). Today: multicycle x {1,2} with TLB 8 / I-cache 1 KiB / fetch32 is board-proven;
TLB 0 and I-cache 0 are simulated at core level only (IPS stages); nothing with `pipeline` exists. **Rule:** a combination below
*implemented* is refused at elaboration by name (as `RD2Soc.scala:119-122` already does), never replaced by the nearest existing one;
a combination that is implemented but not simulated may be built only by a test flow that says so. Passing TLB_ENTRIES/ICACHE_BYTES
through `TcpuCoreBlackBox` and a named-preset/validation-matrix object are deferred until the single-core pipeline is accepted
(P2), and are not part of P0/P1.
