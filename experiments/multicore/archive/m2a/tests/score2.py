#!/usr/bin/env python3
"""MC-M2a oracle: replay the backend event log in the order the backend accepted things, with N harts.

Binding (codex-mc-m2a-dual-backend, implementation step 1): a request is identified by (hart, local txid);
the hart of a TileLink source is looked up in the CPU_SOURCE table the backend announces, never taken from
the DUT's own `cpu=`/`hart=` classification (those are CHECKED against the table). Every expected effect --
the TileLink mapping, the AMO's new word and returned old value, the SC decision, the reservation kills, the
memory image, the D routing -- is derived from the frozen request plus the accepted ORDER, then compared to
what the DUT did, and finally the manager's actual write sequence must equal the model's.

Per-hart rules: one outstanding request; the D and the CPU_RESP of a transaction go to the hart that issued
it; its own reservation (LR sets it; own write / trap / LR error / SC of any outcome clears it; another
hart's write, a successful SC of another hart, or an external write overlapping it clears it; a FAILED SC
writes nothing and clears only its own). Global rules: the backend accepts one transaction at a time; nothing
is accepted between an AMO's Get and its Put; every external A that appears (EXT_A) must have been accepted
by the backend (A_ACC) before its D; the run must end with nothing open on any hart.

  score2.py <run.log> [--harts N] [--min-* N] [--expect-refuse N] [--expect-wrefuse N] [--drain] [--dmax N]
            [--min-tx N] [--error-mask M] [--werr-mask M] [--summary-json FILE]
Exit 0 = clean. Every failure names the cycle and the rule.
"""
import re, sys, argparse, json
ap = argparse.ArgumentParser(); ap.add_argument('log')
ap.add_argument('--harts', type=int, default=2)
for k in ['min-kills', 'min-scfail', 'min-scok', 'min-amo', 'min-ext', 'expect-refuse', 'expect-wrefuse', 'min-illegal', 'min-tx', 'min-scok0', 'min-scok1', 'min-scfail0', 'min-scfail1', 'min-drained']:
    ap.add_argument('--' + k, type=int, default=0)
for k in ['expect-kills', 'expect-scok', 'expect-scfail']:
    ap.add_argument('--' + k, type=int, default=-1, help='exact count required (-1 = not checked)')
ap.add_argument('--drain', action='store_true')
ap.add_argument('--dmax', type=int, default=0, help='declared maximum downstream latency; the wait report is relative to it')
ap.add_argument('--error-mask', type=lambda x: int(x, 0), default=0x800)
ap.add_argument('--werr-mask', type=lambda x: int(x, 0), default=0x400)
ap.add_argument('--rom', type=lambda x: int(x, 0), default=0x10000); ap.add_argument('--rom-size', type=lambda x: int(x, 0), default=0x10000)
ap.add_argument('--dram', type=lambda x: int(x, 0), default=0x80000000); ap.add_argument('--dram-size', type=lambda x: int(x, 0), default=0x10000000)
ap.add_argument('--summary-json')
a = ap.parse_args()
N = a.harts
ev = []
for ln in open(a.log, errors='replace').read().splitlines():
    m = re.match(r'AT\s+(\d+)\s+(\S+)(.*)', ln)
    if not m: continue
    kv = dict(re.findall(r'(\w+)=\s*(0x[0-9a-fA-F]+|-?\d+|\S+)', m.group(3)))
    ev.append((int(m.group(1)), m.group(2), kv, ln))
def num(x): return int(x, 16) if x.startswith('0x') else int(x)
fails = []
def bad(msg): fails.append(msg)
mem = {}
def rd(w): return mem.get(w, 0)
def apply_write(addr, data, mask):
    w = addr & ~7; m = 0
    for b in range(8):
        if (mask >> b) & 1: m |= 0xff << (8 * b)
    mem[w] = (rd(w) & ~m) | (data & m)
def lanes(size, addr):
    return sum(1 << ((addr & 7) + i) for i in range(1 << size)) if size <= 3 else 0xff
def in_err(addr): return (addr & a.error_mask) == a.error_mask
def in_werr(addr): return (addr & a.werr_mask) == a.werr_mask
def in_rom(addr): return a.rom <= addr < a.rom + a.rom_size
def in_dram(addr): return a.dram <= addr < a.dram + a.dram_size
AMO_SWAP, AMO_ADD, AMO_XOR, AMO_AND, AMO_OR, AMO_MIN, AMO_MAX, AMO_MINU, AMO_MAXU = range(1, 10)
TL_ARITH, TL_LOGIC = 2, 3
AMO_MAP = {AMO_SWAP: (TL_LOGIC, 3), AMO_XOR: (TL_LOGIC, 0), AMO_OR: (TL_LOGIC, 1), AMO_AND: (TL_LOGIC, 2),
           AMO_ADD: (TL_ARITH, 4), AMO_MIN: (TL_ARITH, 0), AMO_MAX: (TL_ARITH, 1),
           AMO_MINU: (TL_ARITH, 2), AMO_MAXU: (TL_ARITH, 3)}
def amo_new(op, param, old, opd, size, addr):
    off = (addr & 7) * 8; w = 32 if size == 2 else 64; M = (1 << w) - 1
    o = (old >> off) & M; d = (opd >> off) & M
    def s(x): return x - (1 << w) if x >> (w - 1) else x
    if op == 2: r = {0: (o if s(o) < s(d) else d), 1: (o if s(o) > s(d) else d), 2: min(o, d), 3: max(o, d), 4: (o + d) & M}[param]
    else:       r = {0: o ^ d, 1: o | d, 2: o & d, 3: d}[param]
    return (old & ~(M << off)) | (r << off)

# ---- per-hart state ------------------------------------------------------------------------------------
src_tab = {}                      # hart -> (lo, hi)
def hart_of(src):
    for h, (lo, hi) in src_tab.items():
        if lo <= src < hi: return h
    return None
open_req = {h: None for h in range(N)}     # the request awaiting its CPU_RESP
resv = {h: None for h in range(N)}         # reserved word (addr & ~7) or None
cnt = dict(kill=0, scfail=0, scok=0, amo=0, ext=0, refuse=0, wrefuse=0, illegal=0, cpu_tx=0, drained=0, ext_a=0)
per = {h: dict(tx=0, scok=0, scfail=0, amo=0, illegal=0, maxwait=0, maxturn=0, resp=0) for h in range(N)}
pending = None        # the transaction the backend accepted and has not completed (any source)
amo_cur = None
mgr_writes = []; model_writes = []
hold = {h: False for h in range(N)}; hold_cycles = {h: [] for h in range(N)}
hold_start = {h: None for h in range(N)}; drained_tx = {h: set() for h in range(N)}; answered_in_hold = []
accepted_in_hold = {h: [] for h in range(N)}; applying_all_cyc = None; restart_safe_cyc = None
release_cycles = {h: set(c for c, t, k, l in ev if t == 'HOLD_RELEASE' and int(k.get('hart', '0')) == h) for h in range(N)}
ext_open = {}         # external source -> cycle of its EXT_A not yet seen accepted
accept_seq = []       # (cycle, src, hart) in the backend's acceptance order
def kill_overlapping(lo, hi, writer_hart, why):
    """a write [lo,hi) by writer_hart (None = external) clears every OTHER reservation it overlaps"""
    for h in range(N):
        w = resv[h]
        if w is None or h == writer_hart: continue
        if lo < w + 8 and hi > w: resv[h] = None; cnt['kill'] += 1
for cyc, tag, kv, ln in ev:
    if tag == 'CPU_SOURCE':
        h = int(kv['hart']); src_tab[h] = (num(kv['lo']), num(kv['hi']))
    elif tag == 'CPU_REQ':
        h = int(kv['hart'])
        if h not in open_req: bad(f'{cyc}: CPU_REQ from unknown hart {h}'); continue
        if open_req[h] is not None: bad(f'{cyc}: hart {h} CPU_REQ txid={kv["txid"]} while txid={open_req[h]["txid"]} has no response (single outstanding)')
        addr = num(kv['addr']); size = num(kv['size']); amo = num(kv['amo']); lrsc = num(kv['lrsc']); write = num(kv['write'])
        wdata = num(kv['data']); wmask = num(kv['mask']); legal = num(kv['legal']); cnt['cpu_tx'] += 1; per[h]['tx'] += 1
        atomic = amo != 0 or lrsc != 0
        allowed = lanes(size, addr)
        ok_align = (addr & ((1 << size) - 1)) == 0 if size <= 3 else True
        if amo != 0 or lrsc == 2: ok_mask = (wmask == allowed)
        elif write:              ok_mask = (wmask != 0) and (wmask & ~allowed) == 0
        else:                    ok_mask = True
        ok_kind = (lrsc != 3) and not (amo != 0 and lrsc != 0) and \
                  ((write and amo <= AMO_MAXU) if amo != 0 else (not write) if lrsc == 1 else write if lrsc == 2 else True)
        exp_legal = 1 if (ok_align and ok_mask and ok_kind) else 0
        if atomic and (size not in (2, 3) or not in_dram(addr)): exp_legal = 0
        if legal != exp_legal: bad(f'{cyc}: hart {h} bridge legality {legal} for txid={kv["txid"]} (addr 0x{addr:x} amo={amo} lrsc={lrsc} size={size} mask=0x{wmask:x} write={write}), the V2 contract says {exp_legal}')
        if not legal: cnt['illegal'] += 1; per[h]['illegal'] += 1
        kind = 'amo' if amo else 'lr' if lrsc == 1 else 'sc' if lrsc == 2 else 'st' if write else 'ld'
        if kind == 'amo':  m_op, m_param = AMO_MAP.get(amo, (None, None)); m_data, m_mask = wdata, allowed
        elif kind == 'sc': m_op, m_param, m_data, m_mask = 1, 0, wdata, wmask
        elif kind == 'st': m_op, m_param, m_data, m_mask = 1, 0, wdata, wmask
        else:              m_op, m_param, m_data, m_mask = 4, 0, None, allowed
        open_req[h] = dict(txid=kv['txid'], hart=h, legal=legal, kind=kind, amo=amo, wdata=wdata, wmask=wmask, addr=addr, size=size,
                           exp=None, seen_a=False, off=False, d_cyc=None, req_cyc=cyc, a_cyc=None,
                           m_op=m_op, m_param=m_param, m_data=m_data, m_mask=m_mask)
        if legal and not in_dram(addr):
            open_req[h]['off'] = True
            open_req[h]['exp'] = dict(data=None, err=0, scfail=0)     # unit harness: ROM / MMIO managers answer
    elif tag == 'EXT_A':
        cnt['ext_a'] += 1
        # the external master offered a beat; it must be accepted by the backend before its D (A_ACC / A_BEAT)
        nm = ln.split()[3]; ext_open[nm] = ext_open.get(nm, 0) + 1     # one count per offered beat
    elif tag == 'A_ACC':
        src = num(kv['src']); op = num(kv['op']); param = num(kv['param']); addr = num(kv['addr']); size = num(kv['size'])
        data = num(kv['data']); mask = num(kv['mask']); kind = num(kv['kind'])
        h = hart_of(src)
        dut_cpu = num(kv['cpu']); dut_hart = num(kv['hart'])
        if (h is not None) != (dut_cpu == 1): bad(f'{cyc}: the backend classified source {src} cpu={dut_cpu}, the announced table says hart={h}')
        if h is not None and dut_hart != h: bad(f'{cyc}: the backend attributed source {src} to hart {dut_hart}, the announced table says hart {h}')
        if pending is not None: bad(f'{cyc}: A accepted (src={src}) while src={pending["src"]} still has no D (serialisation broken)')
        if amo_cur is not None: bad(f'{cyc}: A accepted (src={src}) between an AMO\'s Get and its Put (atomic pair broken)')
        accept_seq.append((cyc, src, h))
        if h is not None and hold[h]:
            r0 = open_req[h]
            if r0 is None or r0['req_cyc'] >= hold_start[h]: bad(f'{cyc}: hart {h}: a request issued during the hold was accepted by the backend')
            else: accepted_in_hold[h].append((cyc, r0['txid']))
        w = addr & ~7
        isput = op in (0, 1); isamo = op in (2, 3); isget = op == 4
        req = None
        if h is not None:
            req = open_req[h]
            if req is None or not req['legal']: bad(f'{cyc}: hart {h} A arrived with no legal request open'); req = None
            elif req['seen_a']: bad(f'{cyc}: a second A for hart {h} txid={req["txid"]}'); req = None
            else:
                req['seen_a'] = True; req['a_cyc'] = cyc
                per[h]['maxwait'] = max(per[h]['maxwait'], cyc - req['req_cyc'])
                t = req['txid']; k = req['kind']
                if req['addr'] != addr: bad(f'{cyc}: hart {h} txid={t} A address 0x{addr:x}, the request said 0x{req["addr"]:x}')
                if req['size'] != size: bad(f'{cyc}: hart {h} txid={t} A size {size}, the request said {req["size"]}')
                if req['m_op'] != op: bad(f'{cyc}: hart {h} txid={t} is a {k}' + (f' (amo code {req["amo"]})' if k == 'amo' else '') + f' and must map to TL opcode {req["m_op"]}, the accepted A is opcode {op}')
                elif req['m_param'] != param: bad(f'{cyc}: hart {h} txid={t} is a {k}' + (f' (amo code {req["amo"]})' if k == 'amo' else '') + f' and must map to TL param {req["m_param"]}, the accepted A carries param {param}')
                if req['m_data'] is not None and req['m_data'] != data: bad(f'{cyc}: hart {h} txid={t} operand 0x{req["m_data"]:016x} was shipped as 0x{data:016x}')
                if req['m_mask'] != mask: bad(f'{cyc}: hart {h} txid={t} byte lanes 0x{req["m_mask"]:x} were shipped as 0x{mask:x}')
                want_kind = {'amo': 3, 'lr': 1, 'sc': 2, 'st': 0, 'ld': 0}[k]
                if kind != want_kind: bad(f'{cyc}: hart {h} txid={t} is a {k} but the backend classified kind={kind}')
                op, param, data, mask = req['m_op'], req['m_param'], (req['m_data'] or 0), req['m_mask']
                isput = op in (0, 1); isamo = op in (2, 3); isget = op == 4
                kind = want_kind
        else:
            cnt['ext'] += 1
            # match it to the oldest unaccepted EXT_A (any external name)
            live = [k2 for k2, v2 in ext_open.items() if v2 > 0]
            if not live: bad(f'{cyc}: the backend accepted an external A (src={src}) that no external master offered')
            else: ext_open[live[0]] -= 1
        lo_b, hi_b = addr, addr + (1 << size)
        exp = None
        if kind in (1, 2) and h is None:
            bad(f'{cyc}: the backend treated source {src} as an LR/SC hart but that source is bound to no hart'); kind = 4 if kind == 1 else 0
            isget = kind == 4; isput = kind == 0
        if kind == 1:                                   # LR by hart h
            resv[h] = w; exp = dict(data=rd(w), err=1 if in_err(addr) else 0, scfail=0)
        elif kind == 2:                                 # SC by hart h
            ok = (resv[h] == w); resv[h] = None
            if ok:
                cnt['scok'] += 1; per[h]['scok'] += 1
                if not in_err(addr) and not in_werr(addr): apply_write(addr, data, mask); model_writes.append((addr, mask, mem[w]))
                kill_overlapping(lo_b, hi_b, h, 'sc-write')          # a successful SC is a write
                exp = dict(data=0, err=1 if (in_err(addr) or in_werr(addr)) else 0, scfail=0)
            else:
                cnt['scfail'] += 1; per[h]['scfail'] += 1; exp = dict(data=0, err=0, scfail=1)
        elif isamo:
            cnt['amo'] += 1
            if h is not None: per[h]['amo'] += 1
            if h is not None and resv[h] is not None and lo_b < resv[h] + 8 and hi_b > resv[h]: resv[h] = None; cnt['kill'] += 1
            kill_overlapping(lo_b, hi_b, h, 'amo-write')
            amo_cur = dict(addr=addr, size=size, data=data, op=op, param=param, readerr=in_err(addr), werr=in_werr(addr), put_seen=False, cyc=cyc, hart=h)
            exp = dict(data=0 if in_err(addr) else rd(w), err=1 if (in_err(addr) or in_werr(addr)) else 0, scfail=0)
        elif isput:
            if h is not None and resv[h] is not None and lo_b < resv[h] + 8 and hi_b > resv[h]: resv[h] = None; cnt['kill'] += 1
            kill_overlapping(lo_b, hi_b, h, 'write')
            if not (in_err(addr) or in_werr(addr)): apply_write(addr, data, mask); model_writes.append((addr, mask, mem[w]))
            exp = dict(data=0, err=1 if (in_err(addr) or in_werr(addr)) else 0, scfail=0)
        elif isget:
            exp = dict(data=0 if in_err(addr) else rd(w), err=1 if in_err(addr) else 0, scfail=0)
        pending = dict(src=src, hart=h, kind=kind, exp=exp, addr=addr, put=isput, cyc=cyc)
        if req is not None: req['exp'] = exp
    elif tag == 'A_BEAT':
        if pending is None: bad(f'{cyc}: A_BEAT with nothing accepted'); continue
        pending['beat'] = pending.get('beat', 0) + 1
        if pending['hart'] is None:
            live = [k2 for k2, v2 in ext_open.items() if v2 > 0]
            if live: ext_open[live[0]] -= 1
        addr = num(kv['addr']) + 8 * pending['beat']; data = num(kv['data']); mask = num(kv['mask']); w = addr & ~7
        kill_overlapping(addr, addr + 8, pending['hart'], 'beat')
        if pending['hart'] is not None and resv[pending['hart']] == w: resv[pending['hart']] = None; cnt['kill'] += 1
        if not (in_err(addr) or in_werr(addr)): apply_write(addr, data, mask); model_writes.append((addr, mask, mem[w]))
    elif tag == 'MGR_D':
        if amo_cur is not None and num(kv['get']) == 1 and num(kv['err']) == 1: amo_cur['readerr_seen'] = True
    elif tag == 'AMO_PUT':
        if amo_cur is None: bad(f'{cyc}: AMO_PUT with no AMO in progress'); continue
        if amo_cur.get('readerr_seen') or amo_cur['readerr']: bad(f'{cyc}: AMO Put issued after its Get returned an error')
        if amo_cur['put_seen']: bad(f'{cyc}: a second Put for the same AMO (a retry)')
        amo_cur['put_seen'] = True
        data = num(kv['data']) & ((1 << 64) - 1); w = amo_cur['addr'] & ~7
        exp_new = amo_new(amo_cur['op'], amo_cur['param'], rd(w), amo_cur['data'], amo_cur['size'], amo_cur['addr'])
        if data != exp_new: bad(f'{cyc}: AMO wrote 0x{data:016x}, model says 0x{exp_new:016x} (old 0x{rd(w):016x})')
        if not amo_cur['werr']:
            mem[w] = exp_new; model_writes.append((amo_cur['addr'], lanes(amo_cur['size'], amo_cur['addr']), exp_new))
    elif tag == 'INTERLEAVE':
        bad(f'{cyc}: the backend admitted a write between an AMO\'s halves (src={kv["src"]})')
    elif tag == 'MGR_WRITE':
        mgr_writes.append((num(kv['addr']), num(kv['mask']), num(kv['new'])))
    elif tag == 'MGR_REFUSE':
        cnt['refuse'] += 1
        if in_werr(num(kv['addr'])) and not in_err(num(kv['addr'])): cnt['wrefuse'] += 1
    elif tag == 'D_OUT':
        src = num(kv['src'])
        if pending is None: bad(f'{cyc}: a D (src={src}) with nothing accepted'); continue
        if src != pending['src']: bad(f'{cyc}: D carries source {src} (hart {hart_of(src)}), the accepted transaction was source {pending["src"]} (hart {pending["hart"]}): misrouted response')
        err = num(kv['err']); data = num(kv['data']); scf = num(kv.get('scfail', '0')); e = pending['exp']
        if err != e['err']: bad(f'{cyc}: D error={err}, model says {e["err"]} (src {src}, kind {pending["kind"]})')
        elif not err and not pending['put'] and pending['kind'] in (0, 1, 3) and data != e['data']:
            if pending['kind'] != 0 or e['data'] != 0 or data != 0:
                bad(f'{cyc}: D data 0x{data:016x}, model says 0x{e["data"]:016x} (src {src}, kind {pending["kind"]})')
        if pending['kind'] == 2 and scf != e['scfail']: bad(f'{cyc}: SC result scfail={scf}, model says {e["scfail"]} (hart {pending["hart"]})')
        if pending['kind'] == 1 and err and pending['hart'] is not None:          # an LR that returned an error clears (kills) the reservation it set
            if resv[pending['hart']] is not None: cnt['kill'] += 1
            resv[pending['hart']] = None
        if pending['kind'] == 3: amo_cur = None
        h = pending['hart']
        if h is not None and open_req[h] is not None and open_req[h]['seen_a']:
            open_req[h]['d_cyc'] = cyc
            per[h]['maxturn'] = max(per[h]['maxturn'], cyc - open_req[h]['a_cyc'])
        pending = None
    elif tag == 'CPU_RESP':
        h = int(kv['hart']); r = open_req.get(h)
        if r is None: bad(f'{cyc}: hart {h} CPU_RESP txid={kv["txid"]} with no request open'); continue
        if hold[h]: bad(f'{cyc}: hart {h} CPU_RESP txid={kv["txid"]} delivered while the hart is held (must be discarded by the drain)')
        if kv['txid'] != r['txid']: bad(f'{cyc}: hart {h} CPU_RESP txid={kv["txid"]} but the open request is txid={r["txid"]}')
        data = num(kv['data']); err = num(kv['err']); scf = num(kv['scfail']); per[h]['resp'] += 1
        if not r['legal']:
            if err != 1: bad(f'{cyc}: hart {h} illegal request txid={kv["txid"]} answered without error')
            if r['seen_a']: bad(f'{cyc}: hart {h} illegal request produced a TileLink transaction')
        else:
            if r['off']:
                if r['seen_a']: bad(f'{cyc}: hart {h} txid={kv["txid"]} (outside DRAM) passed through the backend')
            elif not r['seen_a']: bad(f'{cyc}: hart {h} CPU_RESP txid={kv["txid"]} without a TileLink transaction for it')
            elif r['d_cyc'] is None: bad(f'{cyc}: hart {h} CPU_RESP txid={kv["txid"]} before its transaction completed (no D yet)')
            elif cyc < r['d_cyc']: bad(f'{cyc}: hart {h} CPU_RESP txid={kv["txid"]} at {cyc} precedes its D at {r["d_cyc"]}')
            if r['kind'] in ('st', 'sc') and data != 0: bad(f'{cyc}: hart {h} CPU_RESP txid={kv["txid"]} is a {r["kind"]} and must return no data, it returned 0x{data:016x}')
            e = r['exp'] or {}
            if e:
                if err != e['err']: bad(f'{cyc}: hart {h} CPU_RESP txid={kv["txid"]} error={err}, model says {e["err"]}')
                if r['kind'] in ('ld', 'lr', 'amo') and not err and e['data'] is not None:
                    exp_lanes = lanes(r['size'], r['addr']); m = 0
                    for b in range(8):
                        if (exp_lanes >> b) & 1: m |= 0xff << (8 * b)
                    if (data & m) != (e['data'] & m): bad(f'{cyc}: hart {h} CPU_RESP txid={kv["txid"]} data 0x{data:016x}, model says 0x{e["data"] & m:016x} on the request lanes')
                if r['kind'] == 'sc' and scf != e['scfail']: bad(f'{cyc}: hart {h} CPU_RESP txid={kv["txid"]} scFail={scf}, model says {e["scfail"]}')
                if r['kind'] != 'sc' and scf != 0: bad(f'{cyc}: hart {h} CPU_RESP txid={kv["txid"]} carries scFail on a non-SC')
        open_req[h] = None
    elif tag in ('DRAIN_DISCARD', 'LOCAL_DISCARD', 'BUFFERED_DISCARD'):
        h = int(kv['hart']); cnt['drained'] += 1; drained_tx[h].add(kv['txid'])
        if open_req[h] is not None and kv['txid'] == open_req[h]['txid']:
            if tag == 'DRAIN_DISCARD' and open_req[h]['seen_a'] and open_req[h]['d_cyc'] is None: bad(f'{cyc}: hart {h} {tag} txid={kv["txid"]} before its accepted transaction completed (an accepted write may not be dropped by the reset)')
            open_req[h] = None
        else: bad(f'{cyc}: hart {h} {tag} txid={kv["txid"]} does not match the open request')
    elif tag == 'HOLD_ASSERT': h = int(kv['hart']); hold[h] = True; hold_start[h] = cyc; hold_cycles[h].append(('assert', cyc))
    elif tag == 'HOLD_RELEASE': h = int(kv['hart']); hold[h] = False; hold_cycles[h].append(('release', cyc))
    elif tag == 'APPLYING_ALL': applying_all_cyc = cyc
    elif tag == 'RESTART_SAFE': restart_safe_cyc = cyc
    elif tag == 'DRAIN_DONE': h = int(kv['hart']); hold_cycles[h].append(('done', cyc))
    elif tag == 'CPU_TRAP':                     # the core's resvClear: clears (kills) its own valid reservation, nothing else
        h = int(kv['hart'])
        if resv[h] is not None: cnt['kill'] += 1
        resv[h] = None
    elif tag == 'VIOLATION': bad(f'{cyc}: {ln.strip()}')
    if tag == 'CPU_REQ':
        h = int(kv['hart'])
        if hold[h] and cyc not in release_cycles[h]: bad(f'{cyc}: hart {h} issued a request while held in reset')
# ---- end-of-run closure ----------------------------------------------------------------------------------
if pending is not None: bad(f'end: the transaction from source {pending["src"]} never received its D')
for h in range(N):
    if open_req[h] is not None: bad(f'end: hart {h} txid={open_req[h]["txid"]} never received its response (and was not drained)')
if amo_cur is not None: bad('end: an AMO never completed')
left = sum(v2 for v2 in ext_open.values())
if left: bad(f'end: {left} external A beat(s) were offered but never accepted by the backend')
for h in range(N):
    if h not in src_tab: bad(f'no CPU_SOURCE announcement for hart {h}')
if mgr_writes != model_writes:
    bad(f'memory writes differ from the model: manager {len(mgr_writes)} model {len(model_writes)}')
    for i in range(min(len(mgr_writes), len(model_writes))):
        if mgr_writes[i] != model_writes[i]: bad(f'  first difference at write {i}: manager {tuple(hex(x) for x in mgr_writes[i])} model {tuple(hex(x) for x in model_writes[i])}'); break
fin = [e for e in ev if e[1] == 'FINISHED']
if not fin: bad('no FINISHED event')
else:
    k = fin[0][2]
    for name, key in [('scFail', 'scfail'), ('scOk', 'scok'), ('amo', 'amo')]:
        if num(k[name]) != cnt[key]: bad(f'the backend counted {name}={k[name]}, the model {cnt[key]}')
    # exact: nKill is the number of VALID reservations cleared (one per hart per cycle whatever the reasons); the
    # model clears from its own state -- own/other-hart/external/two-beat writes, a successful SC of another hart,
    # the core's resvClear, an LR error -- and never counts an SC consuming its own reservation
    if num(k['kills']) != cnt['kill']: bad(f'the backend counted kills={k["kills"]}, the model counted {cnt["kill"]} cleared reservation(s)')
    if num(k['bridgeIllegal']) != cnt['illegal']: bad(f'the bridges counted illegal={k["bridgeIllegal"]}, the model {cnt["illegal"]}')
    for h in range(N):
        key = f'cpuResp{h}'
        if key in k and num(k[key]) != per[h]['resp']: bad(f'hart {h}: the driver counted {key}={k[key]}, the model saw {per[h]["resp"]} responses')
if a.drain:
    dones = {}; rels = {}
    for h in range(N):
        kinds = [x[0] for x in hold_cycles[h]]
        if not kinds: bad(f'hart {h}: no hold/drain events in a drain run'); continue
        if kinds[:3] != ['assert', 'done', 'release']: bad(f'hart {h}: drain sequence is {kinds}, expected assert, done, release'); continue
        ta = hold_cycles[h][0][1]; td = [c for k2, c in hold_cycles[h] if k2 == 'done'][0]; tr = [c for k2, c in hold_cycles[h] if k2 == 'release'][0]
        dones[h] = td; rels[h] = tr
        # anything the backend accepted for this hart during the hold was a pre-hold request (checked at A_ACC);
        # it must have been discarded by the drain, never answered, and the drain must have waited for its D
        for c, t in accepted_in_hold[h]:
            if t not in drained_tx[h]: bad(f'hart {h}: txid={t} (accepted at {c} during the hold) was not discarded by the drain')
        # the drain waited: no D for this hart after its DRAIN_DONE within the hold
        late = [c for c, tg, k2, l in ev if tg == 'D_OUT' and hart_of(num(k2['src'])) == h and td < c < tr]
        if late: bad(f'hart {h}: a D for this hart arrived at {late[0]} after its DRAIN_DONE at {td} (the drain did not wait)')
    if len(dones) == N:
        # C7.1: no hart leaves reset before EVERY bridge finished draining and the aligned apply was observed
        last_done = max(dones.values())
        for h in range(N):
            if rels[h] < last_done: bad(f'hart {h}: released at {rels[h]} before hart {max(dones, key=dones.get)} finished draining at {last_done} (C7.1 alignment)')
        if applying_all_cyc is None: bad('no APPLYING_ALL: the aligned apply was never observed')
        else:
            for h in range(N):
                if rels[h] <= applying_all_cyc: bad(f'hart {h}: released at {rels[h]} before/at APPLYING_ALL at {applying_all_cyc}')
        if restart_safe_cyc is None: bad('no RESTART_SAFE: applying_all && !pendingWork never held')
    if cnt['drained'] < max(1, a.min_drained): bad(f'drained/discarded transactions {cnt["drained"]} < required {max(1, a.min_drained)}')
for k2, v in [('kill', a.min_kills), ('scfail', a.min_scfail), ('scok', a.min_scok), ('amo', a.min_amo), ('ext', a.min_ext), ('illegal', a.min_illegal), ('cpu_tx', a.min_tx)]:
    if cnt[k2] < v: bad(f'{k2} {cnt[k2]} < required {v}')
for h, key in [(0, 'min_scok0'), (1, 'min_scok1')]:
    if h < N and per[h]['scok'] < getattr(a, key): bad(f'hart {h} scok {per[h]["scok"]} < required {getattr(a, key)}')
for h, key in [(0, 'min_scfail0'), (1, 'min_scfail1')]:
    if h < N and per[h]['scfail'] < getattr(a, key): bad(f'hart {h} scfail {per[h]["scfail"]} < required {getattr(a, key)}')
for k2, v in [('kill', a.expect_kills), ('scok', a.expect_scok), ('scfail', a.expect_scfail)]:
    if v >= 0 and cnt[k2] != v: bad(f'{k2} {cnt[k2]} != required exactly {v} (the intended interleaving did not happen)')
if cnt['refuse'] < a.expect_refuse: bad(f'manager refusals {cnt["refuse"]} < expected {a.expect_refuse}')
if cnt['wrefuse'] < a.expect_wrefuse: bad(f'write-only refusals {cnt["wrefuse"]} < expected {a.expect_wrefuse}')
completed = sum(per[h]['resp'] for h in range(N)) + cnt['ext']
perh = '; '.join('h%d:tx=%d scok=%d scfail=%d amo=%d' % (h, per[h]['tx'], per[h]['scok'], per[h]['scfail'], per[h]['amo']) for h in range(N))
waits = ' '.join(f'h{h}:wait<={per[h]["maxwait"]},turn<={per[h]["maxturn"]}' for h in range(N))
dm = f' dmax={a.dmax} maxwait/dmax={max(per[h]["maxwait"] for h in range(N)) / a.dmax:.1f}' if a.dmax else ''
print(f'SCORE2 harts={N} completed={completed} cpu_tx={cnt["cpu_tx"]} ext={cnt["ext"]} amo={cnt["amo"]} scok={cnt["scok"]} scfail={cnt["scfail"]} kills={cnt["kill"]} illegal={cnt["illegal"]} drained={cnt["drained"]} mgr_writes={len(mgr_writes)} refusals={cnt["refuse"]} per_hart=[{perh}] {waits}{dm} fails={len(fails)}')
for f in fails[:40]: print('  FAIL:', f)
if len(fails) > 40: print(f'  ... {len(fails) - 40} more')
if a.summary_json:
    json.dump(dict(harts=N, completed=completed, cnt=cnt, per=per, fails=fails[:40], nfails=len(fails), dmax=a.dmax), open(a.summary_json, 'w'), indent=1)
sys.exit(1 if fails else 0)
