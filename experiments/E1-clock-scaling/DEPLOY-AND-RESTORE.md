# E1 deployment and restore checklist

Prepared while awaiting the hardware gates, per `codex-review-20260922-decisions`. **Nothing here has
been executed.** The procedure is executable: see `scripts/README.md`. Steps 1–12 are
`e1-precycle.sh` / `e1-record-power-cycle.sh` / `e1-install.sh` / `e1-restore.sh`, rehearsed offline
at 27/27 + 36/36 + 21/21 and independently rerun by Codex. Installing this bitstream is conditional on B0 measurement-identity review, the current
boot/memory/safe-state gates, and two physically coordinated cold cycles.

## Identities

| artefact | sha256 |
| --- | --- |
| E1 `.bit` (accepted offline) | `df043a1def284fd41f72c869239a4ff37f7e4f8b5e7da5334dc28793ab23fb5e` |
| **E1 raw payload** `e1-25mhz.bit.bin` | `6b5da7e786186bac97bd2156a720f4be78e4bf8e7e396bae61351ae9361c3acb` |
| accepted 40 MHz `.bit` | `2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52` |
| **accepted raw payload** `teaching.bit.bin` | `20fae71e4661c6c93a9826397594e058ef4bf6dc01071a41809ebb3a312c9f5a` |

Both payloads are 4,045,564 bytes.

### How the raw payload is derived, and a correction

`bit2bin.py` parses the `.bit` header: the `'e'` field carries a 4-byte big-endian payload length, located
by **self-consistency** — the declared length must equal exactly the bytes remaining after it. Payload
begins at offset 132 and starts with the dummy / bus-width-detection words; `AA995566` is a further **48
bytes into the payload**, not at the start of it.

**An earlier version of this script was wrong.** It searched for the sync word and stripped to it,
discarding those 48 bytes — a `.bin` that would have gone into the fabric without its bus-width detection
pattern. It was caught by requiring the converter to **reproduce the accepted payload byte for byte**
before being trusted with a new one:

```
bit2bin.py <accepted .bit> /tmp/x.bin --expect 20fae71e4661c6c93a982639...
  BIT2BIN_OK payload at 132, 4045564 bytes, sync word 48 bytes into it
  matches the expected hash
```

That self-check is the reason to believe the E1 payload hash.

## Install (only after the gates, and only with a coordinated cold cycle)

1. **user powers the board down and up**, then runs `scripts/e1-record-power-cycle.sh install`.
   The boot signals — a new boot id against the one pinned beforehand, uptime near zero,
   `/root/xv6run` empty, no remote lock, no fesvr — are **necessary checks, not proof of power
   removal**. A warm `reboot` changes every one of them and leaves the PL configured. Nothing
   reachable from the host distinguishes the two, so power removal is **attested by the user** and is
   labelled attested-not-measured wherever it is used. Both are required: the attestation without the
   boot evidence proves nothing about the board's state, and the boot evidence without the
   attestation does not establish a power cycle;
2. claim `board` and `serial`; capture **fresh same-boot memory evidence** and pass the preflight;
3. deploy `e1-25mhz.bit.bin` and re-verify its hash **on the board**;
4. program from the **cold, quiescent** platform; read the adapter status and record it;
5. eight startup probes — four M3, four extension. **A failure stops the session**;
6. `perf03` and `perf04`, **≥5 bounded samples each**, unchanged probe ELF identities;
7. record every sample, the effective channel and device, and ARM health.

The adapter status at 25 MHz is **not predicted here**. It is read and recorded.

## Restore — required, and not authority for unsafe recovery

8. **user powers the board down and up again**, then runs
   `scripts/e1-record-power-cycle.sh restore`. Same pairing as step 1: necessary boot checks plus a
   fresh user attestation. A record older than the pin is refused, because it attests to the earlier
   cycle;
9. deploy and re-verify `teaching.bit.bin` (`20fae71e…`) on the board;
10. program the accepted bitstream from the cold platform;
11. **re-run the eight startup gates** and record them. The session is not closed until they pass;
12. release leases; record the board's actual final state.

## If anything fails

Stop at the failed step. Preserve the evidence. Report the **actual** remaining board state, including
which bitstream is in the PL. Do **not**: hot-reload the PL, assume a power cycle happened, clear an
unknown lock, edit PS/device-tree/SD/network configuration, or read a host exit as PL quiescence.

If the board is left holding the E1 bitstream because restore could not complete, say so plainly — that
is a true statement about the board, and a restore that cannot be completed safely is not made safe by
being attempted twice.

## Metrics, when the samples exist

Cross-frequency comparisons go in **both cycles and nanoseconds**, as explicit experiment metrics. The
guards in `benchmarks/tools/gen_comparisons.py` stay enabled: a 25 MHz row and a 40 MHz row differ in
configured frequency and `ratio()` already refuses to divide them silently. The **CLINT load is the
control** — it never leaves the fabric, so its cycle cost should be unchanged; if it moves, the DRAM
figures from this build are not interpretable.
