# CPU-A — the A extension in the teaching core: design and coverage

Delegation `codex-cpu-a-integration` (acked 2026-09-19). The backend, the V2 port and the V2 bridge were
accepted in `cpu-atomic-backend/` (`CODEX_REVIEW_3.md`); nothing in them is reopened here. Written before
the RTL. Authoritative contract: `cpu-atomic-prep/CODEX_DECISIONS.md`.

## 1. What is added

RV64A in `teaching-cpu-work/cpu/rtl/tcpu_core.v`: `LR.W/D`, `SC.W/D` and the nine AMOs (`SWAP ADD XOR AND
OR MIN MAX MINU MAXU`) × `.W/.D` × all four `aq/rl` combinations. The core stays what it is — no cache,
multi-cycle, one port, one outstanding request. **One A instruction issues exactly one V2 request**; the
core never emulates an atomic with ordinary reads and writes.

`aq`/`rl` are decoded and accepted, and have no further effect: with a single in-order outstanding request
and no cache there is nothing to reorder. That is a property of this core, not a general claim, and it is
stated in the report rather than tested as ordering.

## 2. The port (PHYSICAL_PORT_V2)

The core's existing V1 signals gain exactly what `PhysPortV2.scala` already defines:

| Signal | Direction | Meaning |
|---|---|---|
| `req_amo[3:0]` | core → bridge | 0 = not an AMO, else the `AmoOp` code (SWAP 1, ADD 2, XOR 3, AND 4, OR 5, MIN 6, MAX 7, MINU 8, MAXU 9) |
| `req_lrsc[1:0]` | core → bridge | 0 none, 1 LR, 2 SC (3 is reserved and never issued) |
| `resp_scfail` | bridge → core | the SC's result, valid with `resp_valid` |
| `resv_clear` | core → bridge | one-cycle pulse: drop the reservation (trap taken, core reset) |

Ordinary fetches, loads, stores and every page-table read carry `amo = 0, lrsc = 0`. The request's payload
(address, size, `wdata`, `wmask`, `amo`, `lrsc`) is held stable from the cycle `req_valid` rises until the
handshake, and a response is accepted no earlier than the following cycle — the V1 rules, unchanged.

### Request formation

| Instruction | write | size | addr | `wmask` | `wdata` | `amo` | `lrsc` |
|---|---|---|---|---|---|---|---|
| `LR.W/D` | 0 | 2 / 3 | `rs1` | 0 | 0 | 0 | 1 |
| `SC.W/D` | 1 | 2 / 3 | `rs1` | exact lanes | `rs2 << 8·addr[2:0]` | 0 | 2 |
| `AMO*.W/D` | 1 | 2 / 3 | `rs1` | exact lanes | `rs2 << 8·addr[2:0]` | code | 0 |

"exact lanes" = `(size == 2 ? 8'h0f : 8'hff) << addr[2:0]`, which for an aligned access is exactly the
addressed half or the whole word — the bridge refuses anything else.

### Response handling

| Instruction | `rd` | Notes |
|---|---|---|
| `LR.W` / `AMO*.W` | the old word from `resp_rdata[8·addr[2:0] +: 32]`, **sign-extended** | including `MINU/MAXU`: the *returned* value is the original word, sign-extended |
| `LR.D` / `AMO*.D` | `resp_rdata` | |
| `SC.W/D` | `resp_scfail ? 1 : 0` | |

`rd = x0` still performs every side effect (the request is issued, the memory is modified, the reservation
moves); only the register write is suppressed, exactly as for an ordinary load.

## 3. Decode and legality

Opcode `0101111` (AMO). `funct3` = `010` (.W) or `011` (.D); anything else is illegal. `funct5 =
insn[31:27]`:

| funct5 | insn | funct5 | insn |
|---|---|---|---|
| 00010 | `LR` (**`rs2` must be 0**, else illegal) | 00000 | `AMOADD` |
| 00011 | `SC` | 00001 | `AMOSWAP` |
| 00100 | `AMOXOR` | 01100 | `AMOAND` |
| 01000 | `AMOOR` | 10000 | `AMOMIN` |
| 10100 | `AMOMAX` | 11000 | `AMOMINU` |
| 11100 | `AMOMAXU` | others | **illegal** |

`aq = insn[26]`, `rl = insn[25]`: all four combinations legal. An illegal encoding traps with cause 2 and
`mtval` = the instruction, and **issues nothing on the bus**.

## 4. Exceptions — precise, checked before anything is issued

| Instruction | misaligned | access fault | page fault |
|---|---|---|---|
| `LR.W/D` | 4 | 5 | 13 |
| `SC.W/D`, `AMO*.W/D` | 6 | 7 | 15 |

`mtval` is the faulting virtual address; `mepc` is the instruction's own PC; nothing retires.

Order of checks in the execute state, before any request: illegal encoding → misalignment → translation
(Sv39, when `satp.MODE = 8` and the effective privilege requires it) → physical-address range → issue.
A bus error on the response is a *real* access fault (5 or 7), never disguised as an SC failure.

**Translation class.** The walker gains `acc_type = 3` for AMOs; the existing 1 (load) and 2 (store) stay
as they are:

| Access | walker type | leaf permission | A/D | causes |
|---|---|---|---|---|
| `LR` | 1 (load) | `R`, or `X` when `MXR` | `A` | 13 / 5 |
| `SC` | 2 (store) | `W` | `A` and `D` | 15 / 7 |
| `AMO*` | 3 (amo, new) | `R` **and** `W` (`MXR` does not apply) | `A` and `D` | 15 / 7 |

`SUM`, `MPRV` and the effective privilege work exactly as for loads and stores (CPU-SU/SV39, accepted).
This is the rule Rocket implements (an AMO both reads and writes; an SC only writes).

**SC is checked like any other store even when the reservation is already lost**: alignment, translation,
permission and target legality are evaluated first, and a failure there is an exception, not `rd = 1`. Only
a request that is actually issued can come back as `scFail`.

## 5. The reservation

The reservation itself lives in the accepted backend; the core's part is:

* `resv_clear` is pulsed when a trap is taken (any cause, including an interrupt) and while the core is in
  reset. Ordinary fetches and page-table reads never pulse it.
* Every SC consumes the reservation — that is the backend's rule, unchanged.
* **Priority when `resv_clear` and an in-flight LR/SC coincide.** The clear is a one-cycle pulse raised in
  the trap cycle. A trap can only be taken at an instruction boundary or on this instruction's own fault,
  and the core has at most one outstanding request, so a clear can never overtake an LR that is still in
  flight: if the LR's response has not arrived, the core is in the wait state and takes no trap except that
  LR's own error, and in that case the LR sets no reservation (the backend clears it on an error response).
  The core therefore never pulses `resv_clear` in a cycle where an LR it issued is still outstanding, and
  the "clear then a late LR restores the old reservation" hazard cannot arise. This is asserted in the RTL
  and checked as a named gate.

## 6. Interrupts

Interrupts are sampled where they always were — in `S_IF_REQ`, before a fetch is issued, i.e. at an
instruction boundary. An accepted AMO is never abandoned: once the request is issued the core stays in the
wait state until the response arrives, writes back, retires once, and only then may an interrupt be taken,
with `mepc` = the *next* instruction. A synchronous exception raised by the instruction is never swallowed
by an interrupt.

## 7. The SoC configuration

A new isolated teaching R-BOOT atomic configuration reuses the real TSI / block-device / DDR topology and
the existing ROM, with the V2 bridge and the accepted `WithAtomicHub` backend. The default Rocket, RD2 and
teaching configurations, `xv6` and `start.c` are untouched. The backend's transaction identity (the client
named `teaching-phys`), the declared DRAM region and the PS platform rule all stand as accepted.

The R-BOOT drain is exercised at three points of a live atomic — waiting for the Get, waiting for the Put,
and waiting for the final response — with the accepted fail-stop boundary.

## 8. `misa.A`

`misa.A` is set **only** in the fully integrated atomic configuration, and only once every gate below
passes. Configurations that do not include the backend keep `misa.A = 0`; no global change is made, and
the tests that read `misa` get a recorded, diffed copy rather than an edit in place.

## 9. Frozen gates (the coverage this stage must show)

1. **Instruction matrix.** 9 AMOs × {W, D} × 4 `aq/rl` + `LR`/`SC` × {W, D}; signed/unsigned boundaries,
   overflow, the `.W` halves and the neighbouring bytes, `rd = x0`, `rs1`/`rs2`/`rd` overlap. Expected
   results are computed from the instruction's inputs independently, across three memory timings, and
   compared against the real register file, the real commit stream and the real memory.
2. **Reservation behaviour at core level** against a model that implements the frozen rules: LR/SC success,
   SC without LR, a repeated SC, another LR, the core's own write, an external write, a different word, an
   exception, a reset; under backpressure at least one same-address external race that must fail the SC,
   and a bounded retry loop that must succeed once the racing writer stops. Named coverage for high base
   addresses, page-table aliases, cross-mode access and each fault class.
3. **Interrupts.** A directed IRQ enabled *during* an AMO's wait: the AMO completes, writes back and
   retires exactly once before the interrupt is taken, with the correct `mepc` and old value; a
   synchronous exception is not swallowed; request/response stability, no duplicated write, no side effect
   on the abandoned path — judged from the real event trace.
4. **At least three CPU fault negatives** (e.g. `.W` not sign-extended, an SC that does not consume the
   reservation or returns the wrong result, an AMO classified as a load or retiring early), each rejected
   by a *named* check with the correct control passing. The backend's accepted negatives (mapping, operand,
   error, race) are re-run unchanged and the scorer is not relaxed.
5. **Regressions.** The full IMC / SU / Sv39 suites and the old exception and interrupt gates; the new
   `misa` value only in a recorded, diffed copy of the affected tests, with the genuine illegal-instruction
   and CSR gates preserved.
6. **A rebuilt isolated SoC**: the four M3 programs, the `misa` copies of boot09/boot10, the original
   `hello`, the SU programs on the real CLINT, boot11, and a new **boot12_amo** (an S-mode Sv39 spinlock
   and an LR/SC loop) over ROM / TSI / HTIF and the real bus path; the R-BOOT normal and timeout fail-stop
   gates re-run, with the atomic-in-flight drain as its own scenario. No old simulator result is reused.

One entry point drives all of it; a build failure or a timeout is infrastructure and can never count as a
negative being detected.
