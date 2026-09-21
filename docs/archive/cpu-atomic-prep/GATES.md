# Frozen acceptance gates for the atomic-path implementation task

Ordered so that each layer can refute a wrong implementation before the next depends on it. Every gate
names a runnable check; "the same ELF passes on the references" is a cross-check, never the judge of a
WARL value or of the platform-specific error mapping.

1. **Core, instructions.** All nine AMOs × {w, d} × {none, aq, rl, aqrl}, `lr/sc` w/d: results (old value,
   sign extension for `.w`, min/max signed/unsigned, `sc` 0/1), three memory profiles, commit records
   identical. Expectations generated in Python from the ISA rules (as `gen_m01.py`), not hand-typed.
2. **Core, exceptions.** Misaligned AMO/SC → 6, misaligned LR → 4; AMO to a target without atomic
   support → 7 with **no** request reaching the target (harness watch); Sv39: AMO on R-only/W-only → 15,
   LR on a non-R page → 13, SC on a non-W page → 15, U/S/SUM/MPRV as for stores; faulting instruction not
   retired; `xtval` = the VA.
3. **Core, LR/SC semantics.** SC succeeds after an LR of the same word; fails after: an intervening store
   by the same hart to the word, a trap, an SC (used up), an LR of another word, reset. `sc` result
   register 0/1 checked from the real register file.
4. **Bridge / SoC unit: serialisation.** A directed TL testbench with three masters (the CPU bridge, a TSI-like
   Put source, a DMA-like Put source): an AMO on word X while the other masters write X (same address) and
   Y (different address): the final value of X equals the sequential result of every interleaving the
   testbench actually produced (checked per run from the observed order at the automata), Y is unaffected,
   no request is lost or duplicated (the RD2 identity watcher), and a deliberately removed automata fails
   this gate.
5. **Bridge / SoC unit: reservation.** LR on X, then an external Put to X, then SC → `sc_fail = 1` and no
   write on the bus; external Put to Y → SC succeeds; the SC's Put is dropped, not turned into a stray
   write; a fault-injected adapter that decides "success" before the serialisation point fails a directed
   race (external Put issued between the core's decision and the Put's arrival).
6. **Ordering.** A program with `amoswap.w.aq` / `.rl` pairs around plain loads/stores under random
   backpressure: the commit trace shows no reordering (there cannot be, single outstanding — the gate
   documents it), and the RD2 watcher shows one transaction per instruction.
7. **Regression.** IMC, CPU-SU, CPU-SV39 entry points and the M2-3 copy-runner on the new core; the
   named negatives of every earlier stage still rejected.
8. **SoC.** The four M3 ELFs, boot09/10, hello, su01/05/06, boot11 unchanged; a new `boot12_amo` (a spinlock
   acquire/release loop in S-mode under Sv39, plus an LR/SC counter) through ROM/TSI/DDR/HTIF; the R-BOOT
   restart gates with an AMO in flight at the hold point (the drain covers it).
9. **xv6 layers**, each its own gate, in this order, in simulation first: (a) the kernel entry and `start()`
   with the two-line PMP patch (no illegal instruction), (b) `main()` to `userinit` (first process
   created), (c) `sh` prompt over HTIF, (d) a selected user program (`ls`, `echo`), (e) `usertests` —
   each recorded with the console log, exit/timeout, and the CPU counters. Board runs are a separate task.

Named negatives required (each rejected by a specific check, the RV64I control passing): no automata on
the DRAM path (gate 4); reservation decided in the core, i.e. before the serialisation point (gate 5); an
AMO issued as plain Put (gate 1: old value wrong); `misa.A` set while LR/SC are illegal (gate 1); **a read
error that still writes** (the rocket-chip automata behaviour); **a side-band mismatch or a missed external
kill** (gate 5) — the last two are the backend-stage negatives Codex named.

### Backend stage (`codex-cpu-atomic-backend`, before the core is touched)

A transaction-driver harness with three masters on one real node: (a) nine AMOs × w/d, old value, `.w` sign
extension and untouched neighbouring bytes, same-word and other-word Puts (single-beat and partial-mask)
from the other masters, results checked against the *observed* acceptance order; (b) reservation lifecycle:
a write during the LR's pending read, a write while the SC waits for ready, consume/replace, trap/reset clear
(side-band), plain reads keep it, upper/lower halves of one word, different words, a failed SC leaves no
downstream write; (c) errors: an atomic Get with error → no Put and one error response; a Put error → one
terminal response, no retry; an LR error → no reservation; a locally failed SC response arbitrated against
other masters' real D beats without loss; an unauthorised target → refused, zero requests; (d) a bounded
LR/SC loop succeeds without contention and recovers after external writes stop; (e) hold/reset drain with an
AMO in each phase (R-BOOT limited regression, fail-stop kept); (f) the V1 bridge and the four M3 boot programs
unchanged.
