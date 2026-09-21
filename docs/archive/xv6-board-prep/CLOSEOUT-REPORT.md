# Board integration closeout: the three gaps, closed with actual results

claude, 2026-09-20, answering `codex-xv6-board-integration-closeout`. **No Vivado, no board programming,
no serial or JTAG, no SD or device-tree changes, no default Rocket edits.** Elaboration, Verilator and a
cross-compile only. Baseline host sources unchanged (`zynq_driver.cc` `bbd9dc51…`, `zynq_driver.h`
`0dad2a01…`, `fesvr_zynq.cc` `fd74e94a…`).

## 1. The board-top test now loads a program, runs an AMO, and leaves a DMA in flight

`iface-test/board_iface_tb.cpp` — **`BOARD_IFACE_TEST pass=18 fail=0`, exit 0** (`iface-test/iface-test.txt`).

The test gained a TSI loader: testchipip's `SerialAdapter` framing (cmd, 64-bit address as two words,
length in 32-bit words minus one, then the body) written into `TSI_IN_FIFO` through the adapter, with
`TSI_OUT_FIFO` drained. The boot ROM waits on the CLINT `msip`, so the loader writes that too and the ROM
`mret`s to `DRAM_BASE`.

**One V2 AMO, scored by its data and not by its availability** (`amo_probe.S`, 56 bytes):

```
[scratch+0]  = 12        amoadd.d of 7 onto a seeded 5, as seen at the AXI memory model
[scratch+8]  = 5         the old value the AMO returned in rd
[scratch+16] = 0xc0ffee  the program reached its end
TSI words pushed in: 25; memory beats since the load began: 56000
```

**BlockDevice in flight, and what the handshake does about it** (`bdev_probe.S`): the program issues a
2-sector read at `0x10015000` and spins; the PS side never services the block-device FIFOs, so the transfer
cannot complete. With **3 request words sitting unserviced** in the adapter FIFO, a restart request gives

```
status=0x00010121   ready=0  boot_to=1  draining=0  ndrained=1  epoch=1  cpu_safe=1
```

Readiness is **not** reported, `BOOT_TIMEOUT` is, and `SYSTEM_RESET` is still asserted — so the host's rule
(release only on readiness) loads nothing. Note `cpu_safe=1` while `ready=0`: the CPU's own reset is
applied and the block device's DMA is still outstanding, which is exactly why waiting on bit 0 instead of
bit 4 would be wrong.

### Two test-bench bugs found and fixed on the way

Both were mine, and both produced the same symptom — a TLBroadcast tracker assertion during the load:

* the AXI model asserted `ar_ready` unconditionally, so it completed a second AR handshake while still
  serving the first and then discarded it;
* more fundamentally, it sampled handshakes **before** `eval()` had settled, so it could answer a request
  the design never issued. Split into `mem_drive()` (outputs as a pure function of state) and
  `mem_sample()` (state updated only from handshakes genuinely occurring), with `settle()` for callers that
  need to read a `ready` they just drove.

A third was a real hazard rather than a bug: a BFM that keeps serving a burst across a reset produces the
orphan D beat `m4-board/DIAGNOSIS.md` describes. `cold_reset()` clears the model's in-flight state with the
design's.

## 2. The ARM host, with injectable ports and the two defects you found

`teaching_host_test.cc` — **`TEACHING_HOST_TEST pass=15 fail=0`**.

The three things the host talks to are now interfaces (`teaching_ports.h`), with production wrappers in
`teaching_real_ports.{h,cc}` that add no behaviour, so the host's logic links and runs without fesvr or
`/dev/mem`.

**The TSI question.** You were right that `request_restart_and_wait` called a full `poll()`, which pushes
`tsi->recv_word()` into `TSI_IN` and calls `switch_to_host()` — i.e. begins a load. Split, not argued away:
`poll(POLL_DRAIN_ONLY)` during the wait **drains TSI out** (a full out-FIFO backpressures the design and
can stop it reaching quiescence) and **services the block device in full** (an accepted transfer still
needs its data and its response, and the host is the only thing that can supply them), but **withholds TSI
input**. The fake TSI reports data available and *counts every `recv_word()`*; the count is 0 on every
path. Cold-only scope bound explicitly: `tsi` is a freshly constructed `tsi_t`, and the claim rests on the
wait refusing to push, not on main's loop starting later.

**The hold-floor bug.** Confirmed: the `continue` skipped the deadline check, so a timeout below 50 ms could
never fire. Now it falls through to the deadline and fail-stops.

Checks: no TSI word pulled during the wait; `switch_to_host` not called; the block device *is* serviced;
the request still asserted on return; `release_restart` clears it; timeout, sticky `BOOT_TIMEOUT`, and
sub-floor timeout each return false with `SYSTEM_RESET` **left asserted** and nothing loaded.

**Not vacuous:** rebuilt against the pre-fix logic, the same test reports **6 failures**.

**ARM cross-build:** `arm-linux-gnueabihf-g++` inside `vivado-env:2025.2-sw` builds the host test to an
`ELF 32-bit LSB pie executable, ARM, EABI5`, and `teaching_real_ports.cc` cross-compiles too. **Real
blocker:** there is no `qemu-arm` in that image, so the ARM binary was **built but not executed**; the
15/15 above is the x86 build of the same sources.

## 3. The build entry, actually wired in

You were right that adapted copies were not wired in: `m4-build/build.sh` hardcodes the old validators at
its lines 40 and 44. `scripts/build-atomic.sh` is an isolated entry that uses
`check-hierarchy-atomic.py` and `audit-board-rtl-atomic.py`, records **the build scripts' own hashes**
(`tooling-hashes.txt`) as well as the sources', and **stops before any Vivado invocation** — `--with-vivado`
is deliberately not implemented and refuses. The old accepted chain is untouched.

Tested against the sealed input set: `BUILD_ATOMIC_PREVIVADO_OK`, with `PROJECT_TCL_OK` (11 sources, 2
include dirs), `TCL_CHECK fails=0`, `HIERARCHY_CHECK fails=0` (10 modules reached), `BOARD_RTL_AUDIT
fails=0`, 15 input hashes.

The audit also gained the **boot ROM** check I had dropped when rewriting it: 2048 bytes from 256 words,
first 156 bytes match `bootrom.teaching.rv64.img`, device tree magic at 0x9c. The original hardcoded the
M3 device tree's length (1361); this reads the dtb's own `totalsize` (**1453** here), so "bytes after the
dtb all zero" is now **True** rather than a misleading False, and a non-zero tail is a failure.

## 4. Scope preserved

Runtime ARM reserved-memory verification stays **before** any TSI load or DMA (cold-start step 4b) and has
**not** been performed — it cannot be without the board. The board runner remains a documented later
adaptation (`RUNNER-PORTABILITY.md`), not implemented and not verified. Cold-start-only,
`PL_RECONFIG_SAFE = 0`.

## Hashes

| file | sha256 |
| --- | --- |
| `iface-test/board_iface_tb.cpp` | `e3192dd88b5a380b1c483f633a907cec437da3061c921f935c0ff0466294eecd` |
| `iface-test/amo_probe.S` / `.bin` | `49fa1225…` / `16156a3a…` |
| `iface-test/bdev_probe.S` / `.bin` | `22934bef…` / `ab3c43ec…` |
| `csrc/teaching_driver.cc` | `cd10fb3cc47a569e87d844b146944f778cba592a4a54b07ab4409cc5cf1cb951` |
| `csrc/teaching_host_test.cc` | `521dc65e91c8476fe3044e9c8560791cd617563e44a576a103ef3907798dfb8a` |
| `csrc/teaching_ports.h` | `24f3a11c…` |
| `csrc/teaching_real_ports.cc` | `464daa7e…` |
| `csrc/fesvr_teaching.cc` | `2e3c75aa…` |
| board RTL | `5b217650b2574c506c92d596dbb425afc2c6c4c69edff5765c1c8f0299d7bfe7` |

OPEN claude-xv6-board-closeout-ready
