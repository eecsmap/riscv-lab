# First P4c cold cycle: install refused at the uptime gate (nothing deployed or programmed)
* Attestation (power-attestation-1.txt): the user confirmed the cycle directly at 2026-09-30T23:58Z (an earlier
  relayed confirmation was not recorded). Install job 23:58:18Z: new boot `82c150fb-88f6-4e25-ba12-94ec04ae217c`
  (pin 4d45136e), /root/xv6run absent, no host, NO_LOCK, but **uptime 1811 s > 600 s** -> REFUSE(11). The power-on
  was ~30 min before the install could run. The gate was not changed.
* Re-pin of the (empty) board for a second cycle: precycle2 refused 62 (`cd /root/xv6run` failed: a fresh boot has
  no such directory), precycle3 exited 1 silently (empty file list under pipefail); both were my script defects, both
  read-only. Fixed in e0266d3 / c86609a with an offline empty-board rehearsal (selftest/test-precycle-empty.sh; the
  e0266d3 version fails it). precycle4 (frozen c86609a) pinned 82c150fb -> results/precycle-2/.
* prog_done read 1 on this fresh boot before any programming (recorded; programming is checked by rc + prog_done +
  payload re-hash, never by prog_done alone).
