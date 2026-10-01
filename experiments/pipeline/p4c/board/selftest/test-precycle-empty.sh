#!/bin/bash
# Offline rehearsal of p4c-precycle.sh against a FRESH, EMPTY board (no /root/xv6run): stub transport
# (stub-empty-board.sh), stub console-stop, leases stubbed, a temp workspace whose artefacts link to the real set.
# Must reach P4C_READY_FOR_COLD_CYCLE with the boot id pinned. (e0266d3 exited silently at the backup step.)
B=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); cp -r "$B" $T/board; mkdir -p $T/ws/state
ln -s "${P4C_WS:-/home/engineer/fpga/worktrees/pipe-dual/experiments/pipeline/p4c/ws}/artefacts" $T/ws/artefacts
printf '#!/usr/bin/env python3\nimport sys; open(sys.argv[1],"w").write("stub"); print("CONSOLE ARM prompt, nothing running (stub)")\n' > $T/board/console-stop.py
out=$(P4C_WS=$T/ws E1_BOARD_CMD=$T/board/selftest/stub-empty-board.sh E1_COORD=true bash $T/board/p4c-precycle.sh 2>&1); rc=$?
if [ $rc = 0 ] && grep -q "^P4C_READY_FOR_COLD_CYCLE" <<<"$out" && [ "$(cat $T/ws/state/current-precycle/pin.txt)" = 82c150fb-88f6-4e25-ba12-94ec04ae217c ]; then echo "SELFTEST PASS"; else echo "$out" | tail -5; echo "SELFTEST FAIL rc=$rc"; exit 1; fi
