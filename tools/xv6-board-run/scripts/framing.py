#!/usr/bin/env python3
"""Incremental framing of the transport's end-of-command marker.

This is the production parser. `serial-transport.py` imports it and the tests import the same module, so
there is one implementation and nothing to drift.

The wrapper on the board finishes a command by echoing

    __X<pid>__=<status><newline>

and the shim must do two things at once with the byte stream it sees: pass the target's console through
promptly -- a shell prompt is `"$ "` with no newline after it, and a driver waiting for that prompt cannot
be kept waiting -- while never mistaking a piece of the marker for console output.

Two defects the previous version had, both found in review:

  * **it flushed everything after 150 ms of silence.** Silence proves nothing. `__X123__=` can arrive, then
    a pause, then `130\\r\\n`; the prefix was emitted as console text and the marker was lost.
  * **its pattern accepted an unterminated number.** `TAG=(-?\\d+)` matches `__X123__=1` and yields 1, so a
    status of 130 split as `1` + `30\\r\\n` was recorded as 1 -- a wrong exit status, written as though it
    were framed evidence.

So: a complete record requires its terminator, and what is held back is not "whatever arrived recently"
but precisely *the longest suffix that could still become a marker*. Everything else goes out at once,
which is why no idle timer is needed at all.
"""
import re


class Framer:
    """Feed it bytes; it yields console output and, eventually, one complete status record."""

    def __init__(self, tag):
        self.tag = tag.encode() if isinstance(tag, str) else tag
        #: a complete record: the tag, '=', an optional sign, digits, and a terminator. The terminator is
        #: what makes it complete; without it the digits may still be growing.
        self.complete = re.compile(re.escape(self.tag) + rb"=(-?\d+)(?:\r\n|\n|\r)")
        #: the tag with a partial number and no terminator yet
        self.pending = re.compile(re.escape(self.tag) + rb"=-?\d*$")
        self.buf = b""
        self.status = None

    def feed(self, chunk):
        """Add bytes. Returns the console output that can safely be emitted now.

        When a complete record is seen, `self.status` is set and everything before the record is returned;
        bytes after it are discarded, because the command is over.
        """
        self.buf += chunk
        m = self.complete.search(self.buf)
        if m:
            self.status = int(m.group(1))
            out, self.buf = self.buf[:m.start()], b""
            return out
        keep = self._retain_len()
        out = self.buf[:len(self.buf) - keep] if keep else self.buf
        self.buf = self.buf[len(self.buf) - keep:] if keep else b""
        return out

    def _retain_len(self):
        """How many trailing bytes could still become a marker, and so must not be emitted."""
        b = self.buf
        # the tag has fully arrived and a number is accumulating, still unterminated
        m = self.pending.search(b)
        if m:
            return len(b) - m.start()
        # only part of the tag has arrived, at the very end
        for k in range(min(len(self.tag), len(b)), 0, -1):
            if b.endswith(self.tag[:k]):
                return k
        return 0

    def flush(self):
        """Whatever is still held back, for the end of the stream. Only safe once no more bytes can come:
        at EOF a retained prefix was never going to complete, so it was console text after all."""
        out, self.buf = self.buf, b""
        return out
