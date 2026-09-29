#!/usr/bin/env python3
"""PIPE-P3a: pin the single-pipeline board build to one explicit list of files, each with its hash (derived from
multicore/m4 make-build-manifest-m4.py). The CPU black box is EXACTLY the files of rtl/cpu/pipeline/SOURCES.pipe,
extracted from a named commit into the attempt directory (no directory glob, no multicycle file); wrapper,
constraints, block design and support files are the BASELINE ones, unchanged.
  make-build-manifest-p3.py <out> <board-rtl.v> <shim.v> <rtl snapshot dir> <inc dir> <commit>"""
import sys, os, hashlib, datetime
out, board, shim, rtl, inc, commit = sys.argv[1:7]
FZ = "/home/engineer/fpga/teaching-cpu-work/fpga-zynq"
man = os.path.join(rtl, "SOURCES.pipe")
bb = []
for line in open(man):
    p = line.split()
    if not p or p[0].startswith("#"): continue
    if p[0] in ("top", "module"): bb.append(os.path.join(rtl, os.path.basename(p[1])))
    elif p[0] != "include": sys.exit(f"REFUSE: manifest kind {p[0]}")
ENTRIES = [
 ("include",   f"{FZ}/pynqz1/src/verilog/clocking.vh", "included by the board wrapper"),
 ("include",   os.path.join(inc, "tcpu_defs.vh"), f"included by tcpu_core_pipe.v; include-only dir (from {commit})"),
 ("wrapper",   f"{FZ}/pynqz1/src/verilog/rocketchip_wrapper.v", "the real board top: PS, pins, MMCM, both AXI boundaries. BASELINE, READ ONLY"),
 ("shim",      shim, "module Top: ports straight through to RD2BoardTop (generated from the pipeline board RTL)"),
 ("board-rtl", board, "the elaborated single-pipeline teaching board design (RD2PipeBoardConfig, NUM_CORES=1)"),
] + [("blackbox", f, f"pipeline CPU RTL, rtl/cpu/pipeline/SOURCES.pipe at {commit}") for f in bb] + [
 ("support",   f"{FZ}/pynqz1/src/verilog/AsyncResetReg.v", "instantiated by the generated RTL"),
 ("support",   f"{FZ}/pynqz1/src/verilog/plusarg_reader.v", "kept as in the accepted builds; the board RTL instantiates none (audit section 2)"),
 ("xdc",       f"{FZ}/pynqz1/src/constrs/base.xdc", "baseline constraints, unchanged"),
 ("bd-tcl",    f"{FZ}/pynqz1/src/tcl/pynqz1_bd.tcl", "baseline block design, unchanged; HP0 segment offset 0x0 range 0x20000000"),
]
lines = ["# PIPE-P3a single-pipeline teaching board build manifest",
         f"# generated {datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')} by make-build-manifest-p3.py",
         "# role<TAB>sha256<TAB>bytes<TAB>absolute path<TAB>note",
         "# part xc7z020clg400-1, board www.digilentinc.com:pynq-z1:part0:1.0, top module rocketchip_wrapper",
         "# target clock host_clk_i 40.000 MHz, unchanged from the board-proven build"]
missing = 0
for role, path, note in ENTRIES:
    if not os.path.isfile(path): print(f"MISSING {path}"); missing += 1; continue
    b = open(path, "rb").read(); lines.append(f"{role}\t{hashlib.sha256(b).hexdigest()}\t{len(b)}\t{path}\t{note}")
if missing: print(f"REFUSE: {missing} file(s) missing; no manifest written"); sys.exit(2)
open(out, "w").write("\n".join(lines) + "\n"); print(f"{len(ENTRIES)} sealed sources ({len(bb)} black-box files) -> {out}")
