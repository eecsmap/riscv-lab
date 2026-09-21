# M2-3 event evidence: ordered events instead of end-of-run totals

Delegation: `codex-m2-3-event-evidence-fixes`, after the previous submission was returned on three specific
gaps. Accepted runs: `run-a` (the event evidence) and `gate` (the full M2-3 gate re-run under these sources).
Independent re-derivation: `src/check-m2-3-events.py` and `src/check-m2-3.py`.
`../m2-3` and `../m2-3-fixes` are untouched.

## The three things that were wrong

### 1. The duplicate-store fault only lied to the counter

`DUP_STORE` did one thing: make `watch_writes` add 2 instead of 1. There was no second write. So exit 21
showed that *a wrong count can be detected*, which is circular — the check and the fault were the same
quantity. The claim that the model applied the write twice was not true.

There is now one write-apply path. Every write side effect goes through it, and the counter increments by one
per event, unconditionally: the apply path does not know that any fault switch exists, which is the only way
it can be evidence about one. `DUP_STORE` queues a genuine replay of one selected write and applies it again
a few cycles later. The two events are recorded with their own cycles:

    APPLY events=52 first=184 second=188 data1=0x0 data2=0x0

Two applications, four cycles apart, same value. The checker requires the two cycles to differ, so a future
version cannot go back to counting one edge twice.

What the fault does *not* change: the final memory contents, the program's verdict (`TOHOST code=0`), the
interrupt count, and the bus totals, which are byte-for-byte identical to the clean run
(`WATCH req=102 wreq=51 resp=102 writes=52` against `.../writes=51`). Only the apply-event count sees it.

### 2. The store matrix was injecting into the load

`watch_hit` matched on address alone, and the first data access after arming is the load. All three "store"
runs fired at `watched_load`, so the table claiming a store's request and response phases was wrong.

Injection is now limited by the instruction's PC, the access direction and the address. The response phase
uses the metadata latched at the handshake rather than the request fields, which no longer describe the
outstanding transaction by then. The fire record carries the direction and the address, and they are gated:

| run | fire cycle | pc | state | in flight |
|---|---|---|---|---|
| `store-pw3` | 266 | `watched_store` | MEM_WAIT | a write at `watch_slot` |
| `store-pw4` | 268 | `watched_store` | MEM_WAIT | a write at `watch_slot` |

The checker fails the run if the fire PC is `watched_load`, which is the specific defect being ruled out.

### 3. Retirement was an end-of-run total, and the boundary case checked the wrong instruction

The old `FIRE TARGET` line used `pc_count[fire_pc]` at the end of the run. At the architectural boundary the
PC has already advanced, so that line was reporting on `after_target` — the instruction executed *after* the
interrupt returned — and calling it evidence about `target_insn`.

Two separate inputs now, because they answer two separate questions: `+inject-pc` says where to inject,
`+target-pc` names the instruction the ordered chain is about. The chain records the target's commit cycle,
the first interrupt's cycle, the target's retirement count **sampled at the instant of the interrupt**, and
the architectural register the target wrote, read back through the debug port at that same instant.

| point | fire cycle | pc | state | target committed | interrupt | retired at IRQ |
|---|---|---|---|---|---|---|
| fetch request awaiting ready | 341 | `target_insn` | IF_WAIT | 350 | 353 | 1 |
| fetch response outstanding | 343 | `target_insn` | IF_WAIT | 350 | 353 | 1 |
| data request awaiting ready | 346 | `target_insn` | MEM_WAIT | 350 | 353 | 1 |
| data response outstanding | 348 | `target_insn` | MEM_WAIT | 350 | 353 | 1 |
| writeback, updates scheduled | 350 | `target_insn` | WB | 350 | 353 | 1 |
| architectural boundary, landing | 351 | `after_target` | ARCH | 350 | 353 | 1 |

In every row `x18` already reads 0x1122334455667788 at the interrupt, so the target's architectural result
had landed before the interrupt was taken — not inferred from a later total.

## The gates have negatives

| negative | exit | what rejects it |
|---|---|---|
| a real duplicated write side effect | 25 | the apply-event count, and nothing else could |
| the chain pointed at the wrong instruction, injection unchanged | 23 | the chain: that instruction retires at 917, after the interrupt |
| accepting an interrupt during a committed access | 5 | the protocol monitor, and the chain reports the target never retired |

## A bug found in the harness while doing this

`-G` values are parsed as unsized Verilog literals, so a 32-bit address with the top bit set was
sign-extended into a 64-bit parameter and never matched the PC. It made a targeted injection silently fire
zero times — a gate that looks like it is testing something and is testing nothing. The watched address and
the injection PC are now run-time inputs, where no such rule applies, which also means one simulator binary
serves any target instead of one build per address.

## Regression

The full M2-3 gate was re-run under these sources into `gate/`: `M2_3_DONE fails=0`, and `check-m2-3.py`
reports 0 findings, including the cross-milestone check that retirement counts still match the accepted M2-2
evidence. The six-point enabled-injection matrix from the previous round is re-run here with the corrected
chain, so nothing from that round is lost.

`check-m2-3-events.py` reports 0 findings on `run-a` and 97 on `../m2-3-fixes/run-a`, where the apply-event
records, the direction-gated fires and the symbol-keyed chain do not exist.

## Corrected claims

The previous report's store table described request and response phases of `watched_store`; they were the
load's. Its statement that the model applied the write twice was false — it incremented a counter twice.
Both are superseded here rather than edited out of the old document.

## Evidence

    run-a/   the event evidence: fire records, chains, apply events, logs, exit codes, ELFs, symbols, hashes
    gate/    the full M2-3 gate re-run under the same sources
    src/     sources, tests and all four scripts, with SRC.sha256

Identity chain: `src/SRC.sha256` -> `run-a/source.sha256` and `gate/source.sha256`, all three verified equal
-> `sim.sha256` -> `elf.sha256`. Tool versions in `tools.txt`.

    teaching-cpu-work/cpu/run-m2-3-events.sh <newdir>
    teaching-cpu-work/cpu/check-m2-3-events.py <newdir>

## What this still does not show

- The interrupt controller and the watched-address counters are harness models. Nothing here tests CLINT or
  PLIC wiring, and no claim is made about the original BootROM or `hello`.
- No asynchronous input, no M or C extension, no S/U, no MMU, no PMP, no delegation.
- The ELF is still pre-loaded through a backdoor port; not connected to the M1 bridge or the SoC; nothing
  has been near a board.
