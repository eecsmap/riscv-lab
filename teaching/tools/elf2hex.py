#!/usr/bin/env python3
"""ELF -> $readmemh image of 64-bit little-endian words, base 0x8000_0000, plus the tohost address.

usage: elf2hex.py <objcopy> <nm> <elf> <out.hex> <out.tohost>
The image is the ELF's loadable bytes as a flat binary (objcopy -O binary), so the first word is the word at
the base address and there are no gaps: the probe linker script places everything contiguously from the base.
"""
import subprocess, sys

BASE = 0x80000000

def main():
    objcopy, nm, elf, out_hex, out_tohost = sys.argv[1:6]
    subprocess.run([objcopy, "-O", "binary", elf, out_hex + ".bin"], check=True)
    raw = open(out_hex + ".bin", "rb").read()
    raw += b"\0" * ((-len(raw)) % 8)
    with open(out_hex, "w") as f:
        for i in range(0, len(raw), 8):
            f.write("%016x\n" % int.from_bytes(raw[i:i + 8], "little"))
    syms = subprocess.run([nm, elf], check=True, capture_output=True, text=True).stdout
    tohost = [int(l.split()[0], 16) for l in syms.splitlines() if l.split()[-1] == "tohost"]
    if len(tohost) != 1:
        sys.exit("elf2hex: expected exactly one tohost symbol, found %d" % len(tohost))
    if tohost[0] < BASE or tohost[0] >= BASE + len(raw):
        sys.exit("elf2hex: tohost 0x%x is outside the image" % tohost[0])
    with open(out_tohost, "w") as f:
        f.write("%08x\n" % tohost[0])
    print("elf2hex: %d words, tohost=0x%08x" % (len(raw) // 8, tohost[0]))

if __name__ == "__main__":
    main()
