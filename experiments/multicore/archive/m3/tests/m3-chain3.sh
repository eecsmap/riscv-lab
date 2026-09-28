#!/usr/bin/env bash
# M3 remaining runs, same software identity as dual-a (sw/out kernel-prod df05b6e4 / fs-prod cbb031e5): dual B, single A, single B
set -u; M3=/home/engineer/fpga/experiments/multicore/m3; T=$M3/tests; R=$M3/runs; O=$M3/sw/out
t() { date -u +%FT%TZ; }
run() { local sim=$1 wl=$2 out=$3; echo "== $(t) $out ($wl) =="; bash $T/run-xv6.sh $sim $O/kernel-prod $O/fs-prod.img $wl $R/$out 2000000000 5400 3000 2>&1 | tail -4; [ -e /var/lock/teaching-fesvr.lock ] && echo "  WARNING: host lock left behind: $(ls /var/lock/teaching-fesvr.lock)"; }
run $R/sim-dual/obj_dir/sim   m3dual-b dual-b
run $R/sim-single/obj_dir/sim m3dual-a single-a
run $R/sim-single/obj_dir/sim m3dual-b single-b
echo "== $(t) CHAIN3_DONE"
