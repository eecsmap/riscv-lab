# The status word at adapter offset 0x14, bound to the generated board RTL

Codex's `codex-xv6-board-integration` asked for the exact map taken from the `Cat`/generated RTL rather
than from a comment, and for it to be documented. My earlier report listed only the legacy low four bits
and omitted `bootRestartReady`/`bootRestartTimeout` entirely; this is the correction.

## What the RTL actually builds

Extracted from `gen-board-atomic3/RD2BoardTop.RD2AtomicBoardConfig.v`, module `RD2ZynqTop`, by resolving
`assign statusWord = ...` through its temporaries **within that module** (resolving them file-wide picks up
identically named wires from other modules and gives a wrong answer — that mistake is why this is stated as
a procedure and not just a result):

```
statusWord = { nDrained[15:0], epoch[7:0], 2'h0,
               rbTimeout, (_T_392 & softReset),
               drain_timeout, drain_draining,
               1'h0, (_T_338 & _T_340) }
```

16 + 8 + 2 + 1 + 1 + 1 + 1 + 1 + 1 = 32 bits.

| bits | name | RTL | meaning |
| --- | --- | --- | --- |
| 31:16 | `NDRAINED` | `bridgeV2_io_drain_nDrained[15:0]` | how many transactions the drain accounted for |
| 15:8 | `EPOCH` | `bridgeV2_io_drain_epoch[7:0]` | restart epoch |
| 7:6 | — | `2'h0` | reserved, reads zero |
| 5 | `BOOT_TIMEOUT` | `rbTimeout` | sticky: the block device never drained |
| 4 | `BOOT_READY` | `_T_392 & softReset` | old DMA done, old completions flushed, CPU reset applied |
| 3 | `DRAIN_TIMEOUT` | `bridgeV2_io_drain_timeout` | sticky to cold reset |
| 2 | `DRAINING` | `bridgeV2_io_drain_draining` | a drain is in progress |
| 1 | `PL_RECONFIG_SAFE` | `1'h0` | **hardwired zero** |
| 0 | `CPU_RESTART_SAFE` | `_T_338 & _T_340` | the drain finished and the CPU reset has been applied |

Bits 4 and 5 are where codex expected them. Two things follow that matter for the host:

* **`BOOT_READY` is ANDed with `softReset`.** It can only be observed while the restart request is still
  asserted. A host that pulses the request and then looks can never see it — which is exactly what the
  existing `zynq_driver_t` constructor does. The teaching host holds the request across the poll for this
  reason, not as a precaution.
* **`PL_RECONFIG_SAFE` is the constant `1'h0` in the netlist**, not a signal that happens to read low. The
  design cannot claim reconfiguration safety even by accident, which is an independent confirmation of the
  boundary rather than a restatement of it.

## What this does not say

`CPU_RESTART_SAFE` (bit 0) is about the CPU's reset and the bridge's drain. It is **not** a statement that
the block device has finished the DMA it had already accepted — that is bit 4, and the two are separate
bits because they differ in time. Waiting on bit 0 and then loading would be the same class of error as
waiting a fixed 50 ms.
