#!/usr/bin/env bash
# E1: synthesise and implement the 25 MHz variant. Frozen B0 inputs with exactly one changed constant.
set -u
A=/home/engineer/fpga/riscv-lab/experiments/E1-clock-scaling/build
V=/home/engineer/vivado-docker/vdocker
IMPL=/home/engineer/fpga/experiments/teaching-cpu/m4-build/run_impl.tcl
mkdir -p $A/reports
echo "== environment"
$V run "vivado -version" > $A/environment.txt 2>&1
grep -m2 -E "^Vivado|^Tool Version" $A/environment.txt | sed 's/^/  /'
echo "== 1. create project"
$V run "cd $A && vivado -mode batch -nojournal -log $A/vivado-create.log -source $A/project.tcl" > $A/create.out 2>&1
rc=$?; echo "  create exit=$rc"; grep -E "^(PROJECT_CREATED|ERROR:)" $A/create.out | head -3 | sed 's/^/  /'
[ $rc -ne 0 ] && { echo E1_BUILD_FAIL_CREATE; exit 1; }
XPR=$(find $A/vivado-project -name "*.xpr" | head -1)
echo "  project: $XPR"
echo "== 2. synthesis + implementation + bitstream"
$V run "cd $A && vivado -mode batch -nojournal -log $A/vivado-impl.log -source $IMPL -tclargs $XPR $A/reports 3" > $A/impl.out 2>&1
rc=$?; echo "  impl exit=$rc"
grep -E "WNS|IMPL_|ERROR:" $A/impl.out | head -8 | sed 's/^/  /'
echo "E1_BUILD_DONE rc=$rc"
