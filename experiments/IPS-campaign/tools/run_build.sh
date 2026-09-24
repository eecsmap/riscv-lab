#!/usr/bin/env bash
# Synthesise and implement one campaign stage. Claims the vivado lease; bounded; every input re-hashed
# before Vivado is handed anything.
#
#   run_build.sh <stage-name> <build dir>
set -u
R=/home/engineer/fpga
V=/home/engineer/vivado-docker/vdocker
IMPL=$R/experiments/teaching-cpu/m4-build/run_impl.tcl
STAGE=${1:?usage: run_build.sh <stage> <build dir>}
A=${2:?build dir}
[ -f "$A/project.tcl" ] || { echo "REFUSE: $A/project.tcl is missing; run prep_build.sh first"; exit 2; }
[ -f "$IMPL" ] || { echo "REFUSE: $IMPL is missing"; exit 2; }

echo "== re-hashing every manifest input before Vivado sees any of it"
bad=0
while IFS=$'\t' read -r role sha size path rest; do
  [ -z "${role:-}" ] && continue
  got=$(sha256sum "$path" 2>/dev/null | cut -d' ' -f1)
  [ "$got" = "$sha" ] || { echo "  MISMATCH $role $path"; bad=1; }
done < "$A/board-inputs.tsv"
[ $bad = 0 ] || { echo "REFUSE: the manifest and the files disagree"; exit 2; }
echo "  all inputs match the manifest"

( cd $R && ./coord claim vivado ) >/dev/null 2>&1 || { echo "REFUSE: the vivado lease was not granted"; exit 2; }
trap '( cd $R && ./coord release vivado ) >/dev/null 2>&1' EXIT
echo "  vivado lease claimed"

mkdir -p "$A/reports"
echo "== environment (this build's OWN banner, not a remembered one)"
$V run "vivado -version" > "$A/environment.txt" 2>&1
head -3 "$A/environment.txt" | sed 's/^/  /'

echo "== create project"
$V run "cd $A && vivado -mode batch -nojournal -log $A/vivado-create.log -source $A/project.tcl" > "$A/create.out" 2>&1
rc=$?; echo "  create exit=$rc"
grep -E "^(PROJECT_CREATED|ERROR:)" "$A/create.out" | head -3 | sed 's/^/  /'
[ $rc -ne 0 ] && { echo "IPS_BUILD_FAIL_CREATE $STAGE"; exit 1; }
XPR=$(find "$A/vivado-project" -name "*.xpr" | head -1)
[ -n "$XPR" ] || { echo "IPS_BUILD_FAIL_NOXPR $STAGE"; exit 1; }

echo "== synthesis + implementation + bitstream"
$V run "cd $A && vivado -mode batch -nojournal -log $A/vivado-impl.log -source $IMPL -tclargs $XPR $A/reports 3" > "$A/impl.out" 2>&1
rc=$?; echo "  impl exit=$rc"
grep -E "WNS|IMPL_|ERROR:" "$A/impl.out" | head -10 | sed 's/^/  /'
echo "IPS_BUILD_DONE $STAGE rc=$rc"
exit $rc
