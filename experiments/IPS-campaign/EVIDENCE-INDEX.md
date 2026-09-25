# Evidence index

Every hash here is computed from the file it names. Simulation numbers are **single-run**: the
design is deterministic and the harness carries no randomised initialisation, so a repeat produces
the same cycle counts, but one run is one run and they are marked preliminary accordingly.

## Branches and CPU RTL

| branch | commit | `tcpu_core.v` | modules |
| --- | --- | --- | ---: |
| `ips-baseline` | `66a31223d3ca` | `09449b24e64440f7` | 6 |
| `ips-fetch32` | `60421b5b4c32` | `de6be6cb3b795d38` | 6 |
| `ips-tlb` | `25b8e3fabe69` | `ed5739de2aaa9e42` | 9 |
| `ips-cache` | `674a9723abcc` | `96586a6f2261ae2c` | 12 |

## Bitstreams

| stage | WNS (ns) | WHS (ns) | setup/hold fail | LUT | FF | crit | bitstream |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `baseline` | 0.779 | 0.024 | 0/0 | 13,777 | 5,884 | 0 | `423f7d227a4ae0a5` |
| `fetch32` | 0.733 | 0.020 | 0/0 | 13,841 | 5,880 | 0 | `0cf25aee6b9ed564` |
| `tlb` | 0.273 | 0.037 | 0/0 | 14,092 | 6,685 | 0 | `5add000a9c6c5e86` |
| `cache` | 0.424 | 0.036 | 0/0 | 14,554 | 7,011 | 0 | `e546c0ddb1eda90e` |
| ~~`cache` (superseded)~~ | ~~0.354~~ | | | | | | ~~`d926c09abe3a370c`~~ |

The first cache bitstream is **superseded**: `tcpu_ifill` gained discard-on-invalidate after
it was built. It is kept, renamed, and must not be programmed.

## Tests, and the mutant each one is answerable to

| suite | checks | mutants caught |
| --- | ---: | --- |
| `run-tlb-tb.sh` | 31 | A/D dropped; SUM permitting a fetch; superpage comparing the full VPN; flush not clearing; replacement always writing entry 0 |
| `run-icache-tb.sh` | 21 | invalidate doing nothing; tag not compared; cacheability defaulting to yes; CLINT cached |
| `run-ifill-tb.sh` | 28 | line valid on a failed refill; MMIO cached; data cached; fence.i not reaching the cache; **discard-on-invalidate removed** |
| `run-xlate-amo-tb.sh` | 13 | canonical check removed (fails 5, including both AMO cases) |
| `permcheck_equiv_tb` | 4096 inputs | any change to the extracted permission check |
| `tlb01_sfence` | 4 cases | hit skipping the permission check → case B; flush doing nothing → case A; satp value-watching → case D |
| `tlb02_canonical` | load/store/fetch × 2 halves × 3 page sizes | canonical check removed |
| `cache01_smc` | self-modifying code | fence.i disconnected from the cache |

## SoC regressions

| run | cores | binaries | result |
| --- | --- | ---: | --- |
| stage 1 | baseline, fetch32 | 11 | `fails=0`, 12 metric rows |
| stage 2 | baseline, fetch32, tlb, tlboff | 13 | `fails=0`, 48 rows |
| stage 3 | tlb, cache, cacheoff | 13 | `fails=0`, 36 rows |
| final | baseline, fetch32, tlb, cache | 14 | `fails=0`, 48 rows |

## xv6 with the frozen `b0apps` profile

| core | result |
| --- | --- |
| `fetch32` | **complete** — all three checksums matching the board, `BOARD_RUN stages=6 failed=0`, checker `fails=0`, 3,244,693,508 cycles |
| `cache` | **running** (`ips-xv6-cache-v2`, 6 h bound). An earlier launch used an 8 h bound without amendment and was stopped; a second was stopped because its RTL was superseded by the discard fix. Neither is claimed. |
| `tlb` | **not run** |
| `baseline` | **not run** in this campaign; the accepted 2026-09-23 simulator record exists but its simulator binary differs, which is recorded as the confound it is |

## Not established

* nothing is BOARD-VERIFIED or PERFORMANCE-MEASURED; no bitstream has been programmed
* the hardware IPS comparison needs board samples from all four variants and has none
* full-core atomic regressions: `ext03_a` does not complete in this SoC configuration **even on
  the baseline**, so the applicable atomic coverage is `ext01_m`/`ext02_c`/`ext04_sv39` at the core
  level plus AMO canonicality at the xlate boundary. `ext03_a` itself is not applicable here.
* sample counts are **1** per workload/config; the design is deterministic but one run is one run
