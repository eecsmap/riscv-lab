#!/usr/bin/env python3
"""Decide, fail-closed, whether the ARM's memory really leaves the teaching CPU's DDR window free.

Why this is not a one-line grep. The hazard is recorded in pynqz1_devicetree.dts: give Linux the whole
512 MB and xv6's kinit() memsets every page up to PHYSTOP, over the top of the ARM kernel. The board kernel
at 128 MiB writes DDR 0x1000_0000-0x1800_0000, and the target's whole window is 0x1000_0000-0x1FFF_FFFF
(rocketchip_wrapper.v drives S_AXI_araddr = {4'd1, mem_araddr[27:0]}).

Two things an earlier version of this got wrong, both found in review:

  * device-tree cells are **big-endian**, always, whatever the CPU is. Reading /proc/device-tree/memory/reg
    with `od -tx4` on a little-endian host byte-swaps every cell and silently produces a different address.
    They are decoded here as big-endian, with the cell widths taken from #address-cells/#size-cells rather
    than assumed, and **every** (address, size) tuple is decoded, not just the first.
  * a listing of reserved-memory *names* proves nothing. Each reserved region's own reg tuple is decoded
    and checked.

Everything is fail-closed: unknown, unreadable, redacted, internally inconsistent, or overlapping evidence
is a refusal. There is no "probably fine" outcome.

  mem-preflight.py <evidence-dir> [--expect-session <id>] [--json <out>]

The evidence directory is a capture of the *running* ARM, not anything from this repository:

  session-id                     /proc/sys/kernel/random/boot_id, identifying this boot
  dt/address-cells               /proc/device-tree/#address-cells        (4 bytes, big-endian)
  dt/size-cells                  /proc/device-tree/#size-cells
  dt/memory-reg                  /proc/device-tree/memory/reg            (raw bytes)
  dt/reserved/<name>/reg         each /proc/device-tree/reserved-memory/<node>/reg   (optional)
  proc-iomem                     /proc/iomem
  proc-meminfo                   /proc/meminfo
"""
import sys, os, re, argparse, json

TARGET_BASE = 0x10000000          # the teaching CPU's DDR window, from the wrapper's {4'd1, addr[27:0]}
TARGET_END  = 0x1FFFFFFF
MIB = 1024 * 1024

ap = argparse.ArgumentParser()
ap.add_argument("evidence")
ap.add_argument("--expect-session", default=None,
                help="the session this evidence must belong to; a mismatch is a refusal")
ap.add_argument("--json", default=None)
a = ap.parse_args()

refusals = []
notes = []
def refuse(m): refusals.append(m)
def note(m):   notes.append(m)

E = a.evidence
def path(*p): return os.path.join(E, *p)

def read_bytes(rel, required=True):
    p = path(*rel.split("/"))
    if not os.path.isfile(p):
        if required: refuse(f"missing evidence: {rel}")
        return None
    b = open(p, "rb").read()
    if not b:
        refuse(f"empty evidence: {rel}")
        return None
    return b

#: A boot id is a UUID. Validating the shape stops a malformed or truncated capture from being compared
#: as though it were an identifier.
SESSION_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

def read_text(rel, required=True):
    b = read_bytes(rel, required)
    if b is None: return None
    # Exactly ONE trailing NUL is dropped, as a terminator. Where that comes from was established from the
    # retained capture rather than assumed: this board emits /proc/sys/kernel/random/boot_id as 36
    # characters followed by a NUL and no newline (xv6-board-run/logs/07-capture.log shows the base64
    # ending in AA==), while /proc/iomem and /proc/meminfo in the same capture contain no NUL at all.
    #
    # A NUL anywhere else is corruption, not a convention, and is refused. An earlier version replaced
    # every NUL in every text file, which would have quietly scrubbed exactly that damage out of the
    # evidence -- the opposite of what a fail-closed check is for.
    if b.endswith(b"\x00"):
        b = b[:-1]
    t = b.decode("utf-8", "replace")
    if "\x00" in t:
        refuse(f"{rel} contains an embedded NUL byte: this capture is corrupt, not merely terminated")
        return None
    # A capture that has been edited by hand is not evidence.
    for marker in ("REDACTED", "<snip", "...", "XXXX"):
        if marker in t:
            refuse(f"{rel} contains {marker!r}: redacted or elided evidence cannot be checked")
            return None
    return t

def be32(b, i):   return int.from_bytes(b[i*4:(i+1)*4], "big")
def cells(b, n, i):
    """n device-tree cells starting at cell index i, big-endian, as one integer."""
    v = 0
    for k in range(n):
        v = (v << 32) | be32(b, i + k)
    return v

def parse_reg(blob, ac, sc, what):
    """Decode a device-tree reg property into (address, size) tuples. Every tuple, not just the first."""
    per = (ac + sc) * 4
    if per == 0 or len(blob) % per != 0:
        refuse(f"{what}: {len(blob)} bytes is not a whole number of ({ac}+{sc})-cell tuples; "
               f"the cell widths and the data disagree")
        return []
    out = []
    for t in range(len(blob) // per):
        base = t * (ac + sc)
        out.append((cells(blob, ac, base), cells(blob, sc, base + ac)))
    return out

def overlaps(lo, size, wlo, whi):
    if size == 0: return False
    return lo <= whi and (lo + size - 1) >= wlo

# ---- session -----------------------------------------------------------------------------------------
sess = read_text("session-id")
sess = sess.strip() if sess else None
if sess is not None:
    if not SESSION_RE.match(sess):
        refuse(f"session id {sess!r} is not a boot-id UUID; a malformed identifier cannot be compared")
    elif a.expect_session and sess != a.expect_session:
        refuse(f"this evidence belongs to session {sess}, not {a.expect_session}: the machine has "
               f"rebooted since it was taken, so it says nothing about the system that is running now")
    else:
        note(f"session {sess}")

# ---- device tree -------------------------------------------------------------------------------------
acb = read_bytes("dt/address-cells")
scb = read_bytes("dt/size-cells")
ac = be32(acb, 0) if acb and len(acb) >= 4 else None
sc = be32(scb, 0) if scb and len(scb) >= 4 else None
if ac is None or sc is None:
    refuse("cannot read #address-cells/#size-cells; the reg tuples cannot be decoded without them")
elif not (1 <= ac <= 2 and 1 <= sc <= 2):
    refuse(f"#address-cells={ac} #size-cells={sc} are outside the range this checker understands")
else:
    note(f"#address-cells={ac} #size-cells={sc}")

mem_tuples = []
memblob = read_bytes("dt/memory-reg")
if memblob is not None and ac and sc:
    mem_tuples = parse_reg(memblob, ac, sc, "memory/reg")
    for lo, size in mem_tuples:
        note(f"DT memory: 0x{lo:08x} + 0x{size:08x} ({size // MIB} MiB)")
    if not mem_tuples:
        refuse("the device tree declares no memory at all")

res_tuples = []
resdir = path("dt", "reserved")
if os.path.isdir(resdir):
    for name in sorted(os.listdir(resdir)):
        rp = os.path.join(resdir, name, "reg")
        if not os.path.isfile(rp):
            refuse(f"reserved-memory/{name} has no reg property in the capture: a name alone is not "
                   f"evidence of where the region is")
            continue
        blob = open(rp, "rb").read()
        for lo, size in parse_reg(blob, ac or 1, sc or 1, f"reserved-memory/{name}"):
            res_tuples.append((name, lo, size))
            note(f"DT reserved {name}: 0x{lo:08x} + 0x{size:08x}")
else:
    note("no reserved-memory captured (absent is acceptable; unreadable is not)")

# ---- the decision on the target window ---------------------------------------------------------------
for lo, size in mem_tuples:
    if overlaps(lo, size, TARGET_BASE, TARGET_END):
        refuse(f"Linux is given 0x{lo:08x}+0x{size:08x}, which overlaps the teaching CPU's window "
               f"0x{TARGET_BASE:08x}-0x{TARGET_END:08x}. xv6's kinit would write over the ARM kernel.")
for name, lo, size in res_tuples:
    if overlaps(lo, size, TARGET_BASE, TARGET_END):
        refuse(f"reserved region {name} at 0x{lo:08x}+0x{size:08x} overlaps the teaching CPU's window: "
               f"something on the ARM side already claims memory the target is about to write")

# ---- /proc/iomem corroboration -----------------------------------------------------------------------
iomem = read_text("proc-iomem")
ram_ranges = []
if iomem:
    for ln in iomem.splitlines():
        if "System RAM" not in ln: continue
        rng = ln.split(":", 1)[0].strip()
        try:
            lo_s, hi_s = rng.split("-")
            ram_ranges.append((int(lo_s, 16), int(hi_s, 16)))
        except ValueError:
            refuse(f"cannot parse a System RAM line in /proc/iomem: {ln.strip()!r}")
    if not ram_ranges:
        refuse("/proc/iomem lists no System RAM: this is not a usable capture")
    for lo, hi in ram_ranges:
        note(f"iomem System RAM: 0x{lo:08x}-0x{hi:08x}")
        if hi >= TARGET_BASE:
            refuse(f"/proc/iomem has System RAM up to 0x{hi:08x}, inside the teaching CPU's window")
    # the two sources must agree with each other, or one of them is not describing this machine
    if mem_tuples:
        dt_top = max(lo + size - 1 for lo, size in mem_tuples)
        io_top = max(hi for _, hi in ram_ranges)
        if abs(dt_top - io_top) > 0x100000:
            refuse(f"the device tree tops out at 0x{dt_top:08x} but /proc/iomem at 0x{io_top:08x}: "
                   f"the two descriptions of this machine disagree")

# ---- MemTotal corroboration --------------------------------------------------------------------------
meminfo = read_text("proc-meminfo")
if meminfo:
    kb = None
    for ln in meminfo.splitlines():
        if ln.startswith("MemTotal:"):
            try: kb = int(ln.split()[1])
            except (IndexError, ValueError): pass
    if kb is None:
        refuse("/proc/meminfo has no parsable MemTotal")
    else:
        mb = kb / 1024.0
        note(f"MemTotal {mb:.0f} MiB")
        dt_mb = sum(size for _, size in mem_tuples) / MIB if mem_tuples else 0
        if dt_mb and mb > dt_mb + 8:
            refuse(f"MemTotal is {mb:.0f} MiB but the device tree declares {dt_mb:.0f} MiB: the kernel "
                   f"has more memory than the tree accounts for")
        if mb >= 384:
            refuse(f"MemTotal is {mb:.0f} MiB: Linux has been given more than the low half of the DDR, "
                   f"so the teaching CPU's window is not free")

verdict = "REFUSE" if refusals else "OK"
print(f"## evidence: {E}")
for n in notes: print(f"   {n}")
print(f"## target window: 0x{TARGET_BASE:08x}-0x{TARGET_END:08x}")
for r in refusals: print(f"   REFUSE: {r}")
print(f"MEM_PREFLIGHT {verdict} refusals={len(refusals)}")
if a.json:
    json.dump({"verdict": verdict, "session": sess, "refusals": refusals, "notes": notes},
              open(a.json, "w"), indent=1)
sys.exit(0 if verdict == "OK" else 1)
