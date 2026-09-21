# Board procedure: transport, and the memory check that must come first

claude, 2026-09-20, closing the third pre-board item of `codex-xv6-atomic-vivado-build`. **Nothing here has
been executed.** It is a procedure to be reviewed before it is run, and running it needs programming and
serial authority that has not been granted.

## 1. The check that must happen before any TSI load or DMA

The hazard is recorded in `pynqz1_devicetree.dts` and is not hypothetical: if Linux is given the whole
512 MB, xv6's `kinit()` memsets every page from `end` to `PHYSTOP` and overwrites the ARM kernel, which
produced slab-allocator Oopses. With the board kernel at 128 MiB the target writes DDR
`0x1000_0000–0x1800_0000`; if Linux owns that, the ARM dies mid-run.

**The repository's DTS is not evidence of what is running.** The board may be booted from an SD image built
at another time. So the check reads the *live* system, and all four readings must agree:

*Corrected after review:* an earlier version read `/proc/device-tree/memory/reg` with `od -An -tx4`. That
is wrong. **Device-tree cells are big-endian regardless of the CPU**, so `od -tx4` on a little-endian ARM
byte-swaps every cell and silently reports a different address; and a listing of reserved-memory *names*
is not evidence of where those regions are. The check is therefore not a set of eyeballed greps but a
program, `scripts/mem-preflight.py`, run over a captured evidence bundle:

| captured from the running ARM | into |
| --- | --- |
| `/proc/sys/kernel/random/boot_id` | `session-id` |
| `/proc/device-tree/#address-cells`, `#size-cells` | `dt/address-cells`, `dt/size-cells` (raw) |
| `/proc/device-tree/memory/reg` | `dt/memory-reg` (raw bytes, **not** text) |
| `/proc/device-tree/reserved-memory/<node>/reg` for every node | `dt/reserved/<node>/reg` (raw) |
| `/proc/iomem`, `/proc/meminfo` | `proc-iomem`, `proc-meminfo` |

`mem-preflight.py` decodes the cells big-endian at the widths the tree declares, enumerates **every**
(address, size) tuple of memory and of each reserved region, and refuses unless all of it agrees: no Linux
memory and no reserved region may overlap `0x1000_0000–0x1FFF_FFFF`; `/proc/iomem`'s System RAM must stop
below it and agree with the tree; `MemTotal` must be consistent with the tree and under 384 MiB. Missing,
empty, redacted, malformed or mutually inconsistent evidence is a refusal, not a default.

It is **bound to the boot** it was taken from: the bundle carries the session id and the preflight is run
with `--expect-session`, so evidence from a previous boot is refused by construction. **After any reboot
the capture and the check must be redone, before any load or DMA.**

Self-test: `scripts/mem-preflight-selftest.sh` — 14 cases, all passing. The safe 256 MiB machine is
accepted (and so is the same machine described with 2-cell addresses, which is how the cell widths are
shown to be read rather than assumed); the 512 MiB machine, an overlapping reservation, a malformed reg
blob, evidence from another session, a hand-redacted capture, a device tree that disagrees with
`/proc/iomem`, a reserved-memory name with no `reg`, and each of five kinds of missing file are all
refused with the right reason.

Any refusal is a **stop**. The recovery is to fix the ARM boot configuration, which is outside this task's
scope — no SD or device-tree edits — and to come back.

Ordering, stated so it cannot be reordered by convenience: **check → program the PL (cold) → start
`fesvr-teaching` → TSI load → DMA.** The check is before the load because the load is the first thing that
writes to the target's DDR window.

A second reading, after the run, is worth taking: `MemTotal` and the kernel log should be unchanged. If the
ARM kernel logged allocator errors during the run, the window was not actually free whatever step 1 said.

## 2. The transport

`fesvr-teaching` runs **on the ARM**. The driver runs here. Between them:

* **an authenticated shell session to the board's Linux**, with the driver owning it for the run. The
  session carries `fesvr-teaching`'s stdout, which is the target's console, and its stdin.
* **exactly one host process.** *Corrected after review:* an earlier version of this said the board's UART
  console must not be opened, as though any serial reader were a second HTIF reader. That is wrong and
  worth being precise about — the ARM's serial console carries **Linux's** console, which is a different
  stream from the target's. A terminal attached to it reads nothing of HTIF and contends for nothing here.

  The resources that really are exclusive are named ones:
  * **`fesvr-teaching`'s own stdin/stdout**, which is where the target's console actually is. The
    transport holds that pipe pair and is its only owner.
  * **the mapping of the adapter at `0x43C00000`**, which every host process opens through `/dev/mem`.
    Two hosts would be two owners of the restart handshake and two readers of the same TSI FIFOs, and
    neither would know about the other.

  So the rule is one `fesvr-teaching` at a time — and in particular not one alongside the stock
  `fesvr-zynq`, which pulses `SYSTEM_RESET` in its constructor. `BoardTransport` enforces this with an
  ownership claim and refuses to start when the claim is held.

### Shutdown

Stopping the host does not stop the design. From `STATUS-MAP.md` and the handshake:

* the driver stops `fesvr-teaching` and does **not** release the restart request as cleanup;
* if the host fail-stopped (exit 2), the design is deliberately left held — that is the safe state;
* recovery is a **cold platform restart**. The PL is never reloaded with transactions possibly outstanding;
  `PL_RECONFIG_SAFE` is `1'h0` in the netlist and nothing may read it otherwise.

### What the driver needs, and does not yet have

`RUNNER-PORTABILITY.md` specifies the four-operation transport and the board identity set
(`# platform: board`, bitstream, host binary, run-time device tree). **Not implemented.** It should not be
written until the transport and the authority to use it are decided.

## 3. First-boot sequence

| step | action | pass | timeout | on failure |
| --- | --- | --- | --- | --- |
| 0 | `board-preflight.sh --build <attempt>` | fail-closed preflight passes | — | stop, no programming |
| 1 | **§1 memory check on the running ARM** | all four readings agree | — | stop; fix the ARM boot config |
| 2 | cold power-on; program the PL from a quiescent platform | configuration done | — | power cycle |
| 3 | hold `SYSTEM_RESET` ≥ 50 ms before each load, as the accepted operating condition | — | — | — |
| 4 | the four accepted M3 bare-metal programs on the new bitstream | their four OK markers, each returning 0 | 60 s each | stop, keep the console, roll back |
| 5 | one bare-metal program each for M, C, Sv39 and A | explicit OK markers | 60 s each | stop, report which extension |
| 6 | xv6 kernel (**128 MiB build**) + the pristine `fs.img` (`4691ffea…`) | banner, `init: starting sh`, a prompt | 120 s | capture console, compare against the simulation of the same source |
| 7 | the four accepted commands, judged by the same `check-xv6.py` | `fails=0` | 120 s | report honestly |
| 8 | re-read `MemTotal` and the ARM kernel log | unchanged, no allocator errors | — | the window was not free; stop |

A board pass does not retire a simulation result and a simulation pass does not authorise a board step.
They are separate claims about different machines, and the identity record in each transcript is what says
which.
