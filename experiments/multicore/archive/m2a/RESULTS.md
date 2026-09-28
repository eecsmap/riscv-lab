# MC-M2a results

Generated 2026-09-26T23:46:52Z. Sources: `runs/*/<name>/verdict.txt`, `score.txt`, `score.json`, the group logs.

## kill-new (d13-d17, both crossbar orders, FIXED backend -- exact kill counts)

| scenario | sim exit | score | cycles | completed | cpu tx | ext | amo | scok | scfail | kills | illegal | drained | max wait (h0/h1) | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| d13-ext-kills-both-swap | 0 | 0 | 161 | 8 | 7 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 1/5 | PASS |
| d13-ext-kills-both | 0 | 0 | 161 | 8 | 7 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 5/1 | PASS |
| d14-partial-kills-both-swap | 0 | 0 | 161 | 8 | 7 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 1/5 | PASS |
| d14-partial-kills-both | 0 | 0 | 161 | 8 | 7 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 5/1 | PASS |
| d15-clear-both-swap | 0 | 0 | 122 | 8 | 8 | 0 | 0 | 0 | 2 | 2 | 0 | 0 | 1/5 | PASS |
| d15-clear-both | 0 | 0 | 122 | 8 | 8 | 0 | 0 | 0 | 2 | 2 | 0 | 0 | 1/5 | PASS |
| d16-twobeat-both-swap | 0 | 0 | 161 | 9 | 8 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 1/5 | PASS |
| d16-twobeat-both | 0 | 0 | 161 | 9 | 8 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 5/2 | PASS |
| d17-same-hart-two-reasons-swap | 0 | 0 | 166 | 8 | 7 | 1 | 0 | 1 | 1 | 1 | 0 | 0 | 6/5 | PASS |
| d17-same-hart-two-reasons | 0 | 0 | 166 | 8 | 7 | 1 | 0 | 1 | 1 | 1 | 0 | 0 | 8/1 | PASS |

Group line: `DUAL_ALL_DONE group=kill scenarios=10 infra=0 bad=0`

## kill-old (the same group on the OLD backend, AtomicBackend.scala from d9c4008: the eight two-reservation cases MUST fail with kills=1 vs model 2 -- the reproduction)

| scenario | sim exit | score | cycles | completed | cpu tx | ext | amo | scok | scfail | kills | illegal | drained | max wait (h0/h1) | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| d13-ext-kills-both-swap | 0 | 1 | 161 | 8 | 7 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 1/5 | FAIL |
| d13-ext-kills-both | 0 | 1 | 161 | 8 | 7 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 5/1 | FAIL |
| d14-partial-kills-both-swap | 0 | 1 | 161 | 8 | 7 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 1/5 | FAIL |
| d14-partial-kills-both | 0 | 1 | 161 | 8 | 7 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 5/1 | FAIL |
| d15-clear-both-swap | 0 | 1 | 122 | 8 | 8 | 0 | 0 | 0 | 2 | 2 | 0 | 0 | 1/5 | FAIL |
| d15-clear-both | 0 | 1 | 122 | 8 | 8 | 0 | 0 | 0 | 2 | 2 | 0 | 0 | 1/5 | FAIL |
| d16-twobeat-both-swap | 0 | 1 | 161 | 9 | 8 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 1/5 | FAIL |
| d16-twobeat-both | 0 | 1 | 161 | 9 | 8 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 5/2 | FAIL |
| d17-same-hart-two-reasons-swap | 0 | 0 | 166 | 8 | 7 | 1 | 0 | 1 | 1 | 1 | 0 | 0 | 6/5 | PASS |
| d17-same-hart-two-reasons | 0 | 0 | 166 | 8 | 7 | 1 | 0 | 1 | 1 | 1 | 0 | 0 | 8/1 | PASS |

Group line: `DUAL_ALL_DONE group=kill scenarios=10 infra=0 bad=8`

```
  d13-ext-kills-both: OLD BACKEND UNDERCOUNTS (reproduced): FAIL: the backend counted kills=1, the model counted 2 cleared reservation(s)
  d14-partial-kills-both: OLD BACKEND UNDERCOUNTS (reproduced): FAIL: the backend counted kills=1, the model counted 2 cleared reservation(s)
  d15-clear-both: OLD BACKEND UNDERCOUNTS (reproduced): FAIL: the backend counted kills=1, the model counted 2 cleared reservation(s)
  d16-twobeat-both: OLD BACKEND UNDERCOUNTS (reproduced): FAIL: the backend counted kills=1, the model counted 2 cleared reservation(s)
  d13-ext-kills-both-swap: OLD BACKEND UNDERCOUNTS (reproduced): FAIL: the backend counted kills=1, the model counted 2 cleared reservation(s)
  d14-partial-kills-both-swap: OLD BACKEND UNDERCOUNTS (reproduced): FAIL: the backend counted kills=1, the model counted 2 cleared reservation(s)
  d15-clear-both-swap: OLD BACKEND UNDERCOUNTS (reproduced): FAIL: the backend counted kills=1, the model counted 2 cleared reservation(s)
  d16-twobeat-both-swap: OLD BACKEND UNDERCOUNTS (reproduced): FAIL: the backend counted kills=1, the model counted 2 cleared reservation(s)
  d17-same-hart-two-reasons: old backend correct on one reservation (count 1), as expected
  d17-same-hart-two-reasons-swap: old backend correct on one reservation (count 1), as expected
KILL_REPRO_OLD rc=0 (0 = the undercount is reproduced on all eight two-reservation cases)
```

## dual-directed-fix (after the kill-count fix; supersedes the pre-fix round below)

| scenario | sim exit | score | cycles | completed | cpu tx | ext | amo | scok | scfail | kills | illegal | drained | max wait (h0/h1) | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| d01-lrsc-race | 0 | 0 | 134 | 8 | 8 | 0 | 0 | 1 | 1 | 1 | 0 | 0 | 1/1 | PASS |
| d02-store-kills | 0 | 0 | 111 | 6 | 6 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 1/1 | PASS |
| d03-granules | 0 | 0 | 115 | 8 | 8 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 6/5 | PASS |
| d05-trap-local | 0 | 0 | 142 | 8 | 8 | 0 | 0 | 1 | 1 | 1 | 0 | 0 | 5/4 | PASS |
| d06-dma-kills | 0 | 0 | 148 | 9 | 8 | 1 | 0 | 1 | 1 | 1 | 0 | 0 | 5/4 | PASS |
| d07-partial | 0 | 0 | 111 | 6 | 6 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 1/1 | PASS |
| d08-failed-sc | 0 | 0 | 116 | 6 | 6 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | 1/1 | PASS |
| d09-paths | 0 | 0 | 218 | 35 | 35 | 0 | 2 | 6 | 3 | 3 | 5 | 0 | 6/7 | PASS |
| d10-amo-contend | 0 | 0 | 943 | 41 | 41 | 0 | 36 | 0 | 0 | 0 | 0 | 0 | 23/26 | PASS |
| d11-drain | 0 | 0 | 463 | 20 | 22 | 0 | 18 | 0 | 0 | 0 | 0 | 2 | 23/21 | PASS |
| d12-fair | 0 | 0 | 2961 | 146 | 146 | 0 | 72 | 0 | 0 | 0 | 0 | 0 | 28/13 | PASS |

Group line: `DUAL_ALL_DONE group=directed scenarios=11 infra=0 bad=0`

## dual-random-fix (after the kill-count fix; supersedes the pre-fix round below)

| scenario | sim exit | score | cycles | completed | cpu tx | ext | amo | scok | scfail | kills | illegal | drained | max wait (h0/h1) | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| rnd1 | 0 | 0 | 239791 | 12785 | 11285 | 1500 | 2458 | 139 | 1806 | 1005 | 0 | 0 | 893/592 | PASS |
| rnd10 | 0 | 0 | 239790 | 12779 | 11279 | 1500 | 2434 | 162 | 1715 | 995 | 0 | 0 | 31/27 | PASS |
| rnd2 | 0 | 0 | 239779 | 12774 | 11274 | 1500 | 2430 | 159 | 1833 | 1039 | 0 | 0 | 45/44 | PASS |
| rnd3 | 0 | 0 | 239801 | 12808 | 11308 | 1500 | 2415 | 150 | 1730 | 972 | 0 | 0 | 531/319 | PASS |
| rnd4 | 0 | 0 | 239778 | 12800 | 11300 | 1500 | 2398 | 151 | 1736 | 1034 | 0 | 0 | 46/46 | PASS |
| rnd5 | 0 | 0 | 239784 | 12810 | 11310 | 1500 | 2410 | 161 | 1784 | 1033 | 0 | 0 | 603/303 | PASS |
| rnd6 | 0 | 0 | 239766 | 12821 | 11321 | 1500 | 2426 | 159 | 1714 | 1003 | 0 | 0 | 22/23 | PASS |
| rnd7 | 0 | 0 | 239785 | 12776 | 11276 | 1500 | 2385 | 180 | 1729 | 1037 | 0 | 0 | 859/556 | PASS |
| rnd8 | 0 | 0 | 239799 | 12800 | 11300 | 1500 | 2438 | 152 | 1696 | 1105 | 0 | 0 | 48/50 | PASS |
| rnd9 | 0 | 0 | 239794 | 12736 | 11236 | 1500 | 2335 | 169 | 1766 | 1033 | 0 | 0 | 603/260 | PASS |

Group line: `DUAL_ALL_DONE group=random scenarios=10 infra=0 bad=0`

## dual-topo-fix (after the kill-count fix; supersedes the pre-fix round below)

| scenario | sim exit | score | cycles | completed | cpu tx | ext | amo | scok | scfail | kills | illegal | drained | max wait (h0/h1) | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| rnd1-extra | 0 | 0 | 239792 | 13160 | 11285 | 1875 | 2458 | 135 | 1810 | 1030 | 0 | 0 | 625/292 | PASS |
| rnd1-swap-extra | 0 | 0 | 239793 | 13160 | 11285 | 1875 | 2458 | 149 | 1796 | 1015 | 0 | 0 | 292/626 | PASS |
| rnd1-swap | 0 | 0 | 239791 | 12785 | 11285 | 1500 | 2458 | 138 | 1807 | 1019 | 0 | 0 | 592/893 | PASS |

Group line: `DUAL_ALL_DONE group=topo scenarios=3 infra=0 bad=0`

## dual-neg-fix (after the kill-count fix; supersedes the pre-fix round below)

| scenario | sim exit | score | cycles | completed | cpu tx | ext | amo | scok | scfail | kills | illegal | drained | max wait (h0/h1) | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| neg-interleave | 0 | 1 | 15779 | 843 | 747 | 96 | 157 | 12 | 110 | 69 | 0 | 0 | 531/319 | REJECTED (as declared) |
| neg-no-cross-kill | 0 | 1 | 116 | 6 | 6 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 1/1 | REJECTED (as declared) |
| neg-no-kill | 0 | 1 | 153 | 9 | 8 | 1 | 0 | 1 | 1 | 1 | 0 | 0 | 5/6 | REJECTED (as declared) |
| neg-phys-withdraw | 0 | 1 | 134 | 8 | 8 | 0 | 0 | 1 | 1 | 1 | 0 | 0 | 1/1 | REJECTED (as declared) |
| neg-swap-dsource | 134 | 1 |  | 2 | 4 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 7/5 | REJECTED (as declared) |
| neg-swap-sideband | 134 | 1 |  | 4 | 5 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 5/4 | REJECTED (as declared) |
| neg-tl-withdraw | 0 | 1 | 1008 | 41 | 41 | 0 | 36 | 0 | 0 | 0 | 0 | 0 | 493/4 | REJECTED (as declared) |
| neg-wrong-src | 134 | 1 |  | 4 | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1/1 | REJECTED (as declared) |

Group line: `DUAL_ALL_DONE group=neg scenarios=8 infra=0 bad=0`

## dual-directed-final (pre-fix round -- history; the backend then counted kills as a lower bound)

| scenario | sim exit | score | cycles | completed | cpu tx | ext | amo | scok | scfail | kills | illegal | drained | max wait (h0/h1) | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| d01-lrsc-race | 0 | 0 | 134 | 8 | 8 | 0 | 0 | 1 | 1 | 1 | 0 | 0 | 1/1 | PASS |
| d02-store-kills | 0 | 0 | 111 | 6 | 6 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 1/1 | PASS |
| d03-granules | 0 | 0 | 115 | 8 | 8 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 6/5 | PASS |
| d05-trap-local | 0 | 0 | 142 | 8 | 8 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | 5/4 | PASS |
| d06-dma-kills | 0 | 0 | 148 | 9 | 8 | 1 | 0 | 1 | 1 | 1 | 0 | 0 | 5/4 | PASS |
| d07-partial | 0 | 0 | 111 | 6 | 6 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 1/1 | PASS |
| d08-failed-sc | 0 | 0 | 116 | 6 | 6 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | 1/1 | PASS |
| d09-paths | 0 | 0 | 218 | 35 | 35 | 0 | 2 | 6 | 3 | 1 | 5 | 0 | 6/7 | PASS |
| d10-amo-contend | 0 | 0 | 943 | 41 | 41 | 0 | 36 | 0 | 0 | 0 | 0 | 0 | 23/26 | PASS |
| d11-drain | 0 | 0 | 463 | 20 | 22 | 0 | 18 | 0 | 0 | 0 | 0 | 2 | 23/21 | PASS |
| d12-fair | 0 | 0 | 2961 | 146 | 146 | 0 | 72 | 0 | 0 | 0 | 0 | 0 | 28/13 | PASS |

Group line: `DUAL_ALL_DONE group=directed scenarios=11 infra=0 bad=0`

## dual-random (pre-fix round -- history; the backend then counted kills as a lower bound)

| scenario | sim exit | score | cycles | completed | cpu tx | ext | amo | scok | scfail | kills | illegal | drained | max wait (h0/h1) | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| rnd1 | 0 | 0 | 239791 | 12785 | 11285 | 1500 | 2458 | 139 | 1806 | 911 | 0 | 0 | 893/592 | PASS |
| rnd10 | 0 | 0 | 239790 | 12779 | 11279 | 1500 | 2434 | 162 | 1715 | 912 | 0 | 0 | 31/27 | PASS |
| rnd2 | 0 | 0 | 239779 | 12774 | 11274 | 1500 | 2430 | 159 | 1833 | 943 | 0 | 0 | 45/44 | PASS |
| rnd3 | 0 | 0 | 239801 | 12808 | 11308 | 1500 | 2415 | 150 | 1730 | 878 | 0 | 0 | 531/319 | PASS |
| rnd4 | 0 | 0 | 239778 | 12800 | 11300 | 1500 | 2398 | 151 | 1736 | 928 | 0 | 0 | 46/46 | PASS |
| rnd5 | 0 | 0 | 239784 | 12810 | 11310 | 1500 | 2410 | 161 | 1784 | 942 | 0 | 0 | 603/303 | PASS |
| rnd6 | 0 | 0 | 239766 | 12821 | 11321 | 1500 | 2426 | 159 | 1714 | 919 | 0 | 0 | 22/23 | PASS |
| rnd7 | 0 | 0 | 239785 | 12776 | 11276 | 1500 | 2385 | 180 | 1729 | 930 | 0 | 0 | 859/556 | PASS |
| rnd8 | 0 | 0 | 239799 | 12800 | 11300 | 1500 | 2438 | 152 | 1696 | 1002 | 0 | 0 | 48/50 | PASS |
| rnd9 | 0 | 0 | 239794 | 12736 | 11236 | 1500 | 2335 | 169 | 1766 | 946 | 0 | 0 | 603/260 | PASS |

Group line: `DUAL_ALL_DONE group=random scenarios=10 infra=0 bad=0`

## dual-topo (pre-fix round -- history; the backend then counted kills as a lower bound)

| scenario | sim exit | score | cycles | completed | cpu tx | ext | amo | scok | scfail | kills | illegal | drained | max wait (h0/h1) | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| rnd1-extra | 0 | 0 | 239792 | 13160 | 11285 | 1875 | 2458 | 135 | 1810 | 930 | 0 | 0 | 625/292 | PASS |
| rnd1-swap-extra | 0 | 0 | 239793 | 13160 | 11285 | 1875 | 2458 | 149 | 1796 | 914 | 0 | 0 | 292/626 | PASS |
| rnd1-swap | 0 | 0 | 239791 | 12785 | 11285 | 1500 | 2458 | 138 | 1807 | 921 | 0 | 0 | 592/893 | PASS |

Group line: `DUAL_ALL_DONE group=topo scenarios=3 infra=0 bad=0`

## dual-neg-final (pre-fix round -- history; the backend then counted kills as a lower bound)

| scenario | sim exit | score | cycles | completed | cpu tx | ext | amo | scok | scfail | kills | illegal | drained | max wait (h0/h1) | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| neg-interleave | 0 | 1 | 15779 | 843 | 747 | 96 | 157 | 12 | 110 | 60 | 0 | 0 | 531/319 | REJECTED (as declared) |
| neg-no-cross-kill | 0 | 1 | 116 | 6 | 6 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 1/1 | REJECTED (as declared) |
| neg-no-kill | 0 | 1 | 153 | 9 | 8 | 1 | 0 | 1 | 1 | 1 | 0 | 0 | 5/6 | REJECTED (as declared) |
| neg-phys-withdraw | 0 | 1 | 134 | 8 | 8 | 0 | 0 | 1 | 1 | 1 | 0 | 0 | 1/1 | REJECTED (as declared) |
| neg-swap-dsource | 134 | 1 |  | 2 | 4 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 7/5 | REJECTED (as declared) |
| neg-swap-sideband | 134 | 1 |  | 4 | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 5/4 | REJECTED (as declared) |
| neg-tl-withdraw | 0 | 1 | 1008 | 41 | 41 | 0 | 36 | 0 | 0 | 0 | 0 | 0 | 493/4 | REJECTED (as declared) |
| neg-wrong-src | 134 | 1 |  | 4 | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1/1 | REJECTED (as declared) |

Group line: `DUAL_ALL_DONE group=neg scenarios=8 infra=0 bad=0`

## dual-directed (FIRST ROUND -- history, superseded; the three floor/harness misses are §9 items 6-8, 12-13 of REPORT.md)

| scenario | sim exit | score | cycles | completed | cpu tx | ext | amo | scok | scfail | kills | illegal | drained | max wait (h0/h1) | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| d01-lrsc-race | 0 | 0 | 134 | 8 | 8 | 0 | 0 | 1 | 1 | 1 | 0 | 0 | 1/1 | PASS |
| d02-store-kills | 0 | 0 | 111 | 6 | 6 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 1/1 | PASS |
| d03-granules | 0 | 0 | 115 | 8 | 8 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 6/5 | PASS |
| d05-trap-local | 0 | 0 | 142 | 8 | 8 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | 5/4 | PASS |
| d06-dma-kills | 0 | 1 | 229 | 9 | 8 | 1 | 0 | 2 | 0 | 0 | 0 | 0 | 5/6 | FAIL |
| d07-partial | 0 | 0 | 111 | 6 | 6 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 1/1 | PASS |
| d08-failed-sc | 0 | 0 | 116 | 6 | 6 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | 1/1 | PASS |
| d09-paths | 0 | 1 | 218 | 35 | 35 | 0 | 2 | 6 | 3 | 1 | 5 | 0 | 6/7 | FAIL |
| d10-amo-contend | 0 | 0 | 943 | 41 | 41 | 0 | 36 | 0 | 0 | 0 | 0 | 0 | 23/26 | PASS |
| d11-drain | 0 | 1 | 460 | 20 | 22 | 0 | 18 | 0 | 0 | 0 | 0 | 2 | 21/21 | FAIL |
| d12-fair | 0 | 0 | 2961 | 146 | 146 | 0 | 72 | 0 | 0 | 0 | 0 | 0 | 28/13 | PASS |

## dual-neg (FIRST ROUND -- history, superseded; the three floor/harness misses are §9 items 6-8, 12-13 of REPORT.md)

| scenario | sim exit | score | cycles | completed | cpu tx | ext | amo | scok | scfail | kills | illegal | drained | max wait (h0/h1) | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| neg-interleave | 0 | 1 | 15779 | 843 | 747 | 96 | 157 | 12 | 110 | 60 | 0 | 0 | 531/319 | REJECTED (as declared) |
| neg-no-cross-kill | 0 | 1 | 116 | 6 | 6 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 1/1 | REJECTED (as declared) |
| neg-no-kill | 0 | 1 | 153 | 9 | 8 | 1 | 0 | 1 | 1 | 1 | 0 | 0 | 5/6 | REJECTED (as declared) |
| neg-phys-withdraw | 0 | 0 | 134 | 8 | 8 | 0 | 0 | 1 | 1 | 1 | 0 | 0 | 1/1 | PASS |
| neg-swap-dsource | 134 | 1 |  | 2 | 4 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 7/5 | REJECTED (as declared) |
| neg-swap-sideband | 134 | 1 |  | 4 | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 5/4 | REJECTED (as declared) |
| neg-tl-withdraw | 0 | 1 | 1008 | 41 | 41 | 0 | 36 | 0 | 0 | 0 | 0 | 0 | 493/4 | REJECTED (as declared) |
| neg-wrong-src | 134 | 1 |  | 4 | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1/1 | REJECTED (as declared) |

Group line: `DUAL_ALL_DONE group=neg scenarios=8 infra=0 bad=3`

## atomic-rerun-fix (the original CPU-A scenarios, original score.py)

```
    == unit harness: positives (sim exit 0, a clean pairing/replay score) ==
      amo-basic              sim=0 score=0 SCORE amo=28 scok=0 scfail=0 kills=0 ext=0 cpu_tx=33 illegal=0 drained=0 mgr_writes=30 refusals=0 fails=0
      amo-race               sim=0 score=0 SCORE amo=16 scok=0 scfail=0 kills=0 ext=16 cpu_tx=34 illegal=0 drained=0 mgr_writes=34 refusals=0 fails=0
      amo-partial            sim=0 score=0 SCORE amo=12 scok=6 scfail=0 kills=0 ext=10 cpu_tx=38 illegal=0 drained=0 mgr_writes=34 refusals=0 fails=0
      lrsc-basic             sim=0 score=0 SCORE amo=0 scok=5 scfail=7 kills=0 ext=0 cpu_tx=30 illegal=0 drained=0 mgr_writes=9 refusals=0 fails=0
      lrsc-race              sim=0 score=0 SCORE amo=0 scok=2 scfail=4 kills=4 ext=5 cpu_tx=16 illegal=0 drained=0 mgr_writes=10 refusals=0 fails=0
      errors                 sim=0 score=0 SCORE amo=2 scok=2 scfail=1 kills=0 ext=0 cpu_tx=27 illegal=9 drained=0 mgr_writes=2 refusals=3 fails=0
      progress               sim=0 score=0 SCORE amo=0 scok=32 scfail=0 kills=0 ext=30 cpu_tx=66 illegal=0 drained=0 mgr_writes=63 refusals=0 fails=0
      drain-getd             sim=0 score=0 SCORE amo=7 scok=0 scfail=0 kills=0 ext=0 cpu_tx=9 illegal=0 drained=1 mgr_writes=8 refusals=0 fails=0
      drain-putd             sim=0 score=0 SCORE amo=7 scok=0 scfail=0 kills=0 ext=0 cpu_tx=9 illegal=0 drained=1 mgr_writes=8 refusals=0 fails=0
      drain-resp             sim=0 score=0 SCORE amo=7 scok=0 scfail=0 kills=0 ext=0 cpu_tx=9 illegal=0 drained=1 mgr_writes=8 refusals=0 fails=0
    == unit harness: return backpressure, delayers on both sides of the crossbar, D stalls ==
      bp-amo                 sim=0 score=0 SCORE amo=16 scok=0 scfail=0 kills=0 ext=16 cpu_tx=34 illegal=0 drained=0 mgr_writes=34 refusals=0 fails=0
      bp-lrsc                sim=0 score=0 SCORE amo=0 scok=2 scfail=4 kills=4 ext=5 cpu_tx=16 illegal=0 drained=0 mgr_writes=10 refusals=0 fails=0
      bp-lrsc-basic          sim=0 score=0 SCORE amo=0 scok=5 scfail=7 kills=0 ext=0 cpu_tx=30 illegal=0 drained=0 mgr_writes=9 refusals=0 fails=0
      bp-errors              sim=0 score=0 SCORE amo=2 scok=2 scfail=1 kills=0 ext=0 cpu_tx=27 illegal=9 drained=0 mgr_writes=2 refusals=3 fails=0
      bp-drain               sim=0 score=0 SCORE amo=7 scok=0 scfail=0 kills=0 ext=0 cpu_tx=9 illegal=0 drained=1 mgr_writes=8 refusals=0 fails=0
    == unit harness: negatives (detected only by the declared signature) ==
      neg-readerr-writes     sim=0 score=1 SCORE amo=2 scok=2 scfail=1 kills=0 ext=0 cpu_tx=27 illegal=9 drained=0 mgr_writes=2 refusals=4 fails=3
          -> rejected by the declared check:   FAIL: 24: AMO Put issued after its Get returned an error
      neg-no-kill            sim=0 score=1 SCORE amo=0 scok=2 scfail=4 kills=4 ext=5 cpu_tx=16 illegal=0 drained=0 mgr_writes=14 refusals=0 fails=21
          -> rejected by the declared check:   FAIL: 225: SC result scfail=0, model says 1
    /home/engineer/fpga/experiments/multicore/m2a/tests/atomic-rerun.sh: line 17: 503690 Aborted                    timeout 900 $d/obj_dir/tb +max-cycles=800000 > $d/run.
      neg-wrong-source       sim=134 score=1 SCORE amo=0 scok=0 scfail=0 kills=0 ext=0 cpu_tx=4 illegal=0 drained=0 mgr_writes=3 refusals=0 fails=7
          -> rejected by the declared check:   FAIL: 1: the backend classified source 2 cpu=0, the announced CPU range is [2,3)
    Assertion failed: AtomicBackend: hart 0 mark pushed while one is pending
          (note: no FINISHED -- the run aborted; the detection above is by signature only)
      neg-sc-early           sim=0 score=1 SCORE amo=0 scok=2 scfail=4 kills=4 ext=5 cpu_tx=16 illegal=0 drained=0 mgr_writes=14 refusals=0 fails=26
          -> rejected by the declared check:   FAIL: 224: SC result scfail=0, model says 1
      neg-amo-map            sim=0 score=1 SCORE amo=28 scok=0 scfail=0 kills=0 ext=0 cpu_tx=33 illegal=0 drained=0 mgr_writes=30 refusals=0 fails=36
          -> rejected by the declared check:   FAIL: 33: CPU txid=4 is a amo (amo code 2) and must map to TL opcode 2, the accepted A is opcode 3
      neg-amo-operand        sim=0 score=1 SCORE amo=28 scok=0 scfail=0 kills=0 ext=0 cpu_tx=33 illegal=0 drained=0 mgr_writes=30 refusals=0 fails=110
          -> rejected by the declared check:   FAIL: 17: CPU txid=3 operand 0x0000000000000003 was shipped as 0x0000000300000000
    == the real topology: backend at the coherence-manager hook (before TLBroadcast), memory bus, TLToAXI4, SimAXIMem ==
      soc-amo-race           sim=0 score=0 SCORE amo=16 scok=0 scfail=0 kills=0 ext=16 cpu_tx=34 illegal=0 drained=0 mgr_writes=0 refusals=0 fails=0
      soc-lrsc-race          sim=0 score=0 SCORE amo=0 scok=2 scfail=4 kills=4 ext=5 cpu_tx=16 illegal=0 drained=0 mgr_writes=0 refusals=0 fails=0
      soc-partial            sim=0 score=0 SCORE amo=12 scok=6 scfail=0 kills=0 ext=10 cpu_tx=38 illegal=0 drained=0 mgr_writes=0 refusals=0 fails=0
      soc-errors             sim=0 score=0 SCORE amo=2 scok=3 scfail=0 kills=0 ext=0 cpu_tx=27 illegal=10 drained=0 mgr_writes=0 refusals=0 fails=0
      soc-neg-no-kill        sim=0 score=1 SCORE amo=0 scok=2 scfail=4 kills=4 ext=5 cpu_tx=16 illegal=0 drained=0 mgr_writes=0 refusals=0 fails=19
          -> rejected by the declared check:   FAIL: 30: SC result scfail=0, model says 1
      soc-neg-amo-map        sim=0 score=1 SCORE amo=16 scok=0 scfail=0 kills=0 ext=16 cpu_tx=34 illegal=0 drained=0 mgr_writes=0 refusals=0 fails=30
          -> rejected by the declared check:   FAIL: 15: CPU txid=3 is a amo (amo code 2) and must map to TL opcode 2, the accepted A is opcode 3
    == the scorer against mutated logs ==
        missing-d              rejected:   FAIL: 9: A accepted while src=2 still has no D
        wrong-cpu-data         rejected:   FAIL: 7: CPU_RESP txid=1 is a st and must return no data, it returned 0xdeadbeefdeadbeef
        missing-cpu-response   rejected:   FAIL: 8: CPU_REQ txid=2 while txid=1 has no response
        duplicate-d            rejected:   FAIL: 6: a D (src=2) with nothing accepted
        wrong-d-source         rejected:   FAIL: 6: D carries source 9, the accepted transaction was source 2
        flip-error             rejected:   FAIL: 7: CPU_RESP txid=1 error=1, model says 0
        flip-scfail            rejected:   FAIL: 7: CPU_RESP txid=1 carries scFail on a non-SC
        missing-a              rejected:   FAIL: 6: a D (src=2) with nothing accepted
        missing-cpu-source     rejected:   FAIL: 1: the backend classified source 2 cpu=1, the announced CPU range is [None,None)
        wrong-request-operands rejected:   FAIL: 17: CPU txid=3 operand 0x123456789abcdef0 was shipped as 0x0000000000000003
        wrong-request-amo      rejected:   FAIL: 33: CPU txid=4 is a amo (amo code 1) and must map to TL opcode 3, the accepted A i
        wrong-request-size     rejected:   FAIL: 16: bridge legality 1 for txid=3 (addr 0x80000100 amo=1 lrsc=0 size=2 mask=0xff wr
        wrong-request-mask     rejected:   FAIL: 16: bridge legality 1 for txid=3 (addr 0x80000100 amo=1 lrsc=0 size=3 mask=0xf wri
        resp-before-d          rejected:   FAIL: 1: CPU_RESP txid=1 at 1 precedes its D at 6
      SCORE_SELFTEST_DONE mutations=14 fails=0
    ATOMIC_RERUN_DONE scenarios=27 infra=0 score_fails=0
```

## atomic-rerun (the original CPU-A scenarios, original score.py) -- pre-fix round

```
    == unit harness: positives (sim exit 0, a clean pairing/replay score) ==
      amo-basic              sim=0 score=0 SCORE amo=28 scok=0 scfail=0 kills=0 ext=0 cpu_tx=33 illegal=0 drained=0 mgr_writes=30 refusals=0 fails=0
      amo-race               sim=0 score=0 SCORE amo=16 scok=0 scfail=0 kills=0 ext=16 cpu_tx=34 illegal=0 drained=0 mgr_writes=34 refusals=0 fails=0
      amo-partial            sim=0 score=0 SCORE amo=12 scok=6 scfail=0 kills=0 ext=10 cpu_tx=38 illegal=0 drained=0 mgr_writes=34 refusals=0 fails=0
      lrsc-basic             sim=0 score=0 SCORE amo=0 scok=5 scfail=7 kills=0 ext=0 cpu_tx=30 illegal=0 drained=0 mgr_writes=9 refusals=0 fails=0
      lrsc-race              sim=0 score=0 SCORE amo=0 scok=2 scfail=4 kills=4 ext=5 cpu_tx=16 illegal=0 drained=0 mgr_writes=10 refusals=0 fails=0
      errors                 sim=0 score=0 SCORE amo=2 scok=2 scfail=1 kills=0 ext=0 cpu_tx=27 illegal=9 drained=0 mgr_writes=2 refusals=3 fails=0
      progress               sim=0 score=0 SCORE amo=0 scok=32 scfail=0 kills=0 ext=30 cpu_tx=66 illegal=0 drained=0 mgr_writes=63 refusals=0 fails=0
      drain-getd             sim=0 score=0 SCORE amo=7 scok=0 scfail=0 kills=0 ext=0 cpu_tx=9 illegal=0 drained=1 mgr_writes=8 refusals=0 fails=0
      drain-putd             sim=0 score=0 SCORE amo=7 scok=0 scfail=0 kills=0 ext=0 cpu_tx=9 illegal=0 drained=1 mgr_writes=8 refusals=0 fails=0
      drain-resp             sim=0 score=0 SCORE amo=7 scok=0 scfail=0 kills=0 ext=0 cpu_tx=9 illegal=0 drained=1 mgr_writes=8 refusals=0 fails=0
    == unit harness: return backpressure, delayers on both sides of the crossbar, D stalls ==
      bp-amo                 sim=0 score=0 SCORE amo=16 scok=0 scfail=0 kills=0 ext=16 cpu_tx=34 illegal=0 drained=0 mgr_writes=34 refusals=0 fails=0
      bp-lrsc                sim=0 score=0 SCORE amo=0 scok=2 scfail=4 kills=4 ext=5 cpu_tx=16 illegal=0 drained=0 mgr_writes=10 refusals=0 fails=0
      bp-lrsc-basic          sim=0 score=0 SCORE amo=0 scok=5 scfail=7 kills=0 ext=0 cpu_tx=30 illegal=0 drained=0 mgr_writes=9 refusals=0 fails=0
      bp-errors              sim=0 score=0 SCORE amo=2 scok=2 scfail=1 kills=0 ext=0 cpu_tx=27 illegal=9 drained=0 mgr_writes=2 refusals=3 fails=0
      bp-drain               sim=0 score=0 SCORE amo=7 scok=0 scfail=0 kills=0 ext=0 cpu_tx=9 illegal=0 drained=1 mgr_writes=8 refusals=0 fails=0
    == unit harness: negatives (detected only by the declared signature) ==
      neg-readerr-writes     sim=0 score=1 SCORE amo=2 scok=2 scfail=1 kills=0 ext=0 cpu_tx=27 illegal=9 drained=0 mgr_writes=2 refusals=4 fails=3
          -> rejected by the declared check:   FAIL: 24: AMO Put issued after its Get returned an error
      neg-no-kill            sim=0 score=1 SCORE amo=0 scok=2 scfail=4 kills=4 ext=5 cpu_tx=16 illegal=0 drained=0 mgr_writes=14 refusals=0 fails=21
          -> rejected by the declared check:   FAIL: 225: SC result scfail=0, model says 1
    /home/engineer/fpga/experiments/multicore/m2a/tests/atomic-rerun.sh: line 17: 443855 Aborted                    timeout 900 $d/obj_dir/tb +max-cycles=800000 > $d/run.
      neg-wrong-source       sim=134 score=1 SCORE amo=0 scok=0 scfail=0 kills=0 ext=0 cpu_tx=4 illegal=0 drained=0 mgr_writes=3 refusals=0 fails=7
          -> rejected by the declared check:   FAIL: 1: the backend classified source 2 cpu=0, the announced CPU range is [2,3)
    Assertion failed: AtomicBackend: hart 0 mark pushed while one is pending
          (note: no FINISHED -- the run aborted; the detection above is by signature only)
      neg-sc-early           sim=0 score=1 SCORE amo=0 scok=2 scfail=4 kills=4 ext=5 cpu_tx=16 illegal=0 drained=0 mgr_writes=14 refusals=0 fails=26
          -> rejected by the declared check:   FAIL: 224: SC result scfail=0, model says 1
      neg-amo-map            sim=0 score=1 SCORE amo=28 scok=0 scfail=0 kills=0 ext=0 cpu_tx=33 illegal=0 drained=0 mgr_writes=30 refusals=0 fails=36
          -> rejected by the declared check:   FAIL: 33: CPU txid=4 is a amo (amo code 2) and must map to TL opcode 2, the accepted A is opcode 3
      neg-amo-operand        sim=0 score=1 SCORE amo=28 scok=0 scfail=0 kills=0 ext=0 cpu_tx=33 illegal=0 drained=0 mgr_writes=30 refusals=0 fails=110
          -> rejected by the declared check:   FAIL: 17: CPU txid=3 operand 0x0000000000000003 was shipped as 0x0000000300000000
    == the real topology: backend at the coherence-manager hook (before TLBroadcast), memory bus, TLToAXI4, SimAXIMem ==
      soc-amo-race           sim=0 score=0 SCORE amo=16 scok=0 scfail=0 kills=0 ext=16 cpu_tx=34 illegal=0 drained=0 mgr_writes=0 refusals=0 fails=0
      soc-lrsc-race          sim=0 score=0 SCORE amo=0 scok=2 scfail=4 kills=4 ext=5 cpu_tx=16 illegal=0 drained=0 mgr_writes=0 refusals=0 fails=0
      soc-partial            sim=0 score=0 SCORE amo=12 scok=6 scfail=0 kills=0 ext=10 cpu_tx=38 illegal=0 drained=0 mgr_writes=0 refusals=0 fails=0
      soc-errors             sim=0 score=0 SCORE amo=2 scok=3 scfail=0 kills=0 ext=0 cpu_tx=27 illegal=10 drained=0 mgr_writes=0 refusals=0 fails=0
      soc-neg-no-kill        sim=0 score=1 SCORE amo=0 scok=2 scfail=4 kills=4 ext=5 cpu_tx=16 illegal=0 drained=0 mgr_writes=0 refusals=0 fails=19
          -> rejected by the declared check:   FAIL: 30: SC result scfail=0, model says 1
      soc-neg-amo-map        sim=0 score=1 SCORE amo=16 scok=0 scfail=0 kills=0 ext=16 cpu_tx=34 illegal=0 drained=0 mgr_writes=0 refusals=0 fails=30
          -> rejected by the declared check:   FAIL: 15: CPU txid=3 is a amo (amo code 2) and must map to TL opcode 2, the accepted A is opcode 3
    == the scorer against mutated logs ==
        missing-d              rejected:   FAIL: 9: A accepted while src=2 still has no D
        wrong-cpu-data         rejected:   FAIL: 7: CPU_RESP txid=1 is a st and must return no data, it returned 0xdeadbeefdeadbeef
        missing-cpu-response   rejected:   FAIL: 8: CPU_REQ txid=2 while txid=1 has no response
        duplicate-d            rejected:   FAIL: 6: a D (src=2) with nothing accepted
        wrong-d-source         rejected:   FAIL: 6: D carries source 9, the accepted transaction was source 2
        flip-error             rejected:   FAIL: 7: CPU_RESP txid=1 error=1, model says 0
        flip-scfail            rejected:   FAIL: 7: CPU_RESP txid=1 carries scFail on a non-SC
        missing-a              rejected:   FAIL: 6: a D (src=2) with nothing accepted
        missing-cpu-source     rejected:   FAIL: 1: the backend classified source 2 cpu=1, the announced CPU range is [None,None)
        wrong-request-operands rejected:   FAIL: 17: CPU txid=3 operand 0x123456789abcdef0 was shipped as 0x0000000000000003
        wrong-request-amo      rejected:   FAIL: 33: CPU txid=4 is a amo (amo code 1) and must map to TL opcode 3, the accepted A i
        wrong-request-size     rejected:   FAIL: 16: bridge legality 1 for txid=3 (addr 0x80000100 amo=1 lrsc=0 size=2 mask=0xff wr
        wrong-request-mask     rejected:   FAIL: 16: bridge legality 1 for txid=3 (addr 0x80000100 amo=1 lrsc=0 size=3 mask=0xf wri
        resp-before-d          rejected:   FAIL: 1: CPU_RESP txid=1 at 1 precedes its D at 6
      SCORE_SELFTEST_DONE mutations=14 fails=0
    ATOMIC_RERUN_DONE scenarios=27 infra=0 score_fails=0
```

## rd2-fix (single-core regression vs M1 closeout2)

```
GEN_OK RD2Harness.RD2AtomicXv6FastConfig.v b4a46e14b5659bb5 wall=28s
GEN_OK RD2Harness.RD2AtomicBootConfig.v 25090a641d8c5abb wall=38s
probes-fast rc=0 PROBES label=m2a fails=0
probes-trace rc=0 PROBES label=m2a fails=0
compare-fast  rc=0 COMPARE fails=0  (cycle deltas are reported, not judged)
compare-trace rc=0 COMPARE fails=0  (cycle deltas are reported, not judged)
rboot rc=0 RBOOT_DONE fails=0 infra=0
rboot gates: identical to M1 rboot-after (9 lines)
RD2_REGRESS step=all rc=0

--- compare-fast:
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
--- compare-trace:
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

## rd2 (single-core regression vs M1 closeout2) -- pre-fix round

```
GEN_OK RD2Harness.RD2AtomicXv6FastConfig.v dfaf518233ee09b0 wall=28s
GEN_OK RD2Harness.RD2AtomicBootConfig.v 842c60c360a6a683 wall=41s
probes-fast rc=0 PROBES label=m2a fails=0
probes-trace rc=0 PROBES label=m2a fails=0
compare-fast  rc=0 COMPARE fails=0  (cycle deltas are reported, not judged)
compare-trace rc=0 COMPARE fails=0  (cycle deltas are reported, not judged)
rboot rc=0 RBOOT_DONE fails=0 infra=0
rboot gates: identical to M1 rboot-after (9 lines)
RD2_REGRESS step=all rc=0

--- compare-fast:
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
--- compare-trace:
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

## elaboration refusals (D4 binding)

```
  DualRefuseMissingConfig: refused -- AtomicBackend: client 'teaching-phys-9' must resolve to exactly one client on the inner edge, found 0; clients = teaching-phys-0,teaching-phys-1,ext-t
  DualRefuseStrayConfig: refused -- AtomicBackend: hart-like clients present but not bound: teaching-phys-1
  DualRefuseDupConfig: refused -- AtomicBackend: hart client names must be non-empty and unique, got List(teaching-phys-0, teaching-phys-0)
```


## judge self-tests

```
CHECKER_SELFTEST pass=16 fail=0
SELFTEST score2 pass=32 fail=0 (/home/engineer/fpga/.scratch/score2-selftest.HSBL)
DRAIN_SELFTEST pass=8 fail=0 (experiments/multicore/m2a/runs/score2-drain-selftest)
```
