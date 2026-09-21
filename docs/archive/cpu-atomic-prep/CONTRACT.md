# The atomic-path contract for the teaching core (one preferred scheme) and the xv6 start-up delta

**Synchronised to `CODEX_DECISIONS.md` (2026-09-19), which is authoritative where they differ.** A1–A6 as ruled
(full A in steps; 8-byte reservation set; the shared DRAM node with its exact insertion proven from the generated
RTL; unsupported targets refused at the bridge; transaction-bound side-band; one transaction but final completion),
plus the six semantic corrections folded in below (marked *ruled*).

Basis: `REPORT.md` §1–2 (what xv6 needs, where traffic is serialised), `cpu-su-prep/CODEX_DECISIONS.md` D-6/D-7
(no CPU-internal RMW as the A extension; zero PMP entries), the frozen `PHYSICAL_PORT_V1.md`, the RISC-V
Unprivileged ISA v20240411 ch. 10 "A" (AMO semantics, LR/SC reservation and forward-progress constraints,
`aq/rl`), Privileged v20240411 §3.1.15 (exception priority: AMO faults use the store/AMO causes 6/7/15).

## 3.1 Preferred scheme: atomics executed at the DRAM serialisation point

**Where.** An atomic node of our own (*ruled* 1: rocket-chip's `TLAtomicAutomata` cannot be reused as is — on a
read error it still issues the Put and only ORs the error at the end; the isolated node must issue **no Put after a
Get that returned an error** and terminate with one error response; a write-phase error is reported once, never
retried, and the contract does not claim to undo it) inserted in the teaching/RD2 SoC between the system-bus side
and `TLToAXI4` (i.e. on the DRAM path *after* the crossbar
where the CPU, the TSI adapter and the block-device DMA have merged). Every access to DRAM from every PL
master passes through it; while an AMO's read–modify–write is in progress the automata holds all other
A-channel requests to that manager (`AtomicAutomata.scala:100-102`). **The linearisation point of an AMO is
the automata's write-back Put.** This is not a claim about the PS: its accesses never pass here (§2 of the
report) and are excluded by the platform rule, which the contract states as a precondition.

**Physical port extension** (`PHYSICAL_PORT_V1` → V2, the only field changes):
* `req.amo[3:0]`: 0 none; 1 SWAP, 2 ADD, 3 XOR, 4 AND, 5 OR, 6 MIN, 7 MAX, 8 MINU, 9 MAXU (the nine AMOs).
  With `amo ≠ 0`: `write = 1`, `size ∈ {2, 3}` (w/d), naturally aligned, `wdata` = the operand in the
  address's byte lanes, `wmask` = the operand's lanes; the response carries the **old** memory value in
  `rdata` (the bridge issues `edge.Arithmetic`/`edge.Logical` and expects `AccessAckData`).
* `req.lrsc[1:0]`: 0 none, 1 LR (a read), 2 SC (a write). The bridge passes the mark to the reservation
  adapter (§3.2) on a side-band in the same clock domain; on TL the LR is a Get and the SC is a Put
  (PutFull of the word) *only if the adapter lets it through* — see §3.2.
* `resp.sc_fail` (1 bit, meaningful for an SC): 1 = the store was not performed. Everything else is
  unchanged: one outstanding request, payload held until the handshake, response no earlier than the next
  cycle, `error` for a bus error or an illegal target.

**Legality per address.** The bridge already refuses illegal TL requests and returns `error`; for `amo`
it checks `supportsArithmetic/Logical` of the target manager (true for DRAM through the new automata and
for MMIO through the peripheral-bus automata; false for the ROM, the error slave and any read-only target)
and returns `error` → the core raises **store/AMO access fault (7)**. An AMO to an address with no
manager at all is the same access fault.

**Core.** Decode the nine AMOs (w/d, all `aq/rl` combinations), `lr.w/d`, `sc.w/d`; misaligned AMO/SC → cause 6
(store/AMO misaligned), **misaligned LR → 4** (*ruled*, A4); Sv39: an AMO needs a page with R **and** W and D set
(page fault 15 either way — the spec treats an AMO as a store for permissions), LR needs R (13; MXR lets it
read an executable page), SC needs W (15); MPRV/SUM/MXR as for loads/stores; an unsupported target: AMO/SC → 7,
**LR → 5** (*ruled*); a faulting AMO/LR/SC issues nothing on the bus, and an SC runs the alignment/translation/
permission/target checks **before** its reservation check — `sc_fail` never masks an exception (*ruled*). The AMO's result register receives the old
value (sign-extended for `.w`); `sc` writes 0 on success, 1 on failure. The core remains in-order,
single-outstanding, cacheless: every memory operation is complete (its response consumed) before the
next issues, so `aq`, `rl`, `aqrl` and `fence` are satisfied by construction — the contract states this
as *the* reason and keeps `fence`/`fence.i` no-ops. `misa.A = 1` only when AMOs and LR/SC are both in.

**Reset.** The reservation is cleared by any reset. An in-flight AMO is a write for the drain bridge's
accounting (R-BOOT): the CPU sees one request and one **final** response — the node's internal Get/Put pair is
completed (or terminated by an error) before that response exists (*ruled* A6); a hold/restart waits for that
final completion, never for the read half alone; a failed SC has no physical write but still exactly one
response, and the reservation is gone.

**Ordering evidence (*ruled* 2).** "Single outstanding" is the mechanism but not the proof: the backend's
log records, per transaction, the A handshake at the node, the Put handshake of an AMO's write half, and the
final D — and the tests check that an earlier accepted write is visible to a later read/AMO from any master
(`GATES.md` 4/6). The node processes DRAM transactions strictly in order (one at a time) to make that
argument simple and inspectable.

## 3.2 LR/SC: the reservation lives at the serialisation point

TileLink has no LR/SC and no conditional Put. A reservation kept *inside the core* and checked before the
SC's Put is issued has a window (the bridge/crossbar latency) in which another master's write can land
between the check and the Put's arrival at the DRAM path — the SC would succeed although the location
changed. The contract therefore places the reservation where the order is decided:

* A small **reservation adapter** (ours, in the teaching SoC Scala) sits on the DRAM path immediately
  before the automata. It tracks one reservation for the CPU: set by the CPU's LR (identified by TL source
  id after the crossbar plus the transaction-bound side-band mark, *ruled* A5: the mark is latched with the
  accepted request and travels with it to its response; no "current CPU output" is consulted), address
  granularity one naturally aligned 8-byte word (A2: `lr.w` reserves its enclosing word; an external write
  overlapping any byte of the word kills it; writes to other words do not), cleared by (a) any Put/AMO from
  **another** source that overlaps the word — including one that lands while the LR's own read response is
  still pending (*ruled* 3: the reservation is a candidate from the LR's acceptance and is not re-validated
  when the D returns), (b) the CPU's own SC, success or failure, to any address (every SC consumes it),
  (c) any CPU store to the word, (d) an LR whose read returns an error (no reservation is left), (e) a
  **trap or reset in the core** (a side-band `resv_clear` pulse, *ruled* 3), (f) a newer LR (replaces it).
  Ordinary fetches and page-table reads do **not** touch it (*ruled* 3/4: a TLB-less core must be able to
  complete a bounded LR/SC loop).
* An SC arrives as a marked Put: if the reservation is valid and matches, the Put passes and `sc_fail = 0`
  is returned with the AccessAck; otherwise the adapter **drops** the Put, answers the CPU with an
  AccessAck carrying `sc_fail = 1` (side-band), and nothing reaches memory. Because the adapter sees every
  competing write in order at the same point, there is no window.
* Forward progress (spec constraint: an LR/SC loop of ≤ 16 instructions must eventually succeed) holds
  for a single hart with these writers: TSI and DMA writes are bounded events, not spinning contenders.

## 3.3 What cannot be guaranteed, and the restricted alternative

* **PS-side accesses.** Nothing in the PL sees the ARM's own DDR traffic. Atomicity against the PS is not
  provided by any scheme; the standing platform rule (Linux confined to the low 256 MB; `fesvr-zynq`
  maps only the adapter page) is the precondition and is recorded as such. If that rule is broken no
  hardware here detects it.
* **Restricted experiment (only if Codex prefers to defer §3.2):** AMOs through the automata as above,
  LR/SC left illegal, `misa.A = 0`. This runs the current xv6 binary (it uses only `amoswap`) but is a
  private ISA subset: the kernel would have to be built with a flag that forbids LR/SC, and any recompiled
  code could break. Listed for ruling, not recommended.

## 3.4 Decisions for Codex (only what changes the implementation)

| # | Question | Recommendation |
|---|---|---|
| A1 | Scope: full A (§3.1 + §3.2, `misa.A = 1`) vs the restricted AMO-only experiment (§3.3) | full A |
| A2 | Reservation granularity | one aligned 8-byte word (the core's transfer unit; `lr.w` reserves its enclosing word) |
| A3 | Where the automata goes | on the DRAM path before `TLToAXI4` in the teaching SoC only (isolated Scala); the peripheral-bus automata stays for MMIO |
| A4 | AMO to a target without atomic support (ROM, error slave, read-only) | bridge `error` → access fault 7; no request reaches the target |
| A5 | Side-band vs in-band marking of LR/SC | side-band (this TL version has no user field); documented as an SoC-internal wire between two of our modules |
| A6 | The R-BOOT drain bridge and AMOs | an AMO counts as one outstanding transaction with a data response; the drain must cover it before the CPU is held — part of the implementation gates |

## 4. The xv6 start-up delta (checked against the actual sources, `REPORT.md` §1)

| Item | Actual software | Teaching core today | Delta |
|---|---|---|---|
| PMP | `start.c`: `w_pmpaddr0(0x3fffffffffffff); w_pmpcfg0(0xf);` | `pmpaddr0/pmpcfg0` illegal (D-6, zero entries; S/U have full access by the spec's rule) | **remove the two lines** in a teaching build (`#ifdef TEACHING_NO_PMP` or a patch), the only source change |
| A/D | the port's `vm.c` already sets `PTE_AD` on every mapping (`mappages`) | the walker never writes A/D | none |
| Timer / SSIP | `timerinit` (mtimecmp = mtime + 25000), `timervec` re-arms from `mtime`, sets `sip.SSIP`; `devintr` clears it | implemented and proven on the real CLINT (su06, boot11) | none (the interval is a rate choice; `mtime` ticks every 100 cycles) |
| Delegation | `medeleg = mideleg = 0xffff` | masks 0xB3FF / 0x222 | none (WARL read-back differs; the software never reads it back) |
| ROM | the teaching ROM (mideleg write replaced by NOP) boots the ELF via TSI/MSIP | works with `mideleg` real | none (D-9) |
| Console | `htif.c`: `tohost/fromhost` in DRAM, polled | TSI reads/writes DRAM through the PL | none |
| Disk | `blkdev.c`: MMIO 0x10015000 + DMA, polling | `BlockDevice` present; DMA is a PL master covered by §3 | none |
| PLIC | `plicinit/plicinithart` write the PLIC | `TLPLIC` present, M context only, no source wired | none (writes land; nothing fires; the drivers poll) |
| `menvcfg`, Sstc, `time` | not used (the port removed them) | illegal | none |
| Atomics | `amoswap.w(.aq)` ×4 | illegal today | §3 |
| Everything else in the trap path | `sret/mret`, S CSRs, `sfence.vma`, ecall levels | CPU-SU / CPU-SV39 | none |

Patch plan for the implementation task: a separate patch file `teaching/0002-no-pmp.patch` (two lines
of `start.c` under a build define) applied to an isolated `xv6-teaching` copy; the Rocket build and the
existing `xv6-sim` copy stay untouched; rollback = do not apply the patch. `fs.img` and the user programs
are unchanged.
