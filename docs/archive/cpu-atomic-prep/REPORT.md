# CPU-ATOMIC-PREP — the atomic path and the xv6 start-up delta: audit and contract

Claude, 2026-09-18. Delegation `codex-cpu-atomic-platform-contract` (acked). Read-only: nothing in the
active CPU, bridge, SoC Scala, boot software, Rocket configuration or SD/PS chain was changed; nothing was
synthesised or run on the board. Deliverables: this report (§1 software audit, §2 platform audit),
`CONTRACT.md` (the one preferred scheme with its decisions, and the xv6 start-up delta), `GATES.md` (the
frozen acceptance gates for the implementation task), `scripts/audit-xv6.sh` and
`scripts/audit-platform.sh` (re-runnable; their output is `evidence/xv6-atomics.txt` and `evidence/platform-arbitration.txt`, both hashed), `HASHES.txt`. The old `m0/CONTRACT.md`
now carries a note that its "CPU-internal read-modify-write" suggestion was rejected (m2-prep D5,
`cpu-su-prep/CODEX_DECISIONS.md` D-7) and points here.

## 1. What the software actually needs (`evidence/xv6-atomics.txt`, `scripts/audit-xv6.sh`)

Source: the xv6 kernel built for this platform (`teaching-cpu-work/xv6-sim`, base commit `35b0884`, the
xv6-on-rocket port patch applied, GCC 13.2.0, `-march=rv64gc -mcmodel=medany`), its `kernel.asm`, and the
twenty user ELFs (objdump now).

| Class | Kernel | User (20 ELFs) | Origin | Consequence for the ISA |
|---|---|---|---|---|
| `amoswap.w` | 3 (`release`, `forkret`, `main`) | 0 | `__atomic_store_n(&lk->locked, 0, __ATOMIC_RELEASE)` and the two initialisation stores GCC lowers to a swap | needed |
| `amoswap.w.aq` | 1 (`acquire`) | 0 | `__atomic_exchange_n(&lk->locked, 1, __ATOMIC_ACQUIRE)` | needed, with acquire ordering |
| other AMOs (`amoadd/xor/and/or/min/max/minu/maxu`, `.d`) | 0 | 0 | — | **not used by this binary**; but `-march=rv64gc` lets any recompilation emit them |
| `lr.w/d`, `sc.w/d` | 0 | 0 | — | **not used by this binary**; same caveat |
| `fence` | 7 (`release` `fence iorw,ow` ×1 as the release barrier, `forkret`/`main` `fence` + `fence iorw,ow`, `blkdev_rw` ×2) | 0 | `__sync_synchronize` and the port's MMIO ordering | already a legal no-op on the single-port core (§2.4) |
| `fence.i` | 1 (`userret`) | 0 | — | already a no-op (no cache) |
| `sfence.vma` | 6 | 0 | — | implemented (CPU-SV39) |

"This binary does not use it" and "the ISA does not implement it" are different statements: with the A
extension announced (`misa.A = 1`) the compiler is entitled to emit every AMO and LR/SC for `-march=rv64gc`
code, and `__atomic_exchange_n` cannot be built *without* A in a freestanding kernel (it becomes a
libatomic call). So the implementation is either the whole of A (nine AMOs × w/d, LR/SC) — or A stays 0
and this xv6 cannot be built for the core. A partial "amoswap only" build would be a private ISA and is
listed only as a restricted experiment for Codex to rule on (`CONTRACT.md` §A1).

## 2. Where memory traffic is arbitrated (`evidence/platform-arbitration.txt`, `scripts/audit-platform.sh`)

| Node | Evidence | Status |
|---|---|---|
| Teaching CPU → `ReqRespToTL`/`RD1Bridge` (one source id, Get/PutPartial only; legality per address, error otherwise) | `ReqRespToTL.scala:32,62-68`, `RD1Bridge.scala:61,136-142`, `PHYSICAL_PORT_V1.md` line 11 | **proven**: no atomic TL operation is ever issued today |
| The three PL masters that reach DRAM — the CPU bridge, the TSI `SerialAdapter`, the `BlockDevice` DMA trackers — all attach with `sbus.fromPort` | `TeachingCpuSoc.scala:45-46`, `RD2Soc.scala:90`, `SerialAdapter.scala:184`, `BlockDevice.scala:439` | **proven**: one system-bus crossbar (`TLXbar` in both generated RTLs) is the first point where they meet |
| sbus → `TLBroadcast` hub → `MemoryBus` → `TLToAXI4` → AXI4 HP0 → PS DDR | generated RTL module list (both configurations), `Broadcast.scala:43-44`, `ToAXI4.scala:60-68` | **proven**: the DRAM manager advertises Get/PutFull/PutPartial only; the hub passes that through; **no atomic support exists on the DRAM path** |
| The one `TLAtomicAutomata` in the generated RTL | `PeripheryBus.scala:97`; instantiated by `PeripheryBus` (`SimpleLazyModule_7`) in both RTLs | **proven**: it serves the peripheral bus (MMIO devices), not DRAM |
| `TLAtomicAutomata`'s rule | `AtomicAutomata.scala:100-102` | while an AMO's read–modify–write is in flight, every other A-channel request to the same manager fifo is held: that is a real serialisation point for *everything that passes through the node* |
| Rocket ran xv6 on this board without any of this | Rocket executes AMOs in its coherent D$; TL atomics never reach memory | explains the baseline; not available to a cacheless single-port core |
| PS side: `fesvr-zynq` | `zynq_driver.cc:8,39-43`: maps **one page** of adapter registers at 0x43C00000 via `/dev/mem`; ELF load, `tohost/fromhost`, block-device service all go through the TSI/BlockDevice FIFOs, i.e. through PL masters | **proven** for the host program |
| PS side: the ARM Linux itself | Rocket's `0x8000_0000+` is Zynq DDR `0x1000_0000+`; Linux is limited to the low 256 MB by the device tree (`reg = <0x0 0x10000000>`), `bootm_size`, `cma` (README "memory split") | **software/platform rule, not hardware**: nothing in the PL can serialise or even observe a PS access to DDR; the PS simply must not touch that window. This is already the standing precondition for running anything on the core |
| RD2 additions on the CPU path (`RD2Watch`, `RD2Throttle`, the drain bridge) | `RD2Soc.scala:90` | on the CPU's own port, before the crossbar: they see CPU traffic only |

Conclusion: the complete set of agents that can write xv6's memory through hardware the PL can see is
{CPU, TSI, block-device DMA}; they share one crossbar and one DRAM path; that path has no atomic operation
today; a node inserted on that path (after the crossbar, before the AXI4 port) sees all three and can
serialise them. The PS's own accesses are outside any hardware guarantee and must stay outside the window
by configuration — stated as a platform precondition, never as atomicity.

## 3. The recommended scheme, the decisions and the xv6 delta

See `CONTRACT.md`. In one sentence: execute AMOs in a `TLAtomicAutomata` placed on the DRAM path of the
teaching SoC (so that they are serialised against the TSI and the DMA as well as the CPU), decide LR/SC at
the same point with a reservation that any other master's write kills, extend the physical request with an
`amo` field and an `lrsc` mark, keep the core single-outstanding so `aq/rl`/fence ordering holds by
construction, and set `misa.A` only when all of that is in. The xv6 delta is the two PMP lines in
`start.c`, applied as an isolated teaching-configuration patch, nothing else (§4 of `CONTRACT.md`).

## 4. Not claimed

No RTL or software was changed; no test was run on the core in this task (the gates in `GATES.md` are for
the implementation task). The audit reads the binaries and sources that exist now; a rebuilt xv6 changes
the counts but not the conclusion.
