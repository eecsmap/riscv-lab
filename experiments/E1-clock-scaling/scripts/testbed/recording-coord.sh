#!/usr/bin/env bash
# Records every lease operation. $FAKE_CLAIM_DENY names a lease that cannot be claimed.
set -u
printf '%s\n' "COORD $*" >> "${E1_REC:?}"
[ "${1:-}" = claim ] && [ "${2:-}" = "${FAKE_CLAIM_DENY:-}" ] && exit 1
exit 0
