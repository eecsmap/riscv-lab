# PIPE-P3b REPORT — the single pipeline on the board, and the interactive handoff

Task `codex-pipe-p3b-board-interactive` (user-authorised takeover of the dual-core board). Everything below was
measured on the PYNQ-Z1 in one cold boot, `4d45136e-7c10-46fd-b6f8-dfcd30775917`. The user's instructions are in
`HANDOFF.md`. Evidence: `results/precycle/`, `results/session-pipe-20260929T231052Z/` (job logs, gates, samples,
frequency runs, both xv6 runs with console/stages/judge, both handoff attempts).

| step | result |
|---|---|
| pre-state (before the cycle) | console at the ARM prompt (passive probe), boot `88e9acef…` (the dual interactive boot, up 39.7 h), dual payload `43e5b414…`; the user's working disk `fs-run.img` had changed (`05a4562b…`): read back over the console and hash-matched; pin written |
| cold cycle | the user confirmed "已冷上电" (attested, not measured); new boot id, uptime 9 s, empty `/root/xv6run`, no host, no lock |
| preflight | production memory evidence + `mem-preflight`: passed |
| deploy + program | 20 artefacts hash-verified on the board; programming rc 0, `prog_done` 1, payload re-hashed `5f97d4ab…` |
| 8 single-hart gates | 8/8 with exact markers (incl. `ext03_a` atomics and `ext04_sv39`) |
| perf probes | perf02/03/04/06 3/3 valid samples each |
| **core clock** | **40.00 MHz** (pairs 40.02 / 40.00 / 39.98; each ±0.1 % from the 10 ms resolution) — cycles counted by the core, time by the **ARM's clock** (`/proc/uptime`), load overhead cancelled by a short/long pair; mtime = cycles / 100 exactly |
| xv6 `m4smoke` | PASS (`m5_xv6_check.py`): banner 5.4 s, prompt 7.5 s, b0compute / m3par2 / m3fs, deliberate stop, 15.8 s |
| xv6 `perf-board` | PASS (`perf_check.py`, defaults): 6 perf runs, child checksums identical to the multicycle board run |
| interactive handoff | launcher installed and boot-tested on a throwaway copy (boot → `ls` shows mtimetest/perfcompute/perfarray → Ctrl-C → lock released); no host, no lock, no lease; ready to launch, not running |

## Fixed work, same kernel `133f5b72…` and disk `d558e444…`, 40 MHz
| workload | single pipeline (3 runs) | single multicycle, accepted (`multicore/perf/RESULTS.md`, 3 runs) | T_multicycle / T_pipeline |
|---|---|---|---|
| perfcompute, 8,000,000 iterations | 15.829 / 15.829 / 15.833 s (median 15.829) | 26.588 (26.579–26.588) s | **1.680** |
| perfarray, 8,388,608 updates | 12.700 / 12.691 / 12.696 s (median 12.696) | 40.548 (40.540–40.551) s | **3.194** |

Seconds are mtime units / 400,000; the 400 kHz is now backed by the independent clock measurement above, not assumed.
`mtime()` read cost: 124–126 units (pipeline) vs 189–191 (multicycle). These are two workloads on one board and
one boot per configuration; no general speed-up claim. The multicycle numbers were not re-measured this session
(the task did not ask to reprogram it for comparison).

## Bare-metal probes (CPI = cycles / instructions, median of 3; `results/.../probe-compare.md`)
| probe window | pipeline | multicycle (IPS cache session) |
|---|---|---|
| perf03 32-bit / compressed ALU loop | 2.00 / 2.00 | 6.00 / 6.00 |
| perf02 ALU, bare / 4 KiB / megapage | 2.00 / 2.00 / 2.00 | 6.00 / 8.00 / 8.00 |
| perf02 loads, bare / 4 KiB / megapage | 7.94 / 7.94 / 7.94 | 11.90 / 14.74 / 14.74 |
| perf04 loads from DRAM / from the CLINT | 7.94 / 4.33 | 11.90 / 8.33 |
| perf06 I-cache resident / working set exceeds it | **1.09** / 10.45 | 6.01 / 15.03 |

The loops are 3 instructions with a taken branch, so a CPI of 2 is the loop's redirect bubble; an I-cache-resident
straight-line stream runs at 1.09. Loads still pay the memory round trip (one outstanding request, no D-cache).

## Findings during the session
* The launcher boot test's first version reported FAIL although the launcher worked: its prompt patterns lacked
  `re.S` (a prompt follows a CR/LF), and the script then stopped before removing the throwaway disk. Replayed on
  the recorded transcript (fails without, matches with DOTALL), fixed in `c63b6b3`, rerun: PASS. Both attempts are
  in the results.
* The user's pre-cycle disk was not the deploy image; it is preserved (host backup + `fs-user-previous.img`).

## Not done
No P4, no RTL/Vivado change, no reprogramming of the multicycle image, no push/tag, no disk cleanup beyond the
throwaway copy this session created.
