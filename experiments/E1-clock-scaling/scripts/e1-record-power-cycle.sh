#!/usr/bin/env bash
# The USER runs this after physically removing and restoring power.
#
# A pinned boot id proves a new Linux boot. It does NOT prove power was removed: a warm `reboot` changes
# the boot id, resets uptime and clears the RAM initramfs just as well, and leaves the PL configured.
# Nothing reachable from this host can tell the two apart, so the power-removal fact is ATTESTED here
# and is labelled as attested wherever it is used. It is not measured and is not claimed to be.
set -euo pipefail
cd "$(dirname "$0")"; . ./lib-e1.sh
O=${E1_OUT:-$R/riscv-lab/experiments/E1-clock-scaling}; mkdir -p $O/state
phase=${1:?usage: e1-record-power-cycle.sh <install|restore>}
REC=$O/state/$phase-power.txt
{
  echo "POWER_REMOVED=yes"
  echo "AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "PHASE=$phase"
  echo "BY=${SUDO_USER:-${USER:-unknown}}"
  echo "MEANS=attested by the user, not measured. This host cannot distinguish a power cycle from a warm reboot."
} > "$REC"
echo "recorded: $REC"
cat "$REC"
