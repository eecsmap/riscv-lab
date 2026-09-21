# CPU-SU — test plan for the Bare-address M/S/U implementation

Every test is a bare-metal RV64 program (`tests/`), linked at 0x80000000 with the M2-prep conventions
(`crt.S`, `link.ld`, `testmac.h`: a failing check exits through `tohost` with its own number, PASS is 0).
The expected values are written from the privileged specification (see `SPEC.md`) **before** any run,
never read back from a machine; the two reference machines then confirm that the expectations describe
implementable, agreed behaviour. Where a reference differs from the SPEC the difference is recorded in
`REPORT.md` and the SPEC value stands.

## Assets

| File | Role |
|---|---|
| `tests/su_env.h` | field positions, causes, mode-change macros (`ENTER_S`, `ENTER_U_M`, `ENTER_U_S`, `RET_M`, `RET_S`, ...) |
| `tests/handlers.S` | the M and S trap handlers (log of {cause, epc, tval, status} per trap, counters, a shared event sequence, service requests via a7), `su_init` (handlers, save areas, PMP probe + `sfence.vma`, nothing delegated, interrupts off) |
| `tests/crt.S`, `link.ld`, `testmac.h` | M2-prep copies; `crt.S` adds `.size tohost, 8` for qemu |
| `tests/htif_console.S` | m3tests `htif.S` without its `tohost` (crt owns it); used by the probe only |
| `scripts/build.sh <dir>` | builds every test (rv64imc_zicsr) with disassembly, symbols, hashes |
| `scripts/reference-run.sh <elfdir> <dir>` | runs everything on the Rocket model and on qemu's spike machine, records exits/cycles, prints the probe's answers |

The tests do not depend on the RTL to be written: they run today on the references, and the same ELFs
are the acceptance input for the S/U implementation (through the CPU harness or the SoC simulator).

## The tests and their expectations

Codes are the failing check's number; `want` is the SPEC-derived exit code.

| Test | What it establishes (SPEC §) | want | Reference status (see REPORT for the runs) |
|---|---|---|---|
| `su01_modes` | M→S→U and back through ecall; MPP/SPP read inside the handler; `mret` leaves MIE←MPIE, MPIE←1, MPP←U (§1) | 0 | Rocket 0, qemu 0 |
| `su02_csr_priv` | from S: mstatus/mie/`mret` illegal, S CSRs/satp/`sfence.vma` legal; from U: sstatus/`sret`/satp illegal; cause 2 and epc per instruction; ungated counter reads (§1, §3) | 0 | Rocket 0, qemu 0 |
| `su03_deleg` | medeleg per cause: U ecall to S (SPP/SPIE/SIE inside and after), S ecall to S (SPP = S), traps in M never delegate, U breakpoint with only bit 8 set lands in M (§4) | 0 | Rocket 0, qemu 0 |
| `su04_strap` | nested trap inside the S handler with software save/restore of sepc/scause/sstatus, `sret` with SIE 0/1, the U→S→U→S syscall round trip (§1) | 0 | Rocket 0, qemu 0 |
| `su05_irq_modes` | the acceptance matrix (§4): M-level waits on MIE in M, always taken in S/U (taken at the first instruction after `mret`); delegated S-level never in M, needs SIE in S, always in U; both pending → M first; a non-delegated SSI is M-level | 0 | Rocket 0, qemu 0 |
| `su06_timer_ssip` | the xv6 timer path (§5): CLINT timer to M, rearm, SSIP set in M, taken in S, cleared by S; order-based sequence check; SSIP set/cleared by S | 0 | Rocket 0, qemu 0 |
| `su07_epc_len` | 2-byte `c.ebreak` (resume +2), 4-byte instruction at pc%4 == 2, 2-byte illegal parcel (+2), long mul/div around a trap, `xepc` bit 0 forced 0 and bit 1 kept (§6) | 0 | Rocket 0, qemu 0 |
| `su08_satp_bare` | satp at the Bare-only step: MODE=8 write ignored, MODE=0 with nonzero fields reads 0, accessible from S (§3, D-2) | 0 on the teaching core; **1** on both references (they implement Sv39) | Rocket 1, qemu 1 (as predicted) |
| `su09_warl` | WARL read-backs and gating the references do not follow: misa, medeleg 0xB3FF, mideleg 0x222, mie 0xAAA, sie as a delegated view, mip write mask, mstatus 0xA000E19AA, xtvec direct-only, counteren 0x5, mtval = raw encoding, mhartid 0, counter gating in S and U, sip.STIP read-only, cause 2 delegable | 0 on the teaching core; **1** on both references (misa) | Rocket 1, qemu 1 (as predicted) |
| `su10_wfi` | `wfi` retires as a no-op in M, S and U; pending-but-disabled does not stall; enabled is taken (D-5) | 0 | added after the rulings; qemu makes U-mode wfi illegal (allowed choice), so it is not a reference gate |
| `su11_mip_sw` | mip[1,5,9] software-writable at the M address; sip view/write rules by address; software STIP/SEIP delegated → S, not delegated → M; SUM read-only 0 (CODEX_DECISIONS.md) | 0 | added after the rulings; SPEC-derived, run on the core |
| `su12_aimed_u` | CPU harness only: an M-level interrupt aimed at a U-mode instruction with MIE = 0 — enabled below M, retired-once/RF/mepc chain, MPP = U | 0 | not runnable on the references (test controller) |
| `su_probe` | prints what a machine answers for the su08/su09 questions (no checks) | 0 | recorded in REPORT |

The per-check meaning is in each source file next to the check number, so a failing code on the
implementation names the exact requirement.

## What is not covered here (and why)

* `wfi` in S/U (D-5): the two references disagree (qemu: illegal in U; Rocket: legal) and both are
  spec-legal; the SPEC keeps the no-op. Not a gate.
* `mtval` for `ebreak` (Rocket 0, qemu the pc): spec-optional; the teaching core keeps the pc (CPU-C).
* SEIP / PLIC S context, `time`, Sv39, PMP, AMOs: out of this step (SPEC §8, DECISIONS).
* Interrupts *during* a long operation or a second-parcel fetch on a reference: not controllable there;
  the CPU harness's injection points (CPU-M/CPU-C) cover it on the implementation.

## Acceptance gates for the S/U implementation (proposed)

1. `su01`–`su07` exit 0 on the CPU harness under the three memory profiles, commit traces identical.
2. `su08`, `su09` exit 0 on the CPU harness (SPEC values).
3. The same ELFs on the references reproduce the table above (0/0 and the predicted 1/1).
4. The CPU-M/CPU-C entry points still pass (`run-cpu-c.sh`), with `misa` and the new CSR set as the only
   recorded expectation changes.
5. SoC: the four M3 ELFs, boot09/boot10, hello.riscv unchanged; plus `su01`/`su05`/`su06` through
   ROM/TSI/DDR/HTIF with the real CLINT.
6. Named negatives (with the RTL, `cpu-su/`): `FAULT_NO_DELEG` (medeleg ignored) rejected by su03 check 2;
   `FAULT_S_IRQ_IN_M` (a delegated S interrupt taken in M) rejected by su05 check 13; `FAULT_SRET_SPP`
   (sret leaves SPP) rejected by su03 check 1 — each with the RV64I control still passing.
