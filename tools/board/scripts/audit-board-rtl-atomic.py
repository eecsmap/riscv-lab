#!/usr/bin/env python3
"""The board-RTL audit for the atomic teaching top.

Derived from m4-prep/scripts/audit-board-rtl.py, as a copy rather than an edit: that script is part of the
sealed input set of the accepted board build and its hash is evidence. Running it against this top proved
it does not generalise -- it looks for a `TeachingBoardTop` module and matches the CPU instantiation with
`tcpu_core #(.RESET_PC(n))`, which cannot match once MISA_A is also passed. Both were fixed here, and four
checks were added for things that did not exist when it was written: the V2 physical port, the fault
parameters, the status word's bit order, and the six black-box sources.

  audit-board-rtl-atomic.py <RD2BoardTop....v> [--baseline <Top.ZynqFPGAConfig.v>] [--rom <rom.bin>]
                            [--rtl-dir <cpu/rtl>]
"""
import re, sys, os, hashlib, argparse

ap = argparse.ArgumentParser()
ap.add_argument("rtl")
ap.add_argument("--baseline", default="/home/engineer/fpga/teaching-cpu-work/fpga-zynq/pynqz1/src/verilog/Top.ZynqFPGAConfig.v")
ap.add_argument("--rom", default=None)
ap.add_argument("--write-rom", default=None, help="write the ROM extracted from the RTL here")
ap.add_argument("--rtl-dir", default="/home/engineer/fpga/teaching-cpu-work/cpu/rtl")
ap.add_argument("--top", default="RD2BoardTop")
ap.add_argument("--target", default="RD2ZynqTop")
a = ap.parse_args()
src = open(a.rtl, errors="replace").read()
base = open(a.baseline, errors="replace").read() if os.path.exists(a.baseline) else None
fails = []

def portlist(text, mod):
    m = re.search(rf"^module {mod}\((.*?)\);", text, re.S | re.M)
    if not m: return None
    out = []
    for line in m.group(1).splitlines():
        p = re.match(r"\s*(input|output)\s+(\[[^\]]*\]\s*)?(\w+)", line)
        if p: out.append((p.group(1), (p.group(2) or "").strip(), p.group(3)))
    return out

print(f"## 1. the board top's ports, against the baseline's")
t = portlist(src, a.top); b = portlist(base, "Top") if base else None
if t is None:
    print(f"   FAIL: {a.rtl} has no {a.top} module."); fails.append("not a board top")
else:
    print(f"   teaching {a.top:22s}: {len(t)} ports")
    if b is not None:
        print(f"   baseline Top                    : {len(b)} ports")
        if t == b: print("   identical field for field       : True")
        else:
            print("   identical field for field       : False"); fails.append("port mismatch")
            for x in sorted(set(map(str, t)) ^ set(map(str, b))): print("     ", x)

print("## 2. what is in the RTL that should not be")
for label, pat, want in [("plusarg_reader instances", r"plusarg_reader #\(", 0),
                         ("TLMonitor modules",        r"^module TLMonitor", 0),
                         ("teaching event printfs",   r'\$fwrite\(32\'h80000002,"EV ', 0),
                         ("RD2 master-trace printfs", r'\$fwrite\(32\'h80000002,"RD2M ', 0),
                         ("R-BOOT block-dev printfs", r'\$fwrite\(32\'h80000002,"RBOOT ', 0),
                         ("atomic-path printfs",      r'\$fwrite\(32\'h80000002,"AT ', 0),
                         ("TAILHIT printfs",          r"TAILHIT", 0)]:
    n = len(re.findall(pat, src, re.M))
    nb = len(re.findall(pat, base, re.M)) if base else -1
    ok = n == want
    print(f"   {label:26s} {n:4d}   (baseline {nb:4d})   {'ok' if ok else 'UNEXPECTED, wanted %d' % want}")
    if not ok: fails.append(label)

print("## 3. simulation-only constructs, under this build's defines (no SYNTHESIS, no RANDOMIZE_*)")
stack = []; kinds = {}; unguarded = 0
pat = re.compile(r"\$fwrite|\$fdisplay|\$fatal|\$finish|\$random|\$value\$plusargs|\$test\$plusargs|^\s*initial\b")
for l in src.splitlines():
    s = l.strip()
    m = re.match(r"`(ifdef|ifndef)\s+(\S+)", s)
    if m: stack.append((m.group(1), m.group(2))); continue
    if s.startswith("`else"):
        if stack: k, n = stack[-1]; stack[-1] = ("ifdef" if k == "ifndef" else "ifndef", n)
        continue
    if s.startswith("`endif"):
        if stack: stack.pop()
        continue
    if pat.search(s):
        if not stack: unguarded += 1; continue
        key = " & ".join(f"{k} {n}" for k, n in stack); kinds[key] = kinds.get(key, 0) + 1
for k, v in sorted(kinds.items(), key=lambda x: -x[1]): print(f"   {v:5d}  {k}")
print(f"   {unguarded:5d}  with no guard at all")
if unguarded: fails.append("unguarded simulation construct")

print("## 4. the instrumentation, module by module")
for mod in (a.target, "TeachingCpuV2", "TeachingCpu"):
    pl = portlist(src, mod)
    if pl is None: print(f"   {mod}: not present"); continue
    # `status*` is NOT instrumentation in this design: statusWord is what the PS reads at 0x14 to decide
    # whether the restart handshake may be released, so it is functional and must survive. Only the
    # observation and simulation-knob ports are instrumentation.
    obs = [p for p in pl if re.match(r"(obs|halted|busy|axiStats|bdevStall)", p[2])]
    fn  = [p for p in pl if re.match(r"status", p[2])]
    print(f"   {mod:22s} {len(pl):3d} ports, {len(obs)} instrumentation, {len(fn)} functional status")
    for p2 in obs: print(f"      instrumentation still exported: {p2[2]}")
    if obs: fails.append(f"{mod} exports instrumentation")

print("## 5. the CPU black box: parameters actually passed")
m = re.search(r"tcpu_core\s*#\(([^)]*\)[^;]*?)\s*\)\s*(\w+)\s*\(", src)
inst = re.search(r"tcpu_core\s*#\((.*?)\)\s+\w+\s*\(", src, re.S)
if not inst:
    print("   FAIL: no tcpu_core instantiation found"); fails.append("no tcpu_core")
else:
    params = dict(re.findall(r"\.(\w+)\((\d+)\)", inst.group(1)))
    print(f"   parameters passed: {params}")
    if params.get("RESET_PC") != str(0x10040):
        print(f"   FAIL: RESET_PC = {params.get('RESET_PC')}, wanted {0x10040}"); fails.append("RESET_PC")
    else: print(f"   RESET_PC = {int(params['RESET_PC'])} = {hex(int(params['RESET_PC']))}  ok")
    if params.get("MISA_A") != "1":
        print(f"   FAIL: MISA_A = {params.get('MISA_A')}, wanted 1 for the atomic board"); fails.append("MISA_A")
    else: print("   MISA_A = 1  ok")
    passed_faults = [k for k in params if k.startswith("FAULT_")]
    if passed_faults:
        print(f"   FAIL: fault parameters passed at the instantiation: {passed_faults}")
        fails.append("fault parameter passed")
    else:
        print("   no FAULT_* parameter is passed at the instantiation  ok")

print("## 6. the fault parameters' declared defaults, read from the black-box source")
core = os.path.join(a.rtl_dir, "tcpu_core.v")
if not os.path.exists(core):
    print(f"   FAIL: {core} not found"); fails.append("no tcpu_core.v")
else:
    txt = open(core, errors="replace").read()
    decls = re.findall(r"parameter\s+(FAULT_\w+)\s*=\s*(\d+)", txt)
    bad = [(k, v) for k, v in decls if v != "0"]
    print(f"   {len(decls)} FAULT_* parameters declared, {len(bad)} with a non-zero default")
    for k, v in bad: print(f"     {k} = {v}")
    if bad: fails.append("non-zero fault default")
    if not decls: fails.append("no fault parameters found")

print("## 7. the V2 physical port reaches the black box")
for sig in ("req_amo", "req_lrsc", "resp_scfail", "resv_clear"):
    n = len(re.findall(rf"\.{sig}\(", src))
    print(f"   .{sig:12s} connected {n} time(s)  {'ok' if n >= 1 else 'MISSING'}")
    if n < 1: fails.append(f"{sig} not connected")

print("## 8. the status word's bit order, as built in the RTL")
# statusWord = Cat(nDrained[15:0], epoch[7:0], 0(2), bootTimeout, bootReady, drainTimeout, draining,
#                  plReconfigSafe, cpuRestartSafe)   -> bits 31:16, 15:8, 7:6, 5, 4, 3, 2, 1, 0
m = re.search(r"assign\s+statusWord\s*=\s*\{(.*?)\};", src, re.S)
if not m:
    m = re.search(r"assign\s+io_status\s*=\s*\{(.*?)\};", src, re.S)
if not m:
    print("   the status word is not assembled by a single concatenation in this RTL;")
    print("   the bit map is documented in STATUS-MAP.md and bound there instead.")
else:
    print("   " + " ".join(m.group(1).split()))

print("## 9. the boot ROM, extracted from this RTL (not read from a file beside it)")
ROMIMG="/home/engineer/fpga/teaching-cpu-work/fpga-zynq/common/src/main/resources/teaching/bootrom.teaching.rv64.img"
mrom=re.search(r"^module TLROM\(", src, re.M)
if not mrom:
    print("   FAIL: no TLROM module in this RTL"); fails.append("no TLROM")
else:
    body=src[mrom.start():]; body=body[:body.index("\nendmodule")]
    words={}
    d=re.search(r"\d+'h1 == index \? 64'h[0-9a-f]+ : 64'h([0-9a-f]+)", body)
    if d: words[0]=int(d.group(1),16)
    for mm in re.finditer(r"\d+'h([0-9a-f]+) == index \? 64'h([0-9a-f]+)", body):
        words[int(mm.group(1),16)]=int(mm.group(2),16)
    if not words:
        print("   FAIL: no ROM words found; the emission shape must have changed"); fails.append("no ROM words")
    else:
        rom=b"".join(words.get(i,0).to_bytes(8,"little") for i in range(max(words)+1))
        img=open(ROMIMG,"rb").read()
        dtb=rom.find(b"\xd0\x0d\xfe\xed")
        okimg = rom[:len(img)]==img
        print(f"   {len(rom)} bytes from {max(words)+1} words")
        print(f"   first {len(img)} bytes match {os.path.basename(ROMIMG)}: {okimg}")
        # The original hardcoded 1361, the device tree's length in the M3 configuration. Read the dtb's
        # own totalsize field instead, or this line reports a misleading False for any other config.
        dtb_len = int.from_bytes(rom[dtb+4:dtb+8], "big") if dtb >= 0 else 0
        tail_zero = set(rom[dtb+dtb_len:]) <= {0}
        print(f"   device tree magic at {hex(dtb)}, totalsize {dtb_len}; bytes after the dtb all zero: {tail_zero}")
        if not tail_zero: fails.append("non-zero bytes after the device tree")
        print(f"   sha256 of the extracted ROM: {hashlib.sha256(rom).hexdigest()}")
        if not okimg: fails.append("ROM does not match the teaching image")
        if dtb!=len(img): fails.append("the device tree is not where it should be")
        if a.write_rom:
            open(a.write_rom, "wb").write(rom)
            print(f"   extracted ROM written to {os.path.basename(a.write_rom)}")
        if a.rom:
            if not os.path.exists(a.rom):
                print(f"   FAIL: --rom {a.rom} does not exist"); fails.append("rom file missing")
            else:
                side=open(a.rom,"rb").read()
                same = side==rom
                print(f"   the stored {os.path.basename(a.rom)} equals the extraction: {same}")
                if not same: fails.append("the stored ROM disagrees with the RTL")
        else:
            print("   FAIL: no --rom given. The extraction above stands on its own, but the stored ROM that")
            print("         travels with the RTL is part of what gets built, so it has to be cross-checked")
            print("         rather than left unexamined.")
            fails.append("no --rom given")


print(f"\n   sha256 {hashlib.sha256(src.encode(errors='replace')).hexdigest()}  {os.path.basename(a.rtl)}")
print(f"BOARD_RTL_AUDIT fails={len(fails)}" + (": " + ", ".join(fails) if fails else ""))
sys.exit(1 if fails else 0)
