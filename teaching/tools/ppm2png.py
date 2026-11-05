#!/usr/bin/env python3
"""A PPM image (P3 text or P6 binary) to PNG, each pixel blown up to a square, with nothing but the standard library.

    ppm2png.py <in.ppm> <out.png> [scale=4]

The OLED testbench writes the display's frame buffer as PPM; 96 x 64 is too small to look at, hence the scale.
"""
import struct
import sys
import zlib


def read_ppm(path):
    data = open(path, "rb").read()
    fields, pos = [], 0
    while len(fields) < 4:                       # magic, width, height, maxval; '#' starts a comment
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            pos = data.index(b"\n", pos)
            continue
        end = pos
        while end < len(data) and not data[end:end + 1].isspace():
            end += 1
        fields.append(data[pos:end])
        pos = end
    magic, w, h, maxval = fields[0], int(fields[1]), int(fields[2]), int(fields[3])
    if magic == b"P6":
        px = list(data[pos + 1:pos + 1 + 3 * w * h])
    elif magic == b"P3":
        px = [int(v) for v in data[pos:].split()][:3 * w * h]
    else:
        sys.exit("not a P3/P6 PPM: %s" % path)
    if maxval != 255:
        px = [v * 255 // maxval for v in px]
    return w, h, px


def write_png(path, w, h, px, scale):
    rows = []
    for y in range(h):
        line = bytearray()
        for x in range(w):
            line += bytes(px[3 * (y * w + x):3 * (y * w + x) + 3]) * scale
        rows += [b"\x00" + bytes(line)] * scale
    raw = b"".join(rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w * scale, h * scale, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


if __name__ == "__main__":
    w, h, px = read_ppm(sys.argv[1])
    write_png(sys.argv[2], w, h, px, int(sys.argv[3]) if len(sys.argv) > 3 else 4)
