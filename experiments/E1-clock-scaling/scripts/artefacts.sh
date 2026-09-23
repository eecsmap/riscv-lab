#!/usr/bin/env bash
# Every local file an E1 session needs, with the hash it must have, in one place.
#
# Two of these paths were wrong in the first draft and were found by checking rather than by trying:
# the perf probes live in probes/build-perf (not probes/build), and the E1 payload is under
# build/reports (not build/). Either would have failed on hardware inside a power-cycle window.
P=$R/experiments/teaching-cpu/xv6-board-prep
E1D=$R/riscv-lab/experiments/E1-clock-scaling/build/reports

E1_PAYLOAD=$E1D/e1-25mhz.bit.bin
E1_PAYLOAD_SHA=6b5da7e786186bac97bd2156a720f4be78e4bf8e7e396bae61351ae9361c3acb
ACCEPTED_PAYLOAD=$R/experiments/teaching-cpu/xv6-board-run/derived/teaching.bit.bin
ACCEPTED_PAYLOAD_SHA=20fae71e4661c6c93a9826397594e058ef4bf6dc01071a41809ebb3a312c9f5a
HOSTBIN=$P/deploy-bundle/fesvr-teaching-static
# `: "${SEND:=...}"`, not a plain assignment: lib-e1.sh already makes this overridable and an
# unconditional assignment here silently undid that -- the entrypoint rehearsal then called the REAL
# send-file.py, which opened the serial device and hung. Found by the rehearsal hanging, which is the
# cheapest way to find it.
: "${SEND:=$R/experiments/teaching-cpu/xv6-board-run/scripts/send-file.py}"

# probe name -> local path
elf_path() {
  case "$1" in
    boot0*)  echo "$P/deploy-bundle/$1.elf" ;;
    ext0*)   echo "$P/probes/build/$1.elf" ;;
    perf0*)  echo "$P/probes/build-perf/$1.elf" ;;
    *)       echo "" ;;
  esac
}
PERF_PROBES="perf03_fetch perf04_where"
