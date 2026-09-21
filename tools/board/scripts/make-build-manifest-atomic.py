#!/usr/bin/env python3
"""Pin the atomic board build to one explicit list of files, each with its hash.

Derived from m4-prep/scripts/make-build-manifest.py. Three differences, all forced by what changed:
the board RTL and the shim come from this milestone, the CPU black box is six files rather than three,
and the note on each line says why the file is there. A missing file is a refusal, not a warning.
"""
import sys, os, hashlib, datetime

X   = "/home/engineer/fpga/experiments/teaching-cpu/xv6-board-prep"
FZ  = "/home/engineer/fpga/teaching-cpu-work/fpga-zynq"
CPU = "/home/engineer/fpga/teaching-cpu-work/cpu"

ENTRIES = [
 ("include",   f"{FZ}/pynqz1/src/verilog/clocking.vh",   "included by the board wrapper"),
 ("include",   f"{CPU}/rtl/tcpu_defs.vh",                "included by tcpu_core.v; needs an include dir"),
 ("wrapper",   f"{FZ}/pynqz1/src/verilog/rocketchip_wrapper.v",
               "the real board top: PS, pins, MMCM, both AXI boundaries, and the HP0 address translation "
               "{4'd1, addr[27:0]}. BASELINE, READ ONLY"),
 ("shim",      f"{X}/build-inputs/teaching_top_shim.v",  "module Top: 76 ports straight through to RD2BoardTop"),
 ("board-rtl", f"{X}/gen-board-atomic3/RD2BoardTop.RD2AtomicBoardConfig.v",
               "the elaborated atomic teaching board design"),
 ("blackbox",  f"{CPU}/rtl/tcpu_core.v",     "the teaching CPU, a Verilog black box to Chisel"),
 ("blackbox",  f"{CPU}/rtl/tcpu_csr.v",      "instantiated by tcpu_core"),
 ("blackbox",  f"{CPU}/rtl/tcpu_regfile.v",  "instantiated by tcpu_core"),
 ("blackbox",  f"{CPU}/rtl/tcpu_muldiv.v",   "NEW since the board-proven build: M"),
 ("blackbox",  f"{CPU}/rtl/tcpu_cdecode.v",  "NEW since the board-proven build: C"),
 ("blackbox",  f"{CPU}/rtl/tcpu_ptw.v",      "NEW since the board-proven build: Sv39 page-table walk"),
 ("support",   f"{FZ}/pynqz1/src/verilog/AsyncResetReg.v",  "instantiated by the generated RTL"),
 ("support",   f"{FZ}/pynqz1/src/verilog/plusarg_reader.v",
               "kept in the set because the wrapper/baseline may reference it; the generated board RTL "
               "instantiates none (audit section 2)"),
 ("xdc",       f"{FZ}/pynqz1/src/constrs/base.xdc",      "baseline constraints, unchanged"),
 ("bd-tcl",    f"{FZ}/pynqz1/src/tcl/pynqz1_bd.tcl",     "baseline block design, unchanged; HP0 segment "
                                                         "offset 0x0 range 0x20000000"),
]

out = sys.argv[1]
lines = ["# atomic teaching board build manifest",
         f"# generated {datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')} by make-build-manifest-atomic.py",
         "# role<TAB>sha256<TAB>bytes<TAB>absolute path<TAB>note",
         "# part xc7z020clg400-1, board www.digilentinc.com:pynq-z1:part0:1.0, top module rocketchip_wrapper",
         "# target clock host_clk_i 40.000 MHz, unchanged from the board-proven build"]
missing = 0
for role, path, note in ENTRIES:
    if not os.path.isfile(path):
        print(f"MISSING {path}"); missing += 1; continue
    b = open(path, "rb").read()
    lines.append(f"{role}\t{hashlib.sha256(b).hexdigest()}\t{len(b)}\t{path}\t{note}")
if missing:
    print(f"REFUSE: {missing} file(s) missing; no manifest written"); sys.exit(2)
open(out, "w").write("\n".join(lines) + "\n")
print(f"{len(ENTRIES)} sealed sources -> {out}")
