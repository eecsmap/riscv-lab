#!/usr/bin/env bash
# PIPE-P2b association gate (codex-pipe-p2b-retirement-association), one coord job:
#   positive  gen-3 RD2PipeBootConfig (the delivered wrapper) + the checker: every directed run clean
#   NEG-OLD   gen-2 RD2PipeBootConfig (the wrapper before 0b225e0: isFetch = dbg_req_is_fetch only) + the same checker:
#             on Sv39 programs the FIRST checker failure must be `classify` (a PTE response published as data), and a
#             `soc-register` failure must follow (RD2Soc's awaitingRetire set by it)
#   NEG-PF4   gen-3 with the core's knob 4 STORE_UNDER_TRAP (a data request raised in the cycle an older instruction
#             traps; the requester is flushed and never retires) on p1_store_trap: the FIRST failure must be
#             `association`: on p1_store_trap (whose handler starts with a load) as a requester that never retires
#             before the next data response; on p2b_assoc_trap (whose handler starts with ALU instructions) as the
#             pending data response cleared by an unrelated retirement
#   chain-assoc.sh <fresh outroot>
set -u
W=/home/engineer/fpga/worktrees/pipe-single; P=$W/experiments/pipeline/p2b; A=$P/soc/assoc
OUT=${1:?outroot}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p $OUT
bad=0
bash $A/build-assoc-sim.sh $P/runs/gen-3 $W/rtl/cpu $OUT/sim-pos || bad=1
bash $A/build-assoc-sim.sh $P/runs/gen-2 $W/rtl/cpu $OUT/sim-neg-old || bad=1
bash $A/build-assoc-sim.sh $P/runs/gen-3 $W/rtl/cpu $OUT/sim-neg-pf4 4 || bad=1
[ $bad = 0 ] || { echo "CHAIN_ASSOC build failure"; exit 1; }
echo "== positive"; bash $A/run-assoc.sh $OUT/sim-pos/obj_dir/sim $OUT/run-pos; r=$?; [ $r = 0 ] || bad=1
neg() {  # neg <label> <sim> <programs> <first-check> [following check] [regex the first failure must match]
  local l=$1 sim=$2 progs=$3 want=$4 then=${5:-} rx=${6:-}
  echo "== $l (programs: $progs; the first failure must be '$want'${then:+, followed by '$then'})"
  bash $A/run-assoc.sh $sim $OUT/run-$l "$progs" > $OUT/run-$l.txt 2>&1
  local caught=0
  for p in $progs; do
    local lg=$OUT/run-$l/logs/$p.log f; f=$(grep -m1 "^ASSOC FAIL" $lg | awk '{print $3}')
    local ok=0; [ "$f" = "$want" ] && ok=1
    [ -n "$rx" ] && ! grep -m1 "^ASSOC FAIL" $lg | grep -qE "$rx" && ok=0
    [ -n "$then" ] && ! grep -q "^ASSOC FAIL $then" $lg && ok=0
    [ $ok = 1 ] && caught=$((caught+1))
    printf "  %-13s first failure: %s  -> %s\n" $p "$(grep -m1 '^ASSOC FAIL' $lg | cut -c1-190)" "$([ $ok = 1 ] && echo caught as intended || echo NOT as intended)"
    [ -n "$then" ] && echo "                 $(grep -m1 "^ASSOC FAIL $then" $lg | cut -c1-190)"
  done
  [ $caught = $(echo $progs | wc -w) ] || bad=1
}
neg neg-old $OUT/sim-neg-old/obj_dir/sim "boot11 boot12 walk_preempt hzsv1" classify soc-register
neg neg-pf4 $OUT/sim-neg-pf4/obj_dir/sim "store_trap" association "" "never retired before the next data response"
neg neg-pf4b $OUT/sim-neg-pf4/obj_dir/sim "assoc_trap" association "" "the next retirement is a commit of"
echo "CHAIN_ASSOC_DONE bad=$bad"; exit $bad
