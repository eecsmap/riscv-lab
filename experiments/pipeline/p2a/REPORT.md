# PIPE-P2a REPORT — M and C in the pipeline core, and the walker-wrapper proof

Task `codex-pipe-p2a-extensions-walker`. Worktree `worktrees/pipe-single`, branch `pipe-single`, local commits (no push,
no tag). P1 was accepted at `53b1aac`, recorded in `839652b`. No shared RTL, board, serial, SoC, Scala or Sv39
integration was touched.

| commit | content |
|---|---|
| `f8b7968` | M through the unchanged shared `tcpu_muldiv`; knobs 15/16; harness and top pass-throughs; the M tests and P2a scripts |
| `293656e` | build tooling: a failed simulator build is retried once with `-j 1`, with the first log kept and the retry marked |
| `eb6784f` | `tcpu_ptw_wrap` (pipeline-owned) around the unchanged `tcpu_ptw`, with its unit bench, judge and self-test |
| `16b6dcc` | integer C through the unchanged shared `tcpu_cdecode` (Bare); knobs 17–19; the C tests and script sections |
| (this commit) | the P2a verdict self-test, the gate mutants for the new judges, results, this report |

Final evidence, all from one pinned snapshot at `16b6dcc`: simulators `runs/sims-3` (33), run `runs/run-3`,
walker bench `runs/wb-2`. The only worktree changes at build time were two test scripts; see
`results/worktree-status-sims-3.txt`. Summaries and hashes are in `results/`, listed in `results/SHA256SUMS`.

## 1. Modes and build identity
`tcpu_core_pipe` has two new parameters, `PIPE_EXT_M` and `PIPE_EXT_C`, each 0 or 1.
* **Defaults (0/0).** The accepted P1 configuration, RV64I. It instantiates neither the mul/div unit nor the
  decoder, so its source list is unchanged. The P1 A–H regression on this tree (`results/p1-regression-run-7.txt`) is
  identical to the accepted run-5 in every section, including cycle counts.
* **misa.** It reads I, I+M or I+M+C for the build.
* **Refused at elaboration:** M or C encodings without the extension (illegal instruction), `FAULT_W_SEXT` and
  `FAULT_MULH_SIGN` without M, `FAULT_C_IMM` and `FAULT_C_REG` without C, knobs 15–16 without M, knobs 17–19
  without C, values other than 0/1, and `PIPE_FAULT` > 19.
* **Build identity gate** (`results/identity-sims-3.txt`, 10 checks, all failing for their named reason):
  * M or C selected without the unit's or decoder's source file;
  * one representative of each refusal kind above (knob 15 without M, W_SEXT without M, EXT_M = 2, knob 18 without C, C_IMM without C, EXT_C = 2, PIPE_FAULT = 20);
  * the P1 check with the define and the multicycle source list.

The harness and top pass the new parameters and the M/C fault injections to the pipeline only, defaulting to 0.

## 2. M (a back-end change: EX only)
* **Starting.** The unit starts once per EX occupant: in the first cycle the operands are final (no load-use hazard)
  and the unit is idle. The occupant owns the result until it leaves EX, and holds it through MEM stalls.
* **Flushes.** A WB flush removes the occupant and abandons the unit through its own synchronous reset
  (`tcpu_muldiv.v`: "reset abandons the operation"). A flushed operation therefore cannot complete into a later
  instruction. The claim is additionally tied to the occupant that started the unit.
* **Named assertions.** `md-once` (a second start for one occupant) and `md-owner` (a result claimed by an occupant
  that did not start the unit).
* **Directed tests** (`tests/p2a_md_*.S`, explicit values):
  * forwarding and load-use into M operands;
  * M results as branch operands and load addresses;
  * an M instruction behind a store in MEM;
  * x0 as a destination;
  * older traps and serialisers flushing a running operation: misaligned load, load access fault, ECALL, CSR read,
    two faults in a row;
  * a **wrong-path divide behind MRET**. It starts in EX while the MRET drains and is flushed when the MRET commits.
    The multiply at the MRET's target has other operands, so a stale quotient would be visible as a wrong value;
  * interrupts around long operations;
  * ROIs.
* **All 13 operations on edge operands:** `gen_m01.py`, the CPU-M generator, with values computed in Python.

## 3. C (a front-end change, plus the length through the back end)
* **Extractor.** F2 takes up to two instructions per cycle from its 8-byte word, from its parcel position.
* **Carry.** A 32-bit instruction whose lower parcel is the word's last is carried into the next sequential word.
  This works the same across a word, a cache line or a page.
* **Fetch faults.** A fault on the word is a single faulting instruction. With a carry, mepc is the first parcel and
  mtval the second parcel's address.
* **Expansion.** `tcpu_cdecode` expands the instruction entering ID. ID to WB see the 32-bit form. The raw parcel
  and the length go to WB for the commit record (`commit_insn`, `commit_len`), mtval (an illegal parcel keeps its raw
  value), the link (pc + 2) and the next pc.
* **Alignment.** IALIGN is 16. An uncached fetch reads the whole 8-byte word.

**Tests.**
* The CPU-C programs, unchanged:
  * `c01_compressed` covers the compressed instruction classes and misa I+M+C;
  * `c02_boundary` covers 32-bit instructions starting at pc % 8 = 2, 4 and 6, one straddling the 4 KiB boundary at
    0x8000_1000, illegal and reserved parcels, c.ebreak, and MRET to a halfword address.
* New directed tests: `p2a_c_link` checks the c.jalr link, links from pcs ≡ 2 (mod 4), a jump and a branch to
  targets ≡ 2 (mod 4), and auipc at pc ≡ 2 (mod 4). `p2a_c_irq` checks interrupts in a mixed stream (mepc may be
  ≡ 2 mod 4). `p2a_c_perf` holds the ROIs.
* Generated hazard programs with `--c` (`scripts/gen-hazard-p2a.py`). They prefer x8–x15, rd = rs1 and small
  immediates, drawn from their own random stream. Without flags the output is byte-identical to P1's generator, and
  with `--m` alone to the committed M version.

**The two fetch faults** on c02's straddling instruction at 0x80000ffe (`results/run-3-D.txt`):
| fault on | mcause | mepc | mtval | pipeline | multicycle |
|---|---|---|---|---|---|
| first parcel (beat 0x80000ff8) | 1 | 0x80000ffe | 0x80000ffe | as required | as required |
| second parcel (0x8000_1000) | 1 | 0x80000ffe | 0x80001000 | as required | as required |
The instruction never retires. The harness fails a fetch of an exact request address. With the I-cache, both cores
fetch that line in 8-byte beats, so the first parcel is aimed at its beat. The historical CPU-C run aimed the
multicycle core at 0x80000ffe exactly. That address is never requested, so the tag core stopped at c02's later
illegal parcel instead (cause 2 at 0x800000e4, `multicore/m1/runs/t1.4-core-c-tag.log`). The failed run-2 reproduced
this (`results/run-2-verdict-FAILED.txt`). It is not a pipeline result.

## 4. Results (`runs/run-3`, verdict PASS: `results/run-3-verdict.txt`)
| check | result |
|---|---|
| A: m01, every M operation, pipeline M, 5 profiles | exit 0, 0 assertions; the multicycle reference too |
| A: m01c / c01 / c02, pipeline M+C, 5 profiles | exit 0, 0 assertions; the multicycle copies c01mc / c02 too |
| A: the P1 configuration on m01 | illegal instruction (cause 2) at the first M instruction |
| A: builds without C on c01 | refused: cause 0 at a jump to a target ≡ 2 (mod 4), which IALIGN 32 forbids, before any parcel; no compressed instruction retires |
| B: differential vs the multicycle core, M set | **220 / 220**: m01 without its misa read, the directed M tests, t01, 40 hazard programs with 4,736 M instructions |
| B: differential, M+C set | **235 / 235**: m01, c01 without its misa read, c02, p2a_c_link, the M tests, t01, 40 M+C hazard programs |
| C: interrupts | **180 / 180** pass their own checks, and all 180 align with an identical reference stream. p2a_md_irq: 27 positions × 3 profiles, worst latency 68 cycles (the interrupt waits for the running operation). p2a_c_irq: 33 × 3, worst latency 4 |
| D: negative controls | 12 caught by their intended first signal (below); 5 parcel-fault lines exact; 8 controls pass |
| G | 13 shared/multicycle files byte-identical to the tag |

Every B comparison uses `p1diff.py --require-complete`. misa legitimately differs between the cores (the tag reports
S and U), so the differential copies drop only the misa read, and the self-check copies carry each core's own value.

| negative control | caught by (first signal) |
|---|---|
| 15 MD_STALE_RESULT on p2a_md_fault | `PIPE ASSERT md-owner`; the MRET case also fails its own value check |
| 16 MD_RESTART on p2a_md_hazard | `PIPE ASSERT md-once` |
| FAULT_W_SEXT / FAULT_MULH_SIGN on m01, both cores | check 247 / check 36, the numbers gen_m01 derives |
| 17 C_LINK_LEN on p2a_c_link | check 1: the c.jalr link |
| 18 C_CARRY_DROP on c02 | check 1 |
| FAULT_C_IMM / FAULT_C_REG on c01, both cores | check 6 |
| 19 C_TVAL_FIRST, second-parcel fault | mtval 0x80000ffe instead of 0x80001000 |

**Suites on both implementations.** The CPU-M and CPU-C gates that are architectural run here on both cores:
* m01;
* the M and C fault injections;
* c01 and c02;
* both fetch faults.
The rest drive the multicycle core's internal states and cannot be positioned on the pipeline:
* CPU-M gate 3 (`IRQ_POINT` while in S_MUL) and gate 3b (core reset in S_MUL);
* CPU-C `corereset-if2`.
Their pipeline counterparts are the architectural interrupt test and the flush-during-operation tests above. This is
the same substitution P1 made for i08/i09/j02.
* **Known baseline differences, kept.** c01's misa check (check 34) fails on the tag core, which reports S and U. It
  is one of the recorded "C 16" baseline failures (M1 T1.4). Here it is handled by the c01mc copy, not counted as a
  pass. The c06 IALIGN note from P1 stands: with C the pipeline has IALIGN 16, as the tag core does. That is not a
  regression fix.

## 5. The walker-wrapper proof (`eb6784f`; `runs/wb-2`, `results/walker-*.txt`)
`tcpu_ptw_wrap` relies on two properties of the unchanged walker:
* its request is its own registered output, raised in its WAIT state and held until `req_ready`;
* a synchronous reset clears everything.
**How it works:**
* **Forwarding.** The walker's request is forwarded into the wrapper's port holding register only when the port is
  free and granted by the core's arbiter. A speculative walk forwards only a cacheable PTE address.
* **Abort.** An abort resets the walker at once and marks a forwarded transaction killed.
* **Killed transactions.** A killed transaction stays on the port unchanged until its handshake. Its response is
  consumed and never delivered.
* **Results.** A killed walk never reports done, so nothing can fill a TLB entry or deliver a PA from it.

**The bench** (`walker/wb_tb.v`) uses real Sv39 tables and five walks:
* a 4 KiB page;
* a 2 MiB megapage;
* an invalid PTE (page fault 12);
* a table in non-existent memory (access fault 1);
* a middle table in uncached memory.

The reference walks match the values derived by hand. Every walk is aborted at every cycle from 0 to its length + 2,
over 24 port profiles (arbitration always or every third cycle × ready delay 0–2 × response delay 1–4). A data-side
walk then follows and must equal its reference. A speculative walk at the uncached table must wait unforwarded. It is
then either made non-speculative (it completes) or preempted by a data walk (which completes).

**Properties checked every cycle:**
* withdraw, and payload stability;
* one outstanding request;
* a killed response delivered;
* a response to an unforwarded request;
* a speculative uncached request;
* done after kill;
* wrong result;
* drain.

| variant | runs | failing | first failing property in every failing run |
|---|---|---|---|
| wrapper as designed | 3,456 | 0 | — |
| WRAP_FAULT 1 withdraw | 3,456 | 624 (= every abort while offered, not ready) | withdraw |
| 2 done after kill | 3,456 | 120 (= every abort in a done cycle) | done-after-kill |
| 3 speculative uncached | 3,456 | 48 | spec-uncached |
| 4 killed response delivered | 3,456 | 1,716 | killed-delivered |
Every abort class Codex listed was hit, including IDLE, an unforwarded request, offered-not-ready, outstanding, the
response at each level, and an error response. The shared `tcpu_ptw`, `tcpu_permcheck` and `tcpu_cacheable`
compiled by the bench are byte-identical to the tag. **This is a unit proof only.** The wrapper is not integrated,
and nothing here claims Sv39 in the pipeline (P2b).

## 6. Performance (`results/run-3-F.txt`; simulator, warm I-cache; reported, not gated)
| ROI | multicycle CPI | pipeline CPI | where the change is |
|---|---|---|---|
| 16 multiplies | 69.06 | 63.12 | back end (EX): the unit takes 66 cycles; the pipeline's per-operation interval is 67, against 73 |
| 8 dependent divides | 65.56 | 59.67 | back end |
| 8 × (mul + 3 ALU) | 22.24 | 17.00 | back end: the ALU instructions go at 1 per cycle between operations |
| 64 compressed ALU | 6.00 | 1.00 | front end: two compressed instructions per word read, II = 1 held |
| 16 × (c + 32 + c + 32), 32-bit instructions crossing words | 6.00 | 1.00 | front end: the carry costs no cycle |
| a compressed taken-branch loop | 6.00 | 2.43 | 3 bubbles per taken branch, as in P1 (no prediction) |
M performance is bounded by the shared iterative unit. The pipeline gains only the overlap of neighbouring
instructions. No overall speed-up is claimed.

## 7. Gates and their tests
| gate | self-test | mutants caught |
|---|---|---|
| P2a run verdict (`scripts/p2averdict.py`) | `selftest-p2averdict.sh`: 24 / 24 mutated copies of run-3 | 20 / 20 |
| walker judge (`walker/wbjudge.py`) | `selftest-wbjudge.sh`: 12 / 12 | 11 / 11 |
| P1 gates (strict differential, identity, P1 verdict, flush-window judge) | unchanged | 40 / 40 |
In total `results/gate-mutants-final.txt` reports **71 / 71** mutants caught. One walker mutant first survived: its
self-test lacked a case that only the count clause catches. Two cases were added (a missing line, an extra CHANGED
line), and each clause now has its own mutant.

## 8. Findings and corrections during P2a, recorded
* **Test bugs.**
  * The hazard test reused a register (divisor 1, not 2).
  * The interrupt check's lower bound ignored interrupts legitimately taken before the M block.
  * A compressed branch on a register outside x8–x15 did not assemble.
  * The link test first returned through the link it was testing, so knob 17 derailed the program instead of failing
    the check.
* **The stale-result case needed a wrong-path instruction to be value-visible.** Re-executed operations have the same
  operands. The MRET placement also needed the MRET and the divide in one fetch word: the front end freezes behind
  the MRET.
* **Generator draw order.** Changing it would have changed P1's programs. It was caught by the identity check and
  restored.
* **Verilator 5.022 thread-pool crash.** A crash while tearing down its thread pool hit one knob build of a P1
  regression (`p1/runs/sims-7`, `results/verilator-flake-sims-7.txt`), as it did in Codex's P1 review. The binary had
  been written and that run passed, but it is not used as evidence. The final P1 regression is `p1/runs/sims-8` and
  `run-7`, a clean build. The build scripts now retry once with `-j 1`.
* **Process.**
  * The walker file was added to the RTL directory while a P1 build was reading the tree. That build copies the
    pipeline core by name, so it was unaffected.
  * Short walker smoke sweeps, under a minute in total, overlapped a running job's section H.

## 9. Commands
```bash
P=/home/engineer/fpga/worktrees/pipe-single/experiments/pipeline
bash $P/p2a/scripts/build-p2a.sh $P/p2a/runs/sims-N          # 33 simulators + identity gate; exit 0 only if both pass
bash $P/p2a/scripts/run-p2a.sh $P/p2a/runs/sims-N $P/p2a/runs/run-N 40   # sections A-G; exit status = p2averdict.py
bash $P/p2a/walker/run-wb.sh $P/p2a/runs/wb-N fix:0 w1:1 w2:2 w3:3 w4:4
python3 $P/p2a/walker/wbjudge.py $P/p2a/runs/wb-N fix=clean w1=caught:withdraw w2=caught:done-after-kill w3=caught:spec-uncached w4=caught:killed-delivered
bash $P/p2a/scripts/selftest-p2averdict.sh <passing run dir> <fresh dir>; bash $P/p2a/walker/selftest-wbjudge.sh <wb dir> <fresh dir>
WBRUN=<wb dir> P2RUN=<passing p2a run> bash $P/p1/scripts/mutate-gates.sh <p1 run with H> <its coverage> <p1 sims> <fresh dir>
bash $P/p1/scripts/build-sims.sh $P/p1/runs/sims-N && bash $P/p1/scripts/run-p1.sh $P/p1/runs/sims-N $P/p1/runs/run-N 40   # P1 regression
```

## 10. Not in P2a
S/U delegation, integrated Sv39 and TLB, A, Scala and SoC plumbing, xv6, Vivado, the board, a dual pipeline and a
configuration framework. P2b integrates privilege, MMU and A, using this wrapper.
