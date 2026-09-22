#!/usr/bin/env python3
"""Extract the raw configuration payload from a .bit, as written to /dev/xdevcfg.

The payload is NOT "everything from the sync word". A .bit header ends with an 'e' field carrying a
4-byte big-endian payload length, and the payload proper begins right after it -- starting with the
dummy/bus-width-detection words, with AA995566 a further 48 bytes in. An earlier version of this script
searched for the sync word and stripped to it, which silently discarded those 48 bytes: a .bin that would
have been loaded into the fabric without the bus-width detection pattern in front of it.

So the header is parsed, not guessed, and the 'e' field is located by self-consistency: its declared
length must equal exactly the bytes remaining after it. Anything else is refused.

  bit2bin.py <in.bit> <out.bin> [--expect <sha256>]
"""
import hashlib, struct, sys


def payload_offset(data):
    hits = [(p, struct.unpack(">I", data[p + 1:p + 5])[0])
            for p in range(0, 512)
            if data[p:p + 1] == b'e' and p + 5 <= len(data)
            and struct.unpack(">I", data[p + 1:p + 5])[0] == len(data) - (p + 5)]
    if not hits:
        raise SystemExit("REFUSE: no self-consistent 'e' length field; this is not a .bit header")
    if len(hits) > 1:
        raise SystemExit(f"REFUSE: {len(hits)} candidate 'e' fields {hits}; the header is ambiguous")
    p, n = hits[0]
    return p + 5, n


def convert(src, dst):
    data = open(src, "rb").read()
    off, n = payload_offset(data)
    payload = data[off:]
    assert len(payload) == n
    sync = payload.find(bytes.fromhex("AA995566"))
    if sync < 0:
        raise SystemExit("REFUSE: no AA995566 anywhere in the payload")
    open(dst, "wb").write(payload)
    return off, n, sync, hashlib.sha256(payload).hexdigest()


if __name__ == "__main__":
    off, n, sync, h = convert(sys.argv[1], sys.argv[2])
    print(f"BIT2BIN_OK payload at {off}, {n} bytes, sync word {sync} bytes into it")
    print(f"  sha256 {h}")
    if "--expect" in sys.argv:
        want = sys.argv[sys.argv.index("--expect") + 1]
        if h != want:
            raise SystemExit(f"REFUSE: expected {want}, got {h}")
        print("  matches the expected hash")
