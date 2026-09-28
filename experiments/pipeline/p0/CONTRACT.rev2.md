# PIPE-P0 CONTRACT (rev. 2) — an in-order pipeline behind the accepted TeachingHart interface

Tasks `codex-pipe-p0-contract`, `codex-pipe-config-direction`, `codex-pipe-p0-rulings`. Read-only audit of tag `mc-v1-dual`
(93b8117, worktree `pipe-single`); no RTL or Scala is changed by this package. Anchors are `file:line` in that tree (every one is
range-checked, `evidence/doc-anchor-range.txt`). Rev. 1 is kept as `CONTRACT.rev1.md`. **Rev. 2 closes the eight control gaps of
`codex-pipe-p0-rulings` and applies R1–R8 as ruled.** The control rules below are exercised by a small executable model,
`model/p0model.py` (tables: `model/TABLES.md`): 13 scenarios, 9 invariants, 10 mutations that must each fail for their own reason.
The model is a control skeleton with no datapath; it is evidence that the rules are consistent and deadlock-free on the named
cases, not a proof and not RTL.

## 0. What is fixed, and by whom
| fixed | where | consequence |
|---|---|---|
| the core's ports (61) and the multicycle file itself | `rtl/cpu/tcpu_core.v:48-104`; BlackBox `soc/scala/teaching/TeachingCpuBlackBox.scala:10-72` (`desiredName`, `:71`) | the multicycle file is **not modified**; the pipeline is a separate module with the same 61 ports under a different module name (§6) |
| PHYSICAL_PORT_V2: valid irrevocable, payload held, response ≥ 1 cycle after the handshake, ONE request in flight per hart, wdata/wmask with the request, no CPU transaction id | `experiments/teaching-cpu/PHYSICAL_PORT_V1.md`, `PhysPortV2.scala:1-44`, M0 C2 (`experiments/multicore/archive/m0/CONTRACT.md:55-63`); the bridge accepts only in `sIdle` (`RD2BridgeV2.scala:84`), holds the response until taken (`:196`) | §4 |
| the stable observation bundle: one commit OR one trap per cycle; `pc`; `isFetch`; `halted` | `TeachingCpuBlackBox.scala:214-232`; its SoC consumers `RD2Soc.scala:361-374` | §3.5, §5 |
| implementation state stays private | `TeachingCpuImplObs` (`TeachingCpuBlackBox.scala:233-236`), lint `archive/m1/tests/lint-stable-obs.sh` (fails=0 on the tag, `evidence/lint-stable-obs.txt`) | the pipeline drives `dbg_state`/`dbg_redirect` constant |
| the atomic side-band | `tcpu_core.v:179-184`, `RD2BridgeV2.scala:136-149`, `AtomicBackend.scala:8-15` | §7.4 |
| CORE_IMPL × NUM_CORES, refused not substituted | `RD2Soc.scala:54-58,119-122` | §9 (R7: `pipeline` × 2 refused until P4) |
| fetch32 / 8-entry TLB / 1 KiB I-cache, 40 MHz, no D-cache, no prediction, one outstanding request | task text | §7, §8 |

## 1. Stages, and what "fire" means (Codex items 1-note and 2)
| stage | work in its cycle(s) | leaves when |
|---|---|---|
| **F1** | holds one 8-byte **fetch word** VA; TLB lookup (combinational, one CAM); miss → fetch-side walk (§3) | translated and F2 can take it |
| **F2** | I-cache lookup on the PA registered by F1 (index + tag); hit → the word is ready this cycle; miss → refill engine (2 beats, geometry `tcpu_icache.v`); uncached → one non-speculative request (§4.3) | its word is in FB, or its first instruction is bypassed straight into ID and the rest is in FB |
| **FB** | fetch buffer, at most 2 words; the instruction extractor (§8.1) | — |
| **ID** | decode (`tcpu_cdecode` for C), register read with WB bypass, legality (`tcpu_core.v:288-391` expressions), interrupt attachment (§5) | EX can take it |
| **EX** | ALU, branch decision, address generation, misalignment, MUL/DIV (`tcpu_muldiv.v`, structural stall), serialisation wait (§2.5), redirect (§1.2) | MEM can take it and its work is done |
| **MEM** | data TLB lookup (first MEM cycle), data-side walk, the ONE data request, its response, load formatting | its access is complete (or it faulted without one) |
| **WB** | **the only commit point**: register write, CSR read-modify-write, trap entry, xRET, `commit_*`/`trap_*`, `resv_clear` | always, in one cycle |

### 1.1 Per-stage handshake (replaces rev. 1's global priority list)
For every back-end stage S with successor N: `ready(N) = !valid(N) || fire(N)`; `fire(S) = valid(S) && done(S) && ready(N)`;
on `fire(S)` the payload moves to N; a stage that does not fire keeps valid and payload; a stage that is flushed drops valid.
**WB always fires**: it commits or traps exactly once and clears its valid in the same cycle unless MEM fires into it — it never
holds and never re-commits (model invariant I8; mutation `NO_ONESHOT` recommits and is caught). A flush from WB (trap, serialiser)
clears MEM, EX, ID and the front end in the same cycle; a redirect from EX clears ID and the front end. Age runs WB (oldest) →
MEM → EX → ID → FB → F2 → F1 (youngest): **a stalled front end lets ID and everything OLDER proceed** (rev. 1 had the direction
reversed). The six-cycle table Codex asked for is `model/TABLES.md` scenario `wb-once`, cycles 5-14: ALU pc 0 commits once at
cycle 6 and WB stays empty from 7 to 13 while load pc 1 waits in MEM; branch pc 2 in EX redirects once (cycle 6) and is then held
in EX until the load leaves MEM at 13; the target pc 8 is fetched meanwhile and waits in ID.

### 1.2 Redirect is one-shot
A taken branch/JAL/JALR in EX redirects **once**, in the first cycle its operands are available (so a branch held behind a waiting
load redirects early and the target fetch overlaps the load), and records that it has done so; it does not redirect again while
it is held (invariant I8; mutation `NO_REDIR_ONESHOT` is caught). The redirect penalty on I-cache/TLB hits is **3 cycles**
(`frontend`: branch pc 4 in EX at cycle 8, target pc 10 in EX at 12, retired 10 → 14).

## 2. Hazards
### 2.1 Forwarding
EX takes each source operand from, in order: the EX/MEM register (an ALU result of the instruction now in MEM), the MEM/WB register
(the value of the instruction now in WB, ALU or load), then the register file with the WB bypass of §2.2. Only valid producers with
`rd ≠ 0` forward; `x0` is never forwarded or written (`tcpu_regfile.v:21-24`).
### 2.2 Same-cycle read/write
`tcpu_regfile.v:22-24` writes on the edge and reads asynchronously, so a read in the write cycle returns the old value: ID bypasses
the WB write (compare with WB.rd && WB.we). The regfile module is reused unchanged.
### 2.3 Load-use
A load's value is forwarded **only from the MEM/WB register**, i.e. once the load is in WB at the start of a cycle. The response is
never forwarded combinationally from the port through load formatting into the ALU. A consumer in EX whose producer load is in MEM
at the start of the cycle does not fire (the model had this wrong in its first version and the `frontend` table exposed it:
the consumer left EX in the response cycle; fixed, `load-use` and `frontend` rows 26-29). Mutation `NO_LOADUSE` is caught.
### 2.4 M extension
`tcpu_muldiv.v` unchanged: 64 iterations + 1 (`tcpu_muldiv.v:120-126`); EX starts it and holds until `done`; no interrupt is attached to an
instruction past ID (§5), so a pending interrupt waits for the multiply to retire, as the multicycle core does in `S_MUL`
(`tcpu_core.v:795-797`).
### 2.5 Serialisation (R1 as ruled)
Serialising: the six CSR forms, MRET/SRET, SFENCE.VMA, FENCE.I, FENCE, WFI. (ECALL/EBREAK are not: they trap at WB, and a WB trap already flushes everything younger; every older instruction has retired by then because the pipeline is in order.) When one reaches EX:
1. **freeze**: no new F1 word, no new refill, no new fetch-side walk, no new uncached fetch; an engine that has not issued its
   current request is abandoned (it has nothing outstanding); anything already raised on the port — including a request whose
   valid is up but not yet handshaken, which cannot be withdrawn — completes;
2. **drain**: it stays in EX until MEM and WB are empty, the port holding register is empty, and no walker or refill exists;
3. then it passes MEM (no access) and WB, where its effect lands with the multicycle core's single-cycle atomicity
   (`tcpu_core.v:481-486,805-823`); WB flushes everything younger and refetches pc+len (or xepc).
The cost is **not constant**: it is the time to finish what is in flight. Model `serial-drain-T{2,6,18}` (a CSR reaching EX with a
fetch refill outstanding): EX-to-commit **4, 8, 20 cycles** for T = 2, 6, 18. Invariant I9 checks the drain.
**WFI** is a serialising no-op that retires once, exactly as today (`tcpu_core.v:366-368`); it never waits, so its "wake-up" does not
depend on anything entering ID. Interrupts follow §5 regardless of WFI.

## 3. Transactions, flush, and the walker (Codex items 1 and 3)
### 3.1 Sticky `killed`, bound to the transaction (replaces the 1-bit epoch)
The core owns ONE port holding register: `{owner ∈ {F (refill beat), NC (uncached fetch), WF/WM (fetch/data walker PTE read),
M (data)}, killed, payload}`. Engines (refill, walker) carry their own `killed` too. **Every front-end flush** (EX redirect, WB trap
or serialiser, interrupt-token attachment) sets `killed` on the holding register if its owner is front-end (F, NC, WF), including
a request whose valid is up but not yet handshaken, and on the refill engine and a fetch-side walker that has a request outstanding;
an engine with nothing outstanding is simply dropped. `killed` is **cleared only by the consumption of that transaction's response**
(the register empties). A killed response — data and `error` alike — is consumed and discarded; a killed refill fills no I-cache
line; a killed walk fills no TLB entry and delivers no PA. There is nothing to wrap: the flag is per transaction, not a counter.
The data side is never killed because a data request is only raised by the oldest instruction (§4.1); a WB flush with a data-side
request pending is an invariant violation (I4).
**Why a 1-bit epoch fails** (Codex's case, model `two-flush`): a speculative fetch walk (valid up, not yet handshaken, RD=3) is
outstanding when the younger EX branch redirects (flush 1, cycle 7) and the older MEM load page-faults at WB (flush 2, cycle 8).
Two flips return the epoch to its old value; the handler's word also misses the TLB, so F1 is waiting for a translation when the
stale walk completes; with mutation `EPOCH1` the stale PA is accepted and the "handler" executes pc 4 instead of pc 60 — caught
by I1. With sticky `killed` the stale response is drained at cycle 14 with no fill, and the handler word walks on its own.
Context switch: a `satp` write or `sfence.vma` is serialising (§2.5), so no walk or fill spans it.
### 3.2 Arbitration
Priority for the one port when it is free: data-side walker > MEM data request > fetch-side walker > refill beat > uncached fetch.
A request once raised is never withdrawn; the next is raised only after the previous response was consumed.
### 3.3 Walker ownership, preemption, deadlock (Codex item 3)
One walker, `tcpu_ptw.v` semantics (A/D software-managed, it never writes: `tcpu_ptw.v:1-8`). Rules:
* A **data-side** walk starts only when its instruction is the oldest (same condition as §4.1), so it is never speculative.
* A **fetch-side** walk is speculative unless ID..WB, FB and F2 are all empty. A speculative walk may issue a PTE read only to
  cacheable RAM (`tcpu_cacheable.v`). If its next PTE address is not cacheable RAM and it is speculative, it **releases the
  walker** without issuing and F1 waits (`waitns`) until the front end is non-speculative, then restarts the walk.
* A fetch-side walk that has **not issued** its current PTE read is **preempted** when a data-side walk needs the walker: it is
  dropped (nothing outstanding) and F1 restarts later. A walk with a read outstanding completes that read first.
* Hence no cycle exists: older instructions never wait for a younger fetch walk, and the fetch walk that waits for the
  non-speculative condition holds nothing. Model `walker-deadlock` (older load misses the data TLB while a wrong-path fetch walk
  needs a non-cacheable PTE): correct design retires all; mutation `NONPREEMPT` (the waiting fetch walk keeps the walker)
  deadlocks and is caught by I5.

## 4. Memory effects (R2, R3 as ruled)
### 4.1 Issue condition
MEM raises its data request (registered: visible the next cycle) only in a cycle where **its instruction is the oldest in the
machine**: WB is empty at the start of the cycle, or WB holds an instruction that commits in this cycle **without** a flush (not a
trap, not a serialiser). Because every flush source is WB (trap, serialiser) or younger than MEM (EX redirect, interrupt
attachment at ID), this excludes every older flush, serialisation and exception, not only `WB.trap`. The same condition gates the
start of a data-side walk. From the request until its response MEM does not fire, so nothing enters WB: the requester stays the
oldest until it retires or takes its own fault. Stores and SC/AMO wait for their response in MEM (no store buffer). Model
`store-under-trap`: an ecall reaches WB in the cycle the younger store could issue — correct design issues nothing; mutation
`MEM_SPEC` issues it and is caught by I2/I3 (a data request whose instruction never retired).
### 4.2 Response acceptance
`resp_ready` stays 1 (as `tcpu_core.v:461`): every owner has a register to catch its response — MEM's data register, the
walker's PTE register, the refill line buffer, F2's word register — so a response is never back-pressured and never lost.
### 4.3 Speculative access
Only cacheable RAM may be touched speculatively (refill beats, PTE reads). An uncached fetch is issued only when ID..WB and FB are
empty. Model `spec-uncached-fetch`: correct design waits; mutation `SPEC_NC` is caught by I6. RTL: a simulation assertion inside the
pipeline core (§10 of TESTPLAN) checks the same condition.

## 5. Interrupts (Codex item 4)
Interrupt acceptance is defined by **age**, at one sampling point:
1. The pending-and-enabled condition (`tcpu_csr.v:182-196`, unchanged) is sampled when ID is loaded. If it holds, no interrupt
   token exists, no serialising instruction is in EX/MEM/WB, then the instruction being loaded into ID becomes the **interrupt
   token**: it executes nothing, `epc = its pc`, its own fetch fault (if any) is dropped. It traps when it reaches WB.
2. **No ID input** (F2 waiting on a miss, the front end parked, a flush just happened): if the condition holds and ID would stay
   empty, ID is loaded with a **synthetic token** whose `epc` is the architectural next pc — the pc the extractor would deliver next
   (`fe_next_pc`), not the fetch pointer, which may be ahead. Latency is therefore independent of fetch misses. Model
   `irq-no-input`: the line rises during a 10-cycle refill; the token is created in the same cycle with epc 2; mutation `IRQ_EPC_FE`
   (epc from the fetch pointer) skips instructions and is caught by I1.
3. **One token at a time**: while a token exists no second is created; attaching a token flushes the front end and parks it until
   the token traps or is flushed.
4. **Older synchronous exceptions win by age**: an older instruction's trap at WB flushes the younger token; the token is gone, the
   level is still pending, and it is sampled again at the next ID load. Model `irq-vs-older-fault`: the line rises with the faulting
   load in EX; the token attaches to the younger pc 3, the load's page fault traps first, the handler runs with interrupts
   disabled, and after `mret` the interrupt is taken once with epc 2.
5. **Enables**: they change only in WB (CSR writes, xRET, trap entry); every such instruction is serialising, so no token is created
   while one is in EX/MEM/WB, and the refetch after it samples the landed enables. A token created before such an instruction is
   older than it and correctly precedes it.
6. The trap: `trap_interrupt`, `cause = irq_cause`, `tval = 0`, exactly as `tcpu_core.v:593-598`.

## 6. Retirement association and the SoC's busy (Codex item 5)
What the SoC actually uses: `cpuRestartSafe` is built from the bridges' pending-work state and the aligned apply
(`RD2Soc.scala:264-269`), not from anything in the core, so the reset-drain safety criterion is unchanged by the core
implementation. `busy` (`RD2Soc.scala:361-374,502-503`) is a **diagnostic** consumed only by the simulation main's end-of-run
settle check (`cpu_boot_main.cpp:67-76`). Its `awaitingRetire` term is set by a data response and cleared by **any** commit or trap
(`RD2Soc.scala:371-372`), which is exact only if the first retirement after a data response is the requester's.
For the pipeline this holds **by §4.1, not automatically**: at the response, WB is empty (nothing entered it since the request was
raised), and the older instruction that may have committed did so in the decision cycle, strictly before valid, fire and
response. Invariant I7 replicates the SoC rule in the model and checks it on every scenario (mutation `MEM_SPEC` breaks it).
**Minimal scheme, no new port:** (a) define `obs.pc` (`dbg_pc`) for the pipeline as the pc of the oldest valid instruction, which
while a data request is held or outstanding is the requester; (b) an SoC-level checker over the existing `EV REQ/RESP/COMMIT/TRAP`
lines (`RD2Soc.scala:374-395`) requires that after every `RESP` of a `fetch=0` request the next `COMMIT`/`TRAP` of that hart has the
`REQ`'s pc; (c) the RTL assertion of §4.1. A separate `quiescent` field in `TeachingCpuObs` is not proposed now (it would be a Scala
change); if a later SoC feature needs a true quiescence signal, it is added then as a listed compatibility change.

## 7. Units: what is shared, what is new (R4, R5 as ruled)
### 7.1 Shared, byte-identical, hash-checked
`tcpu_csr.v tcpu_regfile.v tcpu_muldiv.v tcpu_cdecode.v tcpu_ptw.v tcpu_permcheck.v tcpu_icache.v tcpu_cacheable.v tcpu_defs.vh`.
The pipeline instantiates them unchanged; the build manifest records their sha256 and refuses a mismatch.
### 7.2 Multicycle-only, untouched
`tcpu_core.v`, `tcpu_ifill.v` (it wraps the multicycle port), `tcpu_tlb.v`, `tcpu_xlate.v`. Their hashes stay the accepted ones.
### 7.3 Pipeline-only, new (`rtl/cpu/pipeline/`)
`tcpu_core_pipe.v` (the core), `tcpu_tlb2.v` (the SAME 8 entries, round-robin replacement and full-flush policy as `tcpu_tlb.v:96-111`,
with a second combinational lookup port for F1 and MEM in the same cycle; one fill port from the one walker), the fetch unit (F1,
F2, FB, extractor, refill engine). The dual-lookup TLB is a front-end change of its own: its area and its effect on the 40 MHz
critical path are recorded separately at P3 (R4), and it is **not** described as a shared unchanged module.
### 7.4 Reservations
`resv_clear = rst || (trap taken in WB)` (the pipeline's form of `tcpu_core.v:184`). An LR is issued only as the oldest instruction
(§4.1), so no trap can overtake it.

## 8. Front-end throughput and the timing tables (Codex item 8; R6 as ruled)
### 8.1 Where the instruction length is resolved
F1 steps through **fetch words** (8-byte aligned VA), word+8 each cycle: the fetch address sequence does not depend on instruction
lengths at all. Lengths are resolved only in the **extractor** between FB and ID: it looks at the parcel at its halfword pointer,
bits [1:0] give 2 or 4 bytes, and the pointer advances by 1 or 2 halfwords — a 2-bit decode and a mux per cycle, known in the
cycle the instruction enters ID. `pc+2`/`pc+4` of the instruction in ID is therefore known when it is decoded; the next fetch
word is already in F1/F2. A 32-bit instruction starting in the last halfword of a word needs the next word in FB (FB holds two);
if that word crosses a page it has its own F1 translation, and a fault there is reported with `epc = pc`, `tval = pc + 2`
(`tcpu_core.v:646-647,657-658`). One word per cycle supplies ≥ 2 instructions (≥ 4 if compressed), so on hits the front end
sustains more than one instruction per cycle into an extractor that delivers one.
### 8.2 Latencies, kept apart
| kind | value | anchor |
|---|---|---|
| combinational lookup | TLB CAM in the F1 cycle; I-cache index + tag in the F2 cycle (one each per stage; never chained) | `tcpu_tlb.v:85-94`, `tcpu_icache.v:54-58` |
| acceptance interval | one fetch word per cycle into F1 when F2 can take it; one instruction per cycle into ID | model `frontend` rows 3-8 |
| external request | valid one cycle after the decision; handshake after RD; response T ≥ 2 after the handshake (bridge floor), ≈ 3 simulator, ≈ 18 board DRAM | `RD2BridgeV2.scala:168-201`; `riscv-lab/experiments/E1-clock-scaling/README.md:9` |
| refill | two sequential beats: ≈ 2·(1 + RD + T) + 1 | `tcpu_ifill.v:140-157` |
### 8.3 Tables (all in `model/TABLES.md`)
* **Four ALU instructions on hits** (`frontend` cycles 1-9): pc 0 in F1-word 0 at cycle 1, F2 at 2, ID 3, EX 4, MEM 5, WB 6; pcs 0, 1,
  2, 3 retire at cycles 6, 7, 8, 9 — **II = 1** in steady state.
* **Taken branch** (`frontend` 7-14): branch pc 4 in EX at 8 → target word in F1 at 9, F2 10, ID 11, EX 12; retirements 4 at 10 and 10
  at 14: **3 bubbles**.
* **Load with a data-TLB miss** (`frontend` 12-27): lookup at 14, three PTE reads (15-23), data request 24, response 26, retire 27;
  the dependent pc 12 then waits for WB (load-use, §2.3) and retires at 29.
* **WB-once / MEM-wait / EX-branch** (`wb-once` 5-14), **serialisation** (`serial-drain-T*`), **flushes** (`two-flush`).
### 8.4 Performance statement (R6)
No speed-up is promised or used as a gate. The design target is **II = 1 for ALU instructions on I-cache/TLB hits**, shown above;
everything else is measured. With one port and one outstanding request, fetch and data overlap only on I-cache hits, and every
load/store pays the full memory latency (no D-cache, no second outstanding request — both excluded). The rev. 1 mix estimate
(≈1.9 simulator / ≈5.7 board CPI) was an illustrative model of an assumed instruction mix, not a workload; it is withdrawn as a
target. The fixed-work `perfcompute` is dominated by the 65-cycle multiply loop and will show little from pipelining; that is
stated now, not discovered later.

## 9. Configuration, and the rulings as applied
### 9.1 Identity without a new port (R5)
The pipeline core is module **`tcpu_core_pipe`** with the same 61 ports and parameter names; the multicycle file stays module
`tcpu_core`. `TcpuCoreBlackBox` takes the implementation as a constructor argument and sets `desiredName` to `tcpu_core` or
`tcpu_core_pipe`; `TeachingCpuV2`/`TeachingHart` pass `RD2Params.coreImpl` down. A file list that does not match the
configuration fails with "module not found" in Verilator and Vivado alike — a structural guard, no runtime signal, no new port.
**This is a Scala change**, listed: `TeachingCpuBlackBox.scala` (constructor arg, `desiredName`), `TeachingHart.scala` (pass-through),
`RD2Soc.scala` (`require` accepts `pipeline` only with `numCores == 1` until P4; every other value still refused by name). Gate for
it (P1): the generated Verilog of every existing configuration is byte-identical before and after. The build manifest additionally
records `CORE_IMPL` and the sha256 of every core file and refuses a mismatch.
### 9.2 Rulings
| # | ruling (Codex) | where applied |
|---|---|---|
| R1 | drain + refetch, with freeze of new IF/walker and completion of raised requests; WFI not dependent on ID input | §2.5 |
| R2 | stores await their response; issue excludes every older flush/serialisation/exception; WB fires once | §4.1, §1.1 |
| R3 | speculative access only to cacheable RAM, PTE reads included; walker deadlock solved | §3.3, §4.3 |
| R4 | shared 8-entry TLB with two lookup ports, as a separate front-end module with its own area/timing record; multicycle TLB untouched | §7.3 |
| R5 | anti-fallback by module identity + build manifest; no new port; Scala change listed | §9.1 |
| R6 | no ≥2× gate; II = 1 on ALU hits is the design target; everything else measured | §8.4 |
| R7 | P1 standalone RV64I core; P2 full single-core ISA + xv6; P3 single-core board; P4 dual pipeline; `pipeline`×2 refused until P4 | §9.1, TESTPLAN |
| R8 | future composition direction recorded; no framework now | §10 |

## 10. Future configuration boundary (unchanged from rev. 1 except where R5 moved the identity)
| switch | wiring point today | values that exist | pipeline impact |
|---|---|---|---|
| CORE_IMPL | `RD2Params.coreImpl` (`RD2Soc.scala:58`, refused at `:119`) + the core module name (§9.1) | `multicycle` | adds `pipeline` |
| NUM_CORES | `RD2Params.numCores` (`RD2Soc.scala:57`, refused at `:121`) | 1, 2 | orthogonal; `pipeline`×2 refused until P4 |
| fetch policy | inside the core: OPT01 aligned fetch (`tcpu_core.v:607-613`); tags `ips-v1-baseline`/`ips-v1-fetch32` | fetch32 only | the pipeline fetches 8-byte words (§8.1); no switch offered |
| TLB_ENTRIES | Verilog parameter (`tcpu_core.v:15`), not passed by the BlackBox (default 8) | 0, 8 at core level | same name and meaning in `tcpu_core_pipe` |
| ICACHE_BYTES | Verilog parameter (`tcpu_core.v:16`), not passed by the BlackBox (default 1024) | 0, 1024 at core level | same |

Status levels, used verbatim in every later report: *expressible* < *implemented* < *simulated* < *board-proven*. Today
multicycle × {1,2} with TLB 8 / I-cache 1 KiB / fetch32 is board-proven; TLB 0 and I-cache 0 are simulated at core level only;
nothing with `pipeline` exists. A combination below *implemented* is refused at elaboration by name; presets and a validation
matrix come after the single-core pipeline is accepted.
