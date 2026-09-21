#!/usr/bin/env bash
# The pre-Vivado build entry for the atomic teaching board.
#
# Why this exists rather than reusing m4-build/build.sh: that script hardcodes the OLD validators at its
# lines 40 and 44 -- m4-prep/scripts/check-hierarchy.py and audit-board-rtl.py -- and both of them fail on
# this design (the first expects a `TeachingBoardTop` chain of three black boxes, the second matches the CPU
# with `tcpu_core #(.RESET_PC(n))`, which cannot match once MISA_A is also passed). Writing adapted copies
# did not wire them in; this does. The accepted build chain is left exactly as it is.
#
#   build-atomic.sh <attempt-dir> [--with-vivado]
#
# Without --with-vivado it stops before any Vivado invocation and says so. That is the supported mode here:
# this task does not authorise synthesis.
set -uo pipefail
ROOT=/home/engineer/fpga
X=$ROOT/experiments/teaching-cpu/xv6-board-prep
M4P=$ROOT/experiments/teaching-cpu/m4-prep
BI=${BUILD_INPUTS:-$X/build-inputs}
A=${1:?usage: build-atomic.sh <attempt-dir> [--with-vivado]}
WITH_VIVADO=${2:-}
[ -e "$A" ] && { echo "REFUSE: $A exists; use a new attempt directory"; exit 2; }
mkdir -p "$A"
JOBS=${JOBS:-10}
IMG=${VIVADO_IMAGE:-vivado-env:2025.2}
log() { printf '=== %s\n' "$*"; }

log "1. sealing the inputs this build uses"
cp "$BI/MANIFEST.txt" "$A/source-MANIFEST.txt"
cp "$BI/teaching_top_shim.v" "$A/teaching_top_shim.v"
python3 - "$A/source-MANIFEST.txt" <<'PY' || { echo "REFUSE: sealed manifest does not verify"; exit 3; }
import sys, hashlib, os
bad = 0; n = 0
for line in open(sys.argv[1]):
    if line.startswith("#") or not line.strip(): continue
    role, sha, size, path, *_ = line.rstrip("\n").split("\t"); n += 1
    if not os.path.isfile(path) or hashlib.sha256(open(path, 'rb').read()).hexdigest() != sha:
        print(f"  CHANGED/MISSING {path}"); bad += 1
print(f"  {n} sealed sources, {bad} problem(s)")
sys.exit(1 if bad else 0)
PY

log "2. the build scripts themselves, so provenance covers the tooling and not only the sources"
for f in "$X/scripts/build-atomic.sh" "$X/scripts/check-hierarchy-atomic.py" \
         "$X/scripts/audit-board-rtl-atomic.py" "$X/scripts/make-build-manifest-atomic.py" \
         "$X/scripts/make-top-shim-atomic.py" "$M4P/scripts/gen-project-tcl.py" \
         "$M4P/scripts/check-tcl.tcl"; do
  sha256sum "$f"
done > "$A/tooling-hashes.txt"
sed 's/^/  /' "$A/tooling-hashes.txt"

log "3. generating the project script that will actually be executed"
python3 "$M4P/scripts/gen-project-tcl.py" "$A/source-MANIFEST.txt" "$A/project.tcl" \
        --project-dir "$A/project" || exit 3
if command -v tclsh >/dev/null; then
  tclsh "$M4P/scripts/check-tcl.tcl" "$A/project.tcl" || exit 3
else
  VIVADO_IMAGE=vivado-env:2025.2-sw /home/engineer/vivado-docker/vdocker run \
    "tclsh $M4P/scripts/check-tcl.tcl $A/project.tcl" || exit 3
fi

log "4. the ADAPTED validators"
python3 "$X/scripts/check-hierarchy-atomic.py" "$A/source-MANIFEST.txt" > "$A/hierarchy.txt" 2>&1 || \
  { echo "REFUSE: the hierarchy does not close"; tail -3 "$A/hierarchy.txt"; exit 3; }
tail -1 "$A/hierarchy.txt"
RTL=$(awk -F'\t' '$1=="board-rtl"{print $4}' "$A/source-MANIFEST.txt")
python3 "$X/scripts/audit-board-rtl-atomic.py" "$RTL" --rom "$(dirname "$RTL")/rom_from_rtl.bin" \
        > "$A/board-rtl-audit.txt" 2>&1 || { echo "REFUSE: the board RTL audit fails"; tail -2 "$A/board-rtl-audit.txt"; exit 3; }
tail -1 "$A/board-rtl-audit.txt"

log "5. recording the inputs"
for f in $(awk -F'\t' '!/^#/{print $4}' "$A/source-MANIFEST.txt"); do sha256sum "$f"; done > "$A/input-hashes.txt"
echo "  $(wc -l < "$A/input-hashes.txt") input hashes recorded"

if [ "$WITH_VIVADO" != "--with-vivado" ]; then
  log "STOPPING BEFORE VIVADO"
  echo "  Everything above is offline. Synthesis and implementation are a separate, explicitly"
  echo "  authorised step; re-run with --with-vivado once that authorisation exists."
  echo "BUILD_ATOMIC_PREVIVADO_OK $A"
  exit 0
fi

# ---- Authorised by codex-xv6-atomic-vivado-build. The flow below is the accepted one: the same project
# script generator and the same run_impl.tcl the validated build used. What differs is the manifest, the
# shim, the board RTL and the two adapted validators -- which is the whole point of the isolation. The old
# chain in m4-build/build.sh is not modified.
log "6. recording the environment"
{ echo "date: $(date -u +%FT%TZ)"; echo "image: $IMG"; echo "jobs: $JOBS"; echo "host nproc: $(nproc)"; } > "$A/environment.txt"
VIVADO_IMAGE=$IMG /home/engineer/vivado-docker/vdocker run "vivado -version; echo ---; ls -d /opt/Xilinx/*/Vivado" \
  >> "$A/environment.txt" 2>&1
grep -m2 -E "^Vivado|^Tool Version" "$A/environment.txt" | sed 's/^/  /'

log "7. creating the project (vivado, batch)"
VIVADO_IMAGE=$IMG /home/engineer/vivado-docker/vdocker run \
  "cd $A && vivado -mode batch -nojournal -log $A/vivado-create.log -source $A/project.tcl" \
  > "$A/create-project.out" 2>&1
rc=$?
echo "  vivado create exit=$rc"
grep -E "^(PROJECT_CREATED|PASS|FAIL|REFUSE|ERROR:)" "$A/create-project.out" | head -5 | sed 's/^/  /'
if [ $rc -ne 0 ] || ! grep -q "PROJECT_CREATED" "$A/create-project.out"; then
  echo "BUILD_FAILED at project creation (exit $rc)"; exit 4
fi

log "8. synthesis, implementation and bitstream"
VIVADO_IMAGE=$IMG /home/engineer/vivado-docker/vdocker run \
  "cd $A && vivado -mode batch -nojournal -log $A/vivado-impl.log -source $ROOT/experiments/teaching-cpu/m4-build/run_impl.tcl -tclargs $A/project/teaching_pynqz1.xpr $A/reports $JOBS" \
  > "$A/impl.out" 2>&1
rc=$?
echo "  vivado impl exit=$rc"
grep -E "^@@@" "$A/impl.out" | tail -12 | sed 's/^/  /'
if [ $rc -ne 0 ] || ! grep -q "BUILD_OK" "$A/impl.out"; then
  echo "BUILD_FAILED during synthesis/implementation (exit $rc)"
  grep -E "^ERROR:|^CRITICAL WARNING:" "$A/impl.out" | head -10 | sed 's/^/  /'
  exit 5
fi
log "done: $A"
[ -f "$A/reports/run-status.txt" ] && sed 's/^/  /' "$A/reports/run-status.txt"
echo "BUILD_ATOMIC_OK $A"
