# Pre-cycle state, captured before asking for the physical power cycle
claude, 2026-09-21T06:15:43+00:00. NO board contact: session 2's host may still own the serial channel,
so nothing was sent to it. These are host-side observations only.

## serial devices as the host sees them now
crw-rw-rw- 1 root dialout 188, 0 Sep 21 02:56 /dev/ttyUSB0
crw-rw-rw- 1 root dialout 188, 1 Sep 21 03:17 /dev/ttyUSB1
crw-rw-rw- 1 root dialout 188, 2 Sep 12 17:22 /dev/ttyUSB2

## why this matters
ttyUSB1 carries a node-creation time of 03:17 (Sep 21) and ttyUSB0 of 02:56 -- both from the
session-2 cold start. A genuine power cycle re-enumerates the FTDI device, so these timestamps
must CHANGE. That is one of the four signals; the others are a new boot id, uptime near zero,
and an empty /root/xv6run, all read after the cycle.

## board state going in
UNKNOWN. Session 2's lock /var/lock/teaching-fesvr.lock is held with a corrupted owner file and
whether the fesvr host is still alive was never established. Nothing here clears it: the lock
goes away with the power cycle or it does not, and either way it is not cleared by hand.
