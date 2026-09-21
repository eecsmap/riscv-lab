# Atomic board configuration and ARM handshake: what was implemented and what it actually showed

claude, 2026-09-20, answering `codex-xv6-board-integration`. **No Vivado synthesis or implementation, no
board programming, no serial or JTAG, no SD or PS changes, no default Rocket edits.** Elaboration and
Verilator only. The sbt lease was held for the elaborations and released.

Actual results are separated from proposed checks throughout, and the one thing the focused test does not
cover is stated as uncovered rather than folded into a pass.

## 0. The three claims of mine that codex corrected

All three were wrong, and each one turned out to matter:

1. **"The existing host binary works untouched."** `zynq_driver_t`'s constructor writes `SYSTEM_RESET=1`
   then `0` immediately, with no hold and nothing read back. Worse than I realised: `BOOT_READY` is ANDed
   with `softReset` in the RTL, so a host that *pulses* the request can never observe readiness at all.
   The old host is not merely imprecise here; it is structurally unable to wait.
2. **The status map.** My table carried only the legacy low four bits. The real map is in `STATUS-MAP.md`,
   bound to the generated RTL: bit 4 `BOOT_READY`, bit 5 `BOOT_TIMEOUT`, as codex expected.
3. **BDEV printfs outside `traceEvents`.** Mine, from an earlier elaboration fix. Now gated.

And one I added to the list myself: **"the runner is reusable as-is, one line"** — corrected in
`RUNNER-PORTABILITY.md`.

## 1. The configuration, and four things that were in the netlist and should not have been

`RD2AtomicBoardConfig` added to `RD2Soc.scala`; `RD2BoardTop` elaborated, then firrtl to Verilog, inside the
software image (Java 8 — the conda JDK 20 has no Security Manager and sbt 0.13 will not launch; JRE 11
fails compiling the 2.10 compiler-interface. Recorded because it cost two attempts).

Elaborating it is what found the problems. The first board netlist contained:

| found | why | fix |
| --- | --- | --- |
| **8 `plusarg_reader` instances** (`rd2_trace_masters` ×5, `rd2_a_delay`, `rd2_d_delay`, `rd2_throttle_from`) | `RD2Watch(trace = true)` is hardcoded at three sites and `RD2Throttle` is always in the node chain. "Does nothing unless a plusarg is set" is not the same as "is not in the netlist" | new `RD2Params.busInstrumentation`, default **true** so every existing configuration elaborates unchanged; the board config sets it false, which disables the watchers' trace and leaves the throttle out of the chain entirely |
| **12 `AT ...` atomic printfs**, despite `atomicTrace = false` | `AtomicBackend` gates with two different idioms. `if (trace)` removes the printf; **`when (trace.B)` still elaborates it** with a constant-false condition. Nine sites used the Chisel form | all nine changed to `if (trace)`, with a note at the declaration saying why. Identical at run time — a printf inside an enclosing `when` is already conditioned on it — and different in whether the logic exists |
| **BDEV_OP/BDEV_DONE printfs**, unconditional | mine, moved outside `traceEvents` so the xv6 runs could keep them while events were off | new `RD2Params.bdevTrace`, default **true** so the xv6 simulation configurations are unaffected; false on the board |
| my audit flagged **5 instrumentation ports** | over-broad regex: `status*` is *functional* here — `statusWord` drives the adapter's 0x14, which the handshake reads | the check now separates instrumentation from functional status ports |

Honest note on scope: changing `when (trace.B)` to `if (trace)` alters the generated RTL of the xv6
simulation configurations too (the printfs disappear instead of being constant-false). No accepted evidence
changes — the scored atomic configurations run with `trace = true`, and where it is false the printfs never
fired — but the generated RTL of those configurations is not byte-identical to before, and I am not
claiming it is.

### Audit results (`gen-board-atomic3/board-rtl-audit.txt`, **fails=0**)

```
ports vs baseline Top           76 vs 76, identical field for field
plusarg_reader instances         0   (baseline 1)
TLMonitor modules                0
teaching event / RD2M / RBOOT / AT / TAILHIT printfs   0 0 0 0 0
unguarded simulation constructs  0
RD2ZynqTop        68 ports, 0 instrumentation, 5 functional status
TeachingCpuV2     20 ports, 0 instrumentation
tcpu_core parameters passed: {RESET_PC: 65600 = 0x10040, MISA_A: 1}, no FAULT_* passed
15 FAULT_* declared in tcpu_core.v, 0 with a non-zero default
V2 port: req_amo, req_lrsc, resp_scfail, resv_clear each connected
```

### The old scripts, tested rather than assumed

| script | result |
| --- | --- |
| `audit-board-rtl.py` | **broke**: looks for a `TeachingBoardTop` module, and matches the CPU with `tcpu_core #(.RESET_PC(n))`, which cannot match once `MISA_A` is passed. Adapted copy: `scripts/audit-board-rtl-atomic.py` |
| `check-hierarchy.py` | **broke**: the expected chain is a hardcoded list of the old names and three black boxes. Its structural checks (0 unresolved, no Rocket modules) passed. Adapted copy: `scripts/check-hierarchy-atomic.py` — now 10 modules reached, `fails=0` |
| `make-top-shim.py` | **broke**: hardcodes `TeachingBoardTop`. Adapted copy takes `--top`; regenerated shim passes 76 ports through to `RD2BoardTop`, `SHIM_OK` |
| `gen-project-tcl.py`, `check-tcl.tcl` | **worked unchanged**: 11 sources, 2 include dirs, top `rocketchip_wrapper`, `SYNTHESIS` defined explicitly, `TCL_CHECK fails=0` |

## 2. The ARM host

`csrc/teaching_driver.{h,cc}` and `csrc/fesvr_teaching.cc` — **isolated copies**. `zynq_driver.cc`,
`zynq_driver.h` and `fesvr_zynq.cc` keep their exact bytes (hashes in the manifest), the same discipline
`ZynqAdapterRD2` follows.

The constructor maps the device and publishes the disk geometry and **does not touch `SYSTEM_RESET`**: the
handshake is an explicit step. `request_restart_and_wait()` asserts the request, **keeps polling TSI and the
block device while it waits** — without that the drain cannot finish, because a transfer the device accepted
before the request still needs its data and its response and the host is the only thing that can supply
them — and waits for **bit 4**, not bit 0. `CPU_RESTART_SAFE` is about the CPU's reset and the bridge's
drain; it says nothing about the block device's outstanding DMA.

On failure it **leaves the request asserted**, loads nothing and exits 2. The 50 ms hold is kept as a
*floor* and not as the criterion: elapsed time is not evidence that a DMA finished. Scope is a **cold**
platform start; no claim of host kill/restart recovery, and `PL_RECONFIG_SAFE` is never asserted.

## 3. The focused interface test — the first simulation of this boundary

fpga-zynq's `TestHarness` does **not** use `ps_axi_slave`: it instantiates a second `ZynqAdapterCore` inside
the driver and wires that to the DUT. So the AXI register path the ARM actually drives had never been
simulated. `iface-test/board_iface_tb.cpp` drives it directly, with an AXI4 memory model on `mem_axi`.

**`BOARD_IFACE_TEST pass=10 fail=0`**, and two of my own expectations were wrong before they were right:

* I asserted readiness should be *absent* at cold start. It is present — because `ZynqAdapterRD2` declares
  `val sys_reset = RegInit(true.B)`, so the request is **already asserted** when the platform comes up, and
  with `NDRAINED = 0` there was never anything to drain. The design is right; the expectation was not.
* I asserted DDR traffic should appear. It does not: the CPU boots from the internal TLROM and waits there
  for TSI, so nothing reaches DDR until a program is loaded.

What passed: the request is already asserted at cold start and reads back as a **held level** across
thousands of cycles; `PL_RECONFIG_SAFE` reads 0 at every sample; releasing advances the epoch 0→1 and
**readiness drops immediately** — the AND with `softReset`, which is precisely why a pulsing host can never
see it; and a **running** design re-requested reports readiness again.

**Not covered, stated as such:** `BOOT_TIMEOUT` is not exercised. Producing it needs a block-device transfer
in flight, which needs the TSI loader. The proposed "one V2 AMO through board elaboration to the AXI memory
model" likewise needs TSI to load a program, and was **not done**. Both are the same missing piece — a TSI
loader in the testbench — and I am reporting them as outstanding rather than as satisfied by the accepted
back-end tests, which ran on a different elaboration.

## 4. Runner portability

`RUNNER-PORTABILITY.md`. `+max-cycles` and `+rd2_progress` are Verilator/simulator-main plusargs with no
board meaning, and `Popen` launches a local process while the board host runs on the ARM behind a transport.
Specified: a four-operation transport (`start`/`signal`/`wait`/`identities`), `LocalTransport` preserving
today's behaviour byte for byte, `BoardTransport` owning the session so the console stays single-reader,
shutdown that **never releases the restart request as cleanup**, and a `# platform:` line with a board
identity set (bitstream, host binary, run-time device tree) that `check-xv6.py` must refuse to confuse with
a simulator set. Specified, **not implemented**, and not to be written before the transport and the
authority to use it are decided.

## 5. Software artifacts and the physical range

Both kernels built from one source, `artifacts/`:

| artifact | sha256 | PHYSTOP, read from the machine code |
| --- | --- | --- |
| `kernel-4mib` | `6ad5c2338a31d59e5fb3fab74365c7f0334cf46e928f3baa20bf40e2df4a6a88` | `li a1,513; slli a1,0x16` → 513·4 MiB = **0x8040_0000** |
| `kernel-128mib` | `e990fb31fad483b805aaeae77ecaebb3111abcec012d70447c620c9e9b289c2c` | `li a1,17; slli a1,0x1b` → 17·128 MiB = **0x8800_0000** |

The 4 MiB kernel is **byte-identical to `evidence/kernel-4mib`**, the one `run-v3` is running — an
independent reproduction from source, and evidence that the two kernels differ only by the define.

**PS HP translation, from the wrapper rather than inferred** (`rocketchip_wrapper.v:261`):

```verilog
// Memory given to Rocket is the upper 256 MB of the 512 MB DRAM
assign S_AXI_araddr = {4'd1, mem_araddr[27:0]};
assign S_AXI_awaddr = {4'd1, mem_awaddr[27:0]};
```

The target's low 28 bits are prefixed with nibble 1, so target `0x8000_0000–0x8FFF_FFFF` (256 MB) lands at
DDR `0x1000_0000–0x1FFF_FFFF` — the upper half, matching `pynqz1_devicetree.dts` giving Linux only
`reg = <0x0 0x10000000>`. `PHYSTOP = 0x8800_0000` maps to DDR `0x1800_0000`, inside the window with half of
it spare. The block design's HP0 segment is offset 0x0, range 0x2000_0000, so no further translation.

Two things this exposes that are worth stating: bits [31:28] of the target address are **discarded**, so an
access at 0x9000_0000 would alias onto 0x1000_0000 rather than fault; and the 256 MB is a property of the
*wrapper*, not of the device tree.

**Before any loading or DMA**, the runtime ARM reserved-memory / Linux range must be read from the running
system, not from the repository DTS. That is step 4b of the cold-start plan and has **not** been done — it
cannot be, without the board.

## 6. Offline build command and rollback

Sealed input set: `build-inputs/MANIFEST.txt`, **15 sources**, hashes recorded; `build-inputs/project.tcl`,
`build-inputs/hierarchy.txt`, `build-inputs/teaching_top_shim.v`.

```
BUILD_INPUTS=<this build-inputs dir> JOBS=10 VIVADO_IMAGE=vivado-env:2025.2 \
  experiments/teaching-cpu/m4-build/build.sh <fresh attempt dir>
```

Target clock `host_clk_i` 40.000 MHz, part `xc7z020clg400-1`, unchanged. Pass conditions and the baseline
they are judged against (WNS +3.269 ns, TNS 0, 9,146 LUTs = 17.19%) are in `REPORT.md` §3. **Whether the
roughly doubled core closes timing is unknown until built**; a negative WNS gets reported with its failing
paths, not a lowered clock.

Rollback: the validated Rocket baseline identified by `m4-prep/audit/baseline-identity.txt`, which
`board-preflight.sh` binds. **A rollback PL is not loaded into live outstanding PS transactions**; cold,
quiescent programming is required and `PL_RECONFIG_SAFE` stays 0.

## 7. run-v3

Untouched, single reader, no duplicate run: job `xv6-run-v3`, driver v3. It has reached `init: starting sh`
and is in the shell stage. Its result will be reported as it comes out, and board preparation waives
nothing.

OPEN claude-xv6-board-integration-ready
