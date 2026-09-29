#!/bin/bash
# The user's attestation that power was physically removed (not measured: the host cannot tell a power cycle from a
# warm reboot). Copy of the M5 script for the `pipe` variant. Run only after the USER confirms the power cycle.
set -euo pipefail
cd "$(dirname "$0")"; . ./p3b-lib.sh
O=${P3B_OUT:-$P3B/state}; mkdir -p "$O"; REC=$O/pipe-power.txt
{ echo "POWER_REMOVED=yes"; echo "AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "VARIANT=pipe"; echo "BY=${SUDO_USER:-${USER:-unknown}}"
  echo "SOURCE=${P3B_ATTESTATION:?set P3B_ATTESTATION to where the confirmation of the power cycle was recorded}"
  echo "MEANS=attested by the user, not measured. This host cannot distinguish a power cycle from a warm reboot."; } > "$REC"
echo "recorded: $REC"; cat "$REC"
