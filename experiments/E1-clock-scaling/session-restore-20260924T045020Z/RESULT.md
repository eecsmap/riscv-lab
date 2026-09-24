# E1 restore: complete. The board holds the accepted 40 MHz bitstream, 8/8 gates.

Session `session-restore-20260924T045020Z`. Second user-attested power removal at 2026-09-24T04:49:57Z. Leases released.

| step | result |
| --- | --- |
| 8 second cold cycle | **pass** — new boot id `85f052b7-af56-4c29-a09c-9528c67cbe26` against pinned `23981968-…`; uptime 36 s; `/root/xv6run` empty; no fesvr; no lock |
| — memory evidence + production preflight | **pass** for this boot |
| 9 deploy and verify the ACCEPTED payload | **pass** — 10 artefacts, each hash-verified on the board |
| 10 program | **pass** — `rc=0`, `prog_done=1` |
| 11 the eight gates | **8/8** |
| 12 final state, release | done |

```
boot01_marker TEACHING-CPU-M3-OK     ext01_m    TEACHING-EXT-M-OK
boot02_clint  M3-CLINT-OK            ext02_c    TEACHING-EXT-C-OK
boot03_ddr    M3-DDR-OK              ext03_a    TEACHING-EXT-A-OK
boot04_badaddr M3-BADADDR-OK         ext04_sv39 TEACHING-EXT-SV39-OK
```

Final state: `prog_done=1`, `FESVR_N=0`, `NO_LOCK`, and `/root/xv6run/teaching.bit.bin` on the board
hashes `20fae71e4661c6c93a9826397594e058ef4bf6dc01071a41809ebb3a312c9f5a` — the accepted payload.

Adapter: `status=0x00000011 cpu_restart_safe=1 pl_reconfig_safe=0 boot_ready=1 epoch=0 ndrained=0`.

## This is also the control for the 25 MHz failure

The same eight probe ELFs, the same host binary, the same board, two hours apart, differing only in
which bitstream is in the PL:

| | 25 MHz (E1) | 40 MHz (accepted) |
| --- | --- | --- |
| adapter after programming | `0x00000011 … boot_ready=1 epoch=0` | `0x00000011 … boot_ready=1 epoch=0` |
| `boot01_marker` | **exit 55**, marker never printed, `tohost=0x1C00037` | **ok**, `TEACHING-CPU-M3-OK` |
| remaining seven gates | not reached | **all ok** |

So the probes, the host binary, the deployment path and the procedure are **not** the explanation: they
work on this board on the same day. What differs is the bitstream.

That narrows it to the E1 build. It does **not** identify what in the build is wrong, and nothing here
distinguishes an instruction path, a data path, an HTIF handshake or a clock-domain-crossing problem.
A single control point is not a diagnosis.

## E1 has no measurement

`perf03`/`perf04` were never reached. `PREDICTION.json` stands **unchecked**, and
`e1_model.py` has nothing to solve: the two-point model needs a second frequency that works.
