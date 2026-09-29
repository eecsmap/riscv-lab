#!/usr/bin/env bash
# PIPE-P3a: the single-pipeline board build, in an isolated attempt directory, with the ACCEPTED M4 flow
# (m4-prep gen-project-tcl.py + check-tcl.tcl, the validators, then Vivado), differing in the inputs (the
# single-pipeline RD2BoardTop; the pipeline RTL of SOURCES.pipe extracted from a named commit; a shim generated
# from this RTL), the validators being the P3 copies (one pipeline hart, no multicycle module), and the impl script
# being the gated copy (bitstream only after the routed timing/DRC gate). Nothing is programmed.
#   build-board-p3.sh <attempt-dir> <rtl commit> <RD2BoardTop.RD2PipeBoardConfig.v> [--with-vivado]   (JOBS default 4)
set -uo pipefail
ROOT=/home/engineer/fpga; W=$ROOT/worktrees/pipe-single; P3=$W/experiments/pipeline/p3; M4P=$ROOT/experiments/teaching-cpu/m4-prep
A=${1:?attempt dir}; C=${2:?rtl commit}; BRTL=${3:?board rtl}; WITH_VIVADO=${4:-}
[ -e "$A" ] && { echo "REFUSE: $A exists; use a new attempt directory"; exit 2; }
[ -s "$BRTL" ] || { echo "REFUSE: no board RTL $BRTL"; exit 2; }
mkdir -p "$A/inputs/rtl" "$A/inputs/inc"; JOBS=${JOBS:-4}; IMG=${VIVADO_IMAGE:-vivado-env:2025.2}
log() { printf '=== %s\n' "$*"; }
log "0. the pipeline RTL from commit $C (rtl/cpu/pipeline/SOURCES.pipe), the shim, the manifest"
git -C $W rev-parse --verify "$C^{commit}" > "$A/rtl-commit.txt" || { echo "REFUSE: no commit $C"; exit 2; }
git -C $W show "$C:rtl/cpu/pipeline/SOURCES.pipe" > "$A/inputs/rtl/SOURCES.pipe" || exit 2
while read -r kind path; do case "$kind" in ''|\#*) continue;; esac
  case "$kind" in include) git -C $W show "$C:rtl/cpu/$path" > "$A/inputs/inc/$(basename $path)";;
                  top|module) git -C $W show "$C:rtl/cpu/$path" > "$A/inputs/rtl/$(basename $path)";; *) echo "REFUSE: kind $kind"; exit 2;; esac
done < "$A/inputs/rtl/SOURCES.pipe"
ls "$A/inputs/rtl" | sed 's/^/  /'
python3 $P3/tools/make-top-shim-p3.py "$BRTL" "$A/inputs/teaching_top_shim.v" || exit 3
python3 $P3/tools/make-build-manifest-p3.py "$A/source-MANIFEST.txt" "$BRTL" "$A/inputs/teaching_top_shim.v" "$A/inputs/rtl" "$A/inputs/inc" "$(cat $A/rtl-commit.txt)" || exit 3
log "1. the build scripts themselves"
for f in "$P3/scripts/build-board-p3.sh" "$P3/tools/check-hierarchy-p3.py" "$P3/tools/audit-board-rtl-p3.py" "$P3/tools/make-build-manifest-p3.py" \
         "$P3/tools/make-top-shim-p3.py" "$P3/tools/run_impl_p3.tcl" "$M4P/scripts/gen-project-tcl.py" "$M4P/scripts/check-tcl.tcl"; do sha256sum "$f"; done > "$A/tooling-hashes.txt"
log "2. generating the project script"
python3 "$M4P/scripts/gen-project-tcl.py" "$A/source-MANIFEST.txt" "$A/project.tcl" --project-dir "$A/project" || exit 3
VIVADO_IMAGE=$IMG /home/engineer/vivado-docker/vdocker run "cd $A && vivado -mode batch -nolog -nojournal -source $M4P/scripts/check-tcl.tcl -tclargs $A/project.tcl" > "$A/check-tcl.out" 2>&1; rc=$?
grep -E "TCL_CHECK|FAIL" "$A/check-tcl.out" | head -3 | sed 's/^/  /'; grep -q "TCL_CHECK fails=0" "$A/check-tcl.out" || { echo "REFUSE: check-tcl did not pass (exit $rc)"; exit 3; }
log "3. the validators (one pipeline hart)"
python3 "$P3/tools/check-hierarchy-p3.py" "$A/source-MANIFEST.txt" > "$A/hierarchy.txt" 2>&1 || { echo "REFUSE: the hierarchy does not close"; tail -4 "$A/hierarchy.txt"; exit 3; }
tail -1 "$A/hierarchy.txt"
python3 "$P3/tools/audit-board-rtl-p3.py" "$BRTL" --rtl-dir "$A/inputs/rtl" --write-rom "$A/inputs/rom_from_rtl.bin" \
  --rom $ROOT/experiments/multicore/m4/gen/gen-RD2DualBoardConfig/rom_from_rtl.bin > "$A/board-rtl-audit.txt" 2>&1 || { echo "REFUSE: the board RTL audit fails"; tail -3 "$A/board-rtl-audit.txt"; exit 3; }
tail -1 "$A/board-rtl-audit.txt"
log "4. recording the inputs"
for f in $(awk -F'\t' '!/^#/{print $4}' "$A/source-MANIFEST.txt"); do sha256sum "$f"; done > "$A/input-hashes.txt"; echo "  $(wc -l < "$A/input-hashes.txt") input hashes recorded"
if [ "$WITH_VIVADO" != "--with-vivado" ]; then log "STOPPING BEFORE VIVADO"; echo "BUILD_P3_PREVIVADO_OK $A"; exit 0; fi
log "5. recording the environment"
{ echo "date: $(date -u +%FT%TZ)"; echo "image: $IMG"; echo "jobs: $JOBS"; echo "host nproc: $(nproc)"; } > "$A/environment.txt"
VIVADO_IMAGE=$IMG /home/engineer/vivado-docker/vdocker run "vivado -version; echo ---; ls -d /opt/Xilinx/*/Vivado" >> "$A/environment.txt" 2>&1
log "6. creating the project (vivado, batch)"; s=$(date +%s)
VIVADO_IMAGE=$IMG /home/engineer/vivado-docker/vdocker run "cd $A && vivado -mode batch -nojournal -log $A/vivado-create.log -source $A/project.tcl" > "$A/create-project.out" 2>&1; rc=$?
echo "  vivado create exit=$rc"
if [ $rc -ne 0 ] || ! grep -q "PROJECT_CREATED" "$A/create-project.out"; then echo "BUILD_FAILED at project creation (exit $rc)"; exit 4; fi
log "7. synthesis, implementation to route, the gate, then (only if it passes) the bitstream"
VIVADO_IMAGE=$IMG /home/engineer/vivado-docker/vdocker run "cd $A && vivado -mode batch -nojournal -log $A/vivado-impl.log -source $P3/tools/run_impl_p3.tcl -tclargs $A/project/teaching_pynqz1.xpr $A/reports $JOBS" > "$A/impl.out" 2>&1; rc=$?
e=$(date +%s); echo "  vivado impl exit=$rc wall=$((e-s))s"; grep -E "^@@@" "$A/impl.out" | tail -14 | sed 's/^/  /'
[ -f "$A/reports/gate.txt" ] && sed 's/^/  gate: /' "$A/reports/gate.txt"
if [ $rc -ne 0 ] || ! grep -q "BUILD_OK" "$A/impl.out"; then echo "BUILD_FAILED (exit $rc; 7 = the routed gate failed, no bitstream)"; grep -E "^ERROR:|^CRITICAL WARNING:" "$A/impl.out" | head -10 | sed 's/^/  /'; exit 5; fi
log "8. the payload (.bit -> .bit.bin, the accepted converter, self-checked on the accepted M4 payload first)"
B2B=$ROOT/riscv-lab/experiments/E1-clock-scaling/bit2bin.py; M4D=$ROOT/experiments/multicore/m4/deploy
python3 $B2B $M4D/rocketchip_wrapper_dual.bit $A/selfcheck.bin > $A/bit2bin-selfcheck.txt 2>&1 && cmp -s $A/selfcheck.bin $M4D/rocketchip_wrapper_dual.bit.bin \
  || { echo "REFUSE: bit2bin does not reproduce the accepted M4 payload"; exit 6; }; rm -f $A/selfcheck.bin
python3 $B2B $A/reports/rocketchip_wrapper.bit $A/reports/rocketchip_wrapper.bit.bin > $A/bit2bin.txt 2>&1 || { echo "BIT2BIN FAILED"; exit 6; }
sha256sum $A/reports/rocketchip_wrapper.bit $A/reports/rocketchip_wrapper.bit.bin | tee $A/outputs.sha256
echo "BUILD_P3_OK $A (NOT programmed; board use needs a separate authorisation)"
