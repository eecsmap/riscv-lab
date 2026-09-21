# RV64 integer C encodings — what this core does with each 16-bit parcel

Source: the C extension chapter of the unprivileged spec, version 20240411
(<https://docs.riscv.org/reference/isa/v20240411/unpriv/c-st-ext.html>), RV64 columns only. RV32-only
readings (C.JAL, C.FLW/C.FSW/C.FLWSP/C.FSWSP) are **not** applied: on RV64 those encodings are C.ADDIW and
C.LD/C.SD/C.LDSP/C.SDSP. This core has no F/D, so every floating-point compressed encoding is an illegal
instruction, not a silent alias.

Classes: **legal** (expanded to the 32-bit instruction shown, retired once), **HINT** (retired with no
architectural effect — expanded to a canonical no-effect instruction; the commit record carries the original
parcel), **reserved** / **illegal** (illegal-instruction exception, `mtval` = the 16-bit parcel), **custom**
(illegal here, no custom extension exists).

| quadrant / funct3 | encoding | RV64 meaning | class | expansion |
|---|---|---|---|---|
| 00 / 000 | `c.addi4spn rd', nzuimm` | | legal; nzuimm = 0 → **reserved**; parcel 0x0000 → **illegal** | `addi rd', x2, nzuimm` |
| 00 / 001 | `c.fld` | FP | **illegal** (no D) | — |
| 00 / 010 | `c.lw rd', uimm(rs1')` | | legal | `lw rd', uimm(rs1')` |
| 00 / 011 | `c.ld rd', uimm(rs1')` | RV64 | legal | `ld rd', uimm(rs1')` |
| 00 / 100 | — | | **reserved** | — |
| 00 / 101 | `c.fsd` | FP | **illegal** (no D) | — |
| 00 / 110 | `c.sw rs2', uimm(rs1')` | | legal | `sw rs2', uimm(rs1')` |
| 00 / 111 | `c.sd rs2', uimm(rs1')` | RV64 | legal | `sd rs2', uimm(rs1')` |
| 01 / 000 | `c.nop` (rd=0, nzimm=0) | | legal (no effect) | `addi x0, x0, 0` |
| 01 / 000 | `c.nop` with nzimm≠0 (rd=0) | | **HINT** | `addi x0, x0, 0` |
| 01 / 000 | `c.addi rd, nzimm` (rd≠0) | | legal; nzimm = 0 → **HINT** | `addi rd, rd, nzimm` |
| 01 / 001 | `c.addiw rd, imm` | RV64 | legal; rd = 0 → **reserved** | `addiw rd, rd, imm` |
| 01 / 010 | `c.li rd, imm` | | legal; rd = 0 → **HINT** | `addi rd, x0, imm` |
| 01 / 011 | `c.addi16sp nzimm` (rd=2) | | legal; nzimm = 0 → **reserved** | `addi x2, x2, nzimm` |
| 01 / 011 | `c.lui rd, nzimm` (rd≠0,2) | | legal; nzimm = 0 → **reserved**; rd = 0 → **HINT** | `lui rd, nzimm` |
| 01 / 100, bits12:10=x00 | `c.srli rd', shamt` | RV64 shamt 0..63 | legal; shamt = 0 → **HINT** (C.SRLI64) | `srli rd', rd', shamt` |
| 01 / 100, x01 | `c.srai rd', shamt` | | legal; shamt = 0 → **HINT** | `srai rd', rd', shamt` |
| 01 / 100, x10 | `c.andi rd', imm` | | legal | `andi rd', rd', imm` |
| 01 / 100, 011 00/01/10/11 | `c.sub / c.xor / c.or / c.and` | | legal | `sub/xor/or/and rd', rd', rs2'` |
| 01 / 100, 111 00/01 | `c.subw / c.addw` | RV64 | legal | `subw/addw rd', rd', rs2'` |
| 01 / 100, 111 10/11 | — | | **reserved** | — |
| 01 / 101 | `c.j offset` | | legal | `jal x0, offset` |
| 01 / 110 | `c.beqz rs1', offset` | | legal | `beq rs1', x0, offset` |
| 01 / 111 | `c.bnez rs1', offset` | | legal | `bne rs1', x0, offset` |
| 10 / 000 | `c.slli rd, shamt` | RV64 shamt 0..63 | legal; shamt = 0 → **HINT** (C.SLLI64); rd = 0 → **HINT** | `slli rd, rd, shamt` |
| 10 / 001 | `c.fldsp` | FP | **illegal** (no D) | — |
| 10 / 010 | `c.lwsp rd, uimm` | | legal; rd = 0 → **reserved** | `lw rd, uimm(x2)` |
| 10 / 011 | `c.ldsp rd, uimm` | RV64 | legal; rd = 0 → **reserved** | `ld rd, uimm(x2)` |
| 10 / 100, bit12=0 | `c.jr rs1` (rs2=0) | | legal; rs1 = 0 → **reserved** | `jalr x0, 0(rs1)` |
| 10 / 100, bit12=0 | `c.mv rd, rs2` (rs2≠0) | | legal; rd = 0 → **HINT** | `add rd, x0, rs2` |
| 10 / 100, bit12=1 | `c.ebreak` (rd=0, rs2=0) | | legal | `ebreak` |
| 10 / 100, bit12=1 | `c.jalr rs1` (rs2=0) | | legal | `jalr x1, 0(rs1)` |
| 10 / 100, bit12=1 | `c.add rd, rs2` (rs2≠0) | | legal; rd = 0 → **HINT** | `add rd, rd, rs2` |
| 10 / 101 | `c.fsdsp` | FP | **illegal** (no D) | — |
| 10 / 110 | `c.swsp rs2, uimm` | | legal | `sw rs2, uimm(x2)` |
| 10 / 111 | `c.sdsp rs2, uimm` | RV64 | legal | `sd rs2, uimm(x2)` |
| 11 | — | | not compressed: a 32-bit instruction begins | — |

HINTs expand to `addi x0, x0, 0`: no register is written, no memory is touched, the instruction retires once
with its original 16-bit parcel and length 2 in the commit record. Reserved and floating-point encodings
raise cause 2 with `mtval` = the parcel (zero-extended). Nothing custom is decoded.
