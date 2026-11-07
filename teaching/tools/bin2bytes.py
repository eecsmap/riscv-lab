#!/usr/bin/env python3
"""Flat binary -> $readmemh file with one byte per line, for tb_boot.v; prints the plusargs +pay_len and +pay_crc.

usage: bin2bytes.py <image.bin> <out.hex>
"""
import sys, zlib

data = open(sys.argv[1], "rb").read()
with open(sys.argv[2], "w") as f:
    for b in data:
        f.write("%02x\n" % b)
print("+pay_len=%d +pay_crc=%08x" % (len(data), zlib.crc32(data) & 0xFFFFFFFF))
