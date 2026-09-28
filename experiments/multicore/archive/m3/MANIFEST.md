# MC-M3 manifest

Generated 2026-09-27T12:08:58Z.

## Hardware worktree

```
path:   /home/engineer/fpga/worktrees/mc-dual-xv6
branch: mc-dual-xv6
HEAD:   99b53b15b9a162530c0ded802e973a5d6db70ac1  (MC-M3: RD2Harness per-hart user-mode and address-range commit counters)
base:   b147091 (MC-M2b accepted)
dirty:  0 path(s)
diff vs b147091:  1 file changed, 12 insertions(+)
RTL set hash: 52ea751de4126fa0 (M1: 52ea751de4126fa0)
```

## Private common / generated / simulators

```
private common scala == worktree scala
gen-RD2DualXv6FastConfig/RD2Harness.RD2DualXv6FastConfig.v 9c3127d722cb684e
gen-RD2AtomicXv6FastConfig/RD2Harness.RD2AtomicXv6FastConfig.v 7dedf1ca99923cf0
sim-dual/obj_dir/sim                     693aaa1e0f8eaae6
sim-single/obj_dir/sim                   d7ecb822bff087a7
m3_main.cpp 54967c4c7bbc047d   build-xv6-dual-sim.sh 47ad31f10ce590ac
shared scala tree vs M1 baseline: unchanged
```

## Software

```
baseline copy: teaching-cpu-work/xv6-teaching (+ riscv-lab/benchmarks/workloads/src/b0*.c) -> sw/xv6; rebuilt BEFORE edits:
  sw/kernel-baseline  6ad5c2338a31d59e  (accepted kernel-4mib      6ad5c2338a31d59e)
  sw/fs-baseline.img  6bdd8148b79e5983  (accepted fs-b0-pristine   6bdd8148b79e5983)
production / test builds (sw/out/sha256.txt):
  6ad5c2338a31d59e kernel-baseline
  df05b6e462398f6d kernel-prod
  67556eea005e43e1 kernel-prod.asm
  f3851757cd87d157 kernel-prod.syms
  9adf761836870aa0 kernel-raceneg
  4e4edb3c47b5d251 kernel-raceneg.asm
  a8b24c60774b64ca kernel-racepos
  c01f243ad05270d0 kernel-racepos.asm
  6bdd8148b79e5983 fs-baseline.img
  cbb031e5994efbce fs-prod.img
  cbb031e5994efbce fs-raceneg.img
  cbb031e5994efbce fs-racepos.img
source diff vs the shared baseline tree: sw/out/xv6-diff.patch (13 files, 146 changed lines)
  run dual-a: kernel df05b6e462398f6d disk-at-start cbb031e5994efbce disk-after-run 0a068a3fa47d04e7 sim 693aaa1e0f8eaae6
  run dual-b: kernel df05b6e462398f6d disk-at-start cbb031e5994efbce disk-after-run 1480cfc0f06e2193 sim 693aaa1e0f8eaae6
  run single-a: kernel df05b6e462398f6d disk-at-start cbb031e5994efbce disk-after-run 2ad07b88968454b7 sim d7ecb822bff087a7
  run single-b: kernel df05b6e462398f6d disk-at-start cbb031e5994efbce disk-after-run 1480cfc0f06e2193 sim d7ecb822bff087a7
  run race-racepos: kernel a8b24c60774b64ca disk-at-start cbb031e5994efbce disk-after-run cbb031e5994efbce sim 693aaa1e0f8eaae6
  run race-raceneg: kernel 9adf761836870aa0 disk-at-start cbb031e5994efbce disk-after-run cbb031e5994efbce sim 693aaa1e0f8eaae6
toolchain: riscv64-unknown-elf-gcc (gc891d8dc23e) 13.2.0
```

## Runner / judges (isolated copies)

```
0080a7c17453fce5b97c73c6dc1787097030ca2572e5b1e04503e1fa3d81b07d  xv6_console.py
97fd56af4dfb84c5d87ee3c2d2a2910658091e72d791fee54e47d296557880f3  check-xv6.py
c81d02cae721acf4596b632b8ff00bf7f18c38e2e18af3130743d149b91a1645  board-runner.py
bbe4b30bed2802c626e90becdc3b1a5644950d8e98df45e679e99f9367c675c0  board_run.py
b462d851dce3a7249e8e81af72b6a7488c75719d6b95bfb578787d272b72a07e  transport.py
d8938ff19aeb5c4f66524618c81e82fd3875059e0c4b3107737ec403766855ba  board_gate.py
production originals: xv6_console.py 15d83c5490168405 check-xv6.py 97fd56af4dfb84c5 board_run.py bbe4b30bed2802c6
copy vs original differences: 30 lines in xv6_console.py (the m3dual/m3boot profiles), 0 in check-xv6.py, 0 board scripts changed
17cf35aa305ed4df0a05824c0e5f25277b18498daca9a21b4b69b80c299690da  m3_check.py
a3ef5a1435c5d270b734c1fdb79cf1d20d0980f7ad05a7b5d9cd63095090a7a1  m3-check-selftest.sh
dbfe909e27d28d559688647975053abbc00390f673c25f6c356150286de4ddd4  run-xv6.sh
608375efffa017dd27034b4ce881a79f1ab81c4bb9a60b89252eeb11d336d058  m3-race.sh
130fbe5340579fd754b63a5dc47c3cc83c587ad3260ffed440b19ad9cee9cc43  build-sw.sh
d33bd8ca5a60a6842e07f0f872b46db2f89f0e1ba9a0e886b1b95c4c4ed629a8  m3-phase1.sh
3e65dee2110febc3344d5f4fcf0a25829a16ea32c5f9181a31e472847271fc2e  m3-phase2.sh
```

## Tools

```
Verilator 5.022 2024-02-24 rev conda-forge build 1
Python 3.10.14
docker image for sbt: vivado-env:2025.2-sw (612322e4185a), java-8 inside
```
