# CPU-SV39 — serial Sv39 page-table walk, no TLB, on the teaching core

Delegation `codex-cpu-sv39-implementation` (Codex, 2026-09-18). Spec: The RISC-V Privileged Architecture
v20240411, §10.1.11 (satp), §10.3 (Sv39: §10.3.1 addressing, §10.3.2 PTE format, §10.3.3 A/D, §10.3.4
translation process), §3.1.6.3 (MPRV/SUM/MXR), §10.2.1 (SFENCE.VMA); exception priority §3.1.15. Frozen
local contracts: `m0/CONTRACT.md` §A (MMU minimum), `m2-prep/STAGES.md` S3, `cpu-su-prep/CODEX_DECISIONS.md`.
Everything below was written before the RTL; where the spec leaves a choice the choice is named.

## 1. satp and the status bits

| Item | Behaviour |
|---|---|
| `satp.MODE` | 0 (Bare) and 8 (Sv39) supported. A write with any other MODE **ignores the whole write** (spec). A write with MODE = 0 stores 0 in every field (D-2, unchanged). ASIDLEN = 0: the ASID field reads 0. |
| `satp.PPN` | all 44 bits are stored and read back as written (WARL choice: no masking at write time). The physical address space is 32 bits (this SoC): a page-table address or a translated address whose bits 55:32 are not zero is **not truncated** — it raises an *access fault* of the access's own class (1/5/7) at use. So a high PPN is visible (read-back) and honest (faults), never aliased. |
| SUM | a real bit now (was read-only 0 at Bare). mstatus write-all-ones reads `0xA000E19AA`, sstatus `0x2000C0122`. |
| MXR, MPRV, MPP | unchanged storage; their effects are defined below. |
| `misa` | unchanged (`0x8000000000141104`); Sv39 is announced by satp, not misa. |

Bare normalisation: with MODE = 0 an address is used as a physical address after the existing 32-bit range
check (bits 63:32 must be 0, else access fault). No canonical-VA rule applies at Bare.

## 2. When an access is translated

`xlate_fetch = (MODE == 8) && priv != M` — an M-mode fetch is never translated, MPRV has no effect on it.
`xlate_data = (MODE == 8) && eff_priv != M` with `eff_priv = MPRV ? MPP : priv` for loads and stores
(spec §3.1.6.3). The effective privilege is also what the permission check uses. SFENCE.VMA is a
serial no-op: nothing is cached, so there is nothing to invalidate; a satp or status write lands at the
architectural boundary and the very next access uses it (§6).

## 3. The walk (`rtl/tcpu_ptw.v`)

An independent module started by the core with {VA, type ∈ {fetch, load, store}, eff_priv, SUM, MXR,
root PPN}. While busy it owns the physical port (the core's request outputs are muxed to it; one
outstanding transaction as always; a request is never withdrawn; responses no earlier than the next
cycle). Steps, exactly §10.3.4:

1. Canonical VA: bits 63:39 must all equal bit 38, else **page fault** (12/13/15 by type).
2. `a = root_ppn << 12`, level `i = 2`. `pte_addr = a + vpn[i] * 8`; if `pte_addr[55:32] != 0` →
   **access fault** (1/5/7: the PTE address cannot exist). One 8-byte read of the PTE at `pte_addr` as a
   physical access; a bus error on it → access fault (1/5/7).
3. `V = 0`, or `R = 0 ∧ W = 1`, or any of bits 63:54 set (no Svnapot/Svpbmt) → page fault.
4. Non-leaf (`R = X = 0`): if `i = 0`, **or any of D, A, U is set** (reserved on a non-leaf, §10.3.1; a set
   reserved bit is a page fault of the access's class, §10.3.4 step 3 — corrected after Codex's review, the
   first version ignored them), → page fault; else `a = ppn << 12`, `i ← i − 1`, back to 2. G and RSW on a
   non-leaf are ordinary and do not fault.
5. Leaf: superpage alignment — `i = 2` needs `ppn[17:0] = 0`, `i = 1` needs `ppn[8:0] = 0`, else page
   fault. Permission: fetch needs X; load needs R, or X when MXR; store needs W. U-bit: U-mode needs U = 1;
   S-mode data needs U = 0 or SUM; **S-mode fetch from a U page faults regardless of SUM**. `A = 0` →
   page fault; store with `D = 0` → page fault (**software sets A/D; the hardware never writes a PTE** —
   the same choice as this SoC's Rocket, and unlike qemu's default, which updates A/D itself).
6. PA = `{ppn[43:18], va[29:0]}` / `{ppn[43:9], va[20:0]}` / `{ppn, va[11:0]}` for `i = 2/1/0` (56 bits).
   Back in the core: `pa[55:32] != 0` → access fault of the access's class; otherwise the access is issued
   at `pa[31:0]`. The translation happens **before** the PA range check; a high VA that translates to a
   low PA is fine, and a high PA is never truncated.

Faults: page faults 12/13/15 with `xtval = VA`; access faults 1/5/7 with `xtval = VA` (the address the
program used). `xepc` is the instruction's own address. Nothing retires, no register is written, and a
store that faults **never reaches the bus** — the data request is only issued after a successful walk.

## 4. Integration in the core (`rtl/tcpu_core.v`)

One new state `S_XLATE` (12) with a kind: first parcel, second parcel, or data.

* `S_IF_REQ`: interrupt check → `pc[0]` misaligned → *translate* (if `xlate_fetch`) → else Bare range
  check → fetch request. After a successful walk the fetch request goes out with the PA.
* `S_IF2_REQ`: the second parcel (`pc + 2`) is translated **on its own** — a 32-bit instruction may straddle
  two pages that map to non-contiguous physical pages. A fault there: `xepc = pc` (the instruction's
  start), `xtval = pc + 2` (the failing half's VA), exactly as the existing Bare second-parcel error.
* `S_EXEC` for a load/store: the frozen order is kept — misaligned (4/6) is decided on the VA **before**
  translation; then *translate* (if `xlate_data`) → else the Bare range check → request. The write payload
  and mask derive from the VA's low bits, which the PA shares.
* Interrupts are still sampled only in `S_IF_REQ`: a walk is never interrupted, a PTE read is never lost,
  and an interrupt that arrives during a walk is taken once, at the boundary after the instruction (or
  after the fault). A core-only reset during a walk (`+core-reset-at-op=ptw`) follows the existing bridge
  model: the outstanding PTE answer is discarded, the restarted core never sees it.
* `dbg_req_is_fetch` is false during a walk (PTE reads count as data requests in the harness statistics).

## 5. Fault injection (named, one defect each)

| Parameter | Defect | Rejected by |
|---|---|---|
| `FAULT_PTW_NO_PERM` | the leaf's R/W/X/U/SUM/MXR checks are skipped | sv03 (a U-mode access to an S page, a store to a read-only page and an S fetch from a U page all succeed) |
| `FAULT_IF2_NO_XLATE` | the second parcel is fetched at first-PA + 2 instead of being translated | sv05 (the straddling instruction's second half comes from the wrong physical page) |
| `FAULT_PPN_TRUNC` | a PA with bits 55:32 set is truncated and used | sv04 (a leaf with a high PPN aliases into low memory instead of faulting) |

## 6. Tests (`tests/`, built on the CPU-SU environment: handlers, macros, CLINT)

Page tables are built by the test in M-mode inside its own 4 KiB-aligned arrays (identity maps for the
0–1 GiB (CLINT), 1–2 GiB (test controller) and 2–3 GiB (DRAM) gigapages, plus the specific pages a test
needs); A and D are set by software where a page must be usable.

| Test | Covers | References |
|---|---|---|
| sv01_bare_sv39 | Bare → Sv39 → Bare switch; S and U fetch/load/store under identity 1 GiB leaves; satp read-back (MODE 8, ASID 0, PPN); a write with MODE = 3 ignored; the M handler runs untranslated | Rocket/qemu 0 |
| sv02_pages | 4 KiB, 2 MiB, 1 GiB leaves; an alias (VA ≠ PA) for data checked through the PA; code executed through a 2 MiB alias | Rocket/qemu 0 |
| sv03_perms | the permission matrix: R/W/X, U vs S, SUM (data only; S fetch from U page always faults), MXR, MPRV with MPP = S/U from M, M fetch untouched; each fault: cause/epc/tval, no retire, the failed store left memory unchanged | Rocket/qemu 0 |
| sv04_bad_pte | V = 0; W∧¬R; reserved high bits; a pointer at level 0; a misaligned 2 MiB leaf; a non-canonical VA; A = 0; D = 0 on store (load fine); leaf PPN beyond the PA space (access fault); page-table address beyond the PA space; a PTE read that gets a bus error | Rocket/qemu recorded (qemu sets A/D itself) |
| sv05_straddle | a 32-bit instruction straddling two VA pages mapped to non-contiguous PAs; a compressed parcel at a page end; a second-parcel page fault: epc = start, tval = second half | Rocket/qemu 0 |
| sv06_switch | remap a leaf, SFENCE.VMA, the next access uses the new mapping; switch satp to a second root; back to Bare; a delegated page fault handled in S | Rocket/qemu 0 |
| sv09_nonleaf | non-leaf D/A/U reserved bits (added after Codex's review): each bit alone, at level 2 and level 1, for load/store/fetch (13/15/12) with epc/tval, the store leaving the page untouched, and the faulting accesses never retiring; G/RSW on the same pointers and a leaf with U/A/D as controls; the same ELF on the walker before the fix fails at its first case (check 11) | Rocket recorded (its priv-1.10 PTW has no such rule); qemu 0 expected |
| sv07_irq_ptw (harness) | an interrupt injected while a PTE read is outstanding: deferred, taken once after the instruction, the walk completes, the target retires once | core only |
| sv08_reset_ptw (harness) | a core-only reset during a walk: no stale PTE answer used, the re-run retires the instruction once | core only |
| boot11_sv39 (SoC) | S-mode Sv39 fetch + data through an alias, a delegated page fault handled in S, marker `M3-SV39-OK` through ROM/TSI/DDR/HTIF | SoC |

Expectation changes in the CPU-SU tests caused by Sv39 (copies with recorded diffs, the originals kept):
su08 (satp MODE = 8 is now stored: read-back `8 << 60 | ppn`; a write with MODE = 3 is the "ignored" case),
su09 (mstatus/sstatus all-ones read-backs with SUM), su11 (SUM is writable). No illegal/privilege check is
removed.
