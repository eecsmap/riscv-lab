# CPU-SU — M/S/U at Bare on the teaching core: what was built

Implements `cpu-su-prep/SPEC.md` as ruled in `cpu-su-prep/CODEX_DECISIONS.md` (Privileged Architecture
v20240411 §3.1.6, §3.1.8, §3.1.9, §3.3.2, §10.1, §10.1.11). RTL changes are confined to the core's CSR file
and a few lines of the sequencer; diffs against the CPU-C delivery are in `tcpu_csr.pre-su-to-su.diff`
and `tcpu_core.pre-su-to-su.diff`.

## `rtl/tcpu_csr.v` (rewritten)

* **Level.** `cur_priv` (M = 3, S = 1, U = 0), reset M, exported as `priv`. Trap entry writes it; `mret`
  restores it from MPP, `sret` from SPP.
* **One status register.** `mstatus` fields SIE, MIE, SPIE, MPIE, SPP, MPP (write of 2 stores 0, D-3),
  MPRV, MXR are flip-flops; UXL/SXL read 2; SUM/TVM/TW/TSR/FS/XS/VS/SD/xBE read 0. `sstatus` is
  `mstatus & 0x2_0008_0122` for reads and touches only SIE/SPIE/SPP/MXR on writes.
* **mie / sie, mip / sip as views.** `sie` reads `mie & mideleg` and writes only delegated bits.
  `mip` = external levels at 3/7/11 (never stored) plus software bits SSIP/STIP/SEIP (1/5/9) writable at the
  M address; `sip` reads `mip & mideleg` and writes only SSIP when delegated (the rule is by address).
* **Delegation.** `medeleg` masked to 0xB3FF, `mideleg` to 0x222. `delegate = priv <= S && bit` is
  computed from the trap cause (bit 63 selects the table); `trap_vector` is `stvec` or `mtvec` for the core.
  Delegated entry writes sepc/scause/stval, SPIE ← SIE, SIE ← 0, SPP ← (priv == S), priv ← S; otherwise
  the M set with MPP ← priv.
* **Interrupts.** `pend = mip & mie`, split by `mideleg`; `take_m = pend_m && (priv < M || MIE)`,
  `take_s = pend_s && !take_m && (priv < S || (priv == S && SIE))`; cause by MEI > MSI > MTI > SEI > SSI > STI.
  `irq_enabled` (what the injector reports) is "an M-level line would be accepted now".
* **Access rule.** Illegal when the address is unknown (pmp*, menvcfg, time, ...), when `priv < addr[9:8]`,
  when a write aims at a read-only address, or when `cycle`/`instret` are read below M without the
  `mcounteren` (S) and `scounteren` (U) bits. Decided before any side effect, as before.
* **satp.** Reads 0; every write is discarded (the only supported MODE is Bare; an unsupported MODE ignores
  the whole write; MODE = 0 with nonzero fields stores 0 — D-2). No translation exists.
* **Counters.** `mcounteren`/`scounteren` store CY and IR only; `time` is not implemented (D-8).
* **misa** = `0x8000000000141104` (I M C S U; no A — D-7 rejected the RMW substitute).
* Fault injection: `FAULT_NO_DELEG`, `FAULT_S_IRQ_IN_M` (an S-level interrupt taken in M, gated by MIE),
  `FAULT_SRET_SPP`.
* Read-back port widened to 25 selectors (adds the S CSRs, delegation, counteren and `priv`).

## `rtl/tcpu_core.v` (42 changed lines)

`sret` (0x10200073) and `sfence.vma` (funct7 0001001, rd 0) join the SYSTEM decode; `sfence.vma` is a
retiring no-op at Bare. Privilege legality is part of `illegal`, so it is settled before any effect:
`mret` needs M, `sret` and `sfence.vma` are illegal in U (TSR = TVM = 0 keep them legal in S); `wfi` is
legal everywhere (TW = 0). The ecall cause is 8/9/11 by level. `S_TRAP` jumps to `csr_trap_vector`;
`sret_go` joins `mret_go` in S_WB so the level change lands with the retirement. Nothing else moved: the
single port, one outstanding request, the 2/4-byte fetch, interrupts sampled only in S_IF_REQ.

## Testbench

* `tb/tcpu_harness.v`: a precisely defined **CLINT model** at 0x0200_0000 (msip at +0, mtimecmp at +0x4000,
  mtime at +0xBFF8 counting every cycle; other offsets read 0, writes ignored; mtimecmp reset to all ones
  here, unlike the real device — the SoC runs cover the real one). Its msip/mtip are OR-ed into the
  injector's lines. `fire_priv` latches the level at the moment a line is raised. `bd_csr_sel` is 5 bits.
* `tb/tcpu_main.cpp`: CSR selector names up to `priv` (24); the FIRE line prints the latched level; the
  level at exit is printed; `+expect-csr=24:<level>` checks the real level.
