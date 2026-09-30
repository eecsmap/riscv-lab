#!/bin/bash
# The user's attestation that power was physically removed (not measured: the host cannot tell a power cycle from a
# warm reboot). Copy of P3b's script for the `pipedual` variant; written next to the pin of the CURRENT pre-cycle
# step. Run only after the USER confirms the NEW power cycle, with P4C_ATTESTATION naming where they confirmed it.
set -euo pipefail
cd "$(dirname "$0")"; . ./p4c-lib.sh
O=$(readlink -f "$STATE/current-precycle"); [ -s "$O/pin.txt" ] || die $EX_PIN "no current pre-cycle pin ($STATE/current-precycle)"
REC=$O/power.txt; [ -e "$REC" ] && die 2 "$REC exists: one attestation per pre-cycle step"
{ echo "POWER_REMOVED=yes"; echo "AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "VARIANT=pipedual"; echo "BY=${SUDO_USER:-${USER:-unknown}}"
  echo "SOURCE=${P4C_ATTESTATION:?set P4C_ATTESTATION to where the confirmation of the power cycle was recorded}"
  echo "MEANS=attested by the user, not measured. This host cannot distinguish a power cycle from a warm reboot."; } > "$REC"
echo "recorded: $REC"; cat "$REC"
