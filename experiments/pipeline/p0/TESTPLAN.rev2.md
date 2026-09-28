# PIPE-P0 TESTPLAN (rev. 2) — verifying the pipeline core by architectural effect

Rev. 1 kept as `TESTPLAN.rev1.md`. Rev. 2 answers `codex-pipe-p0-rulings` items 6 and 7 and R5–R7: the oracle is redefined, the
real baseline failures are restored, the CPI gate is removed.

## 1. The oracle (Codex item 6)
Two different questions, never mixed:
1. **Architectural equivalence** (differential, pipeline vs the accepted multicycle core, same program, same inputs):
   * the **retirement stream**: per retirement `pc`, raw instruction, length, `rd`, `rd` value; per trap `interrupt`, `cause`, `epc`,
     `tval` (the `commit_*`/`trap_*` outputs, `tcpu_core.v:71-84`);
   * the **committed data/device effects**: the ordered list of data-side port requests (`isFetch = 0` and not a PTE read) — address,
     write, size, wdata, wmask, amo, lrsc — and the final memory image. This list is comparable because a data request is only
     issued by the oldest instruction (CONTRACT §4.1): each one belongs to an instruction that retires or takes its own fault.
   * **not compared**: instruction fetches, refill beats, PTE reads, their order and count, and every cycle number. They differ
     legitimately (speculative fetch, cache hits, wrong-path walks). Fetch-side PTE reads are neither data requests nor retirement
     effects: they are reads of cacheable RAM (or non-speculative reads of other space), and A/D are software-managed, so they
     write nothing.
2. **Protocol and speculation safety** (every run, both cores, no reference needed): the monitors of §3.
### 1.1 Values that legitimately differ
| value | rule instead of equality |
|---|---|
| `mcycle`/`cycle` read by CSR | not compared; checked: between two reads by the same hart with no intervening write of `mcycle`, the later is ≥ the earlier; after a write of w, the next read is ≥ w (software may write it, so it is not unconditionally monotonic) |
| `minstret`/`instret` | **compared exactly** (it counts retirements, which are architectural); software writes land in WB in both cores |
| CLINT `mtime` loads (data MMIO) | the request is compared (address/size); the returned value is excluded from the rd-value comparison and checked monotonic per hart; a program in the differential set must not branch on it — programs that do (`c04`, `d07`, timer tests) are judged by their own self-checks, not differentially |
| interrupt boundary | see §1.2 |
### 1.2 Interrupts in differential runs: DUT-directed reference
Interrupts are injected by architectural position, not by cycle: the pipeline runs first with the harness raising the line at an
architectural event (after the Nth retirement, or when the program writes an arming MMIO word, as the existing
`IRQ_ARM_REQUIRED` does, `tests/cpu/tb/tcpu_harness.v:55`). The retirement count k at which the pipeline took the interrupt is
recorded; the reference is then run with the line raised so that it is taken after exactly k retirements (a new harness mode
`IRQ_AT_RETIRE=k`; the multicycle core samples at the next `S_IF_REQ`, `tcpu_core.v:470-479`). The streams are then compared
entirely. Separately, the pipeline's k must satisfy the latency bound: k − (retirements when the line rose) ≤ the number of
instructions that can be past ID (ID..WB = 4), plus the token itself — a longer delay is a failure, not a legitimate difference.
The existing microarchitectural injector (`IRQ_POINT` 1-12, `tcpu_harness.v:42-51`) stays for the multicycle core's own tests only.

## 2. What is reused
| asset | anchor | use |
|---|---|---|
| standalone core harness (fixed/back-pressure/seeded-random delays, protocol monitors, interrupt injector, external writer for atomics, ELF backdoor) | `tests/cpu/tb/tcpu_harness.v:1-110` | P1/P2, both cores |
| stage suites with the RTL directory as a parameter | `experiments/multicore/archive/m1/tests/core-suites/run-cpu-{c,m,su,sv39,a}-rtl.sh` (e.g. `run-cpu-c-rtl.sh:4-5,44`) | P2 |
| M2-3 regression (`c01-c10`, `i01-i09`, `j01-j02`), stage programs (`m01 m02 boot09`, `c01 c02 boot10`, `su01-su11`, `sv01-sv07 sv09 boot11`, `a01-a05 boot12`) | `tests/cpu/tests2`, `experiments/teaching-cpu/cpu-*/tests` | P1 subset / P2 |
| RD2 event log, checkers `score2.py`, `dual_check.py`, `m3_check.py`, `perf_check.py`, IPS probes | `RD2Soc.scala:361-400`; `experiments/multicore/archive/{m2a,m2b,m3,perf}/tests` | P2/P4 |
| I-cache/TLB unit benches | `worktrees/ips-cache/experiments/IPS-campaign/tests` | regression of the unchanged shared units |
| stable-observation lint | `archive/m1/tests/lint-stable-obs.sh` | every phase |
| the P0 control model | `experiments/pipeline/p0/model/p0model.py` | the scenario list of §4 is its RTL counterpart |

## 3. Monitors and assertions (every run)
Existing: valid irrevocable / payload held (`REQ_WITHDRAW` self-test), no answer in the request cycle (`MEM_SAME_CYCLE`), a load
carries no write payload (`LOAD_WDATA_LEAK`), matched and unique response (`RD2BridgeV2.scala:77,157-158`), one request per hart
(bridge `sIdle`). New, inside the pipeline RTL under a simulation define, each the RTL form of a model invariant:
| assertion | model | negative (RTL knob, P1/P2) |
|---|---|---|
| at most one of commit/trap per cycle; a WB occupant retires once | I8 | `FAULT_WB_HOLD` |
| an EX occupant redirects at most once | I8 | `FAULT_REDIRECT_REPEAT` |
| a data-side request or data-side walk is raised only when MEM holds the oldest instruction (§4.1) | I4 | `FAULT_STORE_UNDER_OLDER_TRAP` |
| a response is consumed only by its own non-killed owner; killed responses fill nothing | I3 | `FAULT_EPOCH_BIT` (1-bit epoch instead of `killed`) |
| uncached fetch / non-cacheable PTE read only when non-speculative | I6 | `FAULT_SPEC_MMIO_FETCH` |
| a serialising instruction leaves EX only with port, walker and refill idle | I9 | `FAULT_CSR_NO_DRAIN` |
| progress: a retirement at least every N cycles (N from the run's latency profile) | I5 | `FAULT_WALK_NO_PREEMPT` |
| the interrupt token's epc is the architectural next pc; one token at a time | I1 | `FAULT_IRQ_EPC_FETCHPTR` |
| a load's value is used only from MEM/WB | I1 (value) | `FAULT_NO_LOADUSE_STALL` |
| forwarding correctness | differential | `FAULT_NO_FWD_EXMEM`, `FAULT_NO_FWD_MEMWB`, `FAULT_NO_WB_BYPASS`, `FAULT_X0_FWD` |
SoC level: the retirement-association checker of CONTRACT §6 over `EV REQ/RESP/COMMIT/TRAP`, and `lint-stable-obs.sh`.

## 4. Short control scenarios (the RTL counterparts of `model/TABLES.md`)
Each runs under the three delay profiles (minimum, fixed back-pressure RD=3/T=4, seeded random) and passes the differential oracle
and the monitors; each named knob must make it fail for its own reason.
| id | scenario | knob that must fail it |
|---|---|---|
| C1 | ALU commits in WB while a load waits in MEM; taken branch behind the load (model `wb-once`) | `FAULT_WB_HOLD`, `FAULT_REDIRECT_REPEAT` |
| C2 | two flushes (EX redirect, then older fault at WB) while a fetch-side walk is outstanding with valid not yet handshaken; handler word misses the TLB (`two-flush`) | `FAULT_EPOCH_BIT` |
| C3 | older load misses the data TLB while a wrong-path fetch walk needs a non-cacheable PTE (`walker-deadlock`) | `FAULT_WALK_NO_PREEMPT` |
| C4 | interrupt while the front end waits on a refill and ID..WB are empty (`irq-no-input`) | `FAULT_IRQ_EPC_FETCHPTR` |
| C5 | interrupt with an older faulting load in EX (`irq-vs-older-fault`); also CSR write disabling MIE, then MRET re-enabling, with the line held | — |
| C6 | four ALU on hits (II = 1), taken branch (3 bubbles), data-TLB-miss load + dependent (`frontend`) | `FAULT_NO_LOADUSE_STALL` |
| C7 | CSR/fence.i/sfence.vma reaching EX with a refill or walk outstanding, T = 2/6/18 (`serial-drain-T*`); fence.i then executes newly stored code | `FAULT_CSR_NO_DRAIN` |
| C8 | ecall immediately followed by a store (`store-under-trap`); also misaligned load followed by a store | `FAULT_STORE_UNDER_OLDER_TRAP` |
| C9 | load-use chain with back-pressure sweep RD 0..3, T 1..8 (`load-use`) | `FAULT_NO_LOADUSE_STALL` |
| C10 | wrong-path fall-through into uncached space (`spec-uncached-fetch`) | `FAULT_SPEC_MMIO_FETCH` |
| C11 | data response and retirement association (`retire-assoc`) + the SoC EV checker | `FAULT_STORE_UNDER_OLDER_TRAP` |
| C12 | 32-bit instruction in the last halfword of a word; the same across a page whose second translation faults (epc = pc, tval = pc + 2) | — |
| C13 | long division with the interrupt line raised mid-operation | — |

## 5. Baselines — stated exactly, not rounded to green (Codex item 7)
The official `riscv-tests` suite has never been run in this project (planned in `experiments/teaching-cpu/m2-prep/TEST_PLAN.md:44`;
Spike not built). The regression baseline is the project's own suites, and **not all of them pass**. As recorded in
`experiments/multicore/archive/m1/REPORT.md` (T1.4) and carried unchanged in `archive/m2b/REPORT.md` §8:
| suite | result on the reference (tag) RTL and on the M1 RTL | classification recorded there |
|---|---|---|
| su | `fails=9`: `su08_satp_bare`, `su09_warl`, `su11_mip_sw` × 3 profiles (checks 1/8/24) | **undiagnosed, deferred**; not claimed to be stale expectations |
| m | `fails=6` | partly stale expectation with source evidence (`m01` check 410 expects misa `0x8000000000001100`; `m23/csr-warl` misa); **undiagnosed**: `m23/csr-illegal` (4 traps vs 6), `m23/jump-targets` (last cause 2), `m23/fault-stale-i01` (2 interrupts vs 1) |
| c | `fails=16` | partly stale misa expectation (`c01` check 34, `corereset-if2-c01` ×3, `m01` 410, `m23/csr-warl`); **mechanism inferred, not verified**: `irq-if2req`/`irq-if2resp` time out waiting for a second-parcel state that fetch32 no longer produces; the two m23 items above |
| sv39 | `fails=0` (after the `oldptw` negative-control build issue was resolved) | pass |
| a | `scenarios=17 infra=0 fails=0` | pass |
| M2-3 | `M2_3_DONE fails=0` in its own stage (`experiments/teaching-cpu/m2-3/REPORT.md:54`); inside the m/c suites the m23 items above fail | historical stage pass ≠ current tag re-run |
Rules: (1) these numbers are re-run on the current tag before P1 starts and reported as the tag baseline, with the historical stage
results kept separate; (2) the pipeline is compared suite by suite against the **tag baseline**: a check that fails on both is
listed as baseline, a check that differs is a finding, and a baseline failure is never reported as a pipeline pass or as
"known harmless"; (3) P1 uses an explicit passing subset (RV64I directed `t01-t03`, `d01-d08`, `c05`, `c06`, `c07`, `c08`, `c09`,
`i08`, `i09`, `j02`, and the generated hazard programs), named in its report; (4) P2 lists every difference from the tag baseline;
(5) `ext03_a` does not complete in the simulation harness and is a board-only gate.

## 6. Phases (R7 as ruled)
* **P1** standalone core, RV64I + minimal traps (mret, mepc/mcause/mtval, mstatus.MIE), harness only: C1–C4, C6, C8–C11 with the
  P1 subset of §5; differential oracle; monitors; knobs. Design target reported, not gated: II = 1 on ALU hits (CONTRACT §8.4).
  Gate for the Scala change of CONTRACT §9.1: generated Verilog of every existing configuration byte-identical.
* **P2** M, C (straddle C12), full CSR/S/U/delegation, Sv39 (dual-lookup TLB, walker rules C3), A (LR/SC/AMO via the V2 port and
  the backend), fence.i/sfence (C7), interrupts (C5, C13); all stage suites against the tag baseline; single-core xv6 in the RD2
  simulation (`m3_check.py --n1`, profiles `m4smoke` and `perf-short`); SoC EV retirement checker.
* **P3** single-core 40 MHz offline implementation through the accepted build chain with `CORE_IMPL=pipeline` (manifest records
  core file hashes); utilisation and timing next to the multicycle cache stage; the dual-lookup TLB's cost recorded separately;
  board comparison only after the user's hand-back and a separate authorisation.
* **P4** `NUM_CORES = 2` with the pipeline core (refused until then): M2b dual gates, M3 dual xv6, fixed-work measurement with
  `perf_check.py`.

## 7. Exit criteria per phase
Every row's oracle holds under all delay profiles; every named knob fails its scenario for its own reason; lint passes; all runs
bounded; the report states the §5 baselines verbatim and lists every difference from them.
