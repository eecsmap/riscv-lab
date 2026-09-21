# CPU-SU preparation — report

Claude, 2026-09-18. Delegation `codex-cpu-su-contract` (acked). Deliverables: `SPEC.md` (the
implementable contract), `DECISIONS.md` (the ten items for Codex), `TEST_PLAN.md`, `tests/` (nine directed
tests + a probe), `scripts/`, `build2/` (ELFs, disassembly, hashes), `ref-run2/` (the runs on the two
references), `HASHES.txt`/`HASHES-VERIFY.txt`. No CPU functional RTL, Rocket/board artefact or boot
software was changed; nothing was synthesised. The CPU-C fix-ups Codex asked for are in
`cpu-c/fixups-run2/` and `cpu-c/REPORT.md` (section "Post-acceptance fix-ups"), 2327/2327 hashes.

## 1. What the SPEC fixes (summary; the tables are in `SPEC.md`)

* Three levels with `priv`; trap entry to M or S per `medeleg`/`mideleg` and the current level; `mret`/
  `sret` exactly as the spec, `sret` illegal in U, `mret` illegal below M; `wfi` a no-op in all modes.
* `mstatus` as one register with `sstatus`/`sie`/`sip` as views; the WARL masks written out
  (`mstatus` 0xA000E19AA, `medeleg` 0xB3FF, `mideleg` 0x222, `mie` 0xAAA, counteren 0x5); `misa` gains S
  and U (`0x8000000000141104`).
* The full S CSR set xv6 uses; `satp` Bare-only with the spec's "unsupported MODE: whole write ignored";
  `sip.SSIP` a real bit (the xv6 timer path depends on it), `STIP/SEIP` read-only 0.
* The interrupt acceptance matrix (M-level: MIE in M only, always below M; S-level: never in M, SIE in
  S, always in U; M first) and the xv6 timer path end to end.
* Out of this step, each with its own decision: PMP (D-6), AMOs (D-7), `time` (D-8), Sv39.
* Corrections to older text: `misa` is fixed-WARL, not "read-only"; `medeleg`/`mideleg` now exist.

## 2. Tests and reference runs

Nine tests, expectations written from the spec first (`TEST_PLAN.md`). Two references: the Rocket
Verilator model (M1-a build `sim-20260914T213208Z`, RV64GC with S/U and Sv39, fesvr) and qemu 10.2's
`spike` machine (same HTIF/CLINT conventions). Results: see §2.1 (filled from `ref-run2/`).

### 2.1 Results (`ref-run2/`, `SU_REFRUN_DONE fails=0`; Rocket with `+verilator+rand+reset+0`, see §2.3)

| Test | Rocket exit | qemu exit | want | Rocket cycles |
|---|---|---|---|---|
| su01_modes | 0 | 0 | 0 | 9822 |
| su02_csr_priv | 0 | 0 | 0 | 9511 |
| su03_deleg | 0 | 0 | 0 | 9838 |
| su04_strap | 0 | 0 | 0 | 9369 |
| su05_irq_modes | 0 | 0 | 0 | 13941 |
| su06_timer_ssip | 0 | 0 | 0 | 807985 (three timer rounds at 4000 mtime ticks) |
| su07_epc_len | 0 | 0 | 0 | 8331 |
| su08_satp_bare | 1 | 1 | 1 (SPEC-only; references have Sv39) | — |
| su09_warl | 1 | 1 | 1 (SPEC-only; misa differs at check 1) | — |
| su_probe | 0 | 0 | 0 (prints, no checks) | 186785 |
| su01 under `+verilator+rand+reset+1` | timeout | — | (documents §2.3) | — |
| su01 under `+verilator+rand+reset+2`, seeds 1/2/3 | timeout / timeout / 0 | — | (documents §2.3) | — |

The two SPEC-only tests fail on both references exactly where predicted (check 1: Sv39 accepted / misa
has A, F, D). Every behaviour test (su01–su07) exits 0 on both machines.

### 2.2 Where the references and the SPEC differ (recorded, not averaged)

From `su_probe` (`ref-run2/su_probe.*.log`) and the debugging runs:

| Question | SPEC (teaching core) | Rocket model | qemu spike |
|---|---|---|---|
| `misa` | 0x8000000000141104 (I M C S U) | 0x800000000014112d (+A F D) | 0x80000000001411ad (+A F D H) |
| `medeleg` write-all-ones | 0xB3FF | **0xB109** (no illegal-instruction, no ecall-S, no access faults) | 0xF4BFFF |
| `mideleg` | 0x222 | 0x222 | 0x3666 |
| `mie` mask | 0xAAA | 0xAAA | 0xFFFFFFFFFFFFFEEE |
| `sie` with mideleg = 0 / all | 0 / 0x222 | 0 / 0x222 | 0 / 0x2222 |
| `mip` writable | SSIP only (0x2) | 0x222 (SSIP, **STIP**, SEIP; the probe read 0x2A2 with the live MTIP level) | 0x26E6 |
| `mstatus` write-all-ones | 0xA000E19AA | 0x8000000A007E79AA (FS, TVM/TW/TSR) | 0x800000CB007E79AA |
| `mtvec`/`stvec` write-all-ones | ...FFFC (direct only) | ...FFC1 (vectored kept) | write ignored (stays) |
| `mcounteren`/`scounteren` | 0x5 | 0x7 (stores TM) but **gates nothing** (S and U read `cycle` with CY = 0) | 0x7FFFF, gates |
| `satp` MODE=8 / MODE=0 with 0x123 | 0 / 0 (Bare-only) | 0x8000000000000123 / 0x123 | same as Rocket |
| `mtval` on illegal / on `ebreak` | encoding / pc | encoding / **0** | encoding / pc |
| `mepc` after an odd write | even | even | even |
| `sip.STIP` written from S | read-only | **writable** | read-only |
| cause 2 (illegal) delegable | yes | **no** (mask) | yes |
| cause 9 (ecall-S) delegable | yes | **no** (mask) | yes |
| `wfi` in U | legal no-op | legal | illegal |

Each bold Rocket item is a spec deviation of that 2018 Rocket (or an older-spec choice); the xv6 port is
written to live with them (its `timervec` reflects non-delegated traps in software). None of them is
needed by xv6, so the SPEC follows the specification and su09 encodes the SPEC values.

### 2.3 The Rocket model's unreset state (found while debugging, kept as evidence)

The first S-mode fetch after `mret` raised an instruction access fault (cause 1, `mtval = mepc`) in about
half of the runs of the *same* binary — with a NAPOT-all-addresses PMP, with a TOR one, with a DRAM-sized
NAPOT one, with `sfence.vma`/`fence.i` before `mret`, at any alignment (`REPORT` debugging table below).
The variable turned out to be Verilator's initial value for state that has no reset:
`+verilator+rand+reset+0` (zeros) passes every time, `+1` (ones) hangs every time, `+2` (random, the
harness default) hangs about half the time; a harness rebuilt with `randReset(0)` in `soc_main.cpp` but
the generated RTL's own `$random` initialisation still varied. So some register in Rocket's Bare-mode
S/U fetch-permission path is not reset (xv6 never runs S-mode at Bare, so the board never sees it).
The reference runs pin `+verilator+rand+reset+0 +verilator+seed+1` and the run log contains the
all-ones and three randomised runs of su01 as the documenting evidence (`ref-run2/su01.rocket-rr*.log`).
This is a limitation of the reference model, not a spec disagreement, and it does not affect M-mode
programs (every earlier M-only run of this model was deterministic).

| Minimal program (su_init; mret to S; exit) | 6 runs, default random reset |
|---|---|
| plain | 2 2 2 2 111 111 (2 = timeout, 111 = reached S) |
| `sfence.vma` before `mret` | 111 2 111 2 111 2 |
| `fence.i` before `mret` | 2 111 111 2 111 111 |
| target aligned 16 | 111 2 111 111 111 111 |
| shifted by 8 | 2 2 111 111 111 2 |
| plain, `+verilator+rand+reset+0`, seeds 1–6 | 111 ×6 |
| plain, `+verilator+rand+reset+1`, seeds 1–6 | 2 ×6 |

With the unreset state zeroed the Rocket runs are deterministic (the earlier "spurious first S software interrupt" seen in su06 was the same unreset state: `mip.SSIP`).

Also found on the way and required by the spec anyway: after writing PMP CSRs an `sfence.vma` is needed
(the Rocket TLB caches PMP results); `su_init` does it, and D-6 records it for the future PMP software.

### 2.4 Runs that failed, kept

`ref-run1/` (build1): su03 check 6 on Rocket (S ecall not delegable there — moved to su09) and su06
check 7 on both (the sequence scan included the final return ecall — a test bug, fixed; and qemu's
wall-clock `mtime` fires the timer again while the handlers run, which the order-based check now
tolerates). Earlier iterations (before the unreset-state finding) are described in §2.3; their scratch
builds were outside the delivery tree and are not claimed.

## 3. What is not claimed

* No RTL for S/U exists yet; the SPEC is what the next task implements, and the tests are its input.
* xv6 cannot run at the Bare step (its `satp` write is ignored by design, D-2) — it needs Sv39.
* The references validate the *behaviour* tests, not the SPEC-only WARL values (those are spec-derived
  and rejected by both references as predicted); the teaching core will be the first machine to pass su08/su09.
* Nothing about performance, and nothing on the board.
