#!/bin/bash
# PIPE-P4a runner-exit self-test (codex-pipe-p4a-runner-exit-fix). No real build: the verilator command and every
# chain step are replaced by stubs that LEAVE AN EXECUTABLE and then exit with a chosen status. Required:
#   a non-zero producer/build status never becomes an overall success (even with the executable present);
#   successful stubs still succeed.
#   selftest-runners.sh <gen dir (inputs only; nothing is written there)>
set -u
S=$(cd "$(dirname "$0")" && pwd); P2=$S/../../p2b/soc; GEN=$(readlink -f ${1:?gen dir}); T=$(mktemp -d /tmp/claude-1000/p4a-rst-XXXX)
RTL=/home/engineer/fpga/worktrees/pipe-dual/rtl/cpu; bad=0; n=0
# a verilator stand-in: create <Mdir>/sim (executable), exit $STUB_RC
cat > $T/verilator-stub <<'ST'
#!/bin/bash
while [ $# -gt 0 ]; do [ "$1" = -Mdir ] && { mkdir -p "$2"; printf '#!/bin/sh\nexit 0\n' > "$2/sim"; chmod +x "$2/sim"; }; shift; done
exit ${STUB_RC:-0}
ST
# a builder stand-in: create <arg3>/obj_dir/sim, exit $STUB_RC unless the output dir matches $STUB_FAIL_ON
cat > $T/builder-stub <<'ST'
#!/bin/bash
out=$3; [ -n "${STUB_NHARTS_CHECK:-}" ] && true; mkdir -p "$out/obj_dir"; printf '#!/bin/sh\nexit 0\n' > "$out/obj_dir/sim"; chmod +x "$out/obj_dir/sim"
case "$out" in *${STUB_FAIL_ON:-__never__}*) echo "stub build FAILED for $out"; exit 1;; esac; echo "stub build ok $out"; exit 0
ST
cat > $T/step-stub <<'ST'
#!/bin/bash
for a in "$@"; do case "$a" in *${STUB_FAIL_ON:-__never__}*) echo "stub step FAILED ($a)"; exit 1;; esac; done; echo "stub step ok"; exit 0
ST
chmod +x $T/verilator-stub $T/builder-stub $T/step-stub
expect() {  # expect <want 0|nonzero> <label> <command...>
  local want=$1 lab=$2; shift 2; n=$((n+1)); "$@" > $T/out.$n 2>&1; local r=$?
  local ok=0; { [ $want = 0 ] && [ $r = 0 ]; } && ok=1; { [ $want = nonzero ] && [ $r != 0 ]; } && ok=1
  printf "  %-4s %-62s exit %s (wanted %s)\n" "$([ $ok = 1 ] && echo ok || echo BAD)" "$lab" $r $want; [ $ok = 1 ] || { bad=$((bad+1)); tail -n 3 $T/out.$n | sed 's/^/        /'; }; }
VF=$GEN/after-RD2PipeDualXv6FastConfig/RD2Harness.RD2PipeDualXv6FastConfig.v; VB=$GEN/after-RD2PipeDualBootConfig/RD2Harness.RD2PipeDualBootConfig.v
V1=$GEN/after-RD2PipeXv6FastConfig/RD2Harness.RD2PipeXv6FastConfig.v
echo "== the build scripts: verilator status 1 with an executable left behind must FAIL; status 0 must pass"
for rc in 1 0; do w=nonzero; [ $rc = 0 ] && w=0
  expect $w "p4a build-rd2-pipe-sim.sh, verilator exit $rc" env VERILATOR=$T/verilator-stub STUB_RC=$rc NHARTS=2 bash $S/build-rd2-pipe-sim.sh $VF $RTL $T/b1-$rc
  expect $w "p4a build-assoc-dual.sh, verilator exit $rc" env VERILATOR=$T/verilator-stub STUB_RC=$rc bash $S/build-assoc-dual.sh $VB $RTL $T/b2-$rc
  expect $w "p2b build-assoc-sim.sh, verilator exit $rc" env VERILATOR=$T/verilator-stub STUB_RC=$rc bash $P2/assoc/build-assoc-sim.sh $GEN $RTL $T/b3-$rc
  expect $w "p2b build-rd2-pipe-sim.sh, verilator exit $rc" env VERILATOR=$T/verilator-stub STUB_RC=$rc bash $P2/build-rd2-pipe-sim.sh $V1 $RTL $T/b4-$rc
done
echo "== chain-sims.sh: one builder fails (its executable present) -> the chain FAILS; all succeed -> passes"
expect nonzero "chain-sims, sim-fast builder fails" env BUILD_SIM=$T/builder-stub BUILD_ASSOC=$T/builder-stub STUB_FAIL_ON=sim-fast bash $S/chain-sims.sh $GEN $T/c1
expect nonzero "chain-sims, a negative's builder fails" env BUILD_SIM=$T/builder-stub BUILD_ASSOC=$T/builder-stub STUB_FAIL_ON=sim-neg-pf4-h1 bash $S/chain-sims.sh $GEN $T/c2
expect 0 "chain-sims, all builders succeed" env BUILD_SIM=$T/builder-stub BUILD_ASSOC=$T/builder-stub bash $S/chain-sims.sh $GEN $T/c3
echo "== chain-xv6.sh: the single-pipeline BUILD fails (executable present) -> FAILS; one run fails -> FAILS; all ok -> passes"
expect nonzero "chain-xv6, single-assoc build fails" env RUN_XV6=$T/step-stub BUILD_ASSOC1=$T/builder-stub RUN_ASSOC=$T/step-stub STUB_FAIL_ON=single-assoc-sim bash $S/chain-xv6.sh $T/sims $GEN $T/x1
expect nonzero "chain-xv6, m4smoke fails" env RUN_XV6=$T/step-stub BUILD_ASSOC1=$T/builder-stub RUN_ASSOC=$T/step-stub STUB_FAIL_ON=xv6-m4smoke bash $S/chain-xv6.sh $T/sims $GEN $T/x2
expect 0 "chain-xv6, all steps succeed" env RUN_XV6=$T/step-stub BUILD_ASSOC1=$T/builder-stub RUN_ASSOC=$T/step-stub bash $S/chain-xv6.sh $T/sims $GEN $T/x3
echo "== run-dual-all.sh: an EARLIER group fails, the last passes -> overall FAILS; all pass -> passes"
expect nonzero "run-dual-all, group traced fails" env RUN_GROUP=$T/step-stub STUB_FAIL_ON=suite-traced bash $S/run-dual-all.sh $T/sims $T/g1
expect 0 "run-dual-all, all groups pass" env RUN_GROUP=$T/step-stub bash $S/run-dual-all.sh $T/sims $T/g2
rm -rf "${T:?}"
echo "SELFTEST_RUNNERS $([ $bad = 0 ] && echo PASS || echo FAIL) ($n cases, $bad bad)"; exit $bad
