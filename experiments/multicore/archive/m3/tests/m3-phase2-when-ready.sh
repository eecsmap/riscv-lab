#!/usr/bin/env bash
# wait for phase 1 (the dual run) to finish -- the production runner's host lock allows one host at a time --
# then run phase 2 (the same software on the single-core simulator)
set -u; M3=/home/engineer/fpga/experiments/multicore/m3
for i in $(seq 1 720); do L=$(ls -t /home/engineer/fpga/.coord/jobs/logs/mc-m3-phase1b-*.log | head -1); grep -q PHASE1_DONE $L && break; sleep 10; done
grep -q PHASE1_DONE $L || { echo "phase 1 did not finish within 2 h; not starting phase 2"; exit 1; }
[ -e /var/lock/teaching-fesvr.lock ] && { echo "host lock still present after phase 1: $(ls /var/lock/teaching-fesvr.lock)"; exit 1; }
bash $M3/tests/m3-phase2.sh
