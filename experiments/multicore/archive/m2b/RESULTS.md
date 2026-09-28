# MC-M2b results

Generated 2026-09-27T04:32:58Z. Sources: `runs/*/<run>/verdict.txt`, `<run>.check`, group logs.

## drain2

| run | verdict (run-dual.sh) | per-hart (harness) | judge |
|---|---|---|---|
| dual06-drain | RUN exit=0 wall=23s Completed after 239807 cycles M2B-DRAIN-OK epoch=0x0000000000000001 survived=0x00000000000 | retired0=33873 traps0=2 maxawait0=11 awaits0=974 epoch0=2 retired1=34834 traps1=2 maxawait1=10 awaits1=844 epoch1=2 | PASS |

## smoke3

| run | verdict (run-dual.sh) | per-hart (harness) | judge |
|---|---|---|---|
| dual01_boot | RUN exit=0 wall=2s Completed after 14926 cycles M2B-BOOT-OK sp1=0x0000000080003000 | retired0=1650 traps0=1 maxawait0=10 awaits0=145 epoch0=1 retired1=2078 traps1=1 maxawait1=11 awaits1=86 epoch1=1 | PASS |
| dual02_clint | RUN exit=0 wall=30s Completed after 314002 cycles M2B-CLINT-OK mtip0=0x0000000000000005 0x0000000000000005 0x0 | retired0=35890 traps0=6 maxawait0=9 awaits0=7178 epoch0=1 retired1=34638 traps1=7 maxawait1=11 awaits1=7598 epoch1=1 | FAIL |
| dual04_pbus | RUN exit=0 wall=8s Completed after 81591 cycles M2B-PBUS-OK senable_rb=0x0000000000000002 0x0000000000000000 s | retired0=8444 traps0=1 maxawait0=6 awaits0=376 epoch0=1 retired1=9667 traps1=1 maxawait1=10 awaits1=167 epoch1=1 | FAIL |
| dual05_fencei | RUN exit=0 wall=2s Completed after 21312 cycles M2B-FENCEI-OK nofence=0x0000000000000001 fence=0x0000000000000 | retired0=2490 traps0=1 maxawait0=6 awaits0=181 epoch0=1 retired1=3244 traps1=1 maxawait1=9 awaits1=60 epoch1=1 | PASS |

```
INFO dual05: without fence.i hart 1 executed the OLD code at X (observed on this implementation, not an ISA claim); new code committed after fence.i: True
```

## suite

| run | verdict (run-dual.sh) | per-hart (harness) | judge |
|---|---|---|---|
| dual03-s1 | RUN exit=0 wall=36s Completed after 4527347 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=345270 traps0=2 maxawait0=22 awaits0=803864 epoch0=1 retired1=356392 traps1=2 maxawait1=22 awaits1=707247 epoch | PASS |
| dual03-s10 | RUN exit=0 wall=36s Completed after 4544826 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=370296 traps0=2 maxawait0=19 awaits0=410920 epoch0=1 retired1=375405 traps1=2 maxawait1=19 awaits1=396008 epoch | PASS |
| dual03-s2 | RUN exit=0 wall=35s Completed after 4492522 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=353928 traps0=2 maxawait0=18 awaits0=524390 epoch0=1 retired1=359020 traps1=2 maxawait1=20 awaits1=510168 epoch | PASS |
| dual03-s3 | RUN exit=0 wall=44s Completed after 5528143 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=389821 traps0=2 maxawait0=23 awaits0=1043924 epoch0=1 retired1=396194 traps1=2 maxawait1=23 awaits1=1008876 epo | PASS |
| dual03-s4 | RUN exit=0 wall=35s Completed after 4039453 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=337678 traps0=2 maxawait0=18 awaits0=565807 epoch0=1 retired1=339636 traps1=2 maxawait1=20 awaits1=580159 epoch | PASS |
| dual03-s5 | RUN exit=0 wall=33s Completed after 4183101 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=348903 traps0=2 maxawait0=19 awaits0=425100 epoch0=1 retired1=359852 traps1=2 maxawait1=19 awaits1=328128 epoch | PASS |
| dual03-s6 | RUN exit=0 wall=37s Completed after 5084496 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=380477 traps0=2 maxawait0=22 awaits0=849905 epoch0=1 retired1=387097 traps1=2 maxawait1=22 awaits1=815256 epoch | PASS |
| dual03-s7 | RUN exit=0 wall=38s Completed after 5072458 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=388077 traps0=2 maxawait0=20 awaits0=605460 epoch0=1 retired1=394975 traps1=2 maxawait1=20 awaits1=567445 epoch | PASS |
| dual03-s8 | RUN exit=0 wall=34s Completed after 4341935 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=338224 traps0=2 maxawait0=22 awaits0=854526 epoch0=1 retired1=345020 traps1=2 maxawait1=21 awaits1=808566 epoch | PASS |
| dual03-s9 | RUN exit=0 wall=35s Completed after 4386312 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=341543 traps0=2 maxawait0=20 awaits0=713591 epoch0=1 retired1=356426 traps1=2 maxawait1=21 awaits1=565796 epoch | PASS |
| dual03-trace | RUN exit=0 wall=444s Completed after 3778622 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e2 | retired0=338913 traps0=2 maxawait0=17 awaits0=300309 epoch0=1 retired1=341429 traps1=2 maxawait1=18 awaits1=304765 epoch | PASS |
| dual06-drain | RUN exit=0 wall=30s Completed after 273521 cycles M2B-DRAIN-OK amo=0x000000000000016a | retired0=37137 traps0=1 maxawait0=9 awaits0=1321 epoch0=2 retired1=37564 traps1=1 maxawait1=13 awaits1=1242 epoch1=2 | FAIL |
| dual07-long | RUN exit=0 wall=68s Completed after 8737743 cycles M2B-LONG-OK iter=0x00000000000186a0 0x00000000000186a0 sum= | retired0=1208492 traps0=1 maxawait0=11 awaits0=39574 epoch0=1 retired1=1209568 traps1=1 maxawait1=9 awaits1=39424 epoch1 | PASS |
| neg01_nohart1 | RUN exit=2 wall=46s *** FAILED *** (no host result, seed 1789976048) after 400000 cycles  | retired0=47641 traps0=1 maxawait0=6 awaits0=1986 epoch0=1 retired1=66391 traps1=1 maxawait1=6 awaits1=13 epoch1=1 | FAIL |
| neg02_wronghart | RUN exit=99 wall=1s *** FAILED *** (tohost = 99) M2B-TRAP-FAIL unexpected trap on hart 0 | retired0=1679 traps0=2 maxawait0=10 awaits0=168 epoch0=1 retired1=2197 traps1=2 maxawait1=11 awaits1=69 epoch1=1 | FAIL |
| neg03_wrongcount | RUN exit=0 wall=30s Completed after 3781873 cycles M2B-LOCK-OK lock=0x0000000000004e1f lrsc=0x0000000000004e20 | retired0=338944 traps0=2 maxawait0=18 awaits0=303274 epoch0=1 retired1=341455 traps1=2 maxawait1=18 awaits1=307760 epoch | FAIL |
| neg04_early | RUN exit=0 wall=75s Completed after 8737395 cycles M2B-LONG-OK iter=0x00000000000186a0 0x00000000000186a0 sum= | retired0=1208450 traps0=1 maxawait0=11 awaits0=39593 epoch0=1 retired1=1209520 traps1=1 maxawait1=9 awaits1=39432 epoch1 | PASS |

```
      INFO dual07: retired [1208492, 1209568], maxAWait [11, 9], aWaits [39574, 39424]
      INFO drain: 6567 answered DRAM writes, 10897 AXI write bursts (>=, the host load writes are included)
  neg01_nohart1              rejected: FAIL: simulator exit 2, expected 0
  neg02_wronghart            rejected: FAIL: simulator exit 99, expected 0
  neg03_wrongcount           rejected: FAIL: lock-protected counter = 19999, expected 20000
  neg04_early                ACCEPTED (must be rejected)
M2B_SUITE_DONE group=all runs=17 bad=2
```

## smoke-r2

| run | verdict (run-dual.sh) | per-hart (harness) | judge |
|---|---|---|---|
| dual01_boot | RUN exit=0 wall=1s Completed after 14926 cycles M2B-BOOT-OK sp1=0x0000000080003000 | retired0=1650 traps0=1 maxawait0=10 awaits0=145 epoch0=1 retired1=2078 traps1=1 maxawait1=11 awaits1=86 epoch1=1 | PASS |
| dual02_clint | RUN exit=0 wall=30s Completed after 314002 cycles M2B-CLINT-OK mtip0=0x0000000000000005 0x0000000000000005 0x0 | retired0=35890 traps0=6 maxawait0=9 awaits0=7178 epoch0=1 retired1=34638 traps1=7 maxawait1=11 awaits1=7598 epoch1=1 | PASS |
| dual04_pbus | RUN exit=0 wall=8s Completed after 81591 cycles M2B-PBUS-OK senable_rb=0x0000000000000002 0x0000000000000000 s | retired0=8444 traps0=1 maxawait0=6 awaits0=376 epoch0=1 retired1=9667 traps1=1 maxawait1=10 awaits1=167 epoch1=1 | PASS |
| dual05_fencei | RUN exit=0 wall=2s Completed after 21312 cycles M2B-FENCEI-OK nofence=0x0000000000000001 fence=0x0000000000000 | retired0=2490 traps0=1 maxawait0=6 awaits0=181 epoch0=1 retired1=3244 traps1=1 maxawait1=9 awaits1=60 epoch1=1 | PASS |

```
      INFO dual04: xv6 S-context addresses read back after writing 2/0: enable(hart0 @0xc002080)=0x2 enable(hart1 @0xc002180)=0x0 threshold(hart0 @0xc201000)=0x0 threshold(hart1 @0xc2030
      INFO dual05: without fence.i hart 1 executed the OLD code at X (observed on this implementation, not an ISA claim); new code committed after fence.i: True
```

## suite-r2

| run | verdict (run-dual.sh) | per-hart (harness) | judge |
|---|---|---|---|
| dual03-s1 | RUN exit=0 wall=30s Completed after 4527347 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=345270 traps0=2 maxawait0=22 awaits0=803864 epoch0=1 retired1=356392 traps1=2 maxawait1=22 awaits1=707247 epoch | PASS |
| dual03-s10 | RUN exit=0 wall=31s Completed after 4544826 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=370296 traps0=2 maxawait0=19 awaits0=410920 epoch0=1 retired1=375405 traps1=2 maxawait1=19 awaits1=396008 epoch | PASS |
| dual03-s2 | RUN exit=0 wall=30s Completed after 4492522 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=353928 traps0=2 maxawait0=18 awaits0=524390 epoch0=1 retired1=359020 traps1=2 maxawait1=20 awaits1=510168 epoch | PASS |
| dual03-s3 | RUN exit=0 wall=38s Completed after 5528143 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=389821 traps0=2 maxawait0=23 awaits0=1043924 epoch0=1 retired1=396194 traps1=2 maxawait1=23 awaits1=1008876 epo | PASS |
| dual03-s4 | RUN exit=0 wall=27s Completed after 4039453 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=337678 traps0=2 maxawait0=18 awaits0=565807 epoch0=1 retired1=339636 traps1=2 maxawait1=20 awaits1=580159 epoch | PASS |
| dual03-s5 | RUN exit=0 wall=28s Completed after 4183101 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=348903 traps0=2 maxawait0=19 awaits0=425100 epoch0=1 retired1=359852 traps1=2 maxawait1=19 awaits1=328128 epoch | PASS |
| dual03-s6 | RUN exit=0 wall=33s Completed after 5084496 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=380477 traps0=2 maxawait0=22 awaits0=849905 epoch0=1 retired1=387097 traps1=2 maxawait1=22 awaits1=815256 epoch | PASS |
| dual03-s7 | RUN exit=0 wall=33s Completed after 5072458 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=388077 traps0=2 maxawait0=20 awaits0=605460 epoch0=1 retired1=394975 traps1=2 maxawait1=20 awaits1=567445 epoch | PASS |
| dual03-s8 | RUN exit=0 wall=28s Completed after 4341935 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=338224 traps0=2 maxawait0=22 awaits0=854526 epoch0=1 retired1=345020 traps1=2 maxawait1=21 awaits1=808566 epoch | PASS |
| dual03-s9 | RUN exit=0 wall=29s Completed after 4386312 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e20 | retired0=341543 traps0=2 maxawait0=20 awaits0=713591 epoch0=1 retired1=356426 traps1=2 maxawait1=21 awaits1=565796 epoch | PASS |
| dual03-trace | RUN exit=0 wall=363s Completed after 3778622 cycles M2B-LOCK-OK lock=0x0000000000004e20 lrsc=0x0000000000004e2 | retired0=338913 traps0=2 maxawait0=17 awaits0=300309 epoch0=1 retired1=341429 traps1=2 maxawait1=18 awaits1=304765 epoch | PASS |
| dual06-drain | RUN exit=0 wall=26s Completed after 273521 cycles M2B-DRAIN-OK amo=0x000000000000016a | retired0=37137 traps0=1 maxawait0=9 awaits0=1321 epoch0=2 retired1=37564 traps1=1 maxawait1=13 awaits1=1242 epoch1=2 | PASS |
| dual07-long | RUN exit=0 wall=58s Completed after 8737743 cycles M2B-LONG-OK iter=0x00000000000186a0 0x00000000000186a0 sum= | retired0=1208492 traps0=1 maxawait0=11 awaits0=39574 epoch0=1 retired1=1209568 traps1=1 maxawait1=9 awaits1=39424 epoch1 | PASS |
| neg01_nohart1 | RUN exit=2 wall=38s *** FAILED *** (no host result, seed 1789921147) after 400000 cycles  | retired0=47641 traps0=1 maxawait0=6 awaits0=1986 epoch0=1 retired1=66391 traps1=1 maxawait1=6 awaits1=13 epoch1=1 | FAIL |
| neg02_wronghart | RUN exit=99 wall=1s *** FAILED *** (tohost = 99) M2B-TRAP-FAIL unexpected trap on hart 0 | retired0=1679 traps0=2 maxawait0=10 awaits0=168 epoch0=1 retired1=2197 traps1=2 maxawait1=11 awaits1=69 epoch1=1 | FAIL |
| neg03_wrongcount | RUN exit=0 wall=25s Completed after 3781873 cycles M2B-LOCK-OK lock=0x0000000000004e1f lrsc=0x0000000000004e20 | retired0=338944 traps0=2 maxawait0=18 awaits0=303274 epoch0=1 retired1=341455 traps1=2 maxawait1=18 awaits1=307760 epoch | FAIL |
| neg04_early | RUN exit=0 wall=57s Completed after 8737532 cycles M2B-LONG-OK iter=0x00000000000186a0 0x0000000000000000 sum= | retired0=1208434 traps0=1 maxawait0=11 awaits0=39906 epoch0=1 retired1=1208799 traps1=1 maxawait1=10 awaits1=39831 epoch | FAIL |

```
      INFO drain: 6567 answered DRAM writes, 10897 AXI write bursts (>=, the host load writes are included)
      INFO dual07: retired [1208492, 1209568], maxAWait [11, 9], aWaits [39574, 39424]
      INFO dual07: retired [1208434, 1208799], maxAWait [11, 10], aWaits [39906, 39831]
M2B_SUITE_DONE group=all runs=17 bad=0 (from round2.sh)
```

## n1-r2 (single-core and unit-harness regressions from the m2b common)

```
== 2026-09-27T03:21:51Z matrix refusals (pipeline, 0, 4 must fail at elaboration with 'unsupported' and the value) ==
  MC1UnsupportedPipelineConfig: refused -- unsupported CORE_IMPL=pipeline: only 'multicycle' is implemented
  MC1UnsupportedZeroConfig: refused -- unsupported NUM_CORES=0: MC-M2b implements 1 and 2 (no harts to bind)
  MC2UnsupportedQuadConfig: refused -- unsupported NUM_CORES=4: MC-M2b implements 1 and 2 (4 is not implemented)
== 2026-09-27T03:22:09Z RD2 single-core regression vs M1 closeout2 (gen x2, probes fast+trace, compare, R-BOOT) ==
RD2_REGRESS step=all rc=0
== 2026-09-27T03:26:37Z the original CPU-A 27 scenarios (original score.py) from the m2b common ==
ATOMIC_RERUN_DONE scenarios=27 infra=0 score_fails=0
== 2026-09-27T03:37:24Z M2a directed + kill groups from the m2b common (backend unchanged; the harness scala is) ==
DUAL_ALL_DONE group=directed scenarios=11 infra=0 bad=0
DUAL_ALL_DONE group=kill scenarios=10 infra=0 bad=0
== 2026-09-27T03:42:45Z N1_REGRESS_DONE rc=0

--- rd2 compare-fast:
program set: 13 expected, before has 13, after has 13
program          marker                     before   after    console  commits          cycles
boot01_marker    TEACHING-CPU-M3-OK         ok       ok       same     (untraced)       6386->6386 (d=+0)
boot02_clint     M3-CLINT-OK                ok       ok       same     (untraced)       44469->44469 (d=+0)
boot03_ddr       M3-DDR-OK                  ok       ok       same     (untraced)       16323->16323 (d=+0)
boot04_badaddr   M3-BADADDR-OK              ok       ok       same     (untraced)       6895->6895 (d=+0)
ext01_m          TEACHING-EXT-M-OK          ok       ok       same     (untraced)       7021->7021 (d=+0)
ext02_c          TEACHING-EXT-C-OK          ok       ok       same     (untraced)       6460->6460 (d=+0)
ext04_sv39       TEACHING-EXT-SV39-OK       ok       ok       same     (untraced)       17834->17834 (d=+0)
boot11_sv39      M3-SV39-OK                 ok       ok       same     (untraced)       45709->45709 (d=+0)
boot12_amo       M3-AMO-OK                  ok       ok       same     (untraced)       49519->49519 (d=+0)
hello            PASS                       ok       ok       same     (untraced)       10293->10293 (d=+0)
tlb01_sfence     TEACHING-TLB-SFENCE-OK     ok       ok       same     (untraced)       31432->31432 (d=+0)
tlb02_canonical  TEACHING-TLB-CANON-OK      ok       ok       same     (untraced)       51894->51894 (d=+0)
cache01_smc      TEACHING-CACHE-SMC-OK      ok       ok       same     (untraced)       9009->9009 (d=+0)
COMPARE fails=0  (cycle deltas are reported, not judged)
--- rd2 compare-trace:
program set: 13 expected, before has 13, after has 13
program          marker                     before   after    console  commits          cycles
boot01_marker    TEACHING-CPU-M3-OK         ok       ok       same     726/726 d=0      6386->6386 (d=+0)
boot02_clint     M3-CLINT-OK                ok       ok       same     6856/6856 d=0    44469->44469 (d=+0)
boot03_ddr       M3-DDR-OK                  ok       ok       same     1909/1909 d=0    16323->16323 (d=+0)
boot04_badaddr   M3-BADADDR-OK              ok       ok       same     725/725 d=0      6895->6895 (d=+0)
ext01_m          TEACHING-EXT-M-OK          ok       ok       same     726/726 d=0      7021->7021 (d=+0)
ext02_c          TEACHING-EXT-C-OK          ok       ok       same     575/575 d=0      6460->6460 (d=+0)
ext04_sv39       TEACHING-EXT-SV39-OK       ok       ok       same     1631/1631 d=0    17834->17834 (d=+0)
boot11_sv39      M3-SV39-OK                 ok       ok       same     4236/4236 d=0    45709->45709 (d=+0)
boot12_amo       M3-AMO-OK                  ok       ok       same     4500/4500 d=0    49519->49519 (d=+0)
hello            PASS                       ok       ok       same     1119/1119 d=0    10293->10293 (d=+0)
tlb01_sfence     TEACHING-TLB-SFENCE-OK     ok       ok       same     2848/2848 d=0    31432->31432 (d=+0)
tlb02_canonical  TEACHING-TLB-CANON-OK      ok       ok       same     4773/4773 d=0    51894->51894 (d=+0)
cache01_smc      TEACHING-CACHE-SMC-OK      ok       ok       same     1045/1045 d=0    9009->9009 (d=+0)
COMPARE fails=0  (cycle deltas are reported, not judged)
--- rboot:
  g1-boot05-fixed        sim=0 check=ok
  g2-read-inflight       sim=0 check=ok
  g2-write-inflight      sim=0 check=ok
  g2-read-target-neg     sim=2 check=ok
  g2-queued-unconsumed   sim=0 check=ok
  g3-three-rounds        sim=0 check=ok
  g4-stuck-device        sim=2 check=ok
  g4-late-recovery       sim=2 check=ok
  g4-counterexample      rejected, as it must be: READY never happened
RBOOT_DONE fails=0 infra=0
```

## n1 (single-core and unit-harness regressions from the m2b common) -- ROUND 1, before the holdAll gating (history)

```
== 2026-09-27T02:39:06Z matrix refusals (pipeline, 0, 4 must fail at elaboration with 'unsupported' and the value) ==
  MC1UnsupportedPipelineConfig: refused -- unsupported CORE_IMPL=pipeline: only 'multicycle' is implemented
  MC1UnsupportedZeroConfig: NOT refused (rc=1 '')
  MC2UnsupportedQuadConfig: refused -- unsupported NUM_CORES=4: MC-M2b implements 1 and 2 (4 is not implemented)
== 2026-09-27T02:39:23Z RD2 single-core regression vs M1 closeout2 (gen x2, probes fast+trace, compare, R-BOOT) ==
RD2_REGRESS step=all rc=1
== 2026-09-27T02:44:02Z the original CPU-A 27 scenarios (original score.py) from the m2b common ==
ATOMIC_RERUN_DONE scenarios=27 infra=0 score_fails=0
== 2026-09-27T02:56:55Z M2a directed + kill groups from the m2b common (backend unchanged; the harness scala is) ==
DUAL_ALL_DONE group=directed scenarios=11 infra=0 bad=0
DUAL_ALL_DONE group=kill scenarios=10 infra=0 bad=0
== 2026-09-27T03:02:22Z N1_REGRESS_DONE rc=1

--- rd2 compare-fast:
ext02_c          TEACHING-EXT-C-OK          ok       ok       DIFF     (untraced)       6460->6460 (d=+0)
  REJECT: ext04_sv39: recovered console differs
ext04_sv39       TEACHING-EXT-SV39-OK       ok       ok       DIFF     (untraced)       17834->18132 (d=+298)
  REJECT: boot11_sv39: recovered console differs
boot11_sv39      M3-SV39-OK                 ok       ok       DIFF     (untraced)       45709->45709 (d=+0)
  REJECT: boot12_amo: recovered console differs
boot12_amo       M3-AMO-OK                  ok       ok       DIFF     (untraced)       49519->49519 (d=+0)
  REJECT: hello: recovered console differs
hello            PASS                       ok       ok       DIFF     (untraced)       10293->10293 (d=+0)
  REJECT: tlb01_sfence: recovered console differs
tlb01_sfence     TEACHING-TLB-SFENCE-OK     ok       ok       DIFF     (untraced)       31432->31432 (d=+0)
  REJECT: tlb02_canonical: recovered console differs
tlb02_canonical  TEACHING-TLB-CANON-OK      ok       ok       DIFF     (untraced)       51894->51894 (d=+0)
  REJECT: cache01_smc: recovered console differs
cache01_smc      TEACHING-CACHE-SMC-OK      ok       ok       DIFF     (untraced)       9009->9009 (d=+0)
COMPARE fails=13  (cycle deltas are reported, not judged)
--- rd2 compare-trace:
  REJECT: ext04_sv39: recovered console differs
  REJECT: ext04_sv39: COMMIT/TRAP sequences differ (346 lines)
ext04_sv39       TEACHING-EXT-SV39-OK       ok       ok       DIFF     1631/1649 d=346  17834->18132 (d=+298)
  REJECT: boot11_sv39: recovered console differs
boot11_sv39      M3-SV39-OK                 ok       ok       DIFF     4236/4236 d=0    45709->45709 (d=+0)
  REJECT: boot12_amo: recovered console differs
boot12_amo       M3-AMO-OK                  ok       ok       DIFF     4500/4500 d=0    49519->49519 (d=+0)
  REJECT: hello: recovered console differs
hello            PASS                       ok       ok       DIFF     1119/1119 d=0    10293->10293 (d=+0)
  REJECT: tlb01_sfence: recovered console differs
tlb01_sfence     TEACHING-TLB-SFENCE-OK     ok       ok       DIFF     2848/2848 d=0    31432->31432 (d=+0)
  REJECT: tlb02_canonical: recovered console differs
tlb02_canonical  TEACHING-TLB-CANON-OK      ok       ok       DIFF     4773/4773 d=0    51894->51894 (d=+0)
  REJECT: cache01_smc: recovered console differs
cache01_smc      TEACHING-CACHE-SMC-OK      ok       ok       DIFF     1045/1045 d=0    9009->9009 (d=+0)
COMPARE fails=14  (cycle deltas are reported, not judged)
--- rboot:
  g1-boot05-fixed        sim=0 check=ok
  g2-read-inflight       sim=0 check=ok
  g2-write-inflight      sim=0 check=ok
  g2-read-target-neg     sim=2 check=ok
  g2-queued-unconsumed   sim=0 check=ok
  g3-three-rounds        sim=0 check=ok
  g4-stuck-device        sim=2 check=ok
  g4-late-recovery       sim=2 check=ok
  g4-counterexample      rejected, as it must be: READY never happened
RBOOT_DONE fails=0 infra=0
```

## judge self-tests

```
DUAL_CHECK_SELFTEST pass=19 fail=0 (experiments/multicore/m2b/runs/dual-check-selftest)
DRAIN_CHECK_SELFTEST pass=16 fail=0 (experiments/multicore/m2b/runs/drain-check-selftest)
--- the round-2 dual06 record re-evaluated with the closed drain rules (expected to FAIL: its in-flight transactions were ROM fetches):
FAIL dual06_drain exit=0 marker='M2B-DRAIN-OK amo=0x000000000000016a' harts={'n': 2, 'retired': [37137, 37564], 'traps': [1, 1], 'cause': [9223372036854775811, 
  FAIL: drain: hart 0: the transaction in flight at the hold is not a DRAM write (addr 0x1005c write=0 fetch=1): the aimed scenario was not reached
  FAIL: drain: hart 1: the transaction in flight at the hold is not a DRAM write (addr 0x1005c write=0 fetch=1): the aimed scenario was not reached
```
