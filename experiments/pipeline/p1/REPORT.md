# PIPE-P1 REPORT — a standalone RV64I pipeline core, verified by architectural differential

Task `codex-pipe-p1-standalone`. Worktree `worktrees/pipe-single` (branch `pipe-single`, from tag `mc-v1-dual` 93b8117).
Standalone harness only: no SoC, Scala, Vivado, board, dual pipeline, push or tag. Final evidence: simulators `runs/sims-4`,
run `runs/run-3` (both kept on disk, not committed; their summaries are in `results/`).

## 1. What was built
`rtl/cpu/pipeline/tcpu_core_pipe.v`: module **`tcpu_core_pipe`**, the same 61 ports and parameter names as the multicycle
`tcpu_core`. It is **not** an unqualified textbook five-stage pipeline. The front end is F1 (fetch-word VA; Bare, so
translation is a range check), F2 (I-cache lookup on the registered PA, 2-beat refill engine or one direct fetch), and a
4-instruction fetch buffer with an F2→ID bypass. The back end is ID / EX / MEM / WB with per-stage `ready = !valid || fire`.
* **Scope (P1 as ruled):** RV64I, Zicsr, MRET, ECALL/EBREAK, FENCE / FENCE.I / WFI, machine-level traps and interrupts,
  Bare addressing only. All three serialise: the front end freezes, the pipeline drains, and the commit in WB flushes and
  refetches from the next instruction. FENCE and WFI do nothing else. FENCE.I also invalidates the I-cache in the cycle it
  commits (`ic_inval = wb_commit && wb_is_fencei`), so the refetch misses. *(Corrected: the first version of this report
  called all three "serialising no-ops", which is wrong for FENCE.I.)*
  **Illegal in P1:** M, A, C (a compressed parcel), SRET, SFENCE.VMA. `misa` reads back `0x8000000000000100` (RV64I).
  IALIGN = 32: a taken branch or jump to an address with bit 1 set raises cause 0.
* **Unchanged shared RTL:** `tcpu_regfile`, `tcpu_csr` (every CSR access, trap entry and MRET happen in WB),
  `tcpu_icache` (same 1 KiB geometry), `tcpu_cacheable`, `tcpu_defs.vh`. The multicycle files `tcpu_core`, `tcpu_ifill`,
  `tcpu_tlb`, `tcpu_xlate` and `tcpu_ptw` are untouched. `results/G.txt` shows 13 files byte-identical to the tag.
* **Control, per CONTRACT rev. 3:** EX/MEM and MEM/WB forwarding, WB→ID bypass, operands refreshed while EX is held.
  A load-use interlock takes the load's value only from MEM/WB. WB fires exactly once, and a redirect is one-shot, taken in
  the first cycle the operands are ready (even while EX is held). A data request is raised only when MEM holds the oldest
  instruction. Fetch transactions carry a sticky per-transaction kill. Serialising instructions freeze the front end, then
  drain. Interrupts attach at the ID load, with a synthetic token when ID has no input. A token is cancelled at WB if its
  line was quieted meanwhile.
* **Refused at elaboration:** every multicycle-only or unimplemented parameter when non-zero (A, M, C, S-mode, Sv39, IRQ and
  A fault injections), an I-cache size other than 0 or 1024, and `PIPE_FAULT` > 14 (> 12 before §9). Each produces a missing-module error
  that names the parameter.
* **Twelve negative controls** via `PIPE_FAULT` = 1..12 (listed in the module header), and two more since §9 (13, 14). Simulation-only assertions (`PIPE
  ASSERT …`), fault-effect lines (`PIPE FAULT-EFFECT …`), coverage counters, and an opt-in per-cycle dump (`+pipe-debug`).

## 2. Implementation selection and source pinning
The harness (`tests/cpu/tb/tcpu_harness.v`) instantiates `tcpu_core_pipe` only under `` `define TCPU_IMPL_PIPE ``, and
`tcpu_core` otherwise. Its default behaviour is unchanged: every new parameter defaults to off. The build copies one source
snapshot and records its hashes (`results/src.sha256`), and lists every module file explicitly.
**Finding: a silent-fallback path, fixed.** The first build (`results/identity-sims-1-FOUND-FALLBACK.txt`) showed that a
build with *no* define and *only* the pipeline sources still succeeded. Verilator treats every `-I` directory as a module
search path too, so it silently compiled `rtl/cpu/tcpu_core.v`. The build now uses an include-only directory holding just
`tcpu_defs.vh`. All four identity checks now fail as required (`results/identity.txt`). *(Runner gate, §8: each check must
now fail with a non-zero, non-timeout status and its named error, and a failed check makes `build-sims.sh` exit non-zero.
At `ef9706f` the checks were only printed.)*
* the define with the multicycle list fails because `tcpu_core_pipe` is not found;
* no define with the pipeline list fails because `tcpu_core` is not found;
* `MISA_A=1` is refused;
* `PIPE_FAULT=13` is refused (since §9 the check uses 15, because 13 and 14 exist).
The same `-I` behaviour exists in the older build scripts (`rd2-build-sim-fast.sh` uses `-I$RTL`), which matters for the P2
SoC flows.
The harness main was copied to `tb/tcpu_main.cpp` (source `teaching-cpu-work/cpu/tb`, hash b67fba09…). The only change is
that it accepts three harness-read plusargs: `+pipe-trace`, `+irq-at-retire`, `+pipe-debug`.

## 3. Verification (`scripts/run-p1.sh`; deterministic; every run bounded by `+max-cycles`, `timeout`, `PROGRESS_BOUND`)
### 3.1 Existing programs on both implementations (`results/A.txt`, min profile, accepted expectations)
| program | multicycle (tag RTL) | pipeline | note |
|---|---|---|---|
| t01–t05, t01n_x0check, c05, c07, c08, c09, d01–d06 (d05 ×7), d08 | PASS | PASS | |
| **c06_targets** | **FAIL (check 3)** | PASS | a baseline failure of the tag core, the M1 `m23/jump-targets` item. The program expects IALIGN-32 behaviour for a bit-1 target; the tag core has C (IALIGN 16), the P1 pipeline has not. **Not a pipeline pass of the baseline item.** |
| **d07_csr_cycle** | FAIL (check 38) | FAIL (check 38) | an M2-1 program asserting that reading `cycle` is illegal. The shared CSR file has implemented the counters since M2-2, and the accepted M2-3 run did not include d07. Same result on both implementations, because the cause is shared; not a P1 finding. |
| p1_misa (pipeline only) | FAIL (by design: the tag reports M, C, S, U) | PASS | |
| i08, i09, j02 | not run | not run | they use the multicycle core's state-based injection points (`IRQ_POINT` 1..12, which read `dbg_state`). The pipeline drives `dbg_state` constant, so they cannot be positioned; they are replaced by the P1 interrupt programs of §3.3. |
The SU 9 / M 6 / C 16 suite baselines (M1 T1.4) apply to M, C and S/U, which P1 does not implement. They were not re-run
here, and none is claimed.

### 3.2 Architectural differential (`results/B.txt`, `results/B-per-run.txt`)
The multicycle core is the reference. Compared: exit code; the full retirement stream (pc, instruction, rd, value, length); the
data-request stream (address, write, size, wdata, wmask; cycles removed); the final memory image (64 KiB). Not compared:
fetches, refills and cycle numbers. The pipeline log must also be free of assertions and protocol, observation, latency or
progress errors.
Programs:
* the completing existing programs;
* 8 directed P1 programs (`tests/`);
* 40 generated hazard programs (`scripts/gen-hazard.py`, 400 instructions each, dense RAW distances 1–3, x0, loads/stores,
  forward branches, counted loops, JAL/JALR, CSR writes, ECALL and misaligned-load traps).

Profiles: min (READY 0 / RESP 1), fixed (2 / 5), random seeds 12345, 777 and 4242.
**Result: 295 / 295 DIFF_OK**, all exiting 0. That is 183,390 retirements and 38,960 data requests compared.
*(Corrected from 183,685: at `ef9706f`, `p1diff.py` counted the commit-trace header line as a retirement, one per run, so
every `retired=` figure in `results/B.txt`, `B-per-run.txt` and `C.txt` is one too high. The files are kept as recorded.
The comparison itself skipped the header on both sides and is unaffected. All 295 pairs, and the 111 aligned interrupt
pairs, also pass the stricter completion check of §8: `results/strict-rejudge-run-3.txt`.)*
**Finding: a real deadlock, fixed.** Run-1 (`results/run-1-deadlock-finding.txt`) had 3 failures, hz22/28/29 on the min
profile: after an ECALL the handler's first CSR instruction never left EX. Cause: a fetch response arriving in the same
cycle as a front-end flush was treated as live by the response logic *and* killed by the flush. That left the engine killed
and "needing" its next beat, never issued and never idle, so every later drain waited forever. Fix: a flush kills only what is
still outstanding after the cycle, and a new assertion (`engine-state`) guards the state. This is the same-cycle case
CONTRACT §3.1 is about. The directed tests had not hit it; the random differential did.

### 3.3 Interrupts (`results/C.txt`)
The oracle is independent of the reference. The programs check cause, epc, the count of executed instructions (none lost or
repeated) and the number of interrupts. The harness bounds the latency between an enabled raised line and its trap, and the
cycles without progress. The line is raised architecturally, after N retirements (`+irq-at-retire`).
Programs:
* **basic**: straight-line block;
* **masked**: masked, then enabled; mepc must be exactly the instruction after the enable;
* **fault**: an older load fault and an interrupt;
* **hold**: a permanently pending line that must be taken three times;
* **empty**: the front end has no instruction for ID;
* **warm**: the token attaches to a real instruction;
* **cancel**: the program quiets the line with a store while a token is in flight.

Coverage: 41 positions × 3 profiles.
**Result: 123 / 123 pass their own checks.** Worst latency is 8 cycles (usually 4). Every path is hit:
* 33 tokens on real instructions;
* 93 synthetic tokens, 57 of them created while the fetch pointer was ahead of the architectural next pc;
* 3 cancelled tokens.

**Equivalence technique (not the oracle):** for each of the 111 runs that took an interrupt, the reference was re-run with
the raise placed so that it took the interrupt after the same number of retirements (k). All 111 streams are identical. The
12 cancel runs took no interrupt, so they have no alignment and are judged by their own checks only.

### 3.4 Negative controls (`results/D.txt`, fixed profile): 12 / 12 caught by the intended property as the FIRST failure
| knob | program | caught by |
|---|---|---|
| 1 WB_HOLD | p1_loaduse | `PIPE ASSERT once-only` (seq retired again) |
| 2 REDIRECT_REPEAT | p1_branch | `PIPE ASSERT redirect-once` |
| 3 EPOCH_BIT | hz10 | `PIPE ASSERT fetch-delivery`. After two flushes the stale refill line is handed to F2 while it waits for the **trap handler's** line, and the program then trap-storms: CONTRACT §3.1's scenario, on real code |
| 4 STORE_UNDER_TRAP | p1_store_trap | `PIPE ASSERT oldest-issue` (a store raised while the older ECALL traps in WB) |
| 5 NO_LOADUSE | p1_loaduse | `PIPE ASSERT load-use` |
| 6 / 7 / 8 NO_FWD_EXMEM / NO_FWD_MEMWB / NO_WB_BYPASS | p1_fwd | the core logs `PIPE FAULT-EFFECT` where the knob changed an operand really used. The first divergence from the reference is such a point: records 1, 18 and 61, counted from 0 *(corrected from 62)* (for knob 8, a store that trapped on a wrong address instead of retiring) |
| 9 X0_FWD | p1_fwd | check 7 (a write to x0 forwarded) |
| 10 IRQ_EPC_FETCHPTR | p1_irq_empty, N=20 | check 1 (instructions skipped) |
| 11 CSR_NO_DRAIN | p1_csr | `PIPE ASSERT drain` |
| 12 SPEC_MMIO_FETCH | c08_accessfault | `PIPE ASSERT spec-uncached` (a jump into non-existent, uncached space) |
Controls: knobs 3, 9, 10 and 12 on programs that do not exercise them pass. No forwarding knob has a control, because
every program forwards.
**Judging corrections made during P1, recorded:**
* the judge now takes the first failure signal: knob 1's assertion is followed by a timeout, and the timeout is not the
  finding;
* a retirement-distance proxy misjudged knobs 7 and 8, because retirement distance is not pipeline position after a
  bubble. It was replaced by the core-logged effect points;
* knob 12 was first reported "not exercisable". That was wrong: `c08` reaches uncached fetch.
* the store, cancel and empty-front-end tests were retimed after tables showed they missed their window.

### 3.5 Monitors and existing injections on the pipeline (`results/E.txt`): 5 / 5 caught
Same-cycle response, request withdrawal and read-with-payload each raise their PROTO ERROR. `X0_WRITABLE` fails `t01`,
and `NO_LOAD_SEXT` fails `t03`.

### 3.6 Test defects found and fixed while writing (not counted as results)
* **Checks that could not fail:** `CHECK_EQ` loaded its constant into `t6`, so `CHECK_EQ(t6, …)` compared a register with
  itself; the macro now uses `gp`. `CHECK_REG(x20, x20)` was replaced by a comparison with the real link address.
* **A startup exit that overwrote main's return value.**
* **A generator write to `mscratch`,** the handler's stack pointer. It now writes `mtval`.
* **Forward labels landing inside loops or between `la` and `jalr`.**
* **A comment the C preprocessor read as `#line`.**
Every one showed up as the *same* wrong result on both implementations, which is how they were told apart from core bugs.

## 4. Performance (`results/F.txt`; second pass, warm I-cache; ROI = retirement to retirement)
| ROI | multicycle CPI (min / fixed) | pipeline CPI (min / fixed) | pipeline interval histogram (min) | cause of anything above 1 |
|---|---|---|---|---|
| 64 independent ALU | 6.00 / 6.00 | **1.00 / 1.00** | 1:65 | — (II = 1 met) |
| 64 dependent ALU (EX/MEM chain) | 6.00 / 6.00 | **1.00 / 1.00** | 1:65 | — (II = 1 met) |
| 16 × (load + dependent add) | 7.94 / 10.85 | 3.42 / 6.33 | 1:1 2:16 5:16 | the load's memory round trip (one request in flight, response ≥ next cycle) plus one load-use bubble; the port is allocated only the cycle after a response |
| taken-branch loop (2 instr) | 6.00 / 6.00 | 2.43 / 2.43 | 1:34 4:31 | 3 bubbles per taken branch (no prediction, by task) |
| 16 independent stores | 9.77 / 15.41 | 4.77 / 10.41 | 1:1 5:16 | each store waits for its response (no store buffer, R2); plus the next-cycle port allocation |
The design target, **II = 1 for ALU instructions on hits, is met**. Everything else is memory-bound, as CONTRACT §8.4 said.
One visible inefficiency: the port is re-allocated only the cycle *after* a response (`port_free = !preq_valid && !pwait`),
which costs one cycle per access. It is not changed in P1. These are **simulator** numbers from the standalone harness,
not board or SoC performance, and no overall speed-up is claimed. The front-end change (fetch words, fetch buffer, bypass)
and the back-end pipelining are not separated here. P3 must compare them separately.

## 5. Lint
`verilator --lint-only -Wall` on the pipeline core reports one warning: BLKSEQ, a blocking assignment to a function-local
variable. It is correct. There are no width, latch or case warnings.

## 6. The P2 seams, and the walker question
* **Translation.** F1 is the translation stage (Bare: a range check). P2 puts the 8-entry dual-lookup TLB and the walker
  there, and MEM's first cycle is the data lookup.
* **Walker: can the unchanged `tcpu_ptw` support abort and preemption through a wrapper?** By analysis, **yes**. Its
  request (`req_valid`, `tcpu_ptw.v:105`) is its own output, and the pipeline's port arbiter decides when to forward it. A
  wrapper can therefore abort a walk with a local synchronous reset (`tcpu_ptw.v:85-89` clears everything) at any moment
  when the walker has **no request accepted by the port**. That covers preemption by a data-side walk, a speculative
  non-cacheable PTE address (visible on `req_addr` before forwarding), and a killed walk after its response has been
  consumed. Nothing is withdrawn on the port, because an unforwarded request never reached it. **Not demonstrated yet:** the
  first P2 item is a unit test that aborts the walker in IDLE, REQ-not-forwarded and after each level's response, and shows
  no port-visible withdrawal and no stale fill. If it fails, a separate pipeline walker is proposed; shared RTL is not changed.
* **Retirement association and the SoC's busy** (CONTRACT §6, rev. 3). P1 has no page-table reads, so every non-fetch request
  is architectural data, and the DREQ comparison covers it. P2 needs explicit owner metadata to separate PTE reads from data.
  The SoC settle behaviour is resolved in P2.
* **Scala/SoC plumbing** (BlackBox `desiredName`, `coreImpl`, and the old-configuration elaboration comparison) is P2, as ruled.

## 7. Rerun
```bash
P=/home/engineer/fpga/worktrees/pipe-single/experiments/pipeline/p1
bash $P/scripts/build-sims.sh $P/runs/sims-N          # 85 s here (sims-5), 27 simulators + identity gate; exit 0 only if both pass
bash $P/scripts/run-p1.sh $P/runs/sims-N $P/runs/run-N 40   # 35 s here (run-4); sections A-H, coverage, verdict = exit status
python3 $P/scripts/p1verdict.py <run dir> [--nhz N] [--coverage FILE]
python3 $P/scripts/p1coverage.py <run dir>
python3 $P/scripts/p1diff.py [--require-complete] <multi-prefix> <pipe-prefix>
bash $P/scripts/selftest-p1diff.sh <run dir> <fresh dir>; bash $P/scripts/selftest-idcheck.sh <sims dir> <fresh dir>
bash $P/scripts/selftest-verdict.sh <run dir> <coverage file> <fresh dir>
bash $P/scripts/mutate-gates.sh <run dir> <coverage file> <sims dir> <fresh dir>   # seconds; no simulator is run
python3 $P/scripts/mutjudge.py first|effect ...
python3 $P/scripts/perf.py <log> <nm-file>
```

## 8. Runner gates (task `codex-pipe-p1-runner-gates`)
At `ef9706f` both entry points exited 0 whatever happened. `build-sims.sh` printed its identity checks without judging
them, and `run-p1.sh` always ended with `RUN_P1_DONE`. The results above were judged by reading the summaries. The fixes
below change only the scripts and this report. No RTL, harness or test program changed. The run-3 evidence was re-judged
from its files as recorded, and nothing was re-run.
* **Identity gate** (`scripts/idcheck.sh`, used by `build-sims.sh`). Each wrong selection must fail to build with a
  status other than 0 or 124 (timeout), *and* its log must contain the named error. Otherwise the check counts as failed,
  and `build-sims.sh` exits non-zero. A build that succeeds, times out, or fails for an unrelated reason is rejected.
* **Strict differential** (`p1diff.py --require-complete`, used for all of B and for the C alignment runs). Equality is not
  success: each side must exit 0, and its log must end with a normal `TOHOST code=0 … (store answered and retired)`. The
  commit stream must not be empty. Two runs that fail or time out identically are now a failure.
* **Verdict** (`scripts/p1verdict.py`, the exit status of `run-p1.sh`). It fails on an unexpected positive-test failure,
  missing or extra output, an uncaught negative control, a failed control run, a changed shared source, or a zero or
  missing coverage counter. The expected results in D and E are what it requires. It tolerates exactly four named baseline
  exceptions in A, each with its exact recorded result:
  * c06_targets on the multicycle core;
  * d07_csr_cycle on both cores;
  * p1_misa on the multicycle core.
  A different failure of the same program is a failure, and so is an exception that unexpectedly passes.
* **Coverage** (`scripts/p1coverage.py`). The old glob matched `[ABC]/*-p.log` *and* `B/*-p.log`, so every B run was
  counted twice. `results/coverage.txt` is kept as recorded: 739 runs. The corrected totals are in
  `results/coverage-dedup-run-3.txt`: 444 runs (A 26, B 295, C 123). The interrupt counters quoted in §3.3 are unchanged,
  because B raises no interrupts. Every other counter was inflated by its B share.

Run-3 under the gates: `results/verdict-run-3.txt` is **PASS**, with the four named exceptions and no failure reasons.
The submitted evidence was re-judged from its files, and neither sims-4 nor run-3 was changed.

End to end, the gated entry points were then run once more into new directories (`results/e2e-sims-5-run-4.txt`).
`build-sims.sh` built `runs/sims-5` from the same source snapshot as sims-4. All four identity checks passed the gate
(`results/identity-sims-5.txt`), and the script exited 0. `run-p1.sh` on it wrote `runs/run-4` and exited 0 with verdict
PASS (`results/verdict-run-4.txt`). Sections A, D, E, F and G are byte-identical to run-3. B and C are identical except
that every `retired=` figure is exactly one lower: 295 of 295 and 111 of 111, the header correction. The coverage
equals the de-duplicated run-3 totals. All 81 program images are identical to run-3.

Self-tests (`results/selftest-*.txt`). Each is cheap and works on copies. Each gate was itself mutation-tested by
`scripts/mutate-gates.sh`: every mutant removes one check from a copy of the gate, and the self-test must then fail.
Result: 28 / 28 caught (`results/gate-mutants.txt`).
| gate | self-test | cases | mutants of the gate, each caught |
|---|---|---|---|
| strict differential | `selftest-p1diff.sh` on copies of a run-3 pair: identical timeouts (strict and, as the old behaviour, non-strict), empty streams, no completion line, identical non-zero exit, a real difference | 7 / 7 | 5 / 5 (exit check, completion check, empty check, strict mode off, stream comparison) |
| identity | `selftest-idcheck.sh`: stubbed builds plus two real `--lint-only` elaborations of the sims-4 sources | 9 / 9 | 3 / 3 (the non-zero-status check, the timeout check, the named-error check). The real `-I` at the RTL directory elaborates and is rejected; the include-only directory is accepted. |
| verdict | `selftest-verdict.sh` on 24 mutated copies of the run-3 summaries, each changing one thing | 24 / 24 | 20 / 20 checks removed one at a time; each turns exactly its own case red |

## 9. Same-cycle flush boundaries in the fetch engine (task `codex-pipe-p1-flush-boundary`)
Codex found two gaps by reading the source. Both are reproduced here on the original core (`c81daae`) and closed by
two guards in `tcpu_core_pipe.v`. No shared module changed.
* **A refill answered in a flush cycle still filled the I-cache.** A live final beat set the fill from the old kill flags.
  The later flush cleared F2 and stopped the engine, but did not cancel the fill. CONTRACT §3.1 says a flushed refill
  fills nothing. The data was the correct memory line, so no program output was wrong. *Fix:* a flush cancels the fill
  scheduled in the same cycle.
* **A request raised in a flush cycle was left with no owner.** The engine could allocate the port in the flush cycle.
  The flush then saw no request yet, killed nothing, and dropped the engine to idle. The request went out anyway, and its
  response was later discarded silently. *Fix:* the engine does not allocate in a flush cycle. The request was never
  visible on the port, so nothing is withdrawn.

**The bench** (`flushwin/`). It drives the pipeline core directly, without the harness: 64 KiB of RAM, one request in
flight, fixed ready and response delays, and an interrupt line. It also answers every fetch of one wrong-path line with
a bus error. A self-checking program forces refills every iteration with FENCE.I, and contains taken jumps and branches
over prefetched lines, ECALL/MRET, CSR accesses, loads and stores. For each of 15 timing profiles the interrupt is
raised at every cycle of the program, one run per cycle. The bench observes the core through hierarchical references,
independently of the core's own assertions, so it judges the original core too. It sees each flush as a toggle of the
front-end epoch register, and classifies the cycle into the windows Codex listed:
* the final or first refill beat answered in the flush cycle;
* the engine allocating in it;
* a fetch request offered and not ready, or handshaking;
* an error response.

It checks these properties:
| property | meaning |
|---|---|
| fill-after-flush | no fill scheduled in a flush cycle |
| killed-fill | no fill from a response of a transaction outstanding across a flush |
| fetch-owner | a fetch request is raised or outstanding exactly when the engine waits for it, with the same kill state |
| fill-data | every fill is the memory line, and never the error line |
| payload / withdraw | an offered request keeps its payload and stays valid until its handshake |
| id-content, id-fetch-fault | every instruction reaching ID is the memory word at its pc; a fetch fault appears only on the error line |
| completion | exit 0, the multicycle reference checksum, and the interrupt count on the trap port equals the program's |

**New assertions in the core.** `PIPE ASSERT fetch-owner` and `PIPE ASSERT fill-after-flush` check the same invariants
in every simulation, so sections A–G check them too.

**Negative controls.** Knob 13 (FLUSH_FILL) removes the fill guard. Knob 14 (FLUSH_ALLOC) removes the allocation
guard.

**Results.** The multicycle reference checksum for the bench program is `4468d22c6cd13710`
(`results/flushwin-ref.txt`).

| core | runs | failing runs | failing property |
|---|---|---|---|
| original, I-cache (`runs/fw-prefix-2`) | 40,171 | 40,171 | fetch-owner in all; fill-after-flush in 870 |
| original, no I-cache | 44,509 | 44,509 | fetch-owner |
| fixed, I-cache (`runs/run-5/H`) | 38,715 | 0 | — |
| fixed, no I-cache | 41,749 | 0 | — |
| knob 13 | 38,715 | 870 | fill-after-flush only, in the bench and in the core |
| knob 14 | 40,171 | 40,171 | fetch-owner only, in the bench and in the core |

Every run of every core exits 0 with the reference checksum. These defects break the contract, not the program's
output, and only the properties catch them. The 870 fill failures are exactly the 870 final-beat windows.

Flushes that fell into each window, fixed core, summed over all runs and flush sources (`results/H-run-5.txt`):
| window | I-cache | no I-cache |
|---|---|---|
| final beat answered | 870 | 1,890 |
| first beat answered | 870 | n/a (one-beat fetches) |
| engine allocating | 1,359,600 | 2,087,842 |
| request offered, not ready | 158,200 | 170,596 |
| request handshaking | 1,820 | 1,890 |
| error response | 120 | 0 (not reached; not required) |

**Windows that needed no change, with the invariant that closes each** (all checked by the properties above):
* **First beat and flush.** The flush overrides the engine's next state to idle, and the port empties in the same
  cycle. Nothing is filled, because only the final beat fills.
* **Offered, not ready, and flush.** The flush kills both the held request and the engine. The request stays valid,
  with the same payload, until its handshake. Its response is consumed and discarded, and it fills nothing. Draining
  waits for it, because the drain condition requires an empty port and an idle engine.
* **Error response and flush.** An error never fills. An error delivered in the flush cycle goes to an F2 that the
  flush empties, so no fault reaches ID.
* **Data requests cannot be orphaned.** A data request needs `oldest_true`, which needs WB to commit normally, and a
  WB flush means WB does not. EX redirects and interrupt attachment flush only younger stages. The existing
  `oldest-issue` and `data-response` assertions and knob 4 cover this.

**The P1 matrix after the fix** (`runs/sims-6`, `runs/run-5`) passes with exit status 0 (`results/verdict-run-5.txt`).
B is 295 / 295, C is 123 / 123 with 111 aligned, D is 12 / 12, E is 5 / 5, G is 13 / 13, and H passes.
* **Unchanged from run-4:** A, F and G, byte for byte, and every B result line, including the retirement counts.
  ALU II = 1 still holds.
* **Changed, but only in timing:**
  * C is identical except the latency figure of 8 cancel-program runs. The worst latency is now 9 cycles, up from 8,
    in one run (p1_irq_cancel N=46 rnd12345). An engine allocation that meets a flush now waits one cycle. The bound
    stays 2000.
  * D and E differ only in cycle counts. Some programs end a few cycles sooner, because orphan fetch requests no longer
    hold the port. Knob 11 is still caught first by its `drain` assertion, now at pc 0x8000015c.
* **Lint:** the `-Wall` warning set of the core is identical to the original.

**Gates.**
| gate | self-test | result |
|---|---|---|
| strict differential | `selftest-p1diff.sh` | 7 / 7 |
| identity | `selftest-idcheck.sh`, now PIPE_FAULT 15 | 9 / 9 |
| verdict | `selftest-verdict.sh`, 3 new H cases | 27 / 27 |
| flush-window judge | `flushwin/selftest-fwjudge.sh` | 14 / 14 |
| all four gates | `mutate-gates.sh` | 40 / 40 mutants caught |

The judge self-test works on a thinned copy of the knob-14 logs, and checks first that the thinned copy is judged
identically to the original (832 MB → 22 MB).

**Bench correction during the work.** The first checksum included `misa`, which differs between the cores by design,
so the multicycle reference disagreed. It now uses `mhartid`. `runs/fw-prefix-1` keeps the first pre-fix sweep, made
with the `misa` program (`results/flushwin-prefix-1.txt`).


## 10. Acceptance (recorded at the start of P2a)
Codex gave P1 its final acceptance on 2026-09-29 (`.coord/proposals/claude-pipe-p1-flush-boundary-ready.md.ack`) for
the standalone scope: RV64I, Zicsr, the machine-level trap subset, Bare addressing, the standalone harness.
**Immutable anchor: commit `53b1aac`** on branch `pipe-single`. The P1 pipeline core is `rtl/cpu/pipeline/tcpu_core_pipe.v` as of that commit.
* **Codex's independent evidence** (`experiments/pipeline-review-p1-final-build` and `-final-run`): a fresh build
  followed by a complete A–H run, `verdict_rc=0`. One Verilator thread-pool internal build failure was retried with
  `-j1` from the same pinned inputs.
* **Results:** B 295; C 123 plus 111 aligned; D 12; E 5. H: both new negative controls caught, and 0 failures in 80,464
  fixed-core runs. The 13 shared files are unchanged, and the ALU ROI CPI is 1.
* **Not claimed:** the four named baseline exceptions stay exceptions, not passes. This is not full-ISA, SoC or board
  certification, and there is no new board evidence.
Later work (P2a onward) changes the pipeline core in new commits. The P1 configuration (M and C off) must keep
passing A–H.
