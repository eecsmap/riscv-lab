#!/usr/bin/env bash
# M3 phase 2: the SAME software (kernel-prod, fs-prod) on the single-core simulator (NUM_CORES=1), same workload
set -u; M3=/home/engineer/fpga/experiments/multicore/m3; T=$M3/tests; R=$M3/runs; O=$M3/sw/out
echo "== $(date -u +%FT%TZ) single-core xv6, workload m3dual =="; bash $T/run-xv6.sh $R/sim-single/obj_dir/sim $O/kernel-prod $O/fs-prod.img m3dual $R/single-m3 2000000000 5400 3000 2>&1 | tail -6
echo "== $(date -u +%FT%TZ) PHASE2_DONE"
