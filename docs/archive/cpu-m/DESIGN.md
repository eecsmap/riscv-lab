# CPU-M — the RV64 integer multiply/divide extension on the multicycle teaching core

Decision D2 (m2-prep/DECISIONS.md): iterative, readable, low-resource. No combinational `*`, `/`, `%`
anywhere in the synthesisable path; no pipelining, no cache, no second outstanding request, no new memory
interface. Nothing else is claimed: no A, no C, no S/U, no Sv39, no PMP.

## The unit (`teaching-cpu-work/cpu/rtl/tcpu_muldiv.v`)

One shared datapath, 64 iterations for every operation, then one cycle to assemble the result:
start-to-done is **65 cycles** for all 13 operations (measured by the unit test, min = max = 65).

* **Multiply**: shift-and-add on magnitudes; `{hi, lo}` shifts right one place per step with the
  multiplier in `lo`. The sign is restored afterwards on the 128-bit product for MUL/MULH (both signed)
  and MULHSU (rs1 signed, rs2 unsigned); MULHU takes the unsigned high half. MULW runs the same datapath on
  the sign-extended low words and narrows.
* **Divide**: restoring division on magnitudes (65-bit remainder, one compare-subtract per step). Then the
  RISC-V rules: quotient sign = sign(a) xor sign(b); remainder sign = sign(a); divisor zero → quotient all
  ones, remainder = dividend; the single overflow (most negative dividend, divisor −1) → most negative
  quotient, remainder 0. The W forms operate on 32-bit values (sign- or zero-extended for the signed and
  unsigned forms respectively) and every W result is sign-extended from bit 31.

**Timing contract.** `start` is accepted only while `busy` is low; on that edge op/a/b are latched once.
`busy` is high from the next cycle until the cycle `done` pulses. `done` is exactly one cycle wide, with
`result` valid on it and held until the next acceptance. A `start` while busy is ignored (no restart, no
duplicate). Synchronous reset clears busy/done and all intermediate state; no `done` can appear after it.

## The core (`tcpu_core.v`)

* Decode: `funct7 == 0000001` on OP (all eight funct3) and OP-32 (funct3 000, 100, 101, 110, 111) is
  `is_muldiv`; other OP-32 funct3 with that funct7 stay illegal. The unit opcode is 0..7 for OP and
  8..12 for OP-32.
* A new state `S_MUL` (4'd9). From `S_EXEC`, after every trap check, an M instruction raises a one-cycle
  `md_start`, sets `npc = pc + 4` and waits in `S_MUL`. On `done` it schedules `wb_we/wb_rd/wb_value` and
  retires through the ordinary `S_WB → S_ARCH` path, so every M instruction retires exactly once, with its
  own PC and encoding on the commit record, and `rd = x0` is discarded by the register file as always.
* No memory request is issued in `S_MUL`, and interrupts are not looked at there: they are only ever
  sampled in `S_IF_REQ`, which follows this instruction's retirement. A pending IRQ therefore waits for the
  result to be written back and `mepc` is the next instruction. Nothing is remembered about a pulse that
  fell meanwhile — a level is what the CPU samples.
* Reset: the core's reset restarts at fetch and the unit's reset clears its state, so no stale result is
  written back. The SoC's controlled restart (R-BOOT) still drains the CPU bridge first; the unit is not a
  reason to cancel a committed bus transaction, because it never owns one.

## CSR

`misa` = `0x8000_0000_0000_1100`: MXL = 2, I (bit 8) and M (bit 12). It remains a fixed WARL value
(writes accepted and discarded). The one existing regression expectation that changes is `c02_warl`'s
`+expect-csr=8:…0100 → …1100`; the change is recorded as a diff next to the re-run.

## Fault injection (named negatives)

`FAULT_W_SEXT` (W results zero-extended) and `FAULT_MULH_SIGN` (signed high half not corrected) are
parameters on the unit, plumbed through the top so that a core built with either fails the M test on the
check that owns that property — and still passes an RV64I program, so the failure is attributable.
