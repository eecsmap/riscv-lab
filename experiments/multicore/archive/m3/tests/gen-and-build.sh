#!/usr/bin/env bash
# M3: generate the dual and single-core FAST configurations from the m3 private common and build their simulators
set -u; M3=/home/engineer/fpga/experiments/multicore/m3; T=$M3/tests; R=$M3/runs; RTL=/home/engineer/fpga/worktrees/mc-dual-xv6/rtl/cpu; GC=$M3/gen/common-xv6
t() { date -u +%FT%TZ; }
for c in RD2DualXv6FastConfig RD2AtomicXv6FastConfig; do echo "== $(t) gen $c =="; TOPPROJ=teaching bash $M3/gen/gen.sh RD2Harness $c $GC $R/gen-$c | tail -1; done
echo "== $(t) build dual sim =="; NHARTS=2 bash $T/build-xv6-dual-sim.sh $R/gen-RD2DualXv6FastConfig/RD2Harness.RD2DualXv6FastConfig.v $RTL $R/sim-dual | tail -1
echo "== $(t) build single sim =="; NHARTS=1 bash $T/build-xv6-dual-sim.sh $R/gen-RD2AtomicXv6FastConfig/RD2Harness.RD2AtomicXv6FastConfig.v $RTL $R/sim-single | tail -1
echo "== $(t) GEN_BUILD_DONE"
