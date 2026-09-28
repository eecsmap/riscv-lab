#!/usr/bin/env bash
# M2b smoke 1: build the dual TRACING simulator, run the short programs on it, then generate + build the FAST
# (trace-free, monitor-free) dual simulator for the long and seeded runs.
set -u; M2B=/home/engineer/fpga/experiments/multicore/m2b; T=$M2B/tests; R=$M2B/runs; RTL=/home/engineer/fpga/worktrees/mc-dual-core/rtl/cpu
t() { date -u +%FT%TZ; }
echo "== $(t) build dual boot sim =="; NHARTS=2 bash $T/build-dual-sim.sh $R/compile-check-1/RD2Harness.RD2DualBootConfig.v $RTL $R/sim-dual-boot 2>&1 | tail -2
SIM=$R/sim-dual-boot/obj_dir/sim; [ -x $SIM ] || { echo "no sim"; exit 1; }
mkdir -p $R/smoke
for p in dual01_boot:400000:120 dual02_clint:6000000:900 dual04_pbus:2000000:600 dual05_fencei:400000:120; do
  n=${p%%:*}; rest=${p#*:}; cyc=${rest%%:*}; wall=${rest#*:}
  echo "== $(t) run $n =="; bash $T/run-dual.sh $SIM $M2B/progs/build/$n.elf $R/smoke/$n $cyc $wall 2>&1 | tail -1; done
echo "== $(t) gen fast =="; TOPPROJ=teaching bash $M2B/gen/gen.sh RD2Harness RD2DualXv6FastConfig $M2B/gen/common-dual $R/gen-dual-fast 2>&1 | tail -1
echo "== $(t) build dual fast sim =="; NHARTS=2 bash $T/build-dual-sim.sh $R/gen-dual-fast/RD2Harness.RD2DualXv6FastConfig.v $RTL $R/sim-dual-fast 2>&1 | tail -1
echo "== $(t) SMOKE1_DONE"
