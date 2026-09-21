# CPU-C — integer compressed instructions and the simplest variable-length fetch

Scope: RV64IMC on the multicycle single-port core. No F/D (so no compressed FP), no A, S/U, MMU, cache,
pipeline, or Zc*. The physical port contract is unchanged: one outstanding request, `valid` never
withdrawn, response no earlier than the next cycle, naturally aligned narrow reads only.

## Decompressor (`rtl/tcpu_cdecode.v`)

Combinational: 16-bit parcel → 32-bit instruction + `illegal` + `hint`. The table is `ENCODINGS.md`. The
core's 32-bit decode is reused unchanged: a compressed instruction is executed as its expansion, but the
core keeps the **original parcel** (`raw_insn`, zero-extended), the **start PC** and the **length** (2 or 4),
which is what the commit record and every exception report carry. A HINT expands to `addi x0, x0, 0`.

## Fetch: serial halfwords

```
S_IF_REQ  : one naturally aligned 2-byte read at pc            (size 1, lane = pc[2:1] of the 64-bit beat)
S_IF_WAIT : capture the parcel. bits[1:0] != 11 → compressed: expand, insn_len = 2, go to S_EXEC.
            else                          → S_IF2_REQ
S_IF2_REQ : one 2-byte read at pc + 2  (its own address register; the add is 64-bit and range-checked)
S_IF2_WAIT: assemble {hi, lo}, insn_len = 4, go to S_EXEC
```
The second read is issued **only** when the first parcel says the instruction is 32 bits wide, so the
fetch never crosses into the next word, page or device speculatively, and no unaligned 32-bit request is
ever put on the bus. The two addresses are held separately (`pc` and `pc2 = pc + 2`).

* A first-parcel error: cause 1, `mepc` = pc, `mtval` = pc. A **second-parcel** error belongs to the same
  instruction: cause 1, `mepc` = pc (the instruction did not run), `mtval` = pc + 2 (the address that
  actually failed). Nothing retires. A high address that would wrap past the physical range is an access
  fault, not a low-address fetch.
* Interrupts are sampled only in `S_IF_REQ` before the first request is raised — never between the two
  halves, and a committed request is never withdrawn.
* Core reset clears the captured first parcel, so a stale half cannot be spliced into a new instruction.

## Alignment and CSRs

* Instruction addresses are 2-byte aligned: the fetch checks `pc[0]`. Branch and JAL immediates are even and
  JALR clears bit 0, so instruction-address-misaligned cannot occur with C; the check remains on bit 0.
* `mepc`: bit 0 forced to 0 on trap entry and on a software write (D4: with C, only bit 0).
* `mtvec`: BASE stays 4-byte aligned (direct mode only); the MODE bits are still forced to 0.
* `misa` = `0x8000_0000_0000_1104`: I, M, C; fixed WARL, writes discarded.
* Data-access alignment rules are unchanged.

## Observation

`commit_insn` carries the raw parcel (16-bit, zero-extended) or the 32-bit word; `commit_len` (new
observation output, not part of the physical port) is 2 or 4.

## Testbench model of the reset bridge

`dbg_req_is_fetch` is true for both parcels (states `S_IF_REQ/S_IF_WAIT/S_IF2_REQ/S_IF2_WAIT`); the first
version covered only the first parcel, so a second-parcel fetch was counted as a *data* request and
`FETCH_ERR_ADDR` could never aim at it (found by `core-run1`, kept). `FETCH_ERR_AFTER` still counts
instructions (first parcels), so the M2-3 expectations that use it are unchanged.

A core-only reset (`bd_core_rst`, the R-BOOT split) can land while the second parcel is outstanding. The
harness models what the RD2 bridge does in the SoC: an offer that never fired is dropped without a protocol
error, an already-accepted request is answered by the memory and the answer is swallowed
(`BRIDGE MODEL: stale response ... discarded`, counted in `n_discard`), and no new request is accepted until
that has happened; an answer that falls due in the very cycle the reset arrives is swallowed in that cycle
(the first version flagged it for later and then waited for a response that had already gone out — `core-run2`
hung on exactly that, kept). The restarted core therefore cannot receive a parcel it did not ask for — with the slower
timing profiles the stale answer arrives *after* the restart, which is exactly the splice this rules out.
