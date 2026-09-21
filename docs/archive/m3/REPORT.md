# M3: the teaching CPU on the legacy SoC, booting for real

Delegation: `codex-m3-soc-boot`, with the ROM question settled by `ROM_DECISION.md`.
Accepted run: `m3c-run`. Regressions: `m3c-regress` (M2-3) and `m3c-rocket` (Rocket isolation).
Directory map, including every superseded build and why it exists: `MANIFEST.md`.
Nothing here went near a board or Vivado.

## What was built

A thin Chisel BlackBox around the teaching CPU's Verilog — no logic of its own — driving the already
accepted M1-b bridge into the real subsystem: `tcpu_core -> PHYSICAL_PORT_V1 -> ReqRespToTL -> sbus -> mbus
-> TL/AXI4 -> SimAXIMem`, with the SoC's own BootROM, CLINT, PLIC, error slave, TSI serial adapter and block
device left as the Rocket configuration has them. No Rocket tile is instantiated; the Rocket configurations
are untouched; the CPU keeps one port and one outstanding transaction.

The CPU's interrupt inputs are wired to the real devices. The CLINT sizes its `msip`/`mtimecmp` arrays from
the number of outgoing interrupt connections, so attaching this sink is what makes `msip[0]` exist at all,
and the bit order is taken from the CLINT's own source (`int(0)` = msip, `int(1)` = mtip) rather than
assumed. The PLIC's M-mode context supplies `meip`. The debug module is kept and tied off, and deliberately
not routed into any interrupt input.

## The ROM, and the one instruction that had to change

The audit in `m3a-audit` is decoded from the image bytes. The boot path needs `addi csrrw jal csrrs sw slli
lw bne auipc wfi mret lui csrrc beq addiw add` — RV64I plus Zicsr plus `wfi` and `mret`, no M, C or A — and
the CSRs `mhartid`, `mtvec`, `mie`, `mideleg`, `mstatus`, `mepc`. Everything but `mideleg` the teaching CPU
already had.

`ROM_DECISION.md` adopted the narrow fix: for the teaching configuration only, the word at offset 0x54
(`csrrw zero, mideleg, zero`, an initialisation a machine with no S-mode has nothing to delegate from)
becomes a NOP. Nothing is inserted or removed, so every address and the TSI convention stay put.
`make-teaching-rom.sh` refuses to run unless the source is 156 bytes, hashes to the expected value and
actually holds `0x30301073` there, and afterwards requires exactly one 32-bit slot to differ.

    original  3c3ba8317ea4ab3562bb765aedf96931e759ffd15b26a3a82c323ad101a68dc5
    teaching  1ca1cbf08c7898784933b311608c5263885e6161238b22b373b57dee76463568

Checking the input file settles nothing about the hardware, so `m3a-rtl` reads it back out of the generated
Verilog: the core is instantiated as `tcpu_core #(.RESET_PC(65600))` — 0x10040, taken from the subsystem's
own `BootROMParams.hang` — and the ROM mux rebuilds to 2048 bytes whose first 156 are byte-identical to the
teaching image and not to the original, with `0x50 = 0x30451073` and `0x54 = 0x00000013`. The region starting
at exactly 0x1009c, the address the ROM computes into `a1`, begins with `d00dfeed`.

## Results (`m3c-run`, `M3_DONE fails=0`)

Four self-contained bare-metal programs — `rv64i_zicsr`, lp64, `norvc`, no library, and the runner rejects
any of them whose disassembly contains an M, C or A instruction — run on two timing profiles. All eight runs
exit 0 with no assertion of any kind in the log, and the event checker reports nothing on any of them.

| program | what it establishes | clean cycles | with backpressure |
|---|---|---|---|
| `boot01_marker` | the boot chain end to end, a console marker, exit 0 | 6611 | 6388 |
| `boot02_clint` | both CLINT sources, masking, the CLINT hole | 74765 | 79255 |
| `boot03_ddr` | DRAM at every access width and byte lane | 21557 | 22578 |
| `boot04_badaddr` | an unserviceable access becomes a precise trap | 7254 | 7485 |

The backpressure profile puts a delayer in the teaching master's own path, so the cycle counts move while the
results do not.

### The boot chain, as ordered events

Not "the host said zero" — the chain itself, out of the per-transaction log:

    cycle    1  first request is a fetch of 0x10040, the ROM's hang address
             .  the ROM wait loop at 0x1005c retires 28 times: it really waits
           673  MSIP comes up, from the real CLINT, after TSI has loaded the ELF
           684  the machine software interrupt is taken, mcause 0x8000000000000003, mepc 0x10060
           936  the first instruction retires in DRAM, after MRET
          6481  the exit store is issued
          6487  it is answered
          6489  it retires
          6611  nothing is left in flight

642 requests and 642 responses, every one matched and every response strictly later than its request. The
host's verdict is treated as a candidate only: the run drains until the CPU has nothing outstanding, and
whether the exit store completed is read out of the events, not inferred from a fixed number of extra cycles.

### The CLINT, closed through the device

`boot02_clint` drives both machine sources from software through the CLINT itself — no harness back door and
no test MMIO — and quiets each the way the device requires:

- software interrupt: `mcause 0x8000000000000003`, raised by writing `msip`, cleared by writing it again;
- timer interrupt: `mcause 0x8000000000000007`, raised by setting `mtimecmp` near `mtime`, quieted by moving
  the comparison out of reach;
- masking: with `mstatus.MIE` clear and the level held high, `mip` shows the source and nothing is accepted;
- the hole: `0x2000004` is inside the CLINT's window but outside the implemented `msip` registers. Measured,
  not assumed: the write is answered with `error=0` and the read returns zero — which is exactly what lets
  the ROM's wake loop exit after one pass on a single-hart machine.

### DRAM through the real AXI path

`boot03_ddr` covers `sd/ld`, `sw/lw/lwu`, `sh/lh/lhu` and `sb/lb/lbu` at every byte offset, including the
sign behaviour of each narrow load and the requirement that a narrow store leaves the other lanes alone,
then walks 64 doublewords. The memory port carries `ar=r=rlast=1675`, `aw=w=wlast=b=340` — non-zero in both
directions and closed per channel, counted with bursts in mind rather than assuming AR equals R.

## Negatives

| negative | result | what rejects it |
|---|---|---|
| the unmodified ROM | the host still reports 0 | the ordered event gate: DRAM is entered at cycle 317, before MSIP arrives at 673 |
| a bridge that drops a response | exit 2 | a request that is never answered |
| an address no manager claims | trap, program passes | cause 5 with the faulting instruction's own PC and the failing address in `mtval` |

The first is the one worth dwelling on, because an earlier draft of the audit got it wrong. It claimed the
original ROM would "stop at the sixth instruction". It does not stop: `mtvec` was set two instructions
earlier, so the illegal-instruction trap at 0x10054 vectors straight into the ROM's boot entry, which clears
`msip`, sets `mepc` and returns into DRAM **before TSI has loaded anything there** — and the run still exits
0. A gate that looked at the exit code, or that waited for a timeout, would have accepted it. Only the order
catches it. The trap itself is also checked: cause 2, `mepc` 0x10054, `mtval` 0x30301073.

## Two defects found in this work, both fixed

- **The subsystem was not held in reset at power-on.** The harness took the dut's reset from `sys_reset`
  alone. That register is not itself reset, so under randomised initialisation it could start deasserted,
  leaving the whole subsystem running on random state before anything had reset it; the bus monitors then
  fired at time zero, in modules that had nothing to do with the CPU. It is now `sys_reset || reset`.
- **The event log printed during reset,** carrying randomised cycle numbers and causes, and assertion text
  printed whether or not assertions were armed. Printing and stopping are now gated on the same switch,
  armed once the subsystem's reset is released. After both fixes, four programs over four repeats produce
  identical event counts — 1751 / 20397 / 5889 / 1979 — which is itself the evidence that the randomised
  initialisation no longer reaches the result.

## Regressions

- `m3c-regress`: the M2-3 event gate and the full M2-3 gate re-run under these sources, `fails=0` each, and
  both checkers report nothing. The CPU's own RTL is byte-identical to the M2-3 accepted snapshot.
- `m3c-rocket`: the Rocket configuration regenerated, its ROM read back out of its own generated RTL — 4096
  bytes, first 156 matching the **original** image and not the teaching one, `0x54 = 0x30301073` — then
  rebuilt and run: `Hello from Rocket Chip on PYNQ-Z1!`, exit 0. The teaching ROM did not leak into it.
  This says the isolation holds; it says nothing about the teaching core.
- The M1-b and M1-soc sources are untouched, byte-for-byte against their archived snapshots, so neither
  gate's change trigger applies.

## Reproducing

    teaching-cpu-work/cpu/make-teaching-rom.sh <original.img> <out.img>
    teaching-cpu-work/cpu/m3-gen.sh <Config> <outdir>
    teaching-cpu-work/cpu/m3-build-sim.sh <generated.v> <outdir>
    teaching-cpu-work/cpu/run-m3.sh <newdir>          # refuses a populated directory
    teaching-cpu-work/cpu/check-m3.py <log> boot|illegal [...]

`m3c-run` carries the ELFs with their disassembly and symbols, every per-case log and exit code, the source
snapshot with `src.sha256`, the four simulators' input hashes in `sim.sha256`, and `tools.txt`.

## What this does not show

- No M, C or A extension; no S or U mode, no MMU, no PMP, no delegation. `mideleg` is still unimplemented,
  which is why the teaching ROM exists.
- The PLIC is wired for `meip` but no device drives it: external interrupts are untested.
- The block device and TSI/DMA concurrency are not exercised; the block device is tied off.
- This is not xv6 and not the original `hello.riscv` on the teaching core: those need extensions this CPU
  does not have.
- Nothing has been near a board, a bitstream, Vivado, or the PS image.
