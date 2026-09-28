# PIPE-P1 REPORT — a standalone RV64I pipeline core, verified by architectural differential

Task `codex-pipe-p1-standalone`. Worktree `worktrees/pipe-single` (branch `pipe-single`, from tag `mc-v1-dual` 93b8117).
Standalone harness only: no SoC, Scala, Vivado, board, dual pipeline, push or tag. Final evidence: simulators `runs/sims-4`,
run `runs/run-3` (both kept on disk, not committed; their summaries are in `results/`).

## 1. What was built
`rtl/cpu/pipeline/tcpu_core_pipe.v`: module **`tcpu_core_pipe`**, the same 61 ports and parameter names as the multicycle
`tcpu_core`. It is **not** an unqualified textbook five-stage pipeline. The front end is F1 (fetch-word VA; Bare, so
translation is a range check), F2 (I-cache lookup on the registered PA, 2-beat refill engine or one direct fetch), and a
4-instruction fetch buffer with an F2→ID bypass. The back end is ID / EX / MEM / WB with per-stage `ready = !valid || fire`.
* **Scope (P1 as ruled):** RV64I, Zicsr, MRET, ECALL/EBREAK, FENCE / FENCE.I / WFI (serialising no-ops), machine-level traps and
  interrupts, Bare addressing only. **Illegal in P1:** M, A, C (a compressed parcel), SRET, SFENCE.VMA. `misa` reads back
  `0x8000000000000100` (RV64I). IALIGN = 32: a taken branch or jump to an address with bit 1 set raises cause 0.
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
  A fault injections), an I-cache size other than 0 or 1024, and `PIPE_FAULT` > 12. Each produces a missing-module error
  that names the parameter.
* **Twelve negative controls** via `PIPE_FAULT` = 1..12 (listed in the module header). Simulation-only assertions (`PIPE
  ASSERT …`), fault-effect lines (`PIPE FAULT-EFFECT …`), coverage counters, and an opt-in per-cycle dump (`+pipe-debug`).

## 2. Implementation selection and source pinning
The harness (`tests/cpu/tb/tcpu_harness.v`) instantiates `tcpu_core_pipe` only under `` `define TCPU_IMPL_PIPE ``, and
`tcpu_core` otherwise. Its default behaviour is unchanged: every new parameter defaults to off. The build copies one source
snapshot and records its hashes (`results/src.sha256`), and lists every module file explicitly.
**Finding: a silent-fallback path, fixed.** The first build (`results/identity-sims-1-FOUND-FALLBACK.txt`) showed that a
build with *no* define and *only* the pipeline sources still succeeded. Verilator treats every `-I` directory as a module
search path too, so it silently compiled `rtl/cpu/tcpu_core.v`. The build now uses an include-only directory holding just
`tcpu_defs.vh`. All four identity checks now fail as required (`results/identity.txt`):
* the define with the multicycle list fails because `tcpu_core_pipe` is not found;
* no define with the pipeline list fails because `tcpu_core` is not found;
* `MISA_A=1` is refused;
* `PIPE_FAULT=13` is refused.
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
**Result: 295 / 295 DIFF_OK**, all exiting 0. That is 183,685 retirements and 38,960 data requests compared.
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
| 6 / 7 / 8 NO_FWD_EXMEM / NO_FWD_MEMWB / NO_WB_BYPASS | p1_fwd | the core logs `PIPE FAULT-EFFECT` where the knob changed an operand really used. The first divergence from the reference is such a point: records 1, 18 and 62 (for knob 8, a store that trapped on a wrong address instead of retiring) |
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
bash $P/scripts/build-sims.sh $P/runs/sims-N          # ~10 min, 27 simulators + identity checks
bash $P/scripts/run-p1.sh $P/runs/sims-N $P/runs/run-N 40   # ~15 min; sections A-G + coverage
python3 $P/scripts/p1diff.py <multi-prefix> <pipe-prefix>
python3 $P/scripts/mutjudge.py first|effect ...
python3 $P/scripts/perf.py <log> <nm-file>
```
