#!/usr/bin/env python3
"""Drive xv6 on the teaching SoC simulator: watch the console, type at the prompt, and stop deliberately.

The simulator's stdout carries the target's console characters interleaved with the harness's own event
lines; the console is what is left when those are removed. The *only* reader of the target's console input
is the host (fesvr) through this process's stdin pipe -- nothing else reads it, so there is no second reader
to split the stream.

Success, deadline and exit semantics, stated up front:
  * a stage passes when its evidence appears on the console (and, for a command, output beyond the echo of
    the command itself);
  * the deadline is a wall-clock timeout *per stage*; hitting it is a failure of that stage;
  * reaching the end of the script is NOT a timeout: a shell is a system that keeps running, so the driver
    stops it on purpose and records that as a controlled stop with the stages it completed.
  xv6-drive.py <sim> <kernel elf> <fs.img> <outdir> [--stage-timeout S] [--max-cycles N]
"""
import argparse, os, re, select, signal, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xv6_console import DRIVER_VERSION, EXPECTED, PROMPT, command_output, output_matches

EVENT = re.compile(r'((AT|RD2|EV|EVA|EVH|RD2HOST|RBOOT)\s+\d+\s+\S.*)$')
ap = argparse.ArgumentParser()
ap.add_argument('sim'); ap.add_argument('elf'); ap.add_argument('disk'); ap.add_argument('outdir')
ap.add_argument('--stage-timeout', type=float, default=900.0)
ap.add_argument('--max-cycles', type=int, default=400_000_000)
ap.add_argument('--progress', type=int, default=2_000_000)   # one PROGRESS line per N cycles
a = ap.parse_args()
os.makedirs(a.outdir, exist_ok=True)
rawlog = open(os.path.join(a.outdir, 'run.log'), 'w')
conlog = open(os.path.join(a.outdir, 'console.txt'), 'w')

# Record what this run is actually made of, at the moment it starts: an archive taken later cannot hash
# the driver that produced the transcript if the source has been edited since.
def _sha(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(65536), b''): h.update(b)
    return h.hexdigest()
_here = os.path.dirname(os.path.abspath(__file__))
IDENT = {'driver': _sha(os.path.abspath(__file__)), 'console-module': _sha(os.path.join(_here, 'xv6_console.py')),
         'simulator': _sha(a.sim), 'kernel': _sha(a.elf), 'disk at start': _sha(a.disk)}

proc = subprocess.Popen([a.sim, f'+max-cycles={a.max_cycles}', f'+blkdev={a.disk}',
                         f'+rd2_progress={a.progress}', a.elf],
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                        bufsize=0)
console = []          # the reconstructed console text
pending = b''
stages = []           # (name, wall seconds, console offset when satisfied)
t0 = time.time()

def pump(deadline, drain=False):
    """Read what is available until the deadline. Returns False when the simulator has exited *and* its
    output has been drained to EOF.

    The console and the harness's event lines share stdout. A stdout line that contains an event is a
    console *fragment* followed by that event: the newline in the stream belongs to the event line, not to
    the target, so the fragment is appended without one. A stdout line with no event in it is console text
    that really did end with a newline, so the newline is kept -- including for empty lines, which the
    checker needs to separate an echoed command from its output."""
    global pending
    while True:
        chunk = b''
        r, _, _ = select.select([proc.stdout], [], [], 0.2)
        if r:
            chunk = proc.stdout.read(65536) or b''
            if chunk:
                rawlog.write(chunk.decode('utf-8', 'replace')); rawlog.flush()
                pending += chunk
                *lines, pending = pending.split(b'\n')
                for ln in lines:
                    t = ln.decode('utf-8', 'replace')
                    m = EVENT.search(t)
                    if m:
                        frag = t[:m.start()]          # console text before an event: no newline of its own
                        if frag: emit(frag)
                    else:
                        emit(t + '\n')               # a real console line, newline included
        exited = proc.poll() is not None
        if exited and not chunk:
            # drained: nothing more is coming. Flush any partial line as console text.
            if pending:
                t = pending.decode('utf-8', 'replace'); pending = b''
                m = EVENT.search(t)
                frag = t[:m.start()] if m else t
                if frag: emit(frag)
            return False
        if not drain and time.time() > deadline:
            return True

def emit(text):
    console.append(text); conlog.write(text); conlog.flush()

# The tail of an event line that has not arrived in full yet: it must not be mistaken for console text.
PARTIAL_EVENT = re.compile(r'(AT|RD2|EV|EVA|EVH|RD2HOST|RBOOT)(\s+\d*(\s.*)?)?$')

def text():
    """The console so far, including the line still being written.

    A shell prompt ends in "$ " with no newline after it, so the line holding it stays in the read buffer
    indefinitely. Waiting only on completed lines would therefore never see a prompt unless an event line
    happened to come along and terminate it. The unterminated tail is offered here for matching, with any
    beginning-of-an-event-line trimmed off it, but it is not committed to console.txt until it completes
    (or until EOF, where pump flushes it)."""
    tail = pending.decode('utf-8', 'replace')
    m = PARTIAL_EVENT.search(tail)
    if m: tail = tail[:m.start()]
    return ''.join(console) + tail

def wait_for(pattern, what, timeout):
    """wait until `pattern` appears in the console; record the stage"""
    rx = re.compile(pattern)
    start = len(text())
    deadline = time.time() + timeout
    while time.time() < deadline:
        if rx.search(text()):
            stages.append((what, round(time.time() - t0, 1), 'ok'))
            print(f"  [{time.time()-t0:7.1f}s] {what}: seen")
            return True
        if not pump(min(deadline, time.time() + 2.0)):
            break
    stages.append((what, round(time.time() - t0, 1), 'TIMEOUT'))
    print(f"  [{time.time()-t0:7.1f}s] {what}: NOT seen within {timeout}s")
    return False

def send(line):
    proc.stdin.write((line + '\n').encode()); proc.stdin.flush()
    print(f"  [{time.time()-t0:7.1f}s] typed: {line!r}")

result = {'stopped': 'unknown'}
try:
    ok_boot  = wait_for(r'xv6 kernel is booting', 'kernel banner', a.stage_timeout)
    ok_init  = wait_for(r'init: starting sh|\$ ', 'init started / first prompt', a.stage_timeout)
    ok_shell = wait_for(r'\$ ', 'shell prompt', a.stage_timeout)
    if not ok_shell:
        result['stopped'] = 'no-shell-prompt'
    else:
        result['stopped'] = 'deliberate-stop-after-all-commands'
        done = 0                       # how many prompt segments have already been accounted for
        for name, cmd, expect in EXPECTED:
            # The shell echoes what is typed, so waiting for the expected text can match the echo of the
            # command itself and race ahead of the command actually running. Wait for the *prompt* to come
            # back first, then read the output through the same segmentation the checker uses -- looking
            # for the text anywhere after the command would find the command's own name inside its output.
            before = text().count(PROMPT)
            send(cmd)
            deadline = time.time() + a.stage_timeout
            alive = True
            while text().count(PROMPT) <= before and time.time() < deadline:
                if not pump(min(deadline, time.time() + 2.0)):
                    alive = False; break
            returned = text().count(PROMPT) > before
            idx, body = command_output(text(), cmd, after=done)
            got = output_matches(body, expect)
            if idx is not None: done = idx + 1
            ok = returned and got
            stages.append((f'command {name}', round(time.time() - t0, 1), 'ok' if ok else 'FAILED'))
            print(f"  [{time.time()-t0:7.1f}s] command {name}: "
                  f"{'output seen and prompt returned' if ok else 'NOT satisfied'}"
                  f"{'' if idx is not None else ' (no segment echoing exactly this command)'}")
            if not ok:
                # Do not type the next command into a shell whose state is unknown: a command that never
                # returned leaves the input stream ambiguous, and later output could not be attributed.
                result['stopped'] = ('simulator-exited-during-command:' + name if not alive
                                     else 'stopped-after-failed-command:' + name)
                break
finally:
    # Record how the simulator really ended, and drain its output to EOF either way: the tail of the
    # console (and the last events) is written after the last command and would be lost by returning as
    # soon as poll() reports an exit.
    if proc.poll() is None:
        result['killed'] = 'SIGTERM'
        proc.send_signal(signal.SIGTERM)
        deadline = time.time() + 20
        while proc.poll() is None and time.time() < deadline:
            pump(time.time() + 1.0)
        if proc.poll() is None:
            result['killed'] = 'SIGKILL'; proc.kill()
    elif result['stopped'] in ('deliberate-stop-after-all-commands', 'unknown'):
        result['stopped'] = f'simulator-exited-on-its-own:{proc.returncode}'
    pump(0, drain=True)          # drain to EOF
    try: proc.wait(timeout=30)
    except subprocess.TimeoutExpired: proc.kill(); proc.wait()
    rawlog.close(); conlog.close()

bad = [s for s in stages if s[2] != 'ok']
with open(os.path.join(a.outdir, 'stages.txt'), 'w') as f:
    for name, t, st in stages: f.write(f"{st}\t{t}\t{name}\n")
    f.write(f"# driver: {DRIVER_VERSION}\n")
    for k, v in IDENT.items(): f.write(f"# {k} sha256: {v}\n")
    f.write(f"# simulator exit: {proc.returncode}\n# stop: {result['stopped']}\n")
    if 'killed' in result: f.write(f"# signalled: {result['killed']}\n")
print(f"XV6_DRIVE stages={len(stages)} failed={len(bad)} sim_exit={proc.returncode} ({result['stopped']})")
sys.exit(1 if bad else 0)
