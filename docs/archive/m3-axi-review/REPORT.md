# M3 AXI causality: the gate now has a timeline

Delegation: `codex-m3-axi-causality`. Accepted run: `run-a`. Nothing was rebuilt — no RTL changed, so this
replays the logs the accepted M3 run already produced. `../m3-fixes/run-b` and everything earlier is
untouched.

## What was wrong

The previous `check-axi.py` loaded every AR and AW into its queues before it looked at a single R or B. A
log in which every response sat at cycle 0 — before the request that asked for it — therefore passed, which
Codex demonstrated directly. B was worse: it was matched by comparing sorted ID counts, with no time in the
comparison at all. The script checked shape and never checked causality.

## What it checks now

`check-axi.py` walks the events in cycle order. Within a cycle it applies the address and write-data events
before the responses, so a response may legitimately share a cycle with the thing it depends on, and the
order the lines happen to be printed in does not matter.

- an R beat belongs to a read burst whose AR has already happened, on the same ID, in order within that ID
  and freely interleaved across IDs; its cycle may not precede its AR;
- a burst gets exactly `LEN + 1` beats, with LAST on the last and nowhere else;
- write data follows AXI4's ordering rule and may arrive **before** its AW, which is buffered and associated
  when the AW appears;
- a B belongs to a write burst whose AW has happened and whose write data is already complete; its cycle may
  not precede that completion;
- responses carry a sane RESP, and nothing may be left outstanding at the end.

The "at least the next cycle" rule the CPU's own port obeys is deliberately **not** applied here: on AXI the
dependency is the handshake, not a fixed cycle gap, so a same-cycle response is accepted and is covered by a
probe.

## The probes

Eighteen cases, and the second half matters as much as the first: a gate that rejects everything is no more
useful than one that accepts everything.

Rejected, each by its own rule — every one of them leaves the channel totals balanced or self-consistent:

    all-B-at-zero  all-R-at-zero  b-before-aw  b-before-last-w  bad-resp  beat-moved
    duplicate-b  extra-b  last-too-early  missing-w  no-last  r-before-ar  unknown-b  unknown-id

Accepted, because they are legal AXI that a naive in-order single-ID reading would wrongly reject:

| case | what it exercises |
|---|---|
| `w-before-aw` | write data ahead of its address |
| `cross-id-oo` | two IDs completing out of order, in order within each |
| `same-cycle` | a response in the same cycle as the request it depends on |
| `line-order` | the real log with the lines of each cycle shuffled |

`line-order` is the one that pins down the claim about print order: it is the accepted `clean-boot01_marker`
log with every cycle's lines permuted, and it still passes.

## Replay

All eight accepted SoC logs pass unchanged:

| log | read bursts | write bursts |
|---|---|---|
| clean-boot01_marker | 581 | 72 |
| clean-boot02_clint | 7271 | 188 |
| clean-boot03_ddr | 1678 | 340 |
| clean-boot04_badaddr | 508 | 141 |
| delay-boot01_marker | 541 | 72 |
| delay-boot02_clint | 7298 | 188 |
| delay-boot03_ddr | 1663 | 340 |
| delay-boot04_badaddr | 488 | 141 |

The three tail runs pass too, including `tail-withheld`, which is stopped with the CPU's own transaction in
flight: the interception is on the CPU's port, not on the memory port, so the AXI side still closes.

The port carries every master in the subsystem, the TSI adapter included. This is a property of the port,
not an attribution of bursts to the CPU, and it is stated rather than blurred.

## Regression scope

No RTL, no Chisel and no C++ changed in this round — only `check-axi.py` and `probe-axi.py`. The simulators,
the generated RTL, the ELFs and every other gate are the ones already accepted in `../m3-fixes/run-b`, whose
log hashes are recorded here in `replayed-logs.sha256`. Nothing needed rebuilding and nothing was rebuilt.
