#!/usr/bin/env bash
# M3 phase 1: the controlled HTIF input race (fixed kernel, then the negative build), then the full dual-core
# xv6 workload. Budgets: race runs 600 s each (they end at the banner + test line; the runner's prompt wait
# is capped at 120 s and is NOT the verdict), the dual workload 2e9 cycles / 5400 s wall / 3000 s per stage.
set -u; M3=/home/engineer/fpga/experiments/multicore/m3; T=$M3/tests; R=$M3/runs; O=$M3/sw/out; SIM=$R/sim-dual/obj_dir/sim
t() { date -u +%FT%TZ; }
bash $T/m3-race.sh 2>&1 | tail -6
echo "== $(t) dual xv6, workload m3dual =="; bash $T/run-xv6.sh $SIM $O/kernel-prod $O/fs-prod.img m3dual $R/dual-m3 2000000000 5400 3000 2>&1 | tail -6
echo "== $(t) PHASE1_DONE"
