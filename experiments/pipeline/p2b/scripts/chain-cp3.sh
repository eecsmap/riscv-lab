#!/bin/bash
# PIPE-P2b checkpoint 3 chain (one coord job): the full P2b run on sims-4, its guard self-test, then the P2a and P1
# regressions on the same tree, each compared section by section with the previous accepted run.
set -u
bad=0; ck() { [ "$1" = 0 ] || bad=1; }
W=/home/engineer/fpga/worktrees/pipe-single/experiments/pipeline
bash $W/p2b/scripts/run-p2b.sh $W/p2b/runs/sims-4 $W/p2b/runs/run-4 > $W/p2b/runs/run-4.log 2>&1; r=$?; ck $r; echo "RUN_P2B_RC=$r"; tail -3 $W/p2b/runs/run-4.log
python3 $W/p2b/scripts/selftest-p2b.py $W/p2b/runs/run-4 > $W/p2b/runs/selftest-run-4.txt 2>&1; r=$?; ck $r; echo "SELFTEST_P2B_RC=$r"; tail -1 $W/p2b/runs/selftest-run-4.txt
bash $W/p2a/scripts/build-p2a.sh $W/p2a/runs/sims-7 > $W/p2a/runs/sims-7.log 2>&1; r=$?; ck $r; echo "P2A_BUILD_RC=$r"; tail -1 $W/p2a/runs/sims-7.log
bash $W/p2a/scripts/run-p2a.sh $W/p2a/runs/sims-7 $W/p2a/runs/run-7 > $W/p2a/runs/run-7.log 2>&1; r=$?; ck $r; echo "RUN_P2A_RC=$r"; tail -1 $W/p2a/runs/run-7/verdict.txt
for f in A B C D F G; do cmp -s $W/p2a/runs/run-6/$f.txt $W/p2a/runs/run-7/$f.txt && echo "  P2a $f identical to run-6" || echo "  P2a $f DIFFERS from run-6"; done
diff <(sed 's#run-6#RUN#g' $W/p2a/runs/run-6/U.txt) <(sed 's#run-7#RUN#g' $W/p2a/runs/run-7/U.txt) > /dev/null && echo "  P2a U identical to run-6 apart from its path" || echo "  P2a U DIFFERS from run-6"
bash $W/p1/scripts/build-sims.sh $W/p1/runs/sims-12 > $W/p1/runs/sims-12.log 2>&1; r=$?; ck $r; echo "P1_BUILD_RC=$r"; tail -1 $W/p1/runs/sims-12.log
bash $W/p1/scripts/run-p1.sh $W/p1/runs/sims-12 $W/p1/runs/run-11 > $W/p1/runs/run-11.log 2>&1; r=$?; ck $r; echo "RUN_P1_RC=$r"; tail -1 $W/p1/runs/run-11/verdict.txt
for f in A B C D E F G; do cmp -s $W/p1/runs/run-10/$f.txt $W/p1/runs/run-11/$f.txt && echo "  P1 $f identical to run-10" || echo "  P1 $f DIFFERS from run-10"; done
diff <(sed 's#run-10#RUN#g' $W/p1/runs/run-10/H.txt) <(sed 's#run-11#RUN#g' $W/p1/runs/run-11/H.txt) > /dev/null && echo "  P1 H identical to run-10 apart from its path" || echo "  P1 H DIFFERS from run-10"
echo "CHAIN_CP3_DONE bad=$bad"; exit $bad
