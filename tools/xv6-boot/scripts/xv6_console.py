"""The console vocabulary shared by the driver and the checker.

These two programs must never disagree about what a command's output is. When they each had their own
idea, run-v2 was aborted on a false negative: the driver attributed output by `rsplit(cmd, 1)`, which for
`ls` split at the `ls` binary's own entry *inside the listing* and so looked only at the tail, where README
does not appear. The checker, segmenting on the prompt, saw the same console as a pass. The answer is not a
better heuristic in one of them -- it is one implementation, used by both.
"""
import re

DRIVER_VERSION = 'v3'
# Transcripts the checker will read. v1 joined console lines with no newlines and cannot be segmented at
# all; v2 and v3 have the same transcript format and differ only in how the driver attributes output.
COMPATIBLE = ('v2', 'v3')
DELIBERATE = 'deliberate-stop-after-all-commands'

PROMPT = '$ '
EXPECTED = [                       # (name, the command as typed, a regex its own output must satisfy)
    ('echo', 'echo teaching-xv6-hello', r'teaching-xv6-hello'),
    ('ls',   'ls',                      r'^\s*README\b'),
    ('cat',  'cat README',              r're-implementation|xv6 is a'),
    ('pipe', 'echo abc | wc',           r'^\s*\d+\s+\d+\s+\d+\s*$'),
]
STAGES = ['kernel banner', 'init started / first prompt', 'shell prompt',
          'command echo', 'command ls', 'command cat', 'command pipe']

#: Named workload profiles. EXPECTED and STAGES above are unchanged and remain the default, so a run that
#: names no profile behaves exactly as before, byte for byte.
#:
#: A profile is (name, command as typed, regex its own output must satisfy). The SAME profile is used by
#: the driver to decide what to send and by the checker to decide what to accept. There is deliberately
#: no way to pass an arbitrary command: a caller selects a NAME, and anything not named here cannot run.
#:
#: The checksums match case-insensitively, via an inline (?i). They were computed on the host with C's
#: %lx, which is lowercase, while xv6's own printf uses "0123456789ABCDEF". A run that produced exactly
#: the right value therefore failed its check on case alone -- found by running it, not by reading it.
PROFILES = {
    'default': EXPECTED,
    'b0apps': [
        ('b0compute', 'b0compute', r'(?i)B0-COMPUTE-CHECKSUM=5adf55920bf7696\b'),
        ('b0array',   'b0array',   r'(?i)B0-ARRAY-CHECKSUM=88133d5bd386db60\b'),
        ('b0file',    'b0file',    r'(?i)B0-FILE-CHECKSUM=62e55f5326378000\b'),
    ],
}


class UnknownProfile(Exception):
    """A workload name that is not in PROFILES. Raised early, and converted to a refusal by callers."""


def profile(name='default'):
    """The named workload and the stage names that go with it. Unknown names are refused.

    Callers must resolve this BEFORE constructing a transport, taking a lease or launching a host: an
    unknown name that is only noticed inside the command loop has already started something on the board.
    """
    if name is None:
        name = 'default'
    if name not in PROFILES:
        raise UnknownProfile(f"unknown workload profile {name!r}; known: {sorted(PROFILES)}")
    exp = PROFILES[name]
    return exp, (STAGES[:3] + [f'command {n}' for n, _, _ in exp])


def segments(text):
    """Split a console into (echoed command line, its output) pairs, one per prompt."""
    out = []
    for p in text.split(PROMPT)[1:]:          # everything after a prompt
        line, _, rest = p.partition('\n')     # the echoed command line, then its output
        out.append((line.strip(), rest))
    return out


def command_output(text, cmd, after=0):
    """The output belonging to `cmd`: the body of the first segment at or after index `after` whose echoed
    line is *exactly* the command. Returns (index, body), or (None, None) if there is no such segment.

    Requiring the echoed line to be exactly the command is what stops a segment carrying more than one
    command -- which is what happens when the next command is typed before the previous one returned -- from
    being read as evidence for either of them."""
    segs = segments(text)
    for i in range(after, len(segs)):
        if segs[i][0] == cmd:
            return i, segs[i][1]
    return None, None


def output_matches(body, rx):
    return body is not None and re.search(rx, body, re.M) is not None


# The tail of an event line that has not arrived in full yet: it must not be mistaken for console text
# when the still-unterminated read buffer is offered for matching.
#
# This is also defined in xv6-drive.py. The duplication is deliberate: that driver is the accepted evidence
# for the four-command milestone and its hash is recorded in run-v3/IDENTITY.md, so it is not being edited
# to import this. The duplication is *checked* rather than trusted -- console-selftest.py asserts the two
# patterns are identical, so they cannot drift apart silently.
PARTIAL_EVENT_OK = re.compile(r'(AT|RD2|EV|EVA|EVH|RD2HOST|RBOOT)(\s+\d*(\s.*)?)?$')
