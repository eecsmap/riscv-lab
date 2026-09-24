# E1 install: the 25 MHz fabric comes up; the first startup gate FAILS

Session `session-install-20260924T043020Z`. **Stopped at the failed gate. No retry, no second programming, no hot reload, no lock
clearing.** Leases released. All evidence preserved in this directory.

## How far it got

| step | result |
| --- | --- |
| 1 cold cycle | **pass** — user-attested power removal 04:23:42Z; new boot id `23981968-4c31-4818-9f93-c328b780cbcf` against pinned `336004e0-…`; uptime 421 s; `/root/xv6run` empty; no fesvr; no lock |
| 2 memory evidence + production preflight | **pass** — captured for this boot, `MEM_PREFLIGHT` accepted it |
| 3 deploy 12 artefacts, each hash-verified on the board | **pass**, executable mode set |
| 4 program the E1 payload | **pass** — programming `rc=0`, `prog_done=1` |
| 5 eight startup gates | **FAILED at the first**, `boot01_marker`, exit 55 |
| 6 perf03/perf04 samples | **not reached — E1 has no measurement** |

## The failure

```
teaching: ready after 50 ms; status=0x00000011 cpu_restart_safe=1 pl_reconfig_safe=0
          draining=0 drain_timeout=0 boot_ready=1 boot_timeout=0 epoch=0 ndrained=0
*** FAILED *** (tohost = 29360183)
RC=55
```

Two separate things, and they disagree:

* **the fabric is alive and healthy.** The adapter answered in 50 ms with
  `status=0x00000011 … boot_ready=1 epoch=0` — byte for byte the cold-start signature the
  `xv6-board-run-3` milestone recorded on the accepted 40 MHz build. The PL was configured and the
  wrapper is in its expected reset state.
* **the target program did not run correctly.** `boot01_marker` is four instructions of work: print
  `TEACHING-CPU-M3-OK` through HTIF, `exit 0`. It cannot return 55. The marker was **never printed**,
  and `tohost` read `29360183` = `0x1C00037` where a clean exit writes `1`.

## What is NOT concluded

The cause is not established. A corrupt `tohost` with no console output is consistent with the target
never executing correctly from DRAM, but this session has no evidence that distinguishes an instruction
path, a data path, an HTIF handshake and a clock-domain-crossing problem — and the E1 build changes the
PL clock, which touches the crossing into the PS DDR path. **That is a hypothesis, not a finding.**

What *is* established: at 25 MHz, on this build, the fabric configures and the adapter reports a healthy
cold start, and the first target program fails before printing anything.

## Actual board state now

| | |
| --- | --- |
| PL holds | **the E1 25 MHz bitstream** (`/root/xv6run/e1-25mhz.bit.bin`, `6b5da7e7…`, still on the board) |
| `prog_done` | 1 |
| boot id | `23981968-…`, unchanged since install started; uptime 1318 s |
| fesvr / lock | none / `NO_LOCK` |

**Restoration is required and is not optional.** It needs a second user-coordinated physical cold cycle,
after which `e1-restore.sh` deploys and programs the accepted `20fae71e…` payload and re-runs the eight
gates. The session is not closed until those pass.
