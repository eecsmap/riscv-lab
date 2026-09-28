#!/usr/bin/env bash
# MC-M2a: every dual-hart scenario through dual-run.sh, from the PRIVATE common. Positives must exit 0 from
# the simulator AND score clean; negatives are detected ONLY by their declared signature (a crash, a timeout
# or a missing FINISHED is never a detection), and each negative's fault-free twin is in the positive list, so
# "activated" is proven by the pair. Infrastructure failures fail the entry point and never count as defects.
#   dual-all.sh <outroot> [group]      group: directed | kill | random | topo | neg | all (default)
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); M2=$(dirname "$HERE"); GC=${GC:-$M2/gen/common-dual}   # GC= overrides (the old-backend reproduction)
OUT=$(readlink -f -m "${1:?outroot}"); GROUP=${2:-all}; mkdir -p "$OUT"
infra=0; bad=0; n=0
# one <name> <Config> <ntx> <lat> <ast> <mgrd> <resp> <dq01> <want: 0 | neg:<regex>> <score2 flags...>
one() { local name=$1 cfg=$2 ntx=$3 lat=$4 ast=$5 mgd=$6 resp=$7 dq=$8 want=$9; shift 9; local flags="$*"; n=$((n+1))
  bash $HERE/dual-run.sh $GC $OUT $name $cfg $ntx $lat $ast $mgd $resp $dq $flags > $OUT/$name.line 2>&1; local rc=$?
  local d=$OUT/$name; local v; v=$(cat $d/verdict.txt 2>/dev/null || tail -1 $OUT/$name.line)
  printf "  %-24s %s\n" "$name" "$(echo "$v" | cut -c1-190)"
  case "$v" in *INFRA*|*TIMEOUT*) infra=$((infra+1)); return;; esac
  if [ "$want" = 0 ]; then
    if [ $rc -ne 0 ]; then bad=$((bad+1)); grep FAIL $d/score.txt | head -3 | cut -c1-170 | sed 's/^/      /'; [ "$(cat $d/exit.txt)" = 0 ] || echo "      -> sim exit $(cat $d/exit.txt)"; fi
  else
    local sig=${want#neg:}
    if grep -qE "$sig" $d/score.txt $d/run.log; then echo "      -> rejected by the declared check: $(grep -hm1 -E "$sig" $d/score.txt $d/run.log | cut -c1-150)"
    else echo "      -> NOT rejected by the declared check ($sig)"; bad=$((bad+1)); fi
    grep -q FINISHED $d/run.log || echo "      (no FINISHED: the run aborted; detection is by signature only)"
  fi }
if [ $GROUP = directed ] || [ $GROUP = all ]; then echo "== directed (the TESTPLAN T2.5 list) =="
one d01-lrsc-race   Dual01LrScRaceConfig        12 4 0 0 0 0 0 --min-scok0 1 --min-scfail1 1 --min-kills 1
one d02-store-kills Dual02StoreKillsConfig      10 4 0 0 0 0 0 --min-scfail0 1 --min-kills 1
one d03-granules    Dual03GranulesConfig        12 4 0 0 0 0 0 --min-scok0 1 --min-scok1 1
one d05-trap-local  Dual05TrapLocalConfig       12 4 0 0 0 0 0 --min-scfail0 1 --min-scok1 1
one d06-dma-kills   Dual06DmaKillsConfig        12 4 0 0 0 0 0 --min-ext 1 --min-kills 1 --min-scfail0 1 --min-scok1 1
one d07-partial     Dual07PartialKillsConfig    10 4 0 0 0 0 0 --min-kills 1 --min-scfail0 1
one d08-failed-sc   Dual08FailedScHarmlessConfig 10 4 0 0 0 0 0 --min-scfail1 1 --min-scok0 1
one d09-paths       Dual09PathsConfig           40 4 0 0 0 0 0 --expect-refuse 1 --expect-wrefuse 1 --min-illegal 3 --min-scfail 3 --min-scok 3 --min-amo 2
one d10-amo-contend Dual10AmoContendConfig      42 6 3 0 0 0 0 --min-amo 27 --min-amo 27
one d11-drain       Dual11DrainConfig           20 8 0 0 0 0 0 --drain --min-amo 4
one d12-fair        Dual12FairConfig           160 6 2 2 0 0 0 --min-amo 60 --dmax 20
fi
# activation evidence for d17: hart 0's trap (its resvClear) and the external write must land in the SAME
# backend cycle, otherwise the "two reasons in one cycle" case was not exercised
same_cycle() { local d=$OUT/$1; local t a; t=$(grep -E "CPU_TRAP hart=0" $d/run.log | awk '{print $2}' | head -1); a=$(grep -E "A_ACC src=.* cpu=0 " $d/run.log | awk '{print $2}' | head -1)
  if [ -n "$t" ] && [ "$t" = "$a" ]; then echo "      activation: hart 0's trap and the external write accepted in the same cycle ($t)"
  else echo "      NOT ACTIVATED: trap at cycle '$t', external write accepted at '$a'"; bad=$((bad+1)); fi; }
if [ $GROUP = kill ] || [ $GROUP = all ]; then echo "== simultaneous kills (codex-mc-m2a-simultaneous-kill-fix): several valid reservations cleared in one cycle; exact counts; both crossbar orders =="
for sw in "" Swap; do sfx=""; [ -n "$sw" ] && sfx="-swap"
one d13-ext-kills-both$sfx      Dual13ExtKillsBoth${sw}Config       12 4 0 0 0 0 0 --expect-kills 2 --expect-scfail 2 --expect-scok 0 --min-ext 1
one d14-partial-kills-both$sfx  Dual14PartialKillsBoth${sw}Config   12 4 0 0 0 0 0 --expect-kills 2 --expect-scfail 2 --expect-scok 0 --min-ext 1
one d15-clear-both$sfx          Dual15ClearBoth${sw}Config          12 4 0 0 0 0 0 --expect-kills 2 --expect-scfail 2 --expect-scok 0
one d16-twobeat-both$sfx        Dual16TwoBeatBoth${sw}Config        12 4 0 0 0 0 0 --expect-kills 2 --expect-scfail 2 --expect-scok 0 --min-ext 1
one d17-same-hart-two-reasons$sfx Dual17SameHartTwoReasons${sw}Config 12 4 0 0 0 0 0 --expect-kills 1 --expect-scfail 1 --expect-scok 1 --min-ext 1
same_cycle d17-same-hart-two-reasons$sfx
done
fi
if [ $GROUP = random ] || [ $GROUP = all ]; then echo "== random (seeds 1-10, ~6000 CPU steps per hart, ext writers, backpressure varied by seed) =="
for s in 1 2 3 4 5 6 7 8 9 10; do lat=$((2 + s % 5)); ast=$((s % 3)); mds=$((s / 2 % 3)); dq=$((s % 2)); resp=$((s % 4 + 1))
  one rnd$s DualRnd${s}Config 13500 $lat $ast $mds $resp $dq 0 --min-tx 10000 --min-scok 50 --min-scfail 100 --min-amo 500 --min-kills 50 --min-ext 100 --dmax $((lat + ast + mds + 12)); done
fi
if [ $GROUP = topo ] || [ $GROUP = all ]; then echo "== topology variants of seed 1 (bridge order swapped at the crossbar; a third external master) =="
one rnd1-swap       DualRnd1SwapConfig      13500 3 1 0 2 1 0 --min-tx 10000 --min-scok 50 --min-scfail 100 --min-amo 500 --min-kills 50 --min-ext 100
one rnd1-extra      DualRnd1ExtraConfig     14200 3 1 0 2 1 0 --min-tx 10000 --min-scok 50 --min-scfail 100 --min-amo 500 --min-kills 50 --min-ext 150
one rnd1-swap-extra DualRnd1SwapExtraConfig 14200 3 1 0 2 1 0 --min-tx 10000 --min-scok 50 --min-scfail 100 --min-amo 500 --min-kills 50 --min-ext 150
fi
if [ $GROUP = neg ] || [ $GROUP = all ]; then echo "== negatives (DUT fault knobs; twin positive above proves the scenario reaches the checked event) =="
one neg-no-cross-kill  DualNegNoCrossKillConfig  10 4 0 0 0 0 "neg:SC result scfail=0, model says 1|scFail=0, model says 1" --min-kills 1
# crossed sidebands: hart 0's LR/SC marks land in hart 1's queue -- the scorer sees hart 1's LR classified as a
# plain read, and the backend's own assertion fires when a second mark is pushed while one is pending
one neg-swap-sideband  DualNegSwapSidebandConfig 12 4 0 0 0 0 "neg:is a (lr|sc) but the backend classified kind=|mark pushed while one is pending"
# a synthesised D sent with the other hart's source: the scorer's routing check when that hart has a transaction
# in flight, otherwise the inner-edge TLMonitor ("'D' channel acknowledged for nothing inflight"); both are checks
one neg-swap-dsource   DualNegSwapDSourceConfig  42 6 3 0 0 0 "neg:misrouted response|D. channel acknowledged for nothing inflight"
one neg-interleave     DualNegInterleaveConfig  900 4 0 1 0 0 "neg:between an AMO's Get and its Put|admitted a write between"
one neg-tl-withdraw    DualNegTlWithdrawConfig   42 6 3 0 0 0 "neg:VIOLATION tl A withdrawn hart=0"
one neg-phys-withdraw  DualNegPhysWithdrawConfig 12 4 0 0 0 0 "neg:VIOLATION phys request withdrawn hart=0"
one neg-wrong-src      DualNegWrongSrcConfig     12 4 0 0 0 0 "neg:attributed source|classified source|bound to no hart|no CPU_SOURCE"
one neg-no-kill        DualNegNoKillConfig       12 4 0 0 0 0 "neg:SC result scfail=0, model says 1|scFail=0, model says 1" --min-ext 1
fi
echo "DUAL_ALL_DONE group=$GROUP scenarios=$n infra=$infra bad=$bad"; [ $infra -eq 0 ] && [ $bad -eq 0 ]
