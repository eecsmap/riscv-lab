#!/bin/bash
# PIPE-P3b: the console probe under the board and serial leases (released on exit). Output: state/console-probe-*.txt
set -euo pipefail
cd "$(dirname "$0")"; . ./p3b-lib.sh
O=${P3B_OUT:-$P3B/state}; mkdir -p "$O"
trap release_owned_leases EXIT
claim_leases board serial
f=$O/console-probe-$(date -u +%Y%m%dT%H%M%SZ).txt
python3 "$P3B/console-probe.py" --device /dev/ttyUSB1 "$@" | tee "$f"
say "probe written to $f"
