#!/usr/bin/env python3
"""Judge an xv6 run: every command must be bound to its own place in the transcript.

Codex's counterexample (CODEX_CHECKER_FINDING.md) showed why a global search is not enough: a transcript
with no `wc` output at all passed, because the pipe's "three numbers" pattern matched a directory entry
printed by an *earlier* `ls`. So the console is split into ordered shell segments here -- prompt, the
echoed command line, that command's output, up to the next prompt -- and each expected command is matched
against its own segment only. A missing stage record is a failure, not a silence, and the driver's record
of how the run ended must be present.

  check-xv6.py <rundir> [--require-commands]
"""
import sys, os, re, signal, argparse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# One implementation of "what is this command's output", shared with the driver: see xv6_console.py.
from xv6_console import (EXPECTED, STAGES, COMPATIBLE, DELIBERATE, profile, UnknownProfile,
                         segments, command_output, output_matches)

ap = argparse.ArgumentParser()
ap.add_argument('rundir'); ap.add_argument('--require-commands', action='store_true')
a = ap.parse_args()

# The workload comes from the RECORD BEING CHECKED, not from a flag, so the checker cannot be pointed at
# a different workload than the one that ran. More than one workload header, or conflicting ones, is a
# corrupt record: taking the first silently would check a transcript against a workload it may not have
# run.
def _workload_name(rundir):
    sp = os.path.join(rundir, 'stages.txt')
    names = []
    if os.path.exists(sp):
        for ln in open(sp):
            if ln.startswith('# workload:'):
                names.append(ln.split(':', 1)[1].strip())
    if len(names) > 1:
        uniq = sorted(set(names))
        raise UnknownProfile(
            f"the record carries {len(names)} workload headers ({uniq}); a transcript states its "
            f"workload once or not at all")
    return names[0] if names else 'default'


try:
    _profile_expected, _profile_stages = profile(_workload_name(a.rundir))
except UnknownProfile as e:
    print(f'  FAIL: {e}')
    print('XV6_CHECK fails=1')
    sys.exit(1)
con_path = os.path.join(a.rundir, 'console.txt')
if not os.path.exists(con_path):
    print(f'XV6_CHECK fails=1\n  FAIL: no console.txt in {a.rundir}'); sys.exit(1)
con = open(con_path, errors='replace').read()
fails = []

def bad(m): fails.append(m)

# ---- the always-required evidence
need_banner = 'xv6 kernel is booting' in con
if not need_banner: bad('no kernel banner: the kernel never reached its console output')
prompts = con.count('$ ')
if prompts < 1: bad('no shell prompt on the console: no user shell was reached')

# ---- ordered segments: text between one prompt and the next
segs = segments(con)

if a.require_commands:
    # each command must own a segment, in order, and its output must be inside that segment
    pos = 0
    for name, cmd, out_rx in _profile_expected:
        found, body = command_output(con, cmd, after=pos)
        if found is None:
            bad(f'command {name}: no prompt segment whose echoed line is exactly "{cmd}" '
                f'(a segment carrying more than the command means the next command was typed early)')
            continue
        if not output_matches(body, out_rx):
            bad(f'command {name}: its own segment carries no matching output '
                f'(the pattern must be satisfied *inside* this command\'s output, not elsewhere)')
        if found + 1 >= len(segs) and not con.rstrip().endswith('$'):
            bad(f'command {name}: the prompt did not come back after it')
        pos = found + 1

# ---- the driver's stage record: complete, in order, all ok, and a real ending
stagefile = os.path.join(a.rundir, 'stages.txt')
stages = []
if not os.path.exists(stagefile):
    bad('no stages.txt: the driver left no record of what it did or how the run ended')
else:
    txt = open(stagefile).read()
    for ln in txt.splitlines():
        if ln.startswith('#'): continue
        p = ln.rstrip('\n').split('\t')
        if len(p) == 3: stages.append((p[0], p[1], p[2]))
    names = [s[2] for s in stages]
    bad_stages = [s for s in stages if s[0] != 'ok']
    if bad_stages: bad('stage(s) not ok: ' + ', '.join(f'{s[2]}={s[0]}' for s in bad_stages))
    if a.require_commands:
        want = [n for n in _profile_stages]
        have = [n for n in names]
        missing = [w for w in want if not any(w in h for h in have)]
        if missing: bad(f'stage record is incomplete: missing {missing}')
        else:
            idx = [next(i for i, h in enumerate(have) if w in h) for w in want]
            if idx != sorted(idx): bad(f'stage records are out of order: {have}')
    # ---- how the run ended, by value and not merely by presence
    def field(label):
        hits = [ln[len(label):].strip() for ln in txt.splitlines() if ln.startswith(label)]
        if len(hits) > 1:
            bad(f'the ending record carries {len(hits)} "{label}" lines ({hits}): a transcript with a '
                f'contradictory ending cannot be read as evidence')
        return hits[0] if hits else None

    drv = field('# driver:')
    if drv not in COMPATIBLE:
        bad(f'the transcript was produced by driver {drv!r}, not one of {COMPATIBLE}: earlier drivers '
            f'joined console lines without newlines, so this console cannot be segmented reliably')

    # ---- which machine produced this transcript, and does its identity set match that claim?
    # A board record and a simulator record are otherwise interchangeable text, and the whole point of the
    # identity record is that a result names the machine that produced it. Transcripts from before the
    # board runner existed carry no platform line and are simulator runs by definition.
    platform = field('# platform:') or 'simulator'
    if platform not in ('simulator', 'board'):
        bad(f'unrecognised platform {platform!r}')
    required = {'simulator': ['# simulator sha256:', '# kernel sha256:'],
                'board':     ['# bitstream sha256:', '# host binary sha256:', '# kernel sha256:']}
    forbidden = {'simulator': ['# bitstream sha256:', '# host binary sha256:'],
                 'board':     ['# simulator sha256:']}
    if platform in required:
        # a pre-identity simulator transcript is still acceptable; a board one is not, because it was
        # written by a runner that always records these
        for label in required[platform]:
            if field(label) is None and not (platform == 'simulator' and drv == 'v2'):
                bad(f'a {platform} run must record {label.strip("#: ")}, and this one does not')
        for label in forbidden[platform]:
            if field(label) is not None:
                bad(f'this transcript claims to be a {platform} run but carries {label.strip("#: ")}: '
                    f'a result must name the machine that actually produced it')

    stop = field('# stop:')
    exitv = field('# simulator exit:') if platform == 'simulator' else field('# host exit:')
    if stop is None:  bad('the driver did not record how the run ended')
    elif not stop:    bad('the driver recorded an empty stop reason')
    elif stop == DELIBERATE:
        # The one legitimate ending: the driver stopped a healthy simulator after finishing its commands.
        # It is only meaningful if every stage actually passed -- otherwise the label contradicts the run.
        if fails:
            bad(f'the run is labelled {DELIBERATE!r} but stages did not all pass; a deliberate stop is '
                f'only an acceptable ending for an otherwise clean run')
    elif stop == 'no-shell-prompt':
        bad('the run never reached a shell prompt')
    elif stop.startswith('stopped-after-failed-command:'):
        bad(f'the driver stopped because a command failed: {stop.split(":",1)[1]}')
    elif stop.startswith(('simulator-exited-during-command:', 'host-exited-during-command:')):
        bad(f'the {platform} host exited while running command {stop.split(":",1)[1]}')
    elif stop.startswith(('simulator-exited-on-its-own:', 'host-exited-on-its-own:')):
        bad(f'the {platform} host terminated unexpectedly on its own (status {stop.split(":",1)[1]}); a run '
            f'that ends by itself did not stop where the driver intended')
    else:
        bad(f'unrecognised stop reason {stop!r}')

    if exitv is None: bad(f"the driver did not record the {platform} host's exit status")
    else:
        try: ev = int(exitv)
        except ValueError: ev = None
        if ev is None: bad(f'the {platform} exit status {exitv!r} is not a number')
        else:
            # What a *deliberate* stop looks like differs by platform, so the accepted values do too.
            # This is not a loosening: each platform has exactly one interruption status it may report.
            #   simulator -- the driver sends SIGTERM to a local process: -15
            #   board     -- the stop is an in-band interrupt on the console, so the wrapper records
            #                128 + SIGINT = 130. There is no SIGTERM to send down a serial line.
            if platform == 'board':
                allowed, how = (0, 130), '0, or 130 (128+SIGINT) for the deliberate in-band interrupt'
            else:
                allowed, how = (0, -signal.SIGTERM), \
                    f'0, or -{int(signal.SIGTERM)} for the driver\'s deliberate SIGTERM'
            if ev not in allowed:
                bad(f'the {platform} exit status is {ev}: expected {how}; anything else is a crash or a '
                    f'forced kill')

    if field('# signalled:') == 'SIGKILL':
        bad('the simulator had to be SIGKILLed: it did not shut down when asked, so the tail of its '
            'output is not trustworthy')

print(f'XV6_CHECK segments={len(segs)} prompts={prompts} stages={len(stages)} '
      f'console_bytes={len(con)} fails={len(fails)}')
for f in fails: print('  FAIL:', f)
sys.exit(1 if fails else 0)
