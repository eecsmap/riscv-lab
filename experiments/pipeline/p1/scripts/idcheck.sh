# PIPE-P1 identity gate (sourced by build-sims.sh and selftest-idcheck.sh).
#   idcheck <label> <expected-error-regex> <verilator args...>
# A wrong implementation selection must FAIL TO BUILD, and fail for the named reason. Counted in ID_FAILS:
#   the build succeeded                 -> the selection silently fell back (the sims-1 finding)
#   rc 124                              -> a timeout proves nothing
#   non-zero without the expected error -> it failed for an unrelated reason
# Needs: $VL (the verilator command), $IDOUT (a scratch directory for logs).
ID_FAILS=0
idcheck() {
  local label=$1 rx=$2; shift 2
  local log=$IDOUT/id-$label.log
  timeout 900 $VL -Mdir $IDOUT/id-$label.obj -o tcpu_tb "$@" > $log 2>&1; local rc=$?
  rm -rf $IDOUT/id-$label.obj
  if [ $rc = 0 ]; then echo "IDFAIL $label: the build SUCCEEDED; a wrong selection must not build"; ID_FAILS=$((ID_FAILS+1))
  elif [ $rc = 124 ]; then echo "IDFAIL $label: timed out"; ID_FAILS=$((ID_FAILS+1))
  elif ! grep -qE "$rx" $log; then echo "IDFAIL $label: rc=$rc but not for the expected reason; first error: $(grep -m1 '%Error' $log | cut -c1-160)"; ID_FAILS=$((ID_FAILS+1))
  else echo "IDOK   $label: rc=$rc, $(grep -m1 -E "$rx" $log | sed 's#.*%Error#%Error#' | cut -c1-160)"; fi
}
