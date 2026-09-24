#!/usr/bin/env bash
# Assemble a Vivado build directory for one campaign stage: frozen board inputs plus THIS stage's CPU.
#
# The board side -- wrapper, shim, elaborated board design, xdc, block design, and the ACCEPTED 40 MHz
# clocking.vh -- comes from riscv-lab/boards/pynq-z1/frozen and is identical for every stage. That is
# the point: the clock is not a variable in this campaign, so a stage differs from its predecessor in
# the CPU and in nothing else, and the manifest records every hash so that is checkable rather than
# asserted.
#
#   prep_build.sh <stage-name> <cpu-rtl-dir> <fresh build dir>
set -u
R=/home/engineer/fpga
LAB=$R/riscv-lab
FROZEN=$LAB/boards/pynq-z1/frozen
STAGE=${1:?usage: prep_build.sh <stage> <cpu-rtl-dir> <build dir>}
RTL=${2:?cpu rtl dir}
OUT=${3:?build dir}
ACCEPTED_CLOCKING=d0fd087a156a336433edadf559d18c23046ed1931f96d5918f5970d9928365e8
[ -d "$RTL" ] || { echo "REFUSE: $RTL is not a directory"; exit 2; }
# The Vivado container mounts only $HOME/fpga. A build directory outside it is invisible to the tool,
# which fails at `cd` with a message that says nothing about Vivado -- the first attempt died exactly
# there, under /tmp, and the cause was three lines down in create.out rather than in any Vivado log.
case "$OUT" in
  /home/engineer/fpga/*) : ;;
  *) echo "REFUSE: $OUT is outside /home/engineer/fpga, which is the only path the Vivado container mounts"; exit 2 ;;
esac
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p "$OUT/inputs" "$OUT/reports"

got=$(sha256sum "$FROZEN/clocking.vh" | cut -d' ' -f1)
[ "$got" = "$ACCEPTED_CLOCKING" ] || {
  echo "REFUSE: clocking.vh is $got, not the accepted 40 MHz $ACCEPTED_CLOCKING"
  echo "        (E1's 25 MHz variant must never end up in a campaign build)"; exit 2; }
echo "  clocking.vh is the accepted 40 MHz one"

for f in clocking.vh rocketchip_wrapper.v teaching_top_shim.v RD2BoardTop.RD2AtomicBoardConfig.v \
         AsyncResetReg.v plusarg_reader.v base.xdc pynqz1_bd.tcl; do
  cp "$FROZEN/$f" "$OUT/inputs/$f" || exit 1
done
# this stage's CPU, whatever files it has -- a stage that adds a module is picked up automatically
for f in "$RTL"/*.v "$RTL"/*.vh; do cp "$f" "$OUT/inputs/"; done

M=$OUT/board-inputs.tsv
: > "$M"
emit() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$(sha256sum "$2" | cut -d' ' -f1)" "$(stat -c%s "$2")" "$2" "$3" >> "$M"; }
emit include   "$OUT/inputs/clocking.vh" "included by the board wrapper; the ACCEPTED 40 MHz constant"
emit include   "$OUT/inputs/tcpu_defs.vh" "included by tcpu_core.v; needs an include dir"
emit wrapper   "$OUT/inputs/rocketchip_wrapper.v" "the real board top: PS, pins, MMCM, both AXI boundaries. BASELINE, READ ONLY"
emit shim      "$OUT/inputs/teaching_top_shim.v" "module Top: straight through to TeachingBoardTop"
emit board-rtl "$OUT/inputs/RD2BoardTop.RD2AtomicBoardConfig.v" "the elaborated atomic teaching board design"
for f in "$OUT/inputs"/tcpu_*.v; do
  emit blackbox "$f" "campaign stage $STAGE: the teaching CPU"
done
emit support   "$OUT/inputs/AsyncResetReg.v" "rocket-chip support"
emit support   "$OUT/inputs/plusarg_reader.v" "rocket-chip support"
emit xdc       "$OUT/inputs/base.xdc" "board constraints, including create_clock -period 8"
emit bd-tcl    "$OUT/inputs/pynqz1_bd.tcl" "the PS block design"
echo "  manifest: $(grep -c . "$M") entries, $(grep -c '^blackbox' "$M") CPU files"

python3 $LAB/tools/gen-project-tcl.py "$M" "$OUT/project.tcl" \
  --project-dir "$OUT/vivado-project" --board-repo "$LAB/boards/pynq-z1/board_files" >/dev/null || exit 1
echo "  project.tcl generated"
echo "PREP_BUILD_OK $STAGE -> $OUT"
