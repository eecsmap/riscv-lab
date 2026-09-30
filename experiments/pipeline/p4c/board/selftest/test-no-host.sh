#!/bin/bash
# Self-test of p4c_no_host (p4c-lib.sh): (a) its board command, run by busybox sh on THIS host's /proc, counts a stub
# host named fesvr-teaching-static (comm "fesvr-teaching-") and nothing else; (b) its decision refuses any non-zero
# count, a present lock, or an unreadable reply (stub transport).   test-no-host.sh [p4c-lib.sh]
LIB=$(readlink -f "${1:-$(dirname "$0")/../p4c-lib.sh}"); bad=0; T=$(mktemp -d)
CMD=$(sed -n 's/^    board_must "\$1" "\(.*\)"$/\1/p' "$LIB" | sed 's/\\\$/$/g; s#/var/lock#'$T'/lock#g')
[ -n "$CMD" ] || { echo "FAIL could not extract the command"; exit 1; }
hc() { busybox sh -c "$CMD" | sed -n 's/^HC=//p'; }
n0=$(hc); printf '#!/bin/sh\nsleep 5\n' > $T/fesvr-teaching-static; chmod +x $T/fesvr-teaching-static; $T/fesvr-teaching-static & sp=$!; sleep 0.5; n1=$(hc); kill $sp
[ "$n0" = 0 ] && echo "ok   comm scan: 0 with no host" || { echo "FAIL comm scan without a host: '$n0'"; bad=$((bad+1)); }
[ "$n1" = 1 ] && echo "ok   comm scan: 1 with the stub host running" || { echo "FAIL comm scan with the stub host: '$n1'"; bad=$((bad+1)); }
for c in "0 0 NO_LOCK:0" "1 0 NO_LOCK:13" "0 1 NO_LOCK:13" "0 0 PRESENT:13" "::13"; do
  reply=${c%%:*}; want=${c##*:}; read -r a b l <<<"$reply"
  printf '#!/bin/sh\n%s\n' "$( [ -n "$reply" ] && printf 'printf "HC=%s\\r\\nHP=%s\\r\\nHL=%s\\r\\n"' "$a" "$b" "$l" || echo 'echo garbage')" > $T/stub; chmod +x $T/stub
  out=$(E1_BOARD_CMD=$T/stub E1_COORD=true bash -c ". '$LIB'; p4c_no_host test; echo SURVIVED" 2>&1); rc=$?
  [ $rc = $want ] && echo "ok   reply '$reply' -> exit $rc" || { echo "FAIL reply '$reply' -> exit $rc (want $want): $out"; bad=$((bad+1)); }; done
echo "SELFTEST $([ $bad = 0 ] && echo PASS || echo "FAIL $bad")"; [ $bad = 0 ]
