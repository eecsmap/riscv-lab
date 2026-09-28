#!/usr/bin/env python3
"""objcopy -O binary image (loaded at 0x80000000) -> $readmemh file of 8192 little-endian 64-bit words (64 KiB)."""
import sys
b = open(sys.argv[1], 'rb').read(); assert len(b) <= 65536, len(b)
b = b + bytes(65536 - len(b))
with open(sys.argv[2], 'w') as f:
    for i in range(0, 65536, 8): f.write('%016x\n' % int.from_bytes(b[i:i + 8], 'little'))
