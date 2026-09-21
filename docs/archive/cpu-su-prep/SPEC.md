# CPU-SU — the privileged contract for the next implementation: Bare-address M/S/U on the teaching core

Claude, 2026-09-18; **synchronised to `CODEX_DECISIONS.md` (Codex, 2026-09-18), which overrides this text wherever they differ.** Delegation `codex-cpu-su-contract`, implementation `codex-cpu-su-implementation`. This document is the implementable specification
for the step after CPU-C: M/S/U privilege levels, delegation, the S-level CSRs, and the cross-mode
interrupt rules, **with satp fixed at Bare** (no translation; Sv39 and the PTW are the following task).
Every requirement below is traced to one of three sources: **The RISC-V Instruction Set Manual Volume II: Privileged Architecture, version 20240411** (`docs.riscv.org/reference/isa/v20240411/priv/`; chapter "Machine-Level ISA" §3.1.6 mstatus, §3.1.8 medeleg/mideleg, §3.1.9 mip/mie, §3.1.14–3.1.16 mepc/mcause/mtval, §3.3.2 trap return, §3.7 PMP; chapter "Supervisor-Level ISA" §10.1 sstatus/sie/sip, §10.1.11 satp, §10.2.1 SFENCE.VMA) — deliberately supported subsets and allowed-choice values are marked as such, the xv6 kernel actually built for this platform (`teaching-cpu-work/xv6-sim/
kernel`, the xv6-on-rocket port applied, its `kernel.asm` audited), and the existing core
(`teaching-cpu-work/cpu/rtl/tcpu_{core,csr}.v`, accepted through CPU-C). Where the choice is ours it is
marked **[D-n]** and argued in `DECISIONS.md`; those few items are what Codex is asked to rule on.

Nothing in this task changes the CPU's functional RTL, the Rocket/board artefacts, or the boot software.
It corrects, by table, the older texts it supersedes: `m2-prep/STAGES.md` lists `misa` as "read-only"
(it is a fixed WARL register: writes are accepted and discarded, as CPU-M/CPU-C implemented) and says
"M-only stage: medeleg/mideleg not writable" (true until now; from this step they exist); the M0
contract's "misa(只读)" is the same correction. Historical documents are left as they are.

## 0. What xv6 actually needs (the audited floor)

From `kernel.asm` (rv64gc build, xv6-on-rocket port, base commit `35b0884`):

| Item | Count / use | Consequence |
|---|---|---|
| `mret` | 3 (`start()` → S, `timervec` return, `reflect`) | M→S with MPP written by software; MPP = S must be a legal, stored value |
| `sret` | 2 (`kernelvec`, `trampoline`) | S→U and S→S returns; SPP both values |
| `ecall` | 0 in the kernel, 22 per user program | cause 8 from U, delegated to S by `medeleg = 0xffff` |
| `wfi` | 0 | keep the existing no-op; no mode rule is exercised by xv6 |
| `sfence.vma` | 6 (`kvminithart`, `trampoline`) | must be legal in S at Bare (no-op) |
| `fence` / `fence.i` | 7 / 1 | already legal no-ops |
| `amoswap.w(.aq)` | 4 (spinlocks) | **not in this step**; see DECISIONS D-7 |
| `lr/sc` | 0 | — |
| M CSRs written | mstatus medeleg mideleg mie mepc mtvec mscratch pmpaddr0 pmpcfg0 (mcause/mtval/mhartid read) | pmp: see D-6 |
| S CSRs | sstatus (14) scause sepc satp stvec stval sip sie sscratch | all of them, real |
| `sip` writes | `csrw sip, 2` from M in `timervec`; `w_sip(r_sip() & ~2)` from S in `devintr` | SSIP is a real, software-writable bit at both levels |
| `sie` | `SIE_SEIE | SIE_STIE | SIE_SSIE` set once in `start()` while in M (after `mideleg = 0xffff`) | sie must accept the write; only SSIE matters at run time |
| `sstatus` writes | `intr_on/intr_off` (SIE), `usertrapret` (SPP cleared, SPIE set), `kerneltrap` restore | no SUM/MXR/TVM/TSR/TW use (grep: none) |
| `mcounteren`, `menvcfg`, `stimecmp`, `time` | defined in `riscv.h`, **never called** (the port removed the menvcfg/Sstc path) | not required; see §3 for what exists |
| Delegation | `medeleg = mideleg = 0xffff`; non-delegated M traps are *reflected* into S by `timervec`'s software path | either a wide or a Rocket-sized medeleg works; D-1 picks |
| Timer | CLINT `mtimecmp`, taken in M, re-armed from `mtime`, reflected as SSIP | §5 scheme; CLINT MMIO unchanged |
| PLIC | `plicinit/plicinithart` write PLIC registers; `devintr` handles cause 9 (SEIP) — but the block device polls and the console is HTIF | SEIP may stay read-only 0 (no S context is wired on the SoC: `plicSink` is the M context only) |

The user programs contain no CSR, AMO, or privileged instruction (audited `_usertests`: 0; 22 `ecall`).

## 1. Privilege levels and the two returns

* Three levels: M (3), S (1), U (0). The current level is a 2-bit state `priv`, reset value M. It is not
  architecturally visible except through its effects (which CSRs are accessible, which trap cause an
  `ecall` produces, and MPP/SPP after a trap).
* **Trap entry** (§4 decides the target level `T` ∈ {M, S}). For `T = M`: `mepc ← pc`, `mcause`, `mtval`,
  `mstatus.MPIE ← MIE`, `MIE ← 0`, `MPP ← priv`, `priv ← M`, `pc ← mtvec`. For `T = S`: `sepc ← pc`,
  `scause`, `stval`, `SPIE ← SIE`, `SIE ← 0`, `SPP ← (priv == S)`, `priv ← S`, `pc ← stvec`.
  `xepc` bit 0 is written 0 (IALIGN = 16, as CPU-C). A trap never retires the instruction, writes no
  register, and `minstret` does not count it (unchanged).
* **`mret`** (M only; illegal in S/U — cause 2, `mtval` = encoding): `priv ← MPP`, `MIE ← MPIE`,
  `MPIE ← 1`, `MPP ← U`; if the new `priv ≠ M` then `MPRV ← 0`; `pc ← mepc`.
* **`sret`** (S or M; illegal in U; **TSR is hardwired 0** so S may always execute it — D-4):
  `priv ← SPP ? S : U`, `SIE ← SPIE`, `SPIE ← 1`, `SPP ← 0`, `MPRV ← 0` (the new priv is never M
  when executed in S; when executed in M the spec's "if xPP ≠ M" rule gives the same), `pc ← sepc`.
* **`ecall`**: cause 8 / 9 / 11 for U / S / M; `xtval = 0`. **`ebreak`**: cause 3, `xtval = pc` (as today).
* **`wfi`**: stays a legal no-op that retires once, **in all three modes** (TW hardwired 0; the spec allows
  U-mode WFI when it completes within a bounded time, and the bound here is zero) — D-5.
* **`sfence.vma`** (rs1/rs2 any): legal no-op in S and M (TVM hardwired 0); **illegal in U** (cause 2).
  At Bare nothing is cached, so no-op is its full semantics, not a stub.
* **Illegal-instruction rule extended**: a CSR instruction whose address has privilege bits (`csr[9:8]`)
  above `priv` is illegal; a write (write intent as decoded today) to a read-only address (`csr[11:10] ==
  11`) is illegal; both are decided before any side effect, exactly as `csr_addr_illegal` is today.
  Counter reads (`cycle`, `instret`) from S require `mcounteren.{CY,IR}`; from U require both
  `mcounteren` and `scounteren` bits; otherwise illegal.

## 2. mstatus / sstatus

`mstatus` is one register; `sstatus` is a **view** of it (same storage, masked). Bits, RV64 positions:

| Bit(s) | Field | Behaviour at this step | Visible in `sstatus` |
|---|---|---|---|
| 1 | SIE | real | yes |
| 3 | MIE | real | no |
| 5 | SPIE | real | yes |
| 7 | MPIE | real | no |
| 8 | SPP | real (1 bit) | yes |
| 12:11 | MPP | real, WARL: legal values 0 (U), 1 (S), 3 (M); a write of 2 stores **0** — D-3 | no |
| 17 | MPRV | real bit, **stored**; effect ("data accesses use MPP's privilege") is a no-op at Bare without PMP, which is its exact semantics here; cleared by `xret` as above | no |
| 18 | SUM | **read-only 0 at the Bare-only step** (Codex correction: satp.MODE is fixed 0, so the bit has no legal meaning yet; Sv39 enables it) | yes (0) |
| 19 | MXR | real bit, stored; effect arrives with Sv39 | yes |
| 20 | TVM | **hardwired 0** (D-4) | no |
| 21 | TW | **hardwired 0** (D-5) | no |
| 22 | TSR | **hardwired 0** (D-4) | no |
| 33:32 | UXL | read-only 2 | yes |
| 35:34 | SXL | read-only 2 | no |
| 14:13 FS, 16:15 XS, 10:9 VS, 63 SD, 6 UBE, 36 SBE, 37 MBE | 0 | read-only 0 (no FPU, little-endian only) | (FS/XS/SD in sstatus, 0) |
| others | 0 | read-only 0 | — |

Write-all-ones read-back: `mstatus = 0x0000_000A_000A_19AA`; `sstatus = 0x0000_0002_0008_0122` (bit 18 clear).
Reset: all writable bits 0 except the level (`priv = M`); `MPP` reads 0 after reset (it is only meaningful
after a trap). This replaces today's "MPP hardwired 11".

## 3. The CSR table

Access column: the level needed (from `csr[9:8]`); RO = read-only address (`csr[11:10] = 11`).

| Addr | CSR | Access | Storage / WARL | Read | Write |
|---|---|---|---|---|---|
| 0x300 | mstatus | M | §2 | §2 | §2 |
| 0x301 | misa | M | fixed WARL | `0x8000_0000_0014_1104` (RV64 I M C **S U**) | discarded |
| 0x302 | medeleg | M | mask **0xB3FF** (D-1): causes 0–9, 12, 13, 15; bit 11 and reserved 10/14 read-only 0 | stored & mask | stored & mask |
| 0x303 | mideleg | M | mask **0x222** (SSI, STI, SEI); M-level interrupts not delegable | stored & mask | stored & mask |
| 0x304 | mie | M | mask 0xAAA (SSIE 1, MSIE 3, STIE 5, MTIE 7, SEIE 9, MEIE 11) | | |
| 0x305 | mtvec | M | direct mode only: `[1:0]` forced 0 (unchanged) | | |
| 0x306 | mcounteren | M | mask 0x5 (CY, IR); **no TM** (no `time` CSR, D-8) | | |
| 0x340 | mscratch | M | full | | |
| 0x341 | mepc | M | bit 0 forced 0 | | |
| 0x342 | mcause | M | full (WARL: any value stored, as today) | | |
| 0x343 | mtval | M | full | | |
| 0x344 | mip | M | MSIP/MTIP/MEIP = external levels (read-only); **SSIP, STIP, SEIP are real software-pending bits, writable at the M address** (Codex correction: M software may inject any S-level interrupt whether or not an S hardware source is wired; at this step no S external line exists, so SEIP reads the software bit; if a line is wired later the read is OR-ed, the read-modify-write still only changes the software bit) | levels ∣ {SEIP,STIP,SSIP} | bits 1, 5, 9 |
| 0x3A0/0x3B0 | pmpcfg0 / pmpaddr0 | M | **not implemented at this step → illegal** (D-6) | — | — |
| 0x30A | menvcfg | M | not implemented → illegal (the port already avoids it) | — | — |
| 0xB00/0xB02 | mcycle / minstret | M | as today | | |
| 0xC00/0xC02 | cycle / instret | RO, U | gated by counteren (§1) | mcycle/minstret | illegal |
| 0xC01 | time | RO, U | **not implemented → illegal** (D-8) | — | — |
| 0xF14 | mhartid | RO, M | 0 | 0 | illegal |
| 0x100 | sstatus | S | view of mstatus (§2) | masked | masked (only the listed S bits change) |
| 0x104 | sie | S | **view of mie ∧ mideleg**: bits whose mideleg bit is 0 read as 0 and are not written | `mie & mideleg` | `mie[b] ← wdata[b]` for delegated b only |
| 0x105 | stvec | S | direct mode only, `[1:0]` forced 0 | | |
| 0x106 | scounteren | S | mask 0x5 | | |
| 0x140 | sscratch | S | full | | |
| 0x141 | sepc | S | bit 0 forced 0 | | |
| 0x142 | scause | S | full | | |
| 0x143 | stval | S | full | | |
| 0x144 | sip | S | view of mip ∧ mideleg: **SSIP writable only when delegated**; STIP/SEIP read-only at the S address (the rule is by CSR address, not by the executing level: an M-mode `csrw sip` also only touches SSIP) | `mip & mideleg` | SSIP only (if mideleg[1]) |
| 0x180 | satp | S (illegal in U; TVM = 0 so S may access it) | **Bare only**: MODE ≠ 0 → the whole write is ignored; MODE = 0 with nonzero ASID/PPN → stored as 0 (only legal value) — D-2 | 0 | as stated |
| any other | — | — | illegal | | |

Notes. (a) *Read-modify-write*: as today, the value written and the value returned derive from one read,
in the retiring cycle; a CSRRS/CSRRC with `rs1 = x0` (or uimm 0) does not write and therefore cannot
trap for a read-only address, but still traps for privilege. (b) *Views*: `sstatus`, `sie`, `sip` must
not be separate registers; an M-mode write to `mie` is immediately visible through `sie` and vice versa.
(c) `mip.SSIP/STIP/SEIP` are the software-pending bits (M address); the xv6 timer scheme relies on SSIP.
(d) The harness read-back port (`dbg_sel`) gains selectors for the new registers and `priv`.

## 4. Where a trap goes (delegation) and which interrupts are taken

**Synchronous exceptions.** `T = S` iff `priv ≤ S` **and** `medeleg[cause] = 1`; otherwise `T = M`.
An exception raised in M never delegates (su03 checks this with `medeleg = all ones`).

**Interrupts** (evaluated at the instruction boundary, as today, from levels ∧ enables):
```
pend_m = mip & mie & ~mideleg          # M-level pending & enabled
pend_s = mip & mie &  mideleg          # S-level pending & enabled
take_m = pend_m ≠ 0 and (priv < M  or (priv == M and MIE))
take_s = pend_s ≠ 0 and (priv < S  or (priv == S and SIE)) and not take_m   # M-level first
```
An M-level interrupt is *always* taken when running in S or U (MIE only gates M-mode itself); an
S-level interrupt is *never* taken in M, always in U, and in S only with SIE. Within a level the priority
order is MEI > MSI > MTI > SEI > SSI > STI (v20240411 §3.1.9). The cause is `1<<63 | n`, the target is M for
`take_m`, S for `take_s`; xepc = the instruction that was about to execute. `EARLY_IRQ`/`STALE_MIE`
fault injection keeps its meaning.

The "acceptance matrix" su05 exercises, with the current mode down the side (E = taken, W = waits):

| | M-level src (`~mideleg`) | S-level src (`mideleg`) |
|---|---|---|
| U | E | E |
| S | E | E if SIE else W |
| M | E if MIE else W | W (never) |

## 5. The xv6 timer path, end to end

CLINT `mtimecmp ≤ mtime` → `MTIP` level → (M-level, `mie.MTIE`) → taken in S/U, or in M with MIE → M
handler (`timervec`): rearms `mtimecmp` from `mtime`, `csrw sip, 2` (SSIP ← 1), `mret` → back in S →
`take_s` (SSIP ∧ SSIE ∧ mideleg[1] ∧ SIE) → `stvec` (`kernelvec`) → `devintr` clears SSIP (`csrc sip`).
su06 runs exactly this with three rounds and checks the strict alternation. Nothing in the CLINT changes.

## 6. Instruction length, alignment, long operations at a trap boundary (unchanged by S/U)

`xepc` = the address of the first parcel of the instruction (2- or 4-byte), bit 0 forced 0; `xtval` for
an illegal instruction = the raw parcel/word; interrupts are only accepted at instruction boundaries,
so a multi-cycle multiply/divide or a two-parcel fetch is never split (CPU-M/CPU-C evidence). su07
checks a 2-byte `c.ebreak`, a 4-byte instruction starting at `pc % 4 == 2`, a 2-byte illegal parcel, and
integer long operations on both sides of a trap.

## 7. Boot, reset, and the ROM

Reset: `priv = M`, `MIE = 0`, delegation 0, PMP none, `satp = 0`. The teaching ROM's `mideleg`
initialisation was replaced by a NOP (`m3/ROM_DECISION.md`); with `mideleg` now existing, **both** the
patched ROM and the original one boot the same way (the reset value is already 0). No ROM change is
made in this task; D-9 records the option to drop the patch later.

## 8. Explicitly out of this step (each becomes its own task)

* Sv39 translation, the PTW, `satp.MODE = 8`, SUM/MXR effects, page-fault causes 12/13/15 (delegable
  bits exist already so xv6's `medeleg` write reads back the same later).
* PMP (D-6): zero entries, the CSRs are illegal; `start.c` is **not** changed now (a future isolated patch).
  The A extension: **D-7 was rejected** — no CPU-internal read-modify-write is offered as the A extension;
  AMO/LR/SC stay illegal and `misa.A = 0` until a real arbitration-domain/atomic-adapter design is ruled on.
* `time` CSR / Sstc (D-8), S-level PLIC context (SEIP stays 0), vectored `xtvec`, `menvcfg`.
* Performance, TLB, pipelining — unchanged policy.

## 9. What is not claimed

No RTL was written; nothing was synthesised. The tests in `tests/` encode this SPEC and were run on two
reference implementations (see `TEST_PLAN.md`/`REPORT.md`); where the references disagree with the
SPEC (Rocket's smaller `medeleg` mask, its `sip.STIP` writability and its un-gated S-mode `cycle`,
both machines' Sv39), the SPEC value is kept and the divergence recorded, not averaged.
