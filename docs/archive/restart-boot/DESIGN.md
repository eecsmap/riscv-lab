# R-BOOT — a controlled program restart that does not leak block-device work across the boundary

The fault being fixed is real and reproduced (`reset-drain/rd2/rd2-d/FINDING-bdev-stale-completion.md`): a
CPU restart while a block-device request is in flight leaves that request's *completion* queued in the
controller, the restarted program consumes it as its own (tags restart from 0, so they even match), and
reads a buffer its own DMA has not finished filling. Two things are wrong at once: old work is still
changing memory after the new program has been loaded, and old bookkeeping is handed to new software.

## Reset domains (unchanged from RD2)

Everything that owes a beat stays in the cold domain: the fabric, `TLToAXI4`, the CPU bridge, the TSI
adapter, the block-device trackers and their DMA. The CPU is the soft domain, via the RD1 bridge's
`cpuResetHold`; the CLINT copy's `msip` is cleared once at `RESET_APPLY`. Nothing here adds a domain.

## The restart FSM (teaching SoC only, `RD2ZynqTopModule`)

```
IDLE ──softReset──▶ DRAIN ──(bridge drained ∧ apply entered ∧ bdev trackers idle ∧ no bdev TL work)──▶ FLUSH ──(queues empty)──▶ READY ──(softReset low)──▶ IDLE
                      │
                      └── cycles ≥ rbootTimeout ──▶ FAILED (terminal; TIMEOUT sticky; READY never; cold reset only)
```

* **Hold.** From the cycle the soft reset is sampled, `bdevHold` is high: the router accepts no new request
  from the frontend. Nothing already presented is withdrawn — a frontend read that is waiting for a tag
  simply keeps waiting (its `ready` is low), and every tracker that has accepted a request runs to its own
  `s_complete`. The CPU is held by the bridge exactly as in RD2.
* **Drain.** Old DMA finishes for real: the host keeps servicing `bdev.req/data/resp` (it is never frozen),
  the trackers keep writing/reading memory until each is idle, and the watcher on the controller's master
  port confirms no TL request is pending or outstanding. The CPU bridge's own drain runs in parallel.
* **Flush.** Only once every tracker is idle: the router's completion queue and allocation queue are emptied.
  Each dropped completion is counted (`bdevDiscarded`) and logged as its own event; it is never delivered to
  the restarted program. The frontend's `addr/offset/len/write` registers are software state the next
  program rewrites before use, so they are left alone and stated as such.
* **Ready.** `BOOT_RESTART_READY` is a level: it means old DMA can no longer change memory, old completions
  are gone, the CPU bridge has drained and the CPU reset has been applied. It is *not* `CPU_RESTART_SAFE`,
  which keeps its narrow meaning (the CPU bridge alone), and it is *not* `PL_RECONFIG_SAFE`, which stays 0.
* **Timeout is terminal.** A device that has not drained by `rbootTimeout` cycles trips
  `BOOT_RESTART_TIMEOUT` (sticky) and the FSM enters `FAILED`, which only a cold reset leaves. In `FAILED`
  the hold stays on (no new submissions), nothing is flushed or cleared, and READY is never asserted — a
  device that answers *late* may finish its own handshakes (recorded as `LATE_DRAIN`), but that changes
  nothing: readiness after a reported failure is not manufactured. The first version left the FSM in DRAIN
  with the completion transition still armed, so a late answer would have produced READY and a release.
  **Precedence:** completion observed at or before the deadline cycle wins; after it, failure is latched.
  Recovery is a cold platform reset, stated rather than automated; a PL reload with live PS transactions
  is not recommended.

## Host order (what `fesvr` / the PS must do)

1. write `0x10 = 1` (hold);
2. poll `0x14` until **bit 4 `BOOT_RESTART_READY`** — not bit 0 — or until bit 5 `BOOT_RESTART_TIMEOUT`,
   in which case stop, report, and treat the failure as latched: a bit 4 seen afterwards must not release
   or reload (the simulation host enters `R_FAILED` and ignores it);
3. write `0x10 = 0` (release);
4. reload the program (`.data` included), clear `tohost`/`fromhost`;
5. write `msip`.

Loading over TSI while the CPU is held keeps working: the TSI adapter is untouched by any of this.

## Status word (`0x14`)

| bit | name | meaning |
|---|---|---|
| 0 | `CPU_RESTART_SAFE` | unchanged, narrow: the CPU bridge alone |
| 1 | `PL_RECONFIG_SAFE` | 0 |
| 2 | `DRAINING` | unchanged |
| 3 | `TIMEOUT` | the bridge's drain timeout, unchanged |
| **4** | **`BOOT_RESTART_READY`** | the whole sequence above has completed and the reset is still held |
| **5** | **`BOOT_RESTART_TIMEOUT`** | sticky: the block device never drained |
| 15:8 / 31:16 | epoch / nDrained | unchanged |

## What is not done here

No arbitrary-time hot reconfiguration, no global multi-master quiesce, no epoch tagging on the frontend.
The frontend and tracker classes are testchipip's; only the router and the controller *wiring* are copied
(`RD2BlockDevice.scala`) to add the hold/flush ports. Default Rocket configurations do not instantiate any
of it.
