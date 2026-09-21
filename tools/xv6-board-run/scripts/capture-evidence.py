#!/usr/bin/env python3
"""Capture the ARM memory evidence bundle from the board, over the console.

The bundle has to hold the device-tree properties as **raw bytes** -- they are big-endian cells and any
text rendering on the way through invites exactly the byte-order mistake this whole check exists to catch.
So each binary property is fetched base64-encoded and decoded here, and the text files are fetched between
explicit markers so a partial read cannot be mistaken for a short file.

Every file is bound to the boot id captured in the same pass: if the board reboots between the capture and
the check, the preflight refuses the bundle rather than describing a machine that is no longer there.

  capture-evidence.py <outdir> [--log <serial log>]
"""
import argparse, base64, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONSOLE = "/home/engineer/fpga/experiments/teaching-cpu/m4-board/console.py"

ap = argparse.ArgumentParser()
ap.add_argument("outdir")
ap.add_argument("--log", default=None)
a = ap.parse_args()
if os.path.exists(a.outdir):
    sys.exit(f"REFUSE: {a.outdir} exists -- evidence is captured into a fresh directory")
os.makedirs(a.outdir)
log = a.log or os.path.join(a.outdir, "capture.log")

# (destination in the bundle, remote path, binary?)
ITEMS = [
    ("session-id",        "/proc/sys/kernel/random/boot_id",   False),
    ("dt/address-cells",  "/proc/device-tree/#address-cells",  True),
    ("dt/size-cells",     "/proc/device-tree/#size-cells",     True),
    ("dt/memory-reg",     "/proc/device-tree/memory/reg",      True),
    ("proc-iomem",        "/proc/iomem",                       False),
    ("proc-meminfo",      "/proc/meminfo",                     False),
]

cmds = []
for dest, remote, _ in ITEMS:
    tag = dest.replace("/", "_").upper()
    cmds.append(f"echo ===B{tag}===; base64 {remote}; echo ===E{tag}===")
# reserved-memory: every node's own reg, or an explicit statement that the node is absent
cmds.append("echo ===BRESERVED===; "
            "if [ -d /proc/device-tree/reserved-memory ]; then "
            "for d in /proc/device-tree/reserved-memory/*/; do "
            "n=$(basename $d); if [ -f $d/reg ]; then echo NODE $n; base64 $d/reg; else echo NOREG $n; fi; "
            "done; else echo ABSENT; fi; echo ===ERESERVED===")
cmds.append("echo ===BHEALTH===; dmesg | tail -40; echo ===EHEALTH===")

rc = subprocess.run([sys.executable, CONSOLE, log, "--timeout", "40"] + cmds,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
text = rc.stdout.decode("utf-8", "replace")
raw = open(log, "rb").read().decode("utf-8", "replace")

def between(tag, s):
    m = re.search(rf"===B{tag}===\s*\n(.*?)\n[^\n]*===E{tag}===", s, re.S)
    return m.group(1) if m else None

def clean(block):
    """Drop the console's own echo of the command and any shell prompt fragments."""
    out = []
    for ln in block.splitlines():
        ln = ln.strip()
        if not ln: continue
        if "===" in ln or "base64 " in ln or ln.startswith("~ #") or ln.startswith("/root #"): continue
        if re.match(r"^__RC_\d+__=", ln): continue
        out.append(ln)
    return out

problems = []
for dest, remote, binary in ITEMS:
    tag = dest.replace("/", "_").upper()
    block = between(tag, raw)
    if block is None:
        problems.append(f"{dest}: markers not found in the console log"); continue
    lines = clean(block)
    p = os.path.join(a.outdir, *dest.split("/"))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    # Everything comes over base64 -- including the text files, because a console adds carriage returns
    # and wraps long lines, and /proc/iomem read as console text is not the file. Decode, then write bytes.
    try:
        data = base64.b64decode("".join(lines), validate=True)
    except Exception as e:
        problems.append(f"{dest}: base64 did not decode ({e})"); continue
    open(p, "wb").write(data)
    print(f"  {dest:20s} <- {remote}  ({os.path.getsize(p)} bytes)")

res = between("RESERVED", raw)
if res is None:
    problems.append("reserved-memory: markers not found")
else:
    lines = clean(res)
    if any(l == "ABSENT" for l in lines):
        print("  reserved-memory      absent on this board")
    else:
        cur, buf = None, []
        def flush():
            if cur and buf:
                d = os.path.join(a.outdir, "dt", "reserved", cur)
                os.makedirs(d, exist_ok=True)
                open(os.path.join(d, "reg"), "wb").write(base64.b64decode("".join(buf)))
                print(f"  reserved/{cur}")
        for l in lines:
            if l.startswith("NODE "):
                flush(); cur, buf = l.split(None, 1)[1], []
            elif l.startswith("NOREG "):
                problems.append(f"reserved-memory node {l.split(None,1)[1]} has no reg property")
            else:
                buf.append(l)
        flush()

health = between("HEALTH", raw)
if health:
    open(os.path.join(a.outdir, "arm-health.txt"), "w").write("\n".join(clean(health)) + "\n")
    print(f"  arm-health.txt       ({len(clean(health))} lines of dmesg)")

if problems:
    print("CAPTURE_PROBLEMS:")
    for p in problems: print("  " + p)
    sys.exit(1)
sid = open(os.path.join(a.outdir, "session-id")).read().strip()
print(f"CAPTURE_OK session={sid} -> {a.outdir}")
