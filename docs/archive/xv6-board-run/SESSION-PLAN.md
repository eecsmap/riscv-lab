# Session plan: the first xv6 run on the teaching CPU, on hardware

claude, 2026-09-20, for `codex-xv6-live-board-run`. Written **before** any hardware access, as that task
requires: the probe artifacts and their pass markers are identified here, so a missing artifact is a
reported gate rather than a stage that quietly does not happen.

**Status: not started. No hardware has been touched.** Two things must happen first — a direct confirmation
of the authorization from the user (§0), and a decision on the probe gap in §3.

## 0. Why this has not started

The task states the user replied "授权" to live board work. That exchange happened in the Codex session; it
did not reach me directly. Programming the PL is the one step in this chain that physically changes
hardware state, and on this exact board a reconfiguration during operation once locked the PS until it was
power-cycled (`m4-board/DIAGNOSIS.md`). Codex's own earlier rulings said repeatedly that board availability
is not programming authority and that programming would be decided separately.

So I am asking the user to confirm once, directly, before claiming `board`. This is not a dispute with the
verdict; it is the same "confirm before something hard to reverse" rule that the rest of this work has
been held to.

## 1. Gates, in order (from the task, not re-negotiated)

| # | gate | stop condition |
| --- | --- | --- |
| 1 | `./coord claim board` (and `serial` if used); register any job over two minutes | another owner holds it — do not disturb, do not read a missing PID as permission |
| 2 | identify the board, its current owners, and a **cold/quiescent** platform | a software reboot is not a PL cold start; if a physical power cycle is needed, **stop and ask the user** |
| 3 | after the FINAL cold boot: capture live `boot_id`, raw DT `#address-cells`/`#size-cells`, `memory/reg`, **every** `reserved-memory/*/reg`, `/proc/iomem`, `/proc/meminfo`, ARM health logs | any overlap with `0x1000_0000–0x1FFF_FFFF`, or missing/redacted/inconsistent evidence → **stop** |
| 4 | `mem-preflight.py <bundle> --expect-session <live boot_id>` | non-zero → **stop**. After **any** reboot, recapture and recheck before any load or DMA |
| 5 | verify deployment identities locally **and on the board** | any mismatch → stop. Pristine disk preserved; a per-run writable copy made and hashed |
| 6 | program the PL from the cold/quiescent platform only | no possibly-outstanding PL transactions; no hot reload |
| 7 | `fesvr-teaching-static --self-test` (no I/O) and the host/reset handshake | never an ordinary host invocation as an unconfigured-PL smoke test; ≥50 ms hold **and** full `BOOT_READY`, not `CPU_RESTART_SAFE` alone |
| 8 | staged bare-metal probes (§3) | a missing artifact is a **reported gate** |
| 9 | xv6: 128 MiB kernel + per-run disk copy, via **production** `board-runner.py` | never `_test_runner.py`; exact-path `--expect`; fixed device lock and real boot-id source |
| 10 | the four commands, judged by the same `check-xv6.py` on the raw console/stages | partial progress is reported as partial, not as acceptance |
| 11 | re-check ARM memory and health after the run | allocator errors mean the window was not free |

## 2. Identities

From the accepted `deploy-bundle/MANIFEST.sha256` (verified 10/10 offline):

| artefact | sha256 |
| --- | --- |
| `rocketchip_wrapper.bit` | `2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52` |
| `fesvr-teaching-static` | `c050eab30f80a21a7c92c8688faa2f043c67aa2900fbc08b80f3dd8de2ba1fb9` |
| `kernel-128mib` | `e990fb31fad483b805aaeae77ecaebb3111abcec012d70447c620c9e9b289c2c` |
| `fs-pristine.img` | `4691ffea6b05562d33a599a3406ab3b6d69e6c2444addb08838f1ef6f97527b7` |
| `boot01_marker.elf` | `69ca91994567a44f…` |
| `boot02_clint.elf` | `0c4ebbb7648a34c0…` |
| `boot03_ddr.elf` | `3089c7e72514eded…` |
| `boot04_badaddr.elf` | `fc3b16962f69e53a…` |

The programmed identity is **never** inferred from a same-named file; programming logs are retained.

## 3. The probes — and a gate found while writing this

### Board-runnable, with markers (the four accepted M3 programs)

| artefact | required marker | exit |
| --- | --- | --- |
| `boot01_marker.elf` | `TEACHING-CPU-M3-OK` | 0 |
| `boot02_clint.elf` | `M3-CLINT-OK` | 0 |
| `boot03_ddr.elf` | `M3-DDR-OK` | 0 |
| `boot04_badaddr.elf` | `M3-BADADDR-OK` | 0 |

Each verified above by extracting the string from the ELF, and each uses HTIF (`tohost`) to report.

### **GATE: the extension probes are not board-observable**

The plan called for "one bare-metal program each for M, C, Sv39 and A". Checking the artefacts rather than
assuming they exist:

* **`amo_probe.bin` and `bdev_probe.bin` are test-bench artefacts, not board programs.** `amo_probe.S`
  stores its results to `0x80001000` and spins; it prints nothing. In the Verilator test bench that was
  exactly right — I read the values out of the AXI memory model. On the board there is no memory model to
  read, no console output and no pass marker, so running them would produce **no observable result**.
  They would not fail; they would tell us nothing.
* **No M, C or Sv39 bare-metal board program exists at all.** Those extensions were verified in the CPU
  test bench, which is a different harness from the board's boot-ROM/HTIF path.

So stage 8 as written cannot be executed with the artefacts that exist. Reporting it rather than skipping
it. Three ways forward, for Codex to choose — I am not choosing unilaterally:

1. **Build HTIF-reporting versions of the probes** (an `AMO-OK` / `M-OK` / `C-OK` / `SV39-OK` marker each,
   written through `tohost` the way the M3 programs do). Offline work, a few small assembly programs, and
   it makes stage 8 mean something. This is what I would propose.
2. **Drop stage 8** and let xv6 carry the extension evidence: it is built `-march=rv64gc`, pages through
   Sv39 from `main()` onwards, and uses atomics in its locks, so reaching a shell exercises M, C, Sv39 and
   A far more thoroughly than four markers would. The cost is that a failure has a much larger haystack.
3. **Run the four M3 programs only** and record stage 8 as not covered.

Option 1 needs no hardware and would be proposed before implementation, as the task requires for anything
beyond its scope.

## 4. What gets written where

Everything new goes under `experiments/teaching-cpu/xv6-board-run/`: capture scripts, raw logs, copied
manifests, `REPORT.md`, hashes. Accepted prep/build/simulation artefacts are not revised.

## 5. On uncertainty

Evidence and ownership are preserved. Stopping the host does not assert reset. `PL_RECONFIG_SAFE` stays 0.
The required cold recovery or user action is reported; there is no automatic recovery loop and no hot
reprogramming. If interrupted, a precise handoff is left behind.
