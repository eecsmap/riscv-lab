# 2026-09-24: the board's console went silent between sessions

Read-only diagnosis, then two single bytes. **No programming, no deployment, no PL reload, no lock
clearing, no retry loop, no power cycle.** Leases claimed and released for each step.

## Timeline

| when (UTC) | what |
| --- | --- |
| 2026-09-23 17:05 | last successful console traffic: B0 application campaign closed out — `prog_done=1`, `FESVR_N=0`, `NO_LOCK`, boot id `ebeab8a6-0ac9-474a-84c3-bd6e0b357d3b`, uptime 210 751 s, every artefact hash unchanged |
| 2026-09-24 03:08 | `e1-precycle.sh install` refused at exit 62 on the FIRST board command |
| 2026-09-24 03:1x | three further bounded reads, all zero bytes |

The user confirms the board is **powered and untouched** since then.

## What was measured

| check | result |
| --- | --- |
| USB adapter | present and bound: Digilent `0403:6010`, serial `003017B5C772`, both interfaces (`1-14:1.0`→ttyUSB0, `1-14:1.1`→ttyUSB1) |
| device holders | none; no `serial-transport`, `board-runner` or `fesvr` process anywhere |
| line settings | 115200/115200, CLOCAL, no CRTSCTS, **IXON and IXOFF both set** |
| modem lines | **DTR and RTS asserted** |
| 20 s listen, writing nothing | **0 bytes** |
| host flow control cleared (local only, no byte on the wire) | **0 bytes** |
| one newline | **0 bytes** |
| XON (`0x11`) | **0 bytes** |
| `serial-transport.py` ×2, one with `--status-file` | exit 124, 0 bytes, **no framing evidence written** |

## The hypothesis that was disproved

`IXON` was set on the host, so an XOFF from the board would have blocked our writes indefinitely — which
fits "opens the device, writes nothing, times out, hears nothing" exactly. Clearing flow control on this
host puts no byte on the wire and would have unblocked it. It changed nothing, and neither did XON.

So this is not flow control. The board is powered, the adapter enumerates, the lines are asserted, and
the UART neither emits nor answers.

## A correction

I first read `/dev/ttyUSB1`'s timestamp of `03:08:12` as a re-created device node, which would have been
evidence of a USB re-enumeration. It is not: that is a **last-write** time, and the write was my own
precheck. The same adapter's other interface, `ttyUSB0`, is untouched since Sep 21. I nearly reported it
as evidence and it would have been wrong.

## What is not concluded

The cause is not established. A hung ARM, a dead console process and a wedged UART are not
distinguishable from this side, and nothing here is evidence for one over the others. Recovering it
needs a physical power cycle, which only the user can do.

## Consequence for E1

`e1-precycle.sh` could not record a boot id, so **no pin was written**. The E1 install cycle must not be
folded into a recovery cycle: the pin exists to prove the boot id changed, and pinning `ebeab8a6-…` from
yesterday's record would prove only that the machine rebooted at some point after 17:05, not that this
power cycle did it.

The sequence that keeps the evidence intact costs one extra cycle of the user's time:

1. a **recovery** power cycle — the board comes back at a fresh boot;
2. `e1-precycle.sh install` runs properly and pins that boot id;
3. the **E1 install** power cycle, attested, with the pin taken immediately before it.
