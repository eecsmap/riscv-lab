#!/usr/bin/env python3
"""A stand-in for the SoC simulator, used to test scripts/xv6-drive.py without an hours-long run.

It reproduces the properties of the real simulator that the driver has to cope with, and nothing else:
console characters arrive in chunks that do not line up with lines, the harness's event lines are
interleaved into the same stdout (so a console line can be cut in half by one), the target echoes what is
typed at it, and output can still be produced at the moment the process is terminated.

Modes (argv[1] after the plusargs): ok | fail-ls | exit-midway
It appends every line it reads from stdin to $FAKESIM_INPUT_LOG, which is how the test proves that a
failed command stops the driver from typing the commands that follow.
"""
import os, sys, signal, time

mode = os.environ.get('FAKESIM_MODE', 'ok')
inlog = os.environ.get('FAKESIM_INPUT_LOG', '/dev/null')
out = sys.stdout
ev = [0]

def w(s):
    out.write(s); out.flush(); time.sleep(0.01)

def event(tag='EVH'):
    ev[0] += 1
    w(f'{tag} {ev[0]*7} bdev op=read sector={ev[0]}\n')

def console(s, newline=True, cut=False):
    """Write console text. cut=True delivers it in two chunks with an event line wedged in before the
    target's own newline -- the case that splits one console line across two stdout lines."""
    if cut:
        half = len(s) // 2
        w(s[:half]); event(); w(s[half:])
    else:
        w(s)
    if newline:
        w('\n')

def farewell(*_):
    # the real simulator prints its tally as it goes down; the driver must still capture it
    w('SIMTAIL cycles=123456 retired=7890\n')
    out.flush()
    os._exit(0)

signal.signal(signal.SIGTERM, farewell)

console('xv6 kernel is booting', cut=True)
console('')                                     # a genuinely empty console line
console('blkdev: 4000 sectors (1 MB), max request 16 sectors')
event('RD2')
console('init: starting sh')

# A real xv6 listing contains entries named after the very commands being run -- `ls`, `echo`, `cat`, `wc`.
# That is what defeats attributing output by searching for the command's name: in run-v2 the driver split
# the console at the `ls` binary's own entry and read only the tail, which does not contain README.
LISTING = ['.              1 1 1024', '..             1 1 1024', 'README         2 2 2441',
           'cat            2 3 36824', 'echo           2 4 35672', 'grep           2 6 40264',
           'ls             2 10 38960', 'sh             2 13 58672', 'wc             2 17 37816']
OUTPUT = {
    'echo teaching-xv6-hello': ['teaching-xv6-hello'],
    'ls':                      LISTING,
    'cat README':              ['xv6 is a re-implementation of Dennis Ritchie\'s and Ken Thompson\'s Unix'],
    'echo abc | wc':           ['      1       1       4'],
}
if mode == 'fail-ls':
    # the listing still mentions `ls`, so a driver that attributes by substring would still
    # find text after it and could pass or fail for the wrong reason
    OUTPUT['ls'] = ['ls: cannot open directory', 'ls             2 10 38960']    # prompt returns, but the expected output never appears

n = 0
while True:
    w('$ ')
    line = sys.stdin.readline()
    if not line:
        farewell()
    cmd = line.rstrip('\n')
    with open(inlog, 'a') as f:
        f.write(cmd + '\n')
    n += 1
    console(cmd, cut=(n == 1))                  # the target echoes what was typed
    if mode == 'exit-midway' and n == 2:
        w('SIMTAIL died after 2 commands\n')
        os._exit(3)
    for ln in OUTPUT.get(cmd, ['sh: command not found']):
        console(ln)
        if n == 2: event()
