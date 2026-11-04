#!/usr/bin/env python3
"""What the core did during a failed step-5 run, in a few lines: the boot chain, step by step, and where it stopped.

    step5-explain.py <log>

The SoC's event log (EV lines) records every bus request, every retirement, every trap and the interrupt levels.
A good boot reads: first fetch at 0x10040 (the ROM) -> ROM loop on wfi -> host raises msip -> interrupt ->
ROM handler at 0x10000 -> mret -> first fetch at 0x80000000 (your program). This prints how far it got.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib import import_module
decode = import_module("explain-log").decode     # the same instruction decoder the step 1-4 failures use
CAUSES = import_module("explain-log").CAUSES

ROM_LO, ROM_HI, DRAM = 0x10000, 0x20000, 0x80000000


def main():
    first_fetch = msip_at = irq_at = first_dram = code = None
    commits, last_pc, sync, irqs = 0, None, [], 0
    for line in open(sys.argv[1], errors="replace"):
        f = re.search(r"\*\*\* FAILED \*\*\* \((?:tohost =|exit code) (\d+)\)", line)
        if f:
            code = int(f[1])
        m = re.match(r"\S*EV +(\d+) (\w+) (.*)", line)
        if not m:
            continue
        cyc, kind, rest = int(m[1]), m[2], m[3]
        if kind == "REQ" and "fetch=1" in rest:
            pc = int(re.search(r"pc=0x([0-9a-f]+)", rest)[1], 16)
            if first_fetch is None:
                first_fetch = (cyc, pc)
            if pc >= DRAM and first_dram is None:
                first_dram = cyc
        elif kind == "COMMIT":
            commits += 1
            last_pc = int(re.search(r"pc=0x([0-9a-f]+)", rest)[1], 16)
        elif kind == "IRQLEVEL" and "msip=1" in rest and msip_at is None:
            msip_at = cyc
        elif kind == "TRAP":
            t = dict(re.findall(r"(\w+)=(0x[0-9a-f]+|\d+)", rest))
            if t.get("interrupt") == "1":
                irqs += 1
                irq_at = irq_at or cyc
            else:
                sync.append((cyc, int(t["cause"], 16), int(t["epc"], 16), int(t["tval"], 16)))

    say = lambda s: print("        " + s)
    if first_fetch is None:
        say("the core never fetched anything")
        return
    c, pc = first_fetch
    say("first fetch: 0x%x at cycle %d%s" % (pc, c, "" if pc == 0x10040 else
        "  <-- should be 0x10040, the boot ROM: the SoC sets RESET_PC; does your core use it?"))
    say("host raised msip (the wake-up): %s" % ("cycle %d" % msip_at if msip_at else "never"))
    in_rom = last_pc is not None and ROM_LO <= last_pc < ROM_HI
    say("interrupts taken: %d%s" % (irqs, "" if irqs or not msip_at or not in_rom else
        "  <-- msip was raised but no interrupt was taken: the core is still waiting in the ROM's wfi loop"))
    say("first fetch from your program at 0x80000000: %s" % ("cycle %d" % first_dram if first_dram else "never"))
    say("instructions retired: %d, last at pc 0x%x%s" % (commits, last_pc or 0,
        " (in the boot ROM)" if last_pc and ROM_LO <= last_pc < ROM_HI else ""))
    if not sync:
        say("synchronous traps: 0")
    if code:
        say("the program itself reported failure code %d: in its source, the check that ends in `, %d)` failed" % (code, code))
    if sync:
        c, cause, epc, tval = sync[0]
        d = decode(tval) if cause == 2 else None
        say("synchronous traps: %d; the first at cycle %d: %s at pc 0x%x, tval 0x%x%s" % (
            len(sync), c, CAUSES.get(cause, "cause %d" % cause), epc, tval, "  = " + d if d else ""))


if __name__ == "__main__":
    main()
