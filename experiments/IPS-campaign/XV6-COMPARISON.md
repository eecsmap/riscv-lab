# xv6 with the frozen `b0apps` profile, per core

Driven through the **production** runner, same kernel `6ad5c233…` and same pristine disk `6bdd8148…`
as the accepted 2026-09-23 simulator record, hashes checked rather than assumed, with a fresh copy of
the disk for every sample.

| core | target cycles | vs fetch32 | vs previous stage | checksums | checker |
| --- | ---: | ---: | ---: | --- | --- |
| `fetch32` | 3,244,693,508 | **1.000x** | — | all three match the board | `fails=0` |
| `tlb` | 728,106,109 | **4.456x** | 4.456x | all three match the board | `fails=0` |
| `cache` | 463,881,498 | **6.995x** | 1.570x | all three match the board | `fails=0` |

`baseline` was not run in this campaign, so the column is **against fetch32**, not against baseline.

These are **target cycles**, which is the result. The simulator wall times differ by far more —
18,481 s for fetch32 against 2,917 s for cache — and measure the simulator, not the CPU.

The TLB's 4.456x on a real application is much larger than its microbenchmark gains, because xv6 runs
under Sv39 with 4 KiB pages: on fetch32 every fetch and every data access walked three levels.

One sample each. The design is deterministic and the harness carries no randomised initialisation,
but one run is one run.
