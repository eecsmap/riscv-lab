#!/usr/bin/env python3
"""MC-M2b judge for one dual-hart run directory (made by run-dual.sh).

Never judges by a success string alone. Every rule reads the EVENT TRACE (events.txt: EV/RD2/RD2H/RD2HOST/EVH
lines, per hart), the host's per-hart totals (HARTS ... in console.txt), the exit code and the program's own
console; a run passes only when all of them agree. Which rules apply is chosen by --prog.

  dual_check.py <rundir> --prog <name> [--fast] [--elf <elf>] [--drain] [--min-retired N] [--atomic-floor N]

Exit 0 = pass; every failure names the rule and the evidence it did not find.
"""
import re, sys, os, argparse, subprocess
ap = argparse.ArgumentParser(); ap.add_argument('rundir'); ap.add_argument('--prog', required=True)
ap.add_argument('--fast', action='store_true', help='trace-free configuration: only console/HARTS/exit rules')
ap.add_argument('--elf'); ap.add_argument('--drain', action='store_true', help='an injected soft reset with both harts in flight is expected')
ap.add_argument('--min-retired', type=int, default=1); ap.add_argument('--atomic-floor', type=int, default=0, help='AT SC_OK/AMO_START per hart floor (tracing dual03)')
ap.add_argument('--apply-cycles', type=int, default=2); ap.add_argument('--expect-exit', type=int, default=0)
ap.add_argument('--cpu-region', type=lambda x: tuple(int(v, 0) for v in x.split(':')), default=(0x80020000, 0x80030000), help='DRAM range only the CPUs write (no host load): every AXI write there must have a CPU request')
ap.add_argument('--scratch', type=lambda x: int(x, 0), default=0x80020000); ap.add_argument('--scratch-stride', type=lambda x: int(x, 0), default=0x4000)
a = ap.parse_args(); D = a.rundir
fails = []
def bad(m): fails.append(m)
def rd(n):
    p = os.path.join(D, n)
    return open(p, errors='replace').read() if os.path.exists(p) else ''
console = rd('console.txt'); stderr = console; events = rd('events.txt').splitlines()   # the simulator's own lines land in the console stream (2>&1)
clean = rd('console-clean.txt')          # the program's own characters, recovered by run-dual.sh (trace prefixes stripped)
exit_code = int(rd('exit').strip() or -1)
if exit_code != a.expect_exit: bad(f'simulator exit {exit_code}, expected {a.expect_exit}')
if a.expect_exit == 0 and 'Completed after' not in stderr: bad('no "Completed after" from the simulator (a timeout or a host failure is not a pass)')
if 'HOSTDONE' not in console and 'HOSTDONE' not in rd('events.txt'): bad('no HOSTDONE: the host never saw the program finish')
MARK = {'dual01_boot': 'M2B-BOOT-OK', 'dual02_clint': 'M2B-CLINT-OK', 'dual03_lock': 'M2B-LOCK-OK', 'dual04_pbus': 'M2B-PBUS-OK',
        'dual05_fencei': 'M2B-FENCEI-OK', 'dual06_drain': 'M2B-DRAIN-OK', 'dual07_long': 'M2B-LONG-OK'}
base = a.prog.split('+')[0]
mark = MARK.get(base)
if mark is None: bad(f'no marker table entry for {base}')
# the console: HTIF characters may be split by trace text on the tracing configuration; trace_aggregate keeps
# the non-trace characters in order, so joining lines and squeezing recovers the program's text
text = clean if clean else console
def find_marker(text, mark):
    m = re.search(re.escape(mark) + r'[^\n]*', text)
    return m.group(0) if m else None
line = find_marker(text, mark) if mark else None
if mark and line is None: bad(f'expected marker {mark} absent from the recovered console')
if re.search(r'M2B-[A-Z]+-FAIL', text): bad('a failure marker is present')
def hexes(s):
    return [int(x, 16) for x in re.findall(r'0x([0-9a-fA-F]+)', s)]
vals = hexes(line) if line else []
# ---- HARTS line: per-hart totals from the harness (not from the program) --------------------------------
hm = re.search(r'HARTS n=(\d+) retired0=(\d+) traps0=(\d+) cause0=0x([0-9a-f]+) maxawait0=(\d+) awaits0=(\d+) epoch0=(\d+) retired1=(\d+) traps1=(\d+) cause1=0x([0-9a-f]+) maxawait1=(\d+) awaits1=(\d+) epoch1=(\d+)', console)
H = None
if not hm: bad('no HARTS line from the host (per-hart totals missing)')
else:
    g = hm.groups(); H = dict(n=int(g[0]), retired=[int(g[1]), int(g[7])], traps=[int(g[2]), int(g[8])], cause=[int(g[3], 16), int(g[9], 16)],
                              maxawait=[int(g[4]), int(g[10])], awaits=[int(g[5]), int(g[11])], epoch=[int(g[6]), int(g[12])])
    if H['n'] != 2: bad(f'HARTS n={H["n"]}, this is a two-hart judgement')
    for h in range(2):
        if H['retired'][h] < a.min_retired: bad(f'hart {h} retired {H["retired"][h]} < required {a.min_retired}')
    if H['epoch'][0] != H['epoch'][1]: bad(f'epochs differ at the end: {H["epoch"]} (the aligned drain must keep them equal)')
# ---- the trace -----------------------------------------------------------------------------------------
EV = re.compile(r'^(EV|EVA|RD2|RD2H|RD2HOST|EVH)\s+(\d+)\s+([A-Z_]+)\s*(.*)$')
ev = []
for ln in events:
    m = EV.match(ln)
    if not m: continue
    kv = dict(re.findall(r'(\w+)=\s*(0x[0-9a-fA-F]+|-?\d+|\S+)', m.group(4)))
    ev.append((m.group(1), int(m.group(2)), m.group(3), kv, ln))
def num(x): return int(x, 16) if str(x).startswith('0x') else int(x)
def wval(kv):
    """the value a store carries, un-shifted: the bus word is lane-aligned (wmask marks the lanes)"""
    mask = num(kv.get('wmask', '0xff')); data = num(kv.get('wdata', '0'))
    if mask == 0: return 0
    lo = (mask & -mask).bit_length() - 1; nb = bin(mask).count('1')
    return (data >> (8 * lo)) & ((1 << (8 * nb)) - 1)
def sel(kind, tag, hart=None, **cond):
    out = []
    for k, c, t, kv, ln in ev:
        if k != kind or t != tag: continue
        if hart is not None and int(kv.get('hart', '0')) != hart: continue
        ok = True
        for ck, cv in cond.items():
            if ck == 'wdata':
                if wval(kv) != cv: ok = False; break
            elif ck not in kv or num(kv[ck]) != cv: ok = False; break
        if ok: out.append((c, kv, ln))
    return out
ENTRY = 0x80000000
MSIP = 0x02000000
if not a.fast:
    if not ev: bad('no trace events in a tracing run')
    # both harts entered the program through the ROM: a COMMIT at the entry on each hart
    ent = [sel('EV', 'COMMIT', h, pc=ENTRY) for h in range(2)]
    for h in range(2):
        if not ent[h]: bad(f'hart {h} never committed the entry instruction at 0x{ENTRY:x}')
    # ROM protocol (CONTRACT C8.1): hart 0 probes msip[1] (write 1, read back 1), probes msip[2] (write 1, read back
    # 0 -> stops: the probe stops at NUM_CORES; no write to msip[3]), clears msip[0]; hart 1 enters after that
    if ent[0] and ent[1]:
        w1 = sel('EV', 'REQ', 0, write=1, addr=MSIP + 4, wdata=1); w2 = sel('EV', 'REQ', 0, write=1, addr=MSIP + 8, wdata=1)
        w3 = sel('EV', 'REQ', 0, write=1, addr=MSIP + 12); clr = sel('EV', 'REQ', 0, write=1, addr=MSIP, wdata=0)
        r2 = [c for c, kv, ln in sel('EV', 'REQ', 0, write=0, addr=MSIP + 8)]
        if not w1: bad('ROM: hart 0 never wrote msip[1]=1 (did not wake hart 1)')
        if not w2: bad('ROM: hart 0 never probed msip[2] (the probe did not run to the end of the harts)')
        if w3: bad('ROM: hart 0 wrote msip[3]: the probe did not stop at NUM_CORES=2 (msip[2] must read back 0)')
        if not r2: bad('ROM: no read-back of msip[2]')
        else:
            # the RESP that answers the msip[2] read-back: the next RESP on hart 0 after that REQ
            c0 = r2[0]; resp = [(c, kv) for c, kv, ln in sel('EV', 'RESP', 0) if c > c0]
            if not resp: bad('ROM: the msip[2] read-back got no response')
            else:
                c, kv = resp[0]
                if num(kv['rdata']) != 0 or num(kv['error']) != 0: bad(f'ROM: msip[2] read back rdata={kv["rdata"]} error={kv["error"]} (U1: an unmapped msip must read 0 without a fault)')
        if not clr: bad('ROM: hart 0 never cleared msip[0]')
        elif ent[1][0][0] < clr[0][0]: bad(f'hart 1 entered at {ent[1][0][0]} before hart 0 cleared msip[0] at {clr[0][0]}')
        if ent[1][0][0] < ent[0][0][0]: bad('hart 1 entered before hart 0 (the ROM protocol makes hart 0 first)')
    # every hart retired: COMMIT counts per hart against the HARTS totals (same source of truth twice)
    if H:
        for h in range(2):
            n = len(sel('EV', 'COMMIT', h))
            if n != H['retired'][h]: bad(f'hart {h}: {n} COMMIT events in the trace, HARTS says {H["retired"][h]}')
    if sel('RD2', 'EPOCH_SKEW'): bad('EPOCH_SKEW: the harts\' epochs diverged')
    t_entry = [ent[h][0][0] if ent[h] else 0 for h in range(2)]   # the program phase of each hart starts here
def after_entry(items, h):
    return [x for x in items if x[0] > t_entry[h]] if not a.fast else items
# ---- per-program rules -------------------------------------------------------------------------------------
def want_len(n, what):
    if len(vals) < n: bad(f'{what}: the marker line carries {len(vals)} values, need {n}: {line!r}')
if base == 'dual01_boot' and line:
    want_len(1, 'dual01')
    if a.elf and vals:
        try:
            nm = subprocess.run(['riscv64-unknown-elf-nm', a.elf], capture_output=True, text=True).stdout
            sb = int(re.search(r'([0-9a-f]+) . _stack_base', nm).group(1), 16)
            if not (sb + 0x1000 <= vals[0] <= sb + 0x2000): bad(f'hart 1 sp 0x{vals[0]:x} is not inside its stack [0x{sb+0x1000:x}, 0x{sb+0x2000:x}]')
        except Exception as e: bad(f'could not read _stack_base from {a.elf}: {e}')
if base == 'dual02_clint' and line:
    want_len(3, 'dual02')
    if len(vals) >= 3:
        if vals[0] < 5 or vals[1] < 5: bad(f'timer traps per hart {vals[0]}/{vals[1]} < 5')
        if vals[2] == 0: bad('hart 1 made no progress while waiting for the IPI')
    if not a.fast:
        for h in range(2):
            n = len(after_entry(sel('EV', 'TRAP', h, interrupt=1, cause=0x8000000000000007), h))
            if n < 5: bad(f'hart {h}: only {n} timer-interrupt traps in the program phase (need >= 5)')
        s1 = len(after_entry(sel('EV', 'TRAP', 1, interrupt=1, cause=0x8000000000000003), 1)); s0 = len(after_entry(sel('EV', 'TRAP', 0, interrupt=1, cause=0x8000000000000003), 0))
        if s1 != 1: bad(f'hart 1 took {s1} software-interrupt traps in the program phase, expected exactly 1 (the IPI; the ROM wake is before entry)')
        if s0 != 0: bad(f'hart 0 took {s0} software-interrupt traps in the program phase (expected 0: the IPI was for hart 1)')
        ipi = sel('EV', 'REQ', 0, write=1, addr=MSIP + 4, wdata=1)
        lvl = [c for c, kv, ln in sel('EV', 'IRQLEVEL', 1, msip=1)]
        prog_ipi = [c for c, kv, ln in ipi if ent[0] and c > ent[0][0][0]] if not a.fast else []
        if not prog_ipi: bad('hart 0 never wrote msip[1]=1 after entering the program (no IPI sent)')
        elif not [c for c in lvl if c >= prog_ipi[0]]: bad('msip level on hart 1 never rose after the IPI write')
        if H and H['traps'][1] < 7: bad(f'HARTS traps1={H["traps"][1]} < 7 (ROM wake + 5 timer + 1 software)')
if base == 'dual03_lock' and line:
    want_len(5, 'dual03')
    if len(vals) >= 3:
        for i, nm_ in enumerate(['lock-protected counter', 'LR/SC counter', 'amoadd counter']):
            if vals[i] != 20000: bad(f'{nm_} = {vals[i]}, expected 20000')
    if not a.fast and a.atomic_floor:
        for h in range(2):
            sc = len(re.findall(r'SC_OK hart=\s*%d\b' % h, console)); am = len(re.findall(r'AMO_START hart=\s*%d\b' % h, console))
            if sc < a.atomic_floor: bad(f'hart {h}: backend trace shows {sc} successful SCs (< {a.atomic_floor})')
            if am < a.atomic_floor: bad(f'hart {h}: backend trace shows {am} AMOs (< {a.atomic_floor})')
    if not a.fast:
        for h in range(2):
            ex = after_entry(sel('EV', 'TRAP', h, interrupt=0), h)
            want = 7 if h == 0 else 5
            if len(ex) != 1 or num(ex[0][1]['cause']) != want: bad(f'hart {h}: expected exactly one access fault (cause {want}), trace has {[(c, kv.get("cause")) for c, kv, ln in ex]}')
            elif num(ex[0][1]['tval']) != (0x50000008 if h == 0 else 0x50000000): bad(f'hart {h}: fault tval {ex[0][1]["tval"]} is not the faulting address')
if base == 'dual04_pbus' and line:
    want_len(4, 'dual04')
    if not a.fast:
        for h in range(2):
            ex = after_entry(sel('EV', 'TRAP', h), h)
            if ex: bad(f'hart {h}: {len(ex)} trap(s) during peripheral-bus traffic: {ex[0][2][:100]}')
        print(f'INFO dual04: xv6 S-context addresses read back after writing 2/0: enable(hart0 @0xc002080)=0x{vals[0]:x} enable(hart1 @0xc002180)=0x{vals[1]:x} threshold(hart0 @0xc201000)=0x{vals[2]:x} threshold(hart1 @0xc203000)=0x{vals[3]:x}' if len(vals) >= 4 else 'INFO dual04: marker values incomplete')
if base == 'dual05_fencei' and line:
    want_len(2, 'dual05')
    if len(vals) >= 2 and vals[1] != 2: bad(f'after fence.i hart 1 executed code returning {vals[1]}, expected 2 (the new code)')
    if not a.fast and a.elf:
        try:
            nm = subprocess.run(['riscv64-unknown-elf-nm', a.elf], capture_output=True, text=True).stdout
            X = int(re.search(r'([0-9a-f]+) . X$', nm, re.M).group(1), 16)
            wr = sel('EV', 'REQ', 0, write=1, addr=X)
            if not wr: bad('hart 0 never wrote the new instruction word at X')
            else:
                tw = wr[0][0]
                fetch1 = [c for c, kv, ln in sel('EV', 'REQ', 1, fetch=1) if X <= num(kv['addr']) < X + 64]
                calls_before = [c for c, kv, ln in sel('EV', 'COMMIT', 1, pc=X) if c < tw]
                fetch_before = [c for c in fetch1 if c < tw]
                if len(calls_before) < 4: bad(f'hart 1 executed X only {len(calls_before)} times before the write (4 warm calls expected)')
                if len(fetch_before) == 0: bad('hart 1 never fetched X from memory before the write')
                if len(fetch_before) >= len(calls_before): bad(f'no I-cache warm-up evidence: {len(fetch_before)} fetches of the X line for {len(calls_before)} executions before the write')
                new_exec = [c for c, kv, ln in sel('EV', 'COMMIT', 1, pc=X, insn=0x00200513) if c > tw]
                if not new_exec: bad('hart 1 never committed the NEW instruction at X (insn 0x00200513) after the write')
                fence_i = [c for c, kv, ln in sel('EV', 'COMMIT', 1, insn=0x0000100f) if c > tw]
                if not fence_i: bad('hart 1 never committed fence.i after the write')
                else:
                    refetch = [c for c in fetch1 if c > fence_i[0]]
                    if not refetch: bad('after fence.i hart 1 did not fetch X from memory again (the I-cache was not invalidated)')
                old_after = [c for c, kv, ln in sel('EV', 'COMMIT', 1, pc=X, insn=0x00100513) if c > tw]
                print(f'INFO dual05: without fence.i hart 1 executed the {"OLD" if old_after else "NEW"} code at X (observed on this implementation, not an ISA claim); new code committed after fence.i: {bool(new_exec)}')
        except Exception as e: bad(f'dual05 trace rules: {e}')
if base == 'dual07_long':
    if H:
        print(f'INFO dual07: retired {H["retired"]}, maxAWait {H["maxawait"]}, aWaits {H["awaits"]}')
    if line:
        want_len(4, 'dual07')
        # the merged completion state: hart 0 may only report once BOTH iteration counters (written by each hart
        # when it finishes, published through the barrier) read ITER -- an early report shows hart 1's as 0
        if len(vals) >= 2:
            for h in range(2):
                if vals[h] != 100000: bad(f'dual07: hart {h} iteration count in the report is {vals[h]}, expected 100000 (hart 0 reported before hart 1 finished, or hart 1 did not run the stream)')
if a.drain:
    # ---- every required event is checked for existence AND count unconditionally; nothing is skipped ----------
    inj = sel('RD2H', 'INJECT')
    if len(inj) != 1: bad(f'drain: {len(inj)} INJECT events from the harness, expected exactly one')
    t_inj = inj[0][0] if inj else 0
    aft = lambda xs: [x for x in xs if x[0] >= t_inj]
    ha = [aft(sel('RD2', 'HOLD_ASSERT', h)) for h in range(2)]; dd = [aft(sel('RD2', 'DRAIN_DONE', h)) for h in range(2)]
    hr = [aft(sel('RD2', 'HOLD_RELEASE', h)) for h in range(2)]; ra = aft(sel('RD2', 'RESET_APPLY')); rs = aft(sel('RD2', 'CPU_RESTART_SAFE'))
    for h in range(2):
        if len(ha[h]) != 1: bad(f'drain: hart {h} has {len(ha[h])} HOLD_ASSERT after the injection, expected exactly one')
        if len(dd[h]) != 1: bad(f'drain: hart {h} has {len(dd[h])} DRAIN_DONE after the injection, expected exactly one')
        if len(hr[h]) != 1: bad(f'drain: hart {h} has {len(hr[h])} HOLD_RELEASE after the injection, expected exactly one')
    if len(ra) != 1: bad(f'drain: {len(ra)} RESET_APPLY events after the injection, expected exactly one (the aligned apply)')
    if len(rs) != 1: bad(f'drain: {len(rs)} CPU_RESTART_SAFE events after the injection, expected exactly one')
    t_ha = [x[0][0] if x else None for x in ha]; t_dd = [x[0][0] if x else None for x in dd]; t_hr = [x[0][0] if x else None for x in hr]
    t_ra = ra[0][0] if ra else None; t_rs = rs[0][0] if rs else None
    if None not in t_ha and t_ha[0] != t_ha[1]: bad(f'drain: the harts were held at different cycles {t_ha}')
    for h in range(2):
        if t_ha[h] is not None and t_dd[h] is not None and t_dd[h] < t_ha[h]: bad(f'drain: hart {h} DRAIN_DONE at {t_dd[h]} before its HOLD_ASSERT at {t_ha[h]}')
        if t_ra is not None and t_dd[h] is not None and t_dd[h] > t_ra: bad(f'drain: RESET_APPLY at {t_ra} before hart {h} finished draining at {t_dd[h]} (C7.1: no apply before every bridge drained)')
        if t_rs is not None and t_dd[h] is not None and t_rs <= t_dd[h]: bad(f'drain: CPU_RESTART_SAFE at {t_rs} not after hart {h} DRAIN_DONE at {t_dd[h]}')
        if t_ra is not None and t_hr[h] is not None and t_hr[h] <= t_ra: bad(f'drain: hart {h} released at {t_hr[h]} not after the aligned apply at {t_ra}')
        if t_rs is not None and t_hr[h] is not None and t_hr[h] <= t_rs: bad(f'drain: hart {h} released at {t_hr[h]} not after CPU_RESTART_SAFE at {t_rs} (the host releases on SAFE)')
    if t_ra is not None and t_rs is not None and t_rs <= t_ra: bad(f'drain: CPU_RESTART_SAFE at {t_rs} not after RESET_APPLY at {t_ra}')
    if None not in t_hr and abs(t_hr[0] - t_hr[1]) > a.apply_cycles: bad(f'drain: releases {abs(t_hr[0]-t_hr[1])} cycles apart (> applyCycles {a.apply_cycles}): {t_hr}')
    if not sel('RD2HOST', 'RELOAD_AFTER_INJECT'): bad('drain: the host never reloaded after the injected reset')
    if H and (H['epoch'][0] != 2 or H['epoch'][1] != 2): bad(f'drain: final epochs {H["epoch"]}, expected [2, 2] (the host\'s load-time reset, then the injected one)')
    # ---- requests by (hart, epoch, seq); responses bound to them ------------------------------------------------
    reqs = {}   # (h, epoch, seq) -> dict
    for h in range(2):
        for c, kv, ln in sel('EV', 'REQ', h):
            reqs[(h, num(kv['epoch']), num(kv['seq']))] = dict(c=c, addr=num(kv['addr']), write=num(kv['write']), fetch=num(kv['fetch']), wdata=num(kv['wdata']), wmask=num(kv['wmask']), resp=None, h=h)
        for c, kv, ln in sel('EV', 'RESP', h):
            k = (h, num(kv['epoch']), num(kv['seq']))
            if k in reqs:
                if reqs[k]['resp'] is not None: bad(f'drain: hart {h} request {k} answered twice')
                reqs[k]['resp'] = c
            else: bad(f'drain: hart {h} RESP {k} matches no request of that epoch (a stale or invented response)')
    # after the release: no response may belong to a request from before the hold (nothing stale is delivered)
    for h in range(2):
        if t_hr[h] is None or t_ha[h] is None: continue
        for k, r in reqs.items():
            if r['h'] == h and r['resp'] is not None and r['resp'] > t_hr[h] and r['c'] < t_ha[h]:
                bad(f'drain: hart {h}: request {k} issued at {r["c"]} before the hold was answered at {r["resp"]} after the release (stale response delivered)')
    # AMO requests (the bus carries the computed value, not wdata): from the backend's own trace, same hart/cycle
    amo_at = set()
    for m in re.finditer(r'AT\s+(\d+)\s+CPU_REQ hart=\s*(\d+) txid=\s*\d+ addr=0x([0-9a-f]+) write=1 size=\d amo=\s*([1-9])', console):
        amo_at.add((int(m.group(2)), int(m.group(1))))
    # ---- the AXI side: AW (addr) + W (strb, data) + B (resp), paired in order per id -------------------------------
    aw = [(c, num(kv['id']), num(kv['addr']), num(kv['len'])) for c, kv, ln in sel('EVA', 'AW')]
    wb = [(c, num(kv['strb']), num(kv['data'])) for c, kv, ln in sel('EVA', 'W') if num(kv['last']) == 1]
    bs = [(c, num(kv['id']), num(kv['resp'])) for c, kv, ln in sel('EVA', 'B')]
    if not aw: bad('drain: no AXI write-address events (EVA AW) in the trace: the per-write binding cannot be done')
    if len(aw) != len(wb): bad(f'drain: {len(aw)} AW but {len(wb)} last W beats')
    if len(aw) != len(bs): bad(f'drain: {len(aw)} AW but {len(bs)} B responses (a write without a completion)')
    # B responses per id, in order
    from collections import defaultdict, deque
    bq = defaultdict(deque)
    for c, i, r in bs: bq[i].append((c, r))
    axi = []
    for n_, (c, i, addr, ln_) in enumerate(aw):
        _, strb, data = wb[n_] if n_ < len(wb) else (None, None, None)
        bc, br = bq[i].popleft() if bq[i] else (None, None)
        if ln_ != 0: bad(f'drain: AXI write burst len={ln_} at {c} (single beats expected on this path)')
        if br is None: bad(f'drain: AXI write at {c} (addr 0x{addr:x}) has no B response')
        elif br != 0: bad(f'drain: AXI write at {c} (addr 0x{addr:x}) completed with resp={br}')
        axi.append(dict(c=c, addr=addr, strb=strb, data=data, bc=bc, used=None))
    # ---- every CPU DRAM write must reach memory EXACTLY once: address, lanes and (for plain stores) data --------------
    def lanes_of(mask): return sum(0xff << (8 * b) for b in range(8) if (mask >> b) & 1)
    cpu_writes = sorted([(k, r) for k, r in reqs.items() if r['write'] == 1 and r['fetch'] == 0 and (r['addr'] >> 28) == 8], key=lambda kr: kr[1]['c'])
    nmatched = 0
    for k, r in cpu_writes:
        is_amo = (r['h'], r['c']) in amo_at
        word = r['addr'] & ~7; m = lanes_of(r['wmask'])
        # the window in which this write's memory effect must have completed: before its response, or -- for the
        # one in flight at the hold, which gets no response -- before that hart's DRAIN_DONE
        h = r['h']
        ub = r['resp'] if r['resp'] is not None else (t_dd[h] if (t_ha[h] is not None and t_dd[h] is not None and r['c'] <= t_ha[h]) else None)
        hit = None
        for x in axi:
            if x['used'] is None and x['c'] > r['c'] and x['addr'] == word and x['strb'] == r['wmask'] and (is_amo or (x['data'] & m) == (r['wdata'] & m)) \
               and (ub is None or (x['bc'] is not None and x['bc'] <= ub)):
                hit = x; break
        if hit is None:
            why = (f'before its response at {r["resp"]}' if r['resp'] is not None else (f'before hart {h} DRAIN_DONE at {ub} (in flight at the hold)' if ub is not None else 'at all'))
            bad(f'drain: hart {k[0]} write {k} (addr 0x{r["addr"]:x} mask 0x{r["wmask"]:x} data 0x{r["wdata"]:016x}{" AMO" if is_amo else ""}) never reached AXI with that address/lanes/data {why}'); continue
        hit['used'] = k; nmatched += 1
        if r['resp'] is not None and hit['bc'] is not None and r['resp'] < hit['bc']: bad(f'drain: hart {k[0]} write {k} was answered at {r["resp"]} before its AXI completion at {hit["bc"]}')
    # nothing in the CPU-only region reached memory without a request (no duplicate, no invented write)
    lo, hi = a.cpu_region
    spurious = [x for x in axi if x['used'] is None and lo <= x['addr'] < hi]
    if spurious: bad(f'drain: {len(spurious)} AXI write(s) in the CPU region [0x{lo:x},0x{hi:x}) match no CPU request (first at cycle {spurious[0]["c"]} addr 0x{spurious[0]["addr"]:x}): a duplicate or invented write')
    print(f'INFO drain: {len(cpu_writes)} CPU DRAM writes, {nmatched} bound to exactly one AXI write each; {len(axi)} AXI writes total (host load included)')
    # ---- the writes in flight at the hold: DRAM writes, completed once at memory before DRAIN_DONE, never answered ---
    inflight = {}
    for h in range(2):
        if t_ha[h] is None: continue
        kv = ha[h][0][1]
        if num(kv['pendingA']) == 0 and num(kv['outstanding']) == 0: bad(f'drain: hart {h} had nothing in flight at the hold (the scenario needs both in flight)'); continue
        cand = [(k, r) for k, r in reqs.items() if r['h'] == h and r['c'] <= t_ha[h] and (r['resp'] is None or r['resp'] > t_ha[h])]
        if len(cand) != 1: bad(f'drain: hart {h}: {len(cand)} request(s) in flight at the hold, expected exactly one (single outstanding)'); continue
        k, r = cand[0]; inflight[h] = (k, r)
        if not (r['write'] == 1 and (r['addr'] >> 28) == 8): bad(f'drain: hart {h}: the transaction in flight at the hold is not a DRAM write (addr 0x{r["addr"]:x} write={r["write"]} fetch={r["fetch"]}): the aimed scenario was not reached'); continue
        if r['resp'] is not None: bad(f'drain: hart {h}: the in-flight write {k} was answered at {r["resp"]} instead of being discarded by the drain')
        hit = next((x for x in axi if x['used'] == k), None)
        if hit is None: bad(f'drain: hart {h}: the in-flight write {k} never reached memory (a committed write was lost by the reset)')
        elif t_dd[h] is not None and hit['bc'] is not None and hit['bc'] > t_dd[h]: bad(f'drain: hart {h}: DRAIN_DONE at {t_dd[h]} before the in-flight write completed at AXI ({hit["bc"]}): the drain did not wait')
        nd = num(hr[h][0][1]['nDrained']) if hr[h] else 0
        if nd < 1: bad(f'drain: hart {h}: HOLD_RELEASE reports nDrained={nd}, but one transaction was in flight at the hold')
    # ---- the program's own read-back after the reload: the survived prefix per hart equals the writes issued before the hold
    if base == 'dual06_drain' and line:
        want_len(3, 'dual06')
        if len(vals) >= 3:
            if vals[0] != 1: bad(f'dual06: the reporting run is epoch {vals[0]} of the program, expected 1 (the run after the reload)')
            for h in range(2):
                if t_ha[h] is None: continue
                base_h = a.scratch + h * a.scratch_stride
                issued = [k for k, r in reqs.items() if r['h'] == h and r['write'] == 1 and r['c'] <= t_ha[h] and base_h <= r['addr'] < base_h + a.scratch_stride and (r['h'], r['c']) not in amo_at]
                if vals[1 + h] != len(issued): bad(f'dual06: hart {h} read back {vals[1+h]} surviving pattern words after the reload, but issued {len(issued)} scratch writes before the hold (incl. the one in flight): {"a write was lost" if vals[1+h] < len(issued) else "more words than written"}')
                else: print(f'INFO dual06: hart {h}: {len(issued)} scratch writes issued before the hold (last one in flight: {inflight.get(h, ("?",))[0]}), {vals[1+h]} read back intact after the reload')
print(('PASS' if not fails else 'FAIL') + f' {a.prog} exit={exit_code} marker={line!r} harts={H}')
for f in fails: print('  FAIL:', f)
sys.exit(1 if fails else 0)
