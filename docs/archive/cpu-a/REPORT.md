# CPU-A — the A extension in the teaching core: report

Claude, 2026-09-19. Delegation `codex-cpu-a-integration` (acked). `DESIGN.md` was written before the RTL.
Two entry points: `scripts/run-cpu-a.sh` (core level) and `scripts/run-soc-a.sh` (the real R-BOOT path).
Section 5 is the SoC part, section 6 a pre-existing failure this stage uncovered, section 7 what is not
claimed.

## 1. What was built

* **`tcpu_core.v`** — RV64A: `LR.W/D`, `SC.W/D` and the nine AMOs, all four `aq/rl` combinations. One A
  instruction issues exactly one V2 request; the core never emulates an atomic with ordinary accesses.
  The port gained `req_amo[3:0]`, `req_lrsc[1:0]`, `resp_scfail` and `resv_clear` (PHYSICAL_PORT_V2); every
  fetch, ordinary access and page-table read carries `amo = 0, lrsc = 0`, and each of the four non-atomic
  request paths clears the fields explicitly. `.W` results are sign-extended (`MINU`/`MAXU` included — only
  the comparison is unsigned); an SC writes 0 or 1 from the side-band result; `rd = x0` keeps every side
  effect. `resv_clear` is raised in the trap cycle and for as long as the core is held in reset, which is
  what makes a reservation taken before an R-BOOT soft reset unusable after it.
* **`tcpu_ptw.v`** — a new access class for AMOs (`acc_type = 3`): `R` **and** `W`, `A` and `D`, store-class
  causes. `MXR` stands in for a load's read permission and deliberately does not apply to an AMO. LR stays
  load-class (13/5), SC store-class (15/7).
* **`tcpu_harness.v`** — the V2 port, a reservation and atomic memory model implementing the frozen rules
  (LR sets, every SC consumes, an overlapping write by anyone kills, `resv_clear` kills), an external writer
  that can be aimed at one word and fired while the core's atomic to that word is in flight, an injection
  point for "an interrupt while an *atomic* is outstanding" (`IRQ_POINT 12`), and a named check for an
  atomic that retires before its response (`A_OBS_FAIL early-retire`).
* **`tcpu_main.cpp`** — `+mem-dump=addr:count:file`, so a checker can compare the real memory image against
  one it computed itself. Read-only; it changes nothing in a run.
* Five CPU fault injections, each one real defect: `.W` not sign-extended, an SC that always reports
  success, an AMO issued as a plain access, an AMO that retires early, a trap that does not drop the
  reservation.

## 2. Results — `run1/` (`CPU_A_DONE scenarios=15 infra=0 fails=0`)

One entry point (`scripts/run-cpu-a.sh`) builds the programs, builds ten simulator configurations, runs and
scores. A build failure, a timeout or a crash is infrastructure: it fails the entry point and can never
stand in for a negative being detected.

| Gate | Configuration | Result |
|---|---|---|
| a01 — the instruction matrix | three memory timings (`t0` immediate, `t1` ready 2 / response 5, `t2` random) | 138 cases, **all 72 op × width × aq/rl combinations**, every `rd` and every memory word recomputed from the instruction's own inputs and compared against the commit stream, the register file and the real memory |
| a02 — the reservation | the same three timings | 13 named cases: LR/SC success, SC without LR, a repeated SC, a newer LR elsewhere, the core's own store, a store to another word, plain loads, a trap, `.W` on both halves, an SC to the other half of the reserved word, the core's own AMO, the bounded retry loop |
| a02 — an external race | `race` (delayed, an external writer aimed at the loop's word, fired while the LR's response is outstanding) | 2 external writes, 1 of them killed a live reservation, that SC failed, the loop retried and succeeded with the racing writer's value + 1 — exactly what the model predicts |
| a03 — exceptions | `t0`, `t1` | LR misaligned 4, SC and AMO misaligned 6, access faults 5 / 7, **an SC that has lost its reservation and faults traps (7) rather than returning 1**, three illegal encodings (reserved `rs2`, unknown `funct5`, byte width) with `mtval` = the instruction; Sv39: read-only page — LR reads, SC and AMO fault 15; execute-only — LR faults 13, `MXR` lets the LR through and the **AMO still faults 15**; no `D` bit — a load is fine, AMO and SC fault 15; a U page from S — LR 13, AMO 15, `SUM` allows it. 21 traps, and **nothing reached the bus** for the faulting or illegal atomics |
| a04 — an interrupt inside an AMO | `irq` (`IRQ_POINT 12`, response delay 6) | the interrupt fired at the AMO's own PC while its response was outstanding; the AMO completed, returned the old value, wrote memory exactly once (the watched address: writes = write requests), retired exactly once, and only then was the interrupt taken, with `mepc` = the instruction after it |

Negatives — each rejected by its own named check, with the correct control passing:

| Defect | Rejected by |
|---|---|
| `.W` old value zero-extended | `rd = 0x00000000ffffffff, the instruction's inputs give 0xffffffffffffffff` (27 cases) |
| an SC always reports success | `case 2 (SC with no LR): the SC returned 0, the rule says 1` |
| a trap does not drop the reservation | `case 8 (a trap between the LR and the SC drops it)` |
| an AMO issued as a plain access | `the instruction's inputs give …` (222 cases) |
| an AMO retires before its response | `A_OBS_FAIL early-retire pc=… : the atomic retired while its response was outstanding` |

The last one is worth naming: the defect derails the program into a trap storm, which is a *crash*, not a
detection. The harness therefore carries an explicit check for it, and that is the signature the runner
requires.

## 3. Regressions on the modified core

* `regress-sv39/` — the whole CPU-SU and CPU-SV39 suite on the core with the A extension:
  `CPU_SV39_DONE fails=0`.
* `regress-m23/` — the M2-3 IMC / CSR / trap / interrupt suite: `M2_3_DONE fails=0`,
  `M23_WITH_SV39_DONE attempt=1 exit=0`.

Those suites build the core with `MISA_A = 0`, where the A instructions are illegal and `misa` reads exactly
what it read before, so the genuine illegal-instruction and CSR gates still hold unchanged and no test
needed a diffed copy. `run2/` is the core-level suite re-run with `MISA_A = 1` after that parameter existed;
`run1/` is the same suite before it.

## 4. `misa.A`

`misa.A` is 1 only where an atomic path really exists, and in that case the A instructions execute; where it
is 0 they are illegal instructions. One parameter decides both, so the two can never disagree:

* `tcpu_core`'s `MISA_A` gates the decoder's `a_legal` and feeds `tcpu_csr`'s `misa` value;
* the V2 CPU wrapper (the atomic configuration) instantiates the core with `MISA_A = 1`, the V1 wrapper with
  `MISA_A = 0`; the core-level harness defaults to 0 and the CPU-A runner builds with 1.

`a05_misa_probe` measures both sides with one program: it reads `misa` and then executes one AMO. On the
atomic configuration it reports `M3-MISA-A-OK` (the AMO ran, old value and sum correct); on the default
configuration it reports `M3-MISA-NOA-OK` (the AMO raised an illegal instruction with `mtval` = the
instruction, and memory was untouched). It fails loudly if the two ever disagree.

## 5. The SoC — `soc-run4/` (`SOC_A_DONE infra=0 fails=0`)

`RD2AtomicBootConfig`: the R-BOOT topology exactly as it is — TSI, the block device, DDR through TLToAXI4,
the teaching ROM, the real CLINT and PLIC, the RD1 drain contract — with the V2 bridge, the V2 CPU wrapper
and the accepted `AtomicBackend` at the coherence-manager hook (`WithAtomicHub`). `RD2Params.atomic` is
false everywhere else, so no configuration that existed before changed.

| Gate | Result |
|---|---|
| the default configuration, rebuilt from current sources | the four M3 programs pass (`RD2_BOOT_GATE_DONE programs=4 fails=0`), `boot11_sv39` passes |
| the atomic configuration, the same programs | the four M3 programs pass, `boot11_sv39` passes |
| `boot12_amo` on the atomic configuration | passes: an S-mode Sv39 spinlock (`amoswap.d`), an LR/SC counter loop and three AMOs per round over ROM / TSI / DDR / HTIF. The event trace shows **64 AMOs, 64 Gets, 64 Puts, 16 SCs succeeding, 1 failing (the final SC with no reservation), 16 reservations** — exactly what the program asks for |
| `misa.A` on both configurations | `M3-MISA-A-OK` on the atomic one, `M3-MISA-NOA-OK` on the default one; `boot12` on the default configuration stops at its own `misa` check |
| the R-BOOT gates on the atomic configuration | seven of eight pass, including both timeout fail-stop gates (`g4-stuck-device`, `g4-late-recovery`) and the counter-example that must be rejected. The eighth is a pre-existing failure — section 6 |
| an R-BOOT restart inside the atomic phase | four restart points (45000, 50000, 55000, 60000 cycles), each with **an atomic in flight at the reset, read out of the event trace**: the drain finishes the transaction it had accepted, the CPU is restarted, the program is reloaded and completes with `M3-AMO-OK`, with every AMO that started also having read and written |

Isolation, measured rather than asserted (`rtl-delta/default-vs-accepted.txt`): the default configuration's
generated Verilog against the accepted `restart-boot/build3` one differs only by the CPU wrapper's new
observation port, the four new BlackBox pins with `core_resp_scfail` tied low, `MISA_A(0)` on the core
instantiation, a wire rename (`cpu` → `cpuV1`), and line numbers inside assertion strings. No functional
logic differs.

## 6. A pre-existing failure this stage uncovered

`g2-write-inflight` (a block-device write restart) no longer passes, and **not because of CPU-A**: it
already fails with the CPU-SU-era core, two stages earlier, and fails identically on this stage's V1 and
atomic configurations, while the accepted R-BOOT build passes it in 34487 cycles. The bisect, the symptom
(the CPU polls the device's completion byte until its bounded loop runs out; it is still fetching and still
winning the bus, so it is neither a deadlock nor starvation) and a 200-million-cycle probe are written up in
`RBOOT_PREEXISTING.md`. Diagnosing the block device's completion path is outside this delegation, so it is
reported rather than worked around: the entry point requires the other seven gates and names this one.

## 7. Not claimed

No synthesis, no board. `xv6` and `start.c` are untouched, as are the default Rocket, RD2 and teaching
configurations. The PS's own DDR accesses remain outside any hardware serialisation (a platform rule).
The atomic path is strictly serial by ruling, so it is slower than the default one; the numbers in
`soc-run4/` are the only performance data this stage has, and none of it is a performance claim.
