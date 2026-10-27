# Project context: read this first

Handoff for any new conversation (Claude Code, claude.ai, a human collaborator). It summarises decisions made
over a long working session from 2026-10-02 to 2026-10-27. The repository is the source of truth; this file
says where to look and why things are the way they are.

## What this repository is

A self-built multicycle RV64 CPU that boots xv6 on a PYNQ-Z1 (Zynq-7020) at 40 MHz, plus a pipelined and a
dual-core variant, an IPS performance campaign (fetch32, TLB, I-cache), and an unusually strict verification
culture: every change is accepted on evidence (tests, mutants that must fail, board logs, hashes).

Branch `teach-rv64ia` turns it into a teaching path: a student rebuilds the core step by step.

## Where to look

| Topic | File |
| --- | --- |
| The 12-step curriculum, status per step | `docs/TEACHING-PLAN.md` |
| The verification track V0..V9 (draft, branch `teach-verify`) | `docs/VERIFICATION-TRACK.md` |
| How to run the steps, the three fixed interfaces | `teaching/README.md` |
| Per-step assignment, tests, mutants | `teaching/stepN/README.md`, `teaching/stepN/TODO.md` |
| Pure-PL BRAM memory and top | `teaching/pl/README.md` |
| MCU-0: core + router + RAM + CLINT + GPIO, on the board | `teaching/mcu0/README.md` |
| CSR lecture deck (Chinese, 10 slides) | `teaching/step3/slides/` |
| Reference core (the oracle) | `rtl/cpu/` |
| Core-level harness, monitors, fault injection | `tests/cpu/tb/tcpu_harness.v` |
| Measured performance, baselines | `benchmarks/baselines/B0/REPORT.md`, tag `ips-v1-icache` |

## Decisions that are not obvious from the code

- **xv6 is reached on RV64IA + Zicsr + Zifencei.** M and C come after xv6 (steps 11, 12) as measured
  extensions. The xv6 build has exactly four source deviations, listed in `software/xv6/Makefile`; user-space
  multiply/divide is `user/softmath.c`, never libgcc.
- **Fetch is 4-byte aligned until step 12.** Parcel fetch arrives with C.
- **Every step is accepted on two things:** its tests pass AND its named fault-injection mutants fail for the
  stated reason (`--grep` on the log). A test that cannot fail proves nothing.
- **RTL stays in the Verilog-2001 subset.** iverilog accepts SystemVerilog-isms that Vivado rejects
  (`for (integer i ...)`, declarations in unnamed blocks, `[N]` array sizes, `default_nettype none` with
  untyped ports); several student bugs came from exactly that.
- **Tests whose expectations depend on the ISA** (step-3 c02, c03, c06) take `-DHAS_C/-DHAS_S/-DHAS_M` via
  `ISA_FLAGS`; the reference core gets all of them automatically.
- **Data on PHYSICAL_PORT is lane-positioned**; only the core shifts. Requests are naturally aligned (TileLink
  requires it), so misaligned accesses trap rather than being supported within a word.
- **The baseline core has 27 CSR addresses.**

## Student status (2026-10-27)

Steps 1 and 2 done by the student; their step-2 core drove MCU-0 on the board (LED blink + button mirror via
JTAG). Step 3 in progress: all d-tests pass, including `d09_pc_highpa`, the first test the student wrote;
the CSR module passes `tb_csr` 44/44; open items are Zicsr writeback (`csr_rdata` into rd in S_WB),
`illegal` must include `csr_addr_illegal`, then TODO 4 (bus errors) and TODO 5 (ecall/ebreak/mret).
The student's own files are `teaching/work/` (gitignored), on their machine.

## Proposed next course (not started)

A first course before this one: **single-cycle RV32I microcontroller with LUTRAM memories**, covering datapath,
control, exceptions and interrupts, and peripherals (GPIO, CLINT, UART, SPI, I2C, a small interrupt
controller), ending in an application on the board. The current 12 steps become the second course (memory
latency, multicycle sequencing, a real bus, xv6). Outline in the 2026-10-27 discussion: A1 datapath ... A10
project.

## Working conventions on the lab machine

- Vivado runs in docker: `~/vivado-docker/bin/vivado`, which mounts only `~/fpga`.
- Long jobs go through `~/fpga/coord`: `./coord claim vivado`, `./coord job start <name> -- <cmd>`, release
  after. Board work also claims `board`.
- Board safety: after programming MCU-0 the PL has no AXI slave; the PS must not touch `0x43C0_0000`.
  Cold-start procedures are in `docs/BOARD.md`.
