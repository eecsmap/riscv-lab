#!/usr/bin/env python3
"""Print a short, readable account of a failed run's log: the first trap, decoded.

    explain-log.py <log>

The raw log says `TRAP cyc=156 cause=2 epc=80000048 tval=0000000030429073`; this prints
`first trap: cycle 156, illegal instruction at 80000048: csrrw zero, mie(0x304), t0`.
"""
import re
import sys

CAUSES = {0: "instruction address misaligned", 1: "instruction access fault", 2: "illegal instruction",
          3: "breakpoint", 4: "load address misaligned", 5: "load access fault",
          6: "store address misaligned", 7: "store access fault", 8: "ecall from U", 9: "ecall from S",
          11: "ecall from M", 12: "instruction page fault", 13: "load page fault", 15: "store page fault"}
INTERRUPTS = {1: "supervisor software", 3: "machine software (msip)", 5: "supervisor timer",
              7: "machine timer (mtip)", 9: "supervisor external", 11: "machine external (meip)"}
CSRS = {0x100: "sstatus", 0x104: "sie", 0x105: "stvec", 0x140: "sscratch", 0x141: "sepc", 0x142: "scause",
        0x143: "stval", 0x144: "sip", 0x180: "satp", 0x300: "mstatus", 0x301: "misa", 0x302: "medeleg",
        0x303: "mideleg", 0x304: "mie", 0x305: "mtvec", 0x340: "mscratch", 0x341: "mepc", 0x342: "mcause",
        0x343: "mtval", 0x344: "mip", 0xB00: "mcycle", 0xB02: "minstret", 0xC00: "cycle", 0xC01: "time",
        0xC02: "instret", 0xF14: "mhartid"}
REGS = ("zero ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 "
        "s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6").split()
SYSTEM_FIXED = {0x00000073: "ecall", 0x00100073: "ebreak", 0x30200073: "mret", 0x10200073: "sret",
                0x10500073: "wfi"}


def decode(insn):
    """Name the instructions a step can trip over; anything else is shown as hex only."""
    if insn in SYSTEM_FIXED:
        return SYSTEM_FIXED[insn]
    if insn & 0x7F == 0x73 and (insn >> 12) & 7 not in (0, 4):
        f3, rd, rs1, csr = (insn >> 12) & 7, (insn >> 7) & 31, (insn >> 15) & 31, insn >> 20
        op = ["", "csrrw", "csrrs", "csrrc", "", "csrrwi", "csrrsi", "csrrci"][f3]
        src = str(rs1) if f3 >= 5 else REGS[rs1]
        text = "%s %s, %s(0x%03x), %s" % (op, REGS[rd], CSRS.get(csr, "unknown CSR"), csr, src)
        if rd == 0 and f3 in (1, 5):   # the assembler's csrw / csrwi
            text += "  (that is: %s %s, %s)" % (op[:3] + op[4:], CSRS.get(csr, hex(csr)), src)
        return text
    return None


def main():
    log = open(sys.argv[1], errors="replace").read().splitlines()
    # a z or x in a report line means a signal the testbench reads from the core is undriven or unknown
    for l in log:
        if re.match(r"(IRQ|WATCH|SUMMARY) ", l):
            for name, v in re.findall(r"(\w+)=([zx])\b", l):
                src = {"fire_enabled": " (it comes from dbg_irq_enabled)"}.get(name, "")
                print("        %s=%s on the %s line%s: %s" % (name, v, l.split()[0], src,
                      "a wire the testbench reads from your core is driven by nothing" if v == "z"
                      else "a wire the testbench reads from your core is unknown (x)"))
    traps = [l for l in log if l.startswith("TRAP ") and "STORM" not in l]
    if not traps:
        print("        no trap was taken")
    else:
        m = re.search(r"cyc=(\d+) cause=(\d+) epc=([0-9a-f]+) tval=([0-9a-f]+)(.*)", traps[0])
        if m:
            cyc, cause, epc, tval, rest = int(m[1]), int(m[2]), m[3], int(m[4], 16), m[5]
            if "interrupt" in rest:
                what = "interrupt: " + INTERRUPTS.get(cause, "cause %d" % cause)
                print("        first trap: cycle %d, %s, taken before %s" % (cyc, what, epc))
            else:
                what = CAUSES.get(cause, "cause %d" % cause)
                if cause == 2:
                    d = decode(tval)
                    detail = ": %08x%s" % (tval, "  = " + d if d else "")
                elif cause in (0, 1, 4, 5, 6, 7):
                    detail = ", address %x" % tval
                else:
                    detail = ""
                print("        first trap: cycle %d, %s at pc %s%s" % (cyc, what, epc, detail))
        if len(traps) > 1:
            print("        (%d traps in all; every TRAP line is in the log)" % len(traps))


if __name__ == "__main__":
    main()
