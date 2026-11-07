#!/usr/bin/env python3
"""Send a program to the MCU-0 bootloader (teaching/uart/uart_boot.c) and start it.

usage: uart_load.py [--port P] [--baud B] [--addr A] [--no-break] [--term | --watch SEC] image.bin

1. A serial break (the line held low for 0.1 s) resets the board into the bootloader (mcu_break, BREAK_RESET=1);
   --no-break skips it: then press BTN3 yourself.
2. Waits for the prompt "boot> ", sends 'L' + address + length, expects 'A'.
3. Sends the bytes and their CRC-32 (zlib.crc32), expects 'K'.
4. Sends 'G', expects 'G'. Then --term turns this into a terminal (Ctrl+] quits), --watch SEC prints what the
   program sends for SEC seconds; without either it exits.
The image is a flat binary linked at --addr (teaching/uart/app.ld: 0x80001000); make boot-load builds and sends one.
"""
import argparse, sys, time, zlib
import serial

PROMPT = b"boot> "


def read_until(port, token, timeout):
    buf = b""
    end = time.time() + timeout
    while time.time() < end:
        buf += port.read(256)
        if token in buf:
            return buf
    return None


def answer(port, timeout):
    """The next byte is the bootloader's one-letter answer; the rest of its line is the explanation."""
    end = time.time() + timeout
    code = b""
    while not code and time.time() < end:
        code = port.read(1)
    if code == b"A":                           # accepted: it is now waiting for the bytes, no prompt follows
        return "A", ""
    rest = read_until(port, PROMPT, timeout) or b""
    text = rest.split(b"\r\n")[0].decode(errors="replace").strip()
    return code.decode(errors="replace"), text


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("image")
    ap.add_argument("--port", default="/dev/serial/by-id/usb-0403_6014-if00-port0")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--addr", type=lambda s: int(s, 0), default=0x80001000)
    ap.add_argument("--no-break", action="store_true")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--term", action="store_true")
    g.add_argument("--watch", type=float, default=0)
    a = ap.parse_args()

    data = open(a.image, "rb").read()
    crc = zlib.crc32(data) & 0xFFFFFFFF
    port = serial.Serial(a.port, a.baud, timeout=0.05)
    port.reset_input_buffer()
    if not a.no_break:
        port.send_break(0.1)
    else:
        print("press BTN3 on the board ...")
    if read_until(port, PROMPT, 3 if not a.no_break else 30) is None:
        sys.exit("no bootloader prompt: is the uart_boot bitstream on the board, and the adapter wired to D0/D1?")
    t0 = time.time()
    port.write(b"L" + a.addr.to_bytes(4, "little") + len(data).to_bytes(4, "little"))
    code, text = answer(port, 2)
    if code != "A":
        sys.exit("refused: %s %s" % (code, text))
    port.write(data + crc.to_bytes(4, "little"))
    code, text = answer(port, 5 + len(data) * 12 / a.baud)
    if code != "K":
        sys.exit("load failed: %s %s" % (code, text))
    print("loaded %d bytes in %.2f s: %s" % (len(data), time.time() - t0, text))
    port.write(b"G")
    code = port.read(1)
    deadline = time.time() + 2
    while not code and time.time() < deadline:
        code = port.read(1)
    if code != b"G":
        sys.exit("no 'G' after go (got %r)" % code)
    port.read_until(b"\n")
    print("running")
    if a.term:
        from serial.tools.miniterm import Miniterm
        term = Miniterm(port, echo=False, eol="cr")
        term.set_rx_encoding("utf-8")
        term.set_tx_encoding("utf-8")
        sys.stderr.write("--- terminal: Ctrl+] quits ---\n")
        term.start()
        try:
            term.join(True)
        except KeyboardInterrupt:
            pass
        term.join()
        term.close()
    elif a.watch:
        end = time.time() + a.watch
        while time.time() < end:
            sys.stdout.write(port.read(256).decode(errors="replace").replace("\r", ""))
            sys.stdout.flush()
        print()


if __name__ == "__main__":
    main()
