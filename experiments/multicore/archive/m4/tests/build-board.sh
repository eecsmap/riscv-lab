#!/usr/bin/env bash
# MC-M4: the dual-core board build, in an isolated attempt directory, with the ACCEPTED flow (xv6-board-prep's
# build-atomic.sh: sealed manifest -> adapted validators -> generated project Tcl -> m4-build/run_impl.tcl),
# differing only in the inputs (dual RD2BoardTop, the mc-dual-xv6 rtl/cpu set, a shim generated from the dual
# RTL) and in the two validators being the M4 copies (two harts). Nothing in the shared checkouts is written.
#   build-board.sh <attempt-dir> [--with-vivado]      (JOBS default 4)
set -uo pipefail
ROOT=/home/engineer/fpga; M4=$ROOT/experiments/multicore/m4; M4P=$ROOT/experiments/teaching-cpu/m4-prep; BI=$M4/build/inputs
A=${1:?usage: build-board.sh <attempt-dir> [--with-vivado]}; WITH_VIVADO=${2:-}
[ -e "$A" ] && { echo "REFUSE: $A exists; use a new attempt directory"; exit 2; }
mkdir -p "$A"; JOBS=${JOBS:-4}; IMG=${VIVADO_IMAGE:-vivado-env:2025.2}
log() { printf '=== %s\n' "$*"; }
log "1. sealing the inputs this build uses"
cp "$BI/MANIFEST.txt" "$A/source-MANIFEST.txt"; cp "$BI/teaching_top_shim.v" "$A/teaching_top_shim.v"
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
log "2. the build scripts themselves"
for f in "$M4/tests/build-board.sh" "$M4/tools/board-build/check-hierarchy-atomic.py" "$M4/tools/board-build/audit-board-rtl-atomic.py" \
         "$M4/tools/board-build/make-build-manifest-m4.py" "$M4/tools/board-build/make-top-shim-atomic.py" "$M4P/scripts/gen-project-tcl.py" \
         "$M4P/scripts/check-tcl.tcl" "$ROOT/experiments/teaching-cpu/m4-build/run_impl.tcl"; do sha256sum "$f"; done > "$A/tooling-hashes.txt"; sed 's/^/  /' "$A/tooling-hashes.txt" | cut -c1-120
log "3. generating the project script"
python3 "$M4P/scripts/gen-project-tcl.py" "$A/source-MANIFEST.txt" "$A/project.tcl" --project-dir "$A/project" || exit 3
# check-tcl.tcl is plain Tcl. No tclsh is installed on this host or in the images any more, so it runs under
# Vivado's own Tcl interpreter (batch mode, no project, no journal); the script's exit code is propagated.
VIVADO_IMAGE=$IMG /home/engineer/vivado-docker/vdocker run "cd $A && vivado -mode batch -nolog -nojournal -source $M4P/scripts/check-tcl.tcl -tclargs $A/project.tcl" > "$A/check-tcl.out" 2>&1; rc=$?
grep -E "TCL_CHECK|FAIL" "$A/check-tcl.out" | head -3 | sed 's/^/  /'; grep -q "TCL_CHECK fails=0" "$A/check-tcl.out" || { echo "REFUSE: check-tcl did not pass (exit $rc)"; exit 3; }
log "4. the M4 validators (two harts)"
python3 "$M4/tools/board-build/check-hierarchy-atomic.py" "$A/source-MANIFEST.txt" > "$A/hierarchy.txt" 2>&1 || { echo "REFUSE: the hierarchy does not close"; tail -3 "$A/hierarchy.txt"; exit 3; }
tail -1 "$A/hierarchy.txt"
RTL=$(awk -F'\t' '$1=="board-rtl"{print $4}' "$A/source-MANIFEST.txt")
python3 "$M4/tools/board-build/audit-board-rtl-atomic.py" "$RTL" --rom "$(dirname "$RTL")/rom_from_rtl.bin" > "$A/board-rtl-audit.txt" 2>&1 || { echo "REFUSE: the board RTL audit fails"; tail -2 "$A/board-rtl-audit.txt"; exit 3; }
tail -1 "$A/board-rtl-audit.txt"
log "5. recording the inputs"
for f in $(awk -F'\t' '!/^#/{print $4}' "$A/source-MANIFEST.txt"); do sha256sum "$f"; done > "$A/input-hashes.txt"; echo "  $(wc -l < "$A/input-hashes.txt") input hashes recorded"
if [ "$WITH_VIVADO" != "--with-vivado" ]; then log "STOPPING BEFORE VIVADO"; echo "BUILD_M4_PREVIVADO_OK $A"; exit 0; fi
log "6. recording the environment"
{ echo "date: $(date -u +%FT%TZ)"; echo "image: $IMG"; echo "jobs: $JOBS"; echo "host nproc: $(nproc)"; } > "$A/environment.txt"
VIVADO_IMAGE=$IMG /home/engineer/vivado-docker/vdocker run "vivado -version; echo ---; ls -d /opt/Xilinx/*/Vivado" >> "$A/environment.txt" 2>&1
grep -m2 -E "^Vivado|^Tool Version|^vivado" "$A/environment.txt" | sed 's/^/  /'
log "7. creating the project (vivado, batch)"; s=$(date +%s)
VIVADO_IMAGE=$IMG /home/engineer/vivado-docker/vdocker run "cd $A && vivado -mode batch -nojournal -log $A/vivado-create.log -source $A/project.tcl" > "$A/create-project.out" 2>&1; rc=$?
echo "  vivado create exit=$rc"; grep -E "^(PROJECT_CREATED|PASS|FAIL|REFUSE|ERROR:)" "$A/create-project.out" | head -5 | sed 's/^/  /'
if [ $rc -ne 0 ] || ! grep -q "PROJECT_CREATED" "$A/create-project.out"; then echo "BUILD_FAILED at project creation (exit $rc)"; exit 4; fi
log "8. synthesis, implementation and bitstream"
VIVADO_IMAGE=$IMG /home/engineer/vivado-docker/vdocker run "cd $A && vivado -mode batch -nojournal -log $A/vivado-impl.log -source $ROOT/experiments/teaching-cpu/m4-build/run_impl.tcl -tclargs $A/project/teaching_pynqz1.xpr $A/reports $JOBS" > "$A/impl.out" 2>&1; rc=$?
e=$(date +%s); echo "  vivado impl exit=$rc wall=$((e-s))s"; grep -E "^@@@" "$A/impl.out" | tail -12 | sed 's/^/  /'
if [ $rc -ne 0 ] || ! grep -q "BUILD_OK" "$A/impl.out"; then echo "BUILD_FAILED during synthesis/implementation (exit $rc)"; grep -E "^ERROR:|^CRITICAL WARNING:" "$A/impl.out" | head -10 | sed 's/^/  /'; exit 5; fi
[ -f "$A/reports/run-status.txt" ] && sed 's/^/  /' "$A/reports/run-status.txt"
echo "BUILD_M4_OK $A"
