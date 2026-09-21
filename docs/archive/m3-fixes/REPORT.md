# M3 validation fixes: the exit transaction, identified rather than guessed

Delegation: `codex-m3-validation-fixes` and then `codex-m3-tail-target-fixes`. Accepted run: `run-b`.
`../m3` is untouched. The first attempt at this work is `run-a`, kept, with what was wrong with it below.

## Round one: four holes in the event gate

Codex mutated a passing log four ways and my checker accepted all four. The causes were all the same shape —
looking at sets and totals rather than at the sequence of events: requests and responses were kept in
dictionaries keyed by sequence number, so a duplicate overwrote its twin; only `requests - responses` was
computed, so an orphan response was invisible; the AXI line was printed and never gated; and the boot chain
had no MRET in it, so deleting the return still looked like a correct boot. The checker also trusted the
runner for the exit code, the host result and the absence of assertions, and checked the exit store for only
one of four programs.

`check-m3.py` is now a state machine over the events, with one outstanding transaction, and every claim tied
to an event. `probe-m3.py` mutates a passing log fifteen ways; all fifteen are rejected, each by its own
rule. That part Codex accepted.

## Round two: the interception was landing on the wrong transaction

The exit-store negative matched on **the write address alone**. `htif_putc` writes that same address for
every console character, so the intercept landed on the first character — PC 0x80000040, data
`0x0101000000000054`, the `T` of the marker — and the program never reached its exit at all. "No host
result" therefore proved nothing about what happens when the host *has* seen `tohost`. That claim is
withdrawn.

The exit transaction is now identified by four things at once: the store's own PC, the address, the
direction, and an HTIF **exit** payload (device 0, command 0, bit 0 set). A console write carries device 1
command 1 and an even payload, so it cannot match. The transaction that was actually intercepted is written
into the log as a `TAILHIT` event and checked:

    EV 6481 TAILHIT seq=630 pc=0x0000000080000084 addr=0x800000c0 wdata=0x0000000000000001

`0x80000084` is `exit_store`; `0x0000000000000001` is `(0 << 1) | 1`. Exactly one transaction is
intercepted in each run, and the gate fails if the hit is anywhere else.

### Three modes, and what each one shows

| run | intercept | result |
|---|---|---|
| `clean-boot01_marker` | none | exit 0, gate passes |
| `tail-withheld` | the response is never delivered | exit 3, and no host result stands |
| `tail-errored` | the response comes back with `error` | the CPU takes a store access fault; the gate rejects it on the errored exit response |
| `tail-delayed` | the response is held back 2000 cycles, then delivered | exit 0, and the gate passes **after waiting** |

`tail-delayed` is the case that carries the argument. Its exit store is requested at cycle 6481 and answered
at **8487**, retiring at 8489, against 6487/6489 in the clean run; the tail drains for 1887 cycles instead
of 5. And the host had already declared success: every run now records `busy` at that instant, and it reads

    HOSTDONE exit_code=0 busy=1

in both the clean and the delayed run. The host's verdict precedes the CPU's completion on *every* run here
— by five cycles normally — so waiting for the CPU is not a hypothetical discipline, it is load-bearing.

`tail-errored` ends with the process exiting 0, because fesvr saw the value in memory before the error was
injected on the response path. That is the honest outcome and it is why the verdict comes from the gate:
the checker rejects the run because the exit store's response carried `error`, and says so. It is not
rejected by a timeout.

The earlier first-fetch negative is kept as `neg-drop-first-fetch`; it shows that an unanswered transaction
is caught, and it is not a substitute for the above.

## The AXI gate is now per burst

The previous check compared totals: `ar == rlast`, `aw == wlast == b`, beats at least bursts. Totals can
balance while individual bursts are wrong, so `check-axi.py` walks the channel events instead: every AR
opens a burst of `len + 1` beats on its ID, R beats close it in order with `LAST` only on the final beat, W
data follows AXI4's ordering rule, every AW is answered by a B with the matching ID, responses are checked,
and nothing may be outstanding at the end.

`probe-axi.py` mutates a clean channel log seven ways, each of which leaves the totals balanced or
self-consistent, and all seven are rejected:

    bad-resp  beat-moved  extra-b  last-too-early  missing-w  no-last  unknown-id

The port carries every master in the subsystem, the TSI adapter included, so this is a property of the port
rather than an attribution to the CPU; that distinction is stated rather than blurred.

## The matrix

Four programs on two timing profiles, eight runs, each gated on its own symbols, marker, interrupt count and
synchronous-exception expectation, and each with its own per-burst AXI check. `boot02_clint` alone accounts
for 7271 read bursts and 188 write bursts, every one closed on its own ID.

Determinism, in place of a seed: `-s` is parsed by the simulator's `main` but rejected by fesvr, which
parses the same command line, so no seed is passed. The same binary is run twice and must produce the same
number of events — 1802 both times.

## Scope

`ReqRespToTL.scala` and `PhysPort.scala` are byte-identical to their M1-soc snapshots and the CPU's RTL is
byte-identical to the M2-3 snapshot, so no regression trigger applies. The changed integration file is
`TeachingCpuSoc.scala`: the four-way exit match, the bounded-delay mode, the `TAILHIT` record, the per-burst
AXI events, and a `busy` that covers a request offered but not yet accepted and a response awaiting
retirement. `cpu_boot_main.cpp` records `busy` at the host result and fails on a trap taken after it.

`run-b/src.sha256` includes the runner, both checkers and both probe scripts.

## Still not shown

No M, C or A; no S or U mode, no MMU, no PMP, no delegation. The PLIC is wired for `meip` but nothing drives
it. The block device is tied off. Nothing has been near a board.
