#!/bin/bash
# PIPE-P4b: can the adapted (two-hart) validators fail? Each mutant must be refused for its own reason.
#   selftest-validators.sh <pre-vivado attempt dir> <gen-p3 dir>
set -u
A=$(readlink -f ${1:?attempt}); G=$(readlink -f ${2:?gen dir}); T=$(cd "$(dirname "$0")/../tools" && pwd)
M=/home/engineer/fpga/worktrees/pipe-dual/rtl/cpu; ROM=/home/engineer/fpga/experiments/multicore/m4/gen/gen-RD2DualBoardConfig/rom_from_rtl.bin
BRD=$G/gen/after-RD2PipeDualBoardConfig/RD2BoardTop.RD2PipeDualBoardConfig.v; S=$(mktemp -d /tmp/claude-1000/p3st-XXXX); bad=0
t() { local name=$1 rx=$2; shift 2; local o; o=$("$@" 2>&1); local rc=$?
  if [ $rc != 0 ] && echo "$o" | grep -qE "$rx"; then echo "  refused  $name: $(echo "$o" | grep -m1 -E "$rx" | sed 's/^ *//' | cut -c1-110)"
  else echo "  ACCEPTED $name (rc=$rc)"; bad=1; fi; }
python3 $T/check-hierarchy-p4b.py $A/source-MANIFEST.txt > /dev/null && echo "  unmutated hierarchy: pass" || { echo "  unmutated hierarchy FAILS"; bad=1; }
python3 $T/audit-board-rtl-p4b.py $BRD --rtl-dir $A/inputs/rtl --rom $ROM > /dev/null && echo "  unmutated audit: pass" || { echo "  unmutated audit FAILS"; bad=1; }
t "hierarchy + the multicycle tcpu_core.v" "multicycle module tcpu_core present" python3 $T/check-hierarchy-p4b.py $A/source-MANIFEST.txt --add $M/tcpu_core.v
t "hierarchy - tcpu_tlb2.v" "unresolved tcpu_tlb2" python3 $T/check-hierarchy-p4b.py $A/source-MANIFEST.txt --drop $A/inputs/rtl/tcpu_tlb2.v
t "audit on the multicycle DUAL board RTL" "tcpu_core present" python3 $T/audit-board-rtl-p4b.py $G/gen/after-RD2DualBoardConfig/RD2BoardTop.RD2DualBoardConfig.v --rtl-dir $A/inputs/rtl --rom $ROM
sed -E 's/^(\s*tcpu_core_pipe #\()/\1.PIPE_FAULT(4), /' $BRD > $S/pf.v
t "audit with .PIPE_FAULT(4) passed" "extra parameter passed" python3 $T/audit-board-rtl-p4b.py $S/pf.v --rtl-dir $A/inputs/rtl --rom $ROM
sed -E 's/\.PIPE_EXT_C\(1\)/.PIPE_EXT_C(0)/' $BRD > $S/nc.v
t "audit with PIPE_EXT_C(0)" "PIPE_EXT_C = 0" python3 $T/audit-board-rtl-p4b.py $S/nc.v --rtl-dir $A/inputs/rtl --rom $ROM
sed -E 's/\.HART_ID\(1\)/.HART_ID(0)/' $BRD > $S/h00.v
t "audit with both harts HART_ID(0)" "HART_ID" python3 $T/audit-board-rtl-p4b.py $S/h00.v --rtl-dir $A/inputs/rtl --rom $ROM
mkdir $S/kd; cp $A/inputs/rtl/* $S/kd/; sed -i -E '0,/parameter +PIPE_FAULT = 0/s//parameter        PIPE_FAULT = 4/' $S/kd/tcpu_core_pipe.v
t "audit with a PIPE_FAULT default of 4" "non-zero fault default" python3 $T/audit-board-rtl-p4b.py $BRD --rtl-dir $S/kd --rom $ROM
rm -rf "${S:?}"
echo "SELFTEST_VALIDATORS $([ $bad = 0 ] && echo PASS || echo FAIL)"; exit $bad
