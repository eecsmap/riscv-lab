# Why the first board test hung, what was wrong, and what fixed it

Sessions 2–5 on 2026-09-16, one board, one console, every byte logged. Numbers below are counts of runs.

## 1. The symptom

A program that had just passed would, on the next `fesvr-zynq` invocation, produce **nothing at all** —
no marker, no failure exit — and fesvr would sit polling until interrupted. The first run after a fresh PL
configuration always worked (3 of 3 in session 3, and every reload-then-run since). Any run that followed
a *running* CPU hung roughly half the time, whichever program it was.

Reconfiguring the PL while the teaching CPU was running made it worse: from that moment **every** design
hung on its first memory access, the validated Rocket bitstream included, until the board was power
cycled (session 3, 10:19–10:28Z).

## 2. The mechanism, read out of the RTL and confirmed on the board

The teaching CPU has no cache. After `htif_exit` it spins in `2: j 2b`, and every iteration is an
instruction fetch on the PS HP memory port, so a fetch is in flight almost all the time.

fesvr resets the target with two back-to-back writes, `SYSTEM_RESET=1` then `0`. The subsystem restarts
in a few cycles; the DDR read that was in flight does not care, and its response comes back a few hundred
nanoseconds later. `AXI4UserYanker` passes it through (`in.r <> out.r`), `TLToAXI4` turns it into a
TileLink D beat (`out.r.ready := in.d.ready`) routed to the client that asked: my bridge, `ReqRespToTL`,
now sitting in `sIdle` with `tl.d.ready = 0`. The orphan parks in the converter's single D slot, and
because `out.b.ready := in.d.ready && !r_wins`, **every other client's responses are blocked too** — the
serial adapter's first ELF-load write never gets its B, and the next program never starts.

If the PL is *reconfigured* with a read in flight, the orphan sits in the PS AFI instead and is handed to
whatever design comes next. Rocket never trips this because its spin loop is served from the I-cache.

## 3. The fix, in two parts

**Design** (`ReqRespToTL.scala`, proposal `claude-m4c-orphan-response-fix`): the bridge accepts and
discards a D beat that arrives while it has nothing outstanding. Legal TileLink; no CPU, interface or reset
semantics change; `audit/orphanfix-rtl-diff.txt` shows exactly one of 120 board-RTL modules differs.
Regressed: M3 gates `fails=0` with event streams identical to the pre-fix round on every deterministic
run; the bridge's own 13 cases `fails=0`; attempt-2 bitstream closes at WNS +3.269 ns.

**Procedure** (runbook §8): before each `fesvr-zynq` run, and before any `/dev/xdevcfg` write, assert
`SYSTEM_RESET` through the adapter register and hold it ≥ 50 ms. With the bridge fix the in-flight response
is then consumed while the CPU is held, and nothing is in flight when fesvr releases it. Without the fix,
holding reset did not help (session 3: 4 of 8 held-reset runs still hung), because the parked beat stayed
parked.

## 4. The evidence that it is fixed (session 4, attempt-2 bitstream)

| series | result | hangs |
|---|---|---|
| `boot02_clint` ×6 back to back, fesvr's own reset only, right after a PL load | PPPPPP | 0/6 |
| `boot04_badaddr` ×10, no hold | PHHHHPHHPH | 7/10 |
| (`boot02`, `boot04`) ×5, no hold | HPPPPPHHHH | 5/10 |
| verdict order ×3, no hold | PHHPHHHHPHHP | 8/12 |
| **verdict order ×3, hold before each run** | PPPPPPPPPPPP | **0/12** |
| **`boot04_badaddr` ×10, hold before each run** | PPPPPPPPPP | **0/10** |

Once a run hangs and is interrupted, the following runs cascade (the `HHHH` groups) until a hold clears
the state. The hold series were run *after* the no-hold series on the same loaded PL, so they started from
the dirtiest state and still passed every time.

fesvr's own two-write pulse is therefore still a race on this design even with the bridge fix: the
orphan can arrive after the release and collide with the CPU's first fetches. The hold closes that race
from outside. A self-contained closure would be a reset stretch inside the SoC — hold the CPU (only) in
reset for a few thousand cycles after `sys_reset` releases, so any in-flight response returns while the
bridge is idle. That is proposed as the next design step, not done here.

## 5. `boot04_badaddr` specifically

Its verdict run in session 4 hung, and for a while that looked like a second defect. It was not:
`diag_badaddr` — the same accesses with markers between them — passed on hardware with the expected
faults (`ld 0x50000000` → cause 5, tval 0x50000000; `sd` → cause 7; `ld 0x3000` on the error device →
cause 5; DRAM read-back 0x1234). The bridge rejects the unmapped address locally, exactly as in simulation
(sim log: REQ, then TRAP four cycles later, no bus response). `boot04` simply drew the short straw in the
race above; with the hold it passes 10 of 10.

## 6. Two mistakes of mine along the way, recorded

* `console.py` kept a marker-matching race that `m4c.py` had already been cured of; it produced a false
  "HASH MISMATCH" in session 4 (the image on the board was correct, `6f5dd108…`). Fixed.
* Reconfiguring the PL under a running teaching CPU (10:19:39Z) is what wedged the PS. The runbook now
  forbids exactly that.
