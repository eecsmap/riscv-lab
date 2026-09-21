#!/usr/bin/env python3
"""Build the captured-evidence fixtures the memory preflight is tested against.

These stand in for a capture of a running ARM. They are written here rather than taken from a board because
this task has no hardware access, and they are written as *bytes* -- big-endian device-tree cells, real
/proc/iomem and /proc/meminfo text -- so the parser is exercised on the same shapes it will see.

  make-mem-fixtures.py <outdir>
"""
import sys, os, struct

out = sys.argv[1]
if os.path.exists(out):
    print(f"REFUSE: {out} exists -- give a fresh directory"); sys.exit(2)

MIB = 1024 * 1024
SESSION = "6f1d0a3c-2b47-4e18-9f55-1c0de7a94b21"

def be(*vals): return b"".join(struct.pack(">I", v) for v in vals)

def write(d, rel, data):
    p = os.path.join(d, *rel.split("/"))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "wb").write(data if isinstance(data, bytes) else data.encode())

def base_case(name, mem_tuples, memtotal_kb, iomem_top, reserved=None, session=SESSION,
              address_cells=1, size_cells=1):
    d = os.path.join(out, name)
    write(d, "session-id", session + "\n")
    write(d, "dt/address-cells", struct.pack(">I", address_cells))
    write(d, "dt/size-cells", struct.pack(">I", size_cells))
    blob = b""
    for lo, size in mem_tuples:
        blob += be(lo) if address_cells == 1 else be(lo >> 32, lo & 0xffffffff)
        blob += be(size) if size_cells == 1 else be(size >> 32, size & 0xffffffff)
    write(d, "dt/memory-reg", blob)
    for rname, rlo, rsize in (reserved or []):
        write(d, f"dt/reserved/{rname}/reg", be(rlo) + be(rsize))
    io = ("00000000-%08x : System RAM\n" % iomem_top +
          "  00008000-0087ffff : Kernel code\n"
          "  00980000-009fffff : Kernel data\n"
          "43c00000-43c00fff : /amba_pl/htif@43c00000\n")
    write(d, "proc-iomem", io)
    write(d, "proc-meminfo",
          f"MemTotal:       {memtotal_kb} kB\nMemFree:         180000 kB\nBuffers:           2000 kB\n")
    return d

# 1. the safe case: Linux owns the low 256 MiB only
base_case("safe-256", [(0x00000000, 256 * MIB)], 256 * 1024 - 8000, 0x0fffffff,
          reserved=[("linux,cma", 0x08000000, 16 * MIB)])

# 2. the unsafe case: Linux has been given all 512 MiB, which is the recorded incident
base_case("unsafe-512", [(0x00000000, 512 * MIB)], 512 * 1024 - 8000, 0x1fffffff)

# 3. a reserved region that reaches into the teaching CPU's window
base_case("overlapping-reservation", [(0x00000000, 256 * MIB)], 256 * 1024 - 8000, 0x0fffffff,
          reserved=[("linux,cma", 0x08000000, 16 * MIB),
                    ("vendor-blob", 0x0ff00000, 32 * MIB)])     # runs from 0x0ff00000 into 0x11efffff

# 4. malformed: a reg blob that is not a whole number of tuples
d = base_case("malformed", [(0x00000000, 256 * MIB)], 256 * 1024 - 8000, 0x0fffffff)
open(os.path.join(d, "dt", "memory-reg"), "wb").write(be(0x00000000, 0x10000000) + b"\x00\x00")

# 5. evidence from a different boot than the one we are about to load into
base_case("changed-session", [(0x00000000, 256 * MIB)], 256 * 1024 - 8000, 0x0fffffff,
          session="00000000-1111-2222-3333-444444444444")

# 6. redacted: someone tidied the capture by hand
d = base_case("redacted", [(0x00000000, 256 * MIB)], 256 * 1024 - 8000, 0x0fffffff)
open(os.path.join(d, "proc-iomem"), "w").write("00000000-REDACTED : System RAM\n")

# 7. the two sources disagree: a little-endian misread of the DT would look like this
base_case("inconsistent", [(0x00000000, 256 * MIB)], 256 * 1024 - 8000, 0x1fffffff)

# 8. reserved-memory present but with no reg: a name listing, which is not evidence
d = base_case("reserved-name-only", [(0x00000000, 256 * MIB)], 256 * 1024 - 8000, 0x0fffffff)
os.makedirs(os.path.join(d, "dt", "reserved", "mystery-region"), exist_ok=True)

# 9. the same safe machine described with 2-cell addresses, to show the widths are read and not assumed
base_case("safe-256-2cell", [(0x00000000, 256 * MIB)], 256 * 1024 - 8000, 0x0fffffff,
          address_cells=2, size_cells=2)

# ---- NUL and identifier-syntax boundary cases -------------------------------------------------------
# The live board emits boot_id as 36 characters + ONE trailing NUL and no newline; /proc/iomem and
# /proc/meminfo from the same capture contain none. These fixtures pin that boundary so the normalisation
# stays narrow: a terminator is tolerated, corruption is not.
d = base_case("nul-terminated-session", [(0x00000000, 256 * MIB)], 256 * 1024 - 8000, 0x0fffffff)
open(os.path.join(d, "session-id"), "wb").write(SESSION.encode() + b"\x00")   # exactly as the board sends

d = base_case("nul-embedded-session", [(0x00000000, 256 * MIB)], 256 * 1024 - 8000, 0x0fffffff)
open(os.path.join(d, "session-id"), "wb").write(SESSION.encode()[:10] + b"\x00" + SESSION.encode()[11:])

d = base_case("nul-in-iomem", [(0x00000000, 256 * MIB)], 256 * 1024 - 8000, 0x0fffffff)
b = open(os.path.join(d, "proc-iomem"), "rb").read()
open(os.path.join(d, "proc-iomem"), "wb").write(b[:20] + b"\x00" + b[21:])

d = base_case("malformed-session", [(0x00000000, 256 * MIB)], 256 * 1024 - 8000, 0x0fffffff)
open(os.path.join(d, "session-id"), "w").write("not-a-uuid-at-all\n")

d = base_case("truncated-session", [(0x00000000, 256 * MIB)], 256 * 1024 - 8000, 0x0fffffff)
open(os.path.join(d, "session-id"), "w").write(SESSION[:20] + "\n")

print(f"fixtures written to {out}")
