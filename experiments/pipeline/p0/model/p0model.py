#!/usr/bin/env python3
"""PIPE-P0 control model: the pipeline's CONTROL skeleton, cycle by cycle, with no datapath.

What it models (CONTRACT.md §1-§5, rev. 2):
  front end  F1 (fetch-word VA, TLB lookup) -> F2 (I-cache lookup on the PA) -> FB (<= 2 words) -> ID,
             with an F2->ID bypass; words are 8 bytes = two 32-bit instructions (the length logic is in §8 of the
             contract, not here)
  back end   ID -> EX -> MEM -> WB, per-stage valid/ready/fire: ready(S) = !valid(S) || fire(S); WB always fires
  port       ONE holding register (owner, killed, valid_at, ready_at, fired, resp_at): a request, once valid, stays
             valid until its handshake and is answered cfg.T cycles later; at most one in flight
  engines    one page-table walker (fetch side F or data side M), one I-cache refill engine (2 beats),
             one uncached-fetch request
  control    sticky `killed` per transaction (default) or a 1-bit epoch (mutation EPOCH1); drain-based
             serialisation; interrupts attached at ID (or a synthesised token when ID has no input)

Invariants checked on every run (a violation is printed with its cycle):
  I1  the retirement stream equals the architectural one (golden sequential interpreter, DUT-directed for the
      interrupt boundary: the DUT's interrupt epc must equal the golden next pc)
  I2  the data-request stream (every data-side request that fired, in order) equals the loads/stores that retired or
      took their OWN bus-error fault, in retirement order -- nothing issued for a flushed instruction
  I3  no response is consumed by an owner it was not issued for (a live engine only accepts its own)
  I4  a data request is raised only when the MEM instruction is the oldest (WB empty or committing without flush)
  I5  progress: some retirement at least every cfg.stall_limit cycles (a deadlock is a violation)
  I6  an uncached fetch or a PTE read from a non-cacheable address is issued only when the front end is
      non-speculative (ID..WB and FB/F2 empty)
  I7  the SoC's awaitingRetire rule (RD2Soc.scala:371-372) is cleared only by the retirement of the data requester
  I8  each EX occupant redirects at most once; each WB occupant retires once
  I9  a serialising instruction leaves EX only with the port idle, no walker and no refill (drained)

  p0model.py                      run every scenario, correct design and every mutation; exit 1 on any surprise
  p0model.py --table <scenario>   print the cycle table of one scenario (correct design)
"""
import sys, argparse, copy

SERIAL = {'csr', 'mret', 'fencei', 'sfence'}
MEMK = {'load', 'store'}


class Cfg:
    def __init__(self, **kw):
        self.T = 2            # port: fire -> response cycles (bridge floor 2; simulator ~3; board ~18)
        self.RD = 0           # port: valid -> ready delay (back-pressure)
        self.entry = 0
        self.H = 60           # trap handler pc
        self.itlb_miss = set()    # fetch words that miss the TLB (a 3-level walk)
        self.pte_nc = set()       # fetch words whose walk's first PTE read is NOT cacheable RAM
        self.icache_miss = set()  # fetch words that miss the I-cache (2-beat refill)
        self.nc_words = set()     # fetch words in uncached space (single request, non-speculative only)
        self.levels = 3
        self.irq_at = None        # cycle at which the interrupt line rises (stays high until taken)
        self.max_cycles = 600
        self.stall_limit = 250
        for k, v in kw.items():
            setattr(self, k, v)


class Sim:
    def __init__(self, prog, cfg, mut=()):
        self.prog, self.cfg, self.mut = prog, cfg, set(mut)
        self.c = 0
        self.F1 = self.F2 = self.ID = self.EX = self.MEM = self.WB = None
        self.FB = []                        # [ {'data': word, 'slot': k} ]
        self.req = None
        self.walker = None
        self.refill = None
        self.fetch_w, self.fetch_slot = cfg.entry // 2, cfg.entry % 2
        self.fe_next_pc = cfg.entry         # the pc ID will receive next (architectural next pc when ID..WB empty)
        self.fe_epoch = 0
        self.fe_stopped = False             # front end parked behind an interrupt token
        self.itlb = set(); self.icache = set()
        self.irq = False; self.irq_inflight = False; self.in_handler = False
        self.epc = None; self.epc_ret = 0
        self.seq = 0
        self.events = []                    # ('C', pc) / ('T', epc, cause)
        self.data_reqs = []                 # pcs of data requests that fired
        self.viol = []
        self.rows = []
        self.halted = False
        self.ar = False; self.last_data_pc = None   # the SoC's awaitingRetire, replicated
        self.last_retire_c = 0
        self.redirects = {}                 # seq -> count
        self.frozen = False

    # ---------------------------------------------------------------- helpers
    def V(self, msg):
        self.viol.append(f"c{self.c}: {msg}")

    def mk_tok(self, pc):
        self.seq += 1
        d = dict(self.prog.get(pc, {'kind': 'alu'}))
        d.update(pc=pc, seq=self.seq)
        if d['kind'] in MEMK: d['mstate'] = 'xlate'
        if d['kind'] == 'mul': d['mleft'] = d.get('lat', 65)
        return d

    def backend_empty(self):
        return self.ID is None and self.EX is None and self.MEM is None and self.WB is None

    def nonspec_f2(self):        # F2's word is the oldest thing in the machine
        return self.backend_empty() and not self.FB

    def nonspec_f1(self):
        return self.nonspec_f2() and self.F2 is None

    def serial_in_flight(self):
        return any(t is not None and t['kind'] in SERIAL for t in (self.EX, self.MEM, self.WB))

    def alloc(self, owner, **kw):
        assert self.req is None
        r = dict(owner=owner, killed=False, ep=self.fe_epoch, valid_at=self.c + 1,
                 ready_at=self.c + 1 + self.cfg.RD, fired=False, resp_at=None)
        r.update(kw)
        self.req = r
        return r

    def kill_front(self):
        """A front-end flush: every fetch-side transaction and engine is killed or abandoned."""
        self.fe_epoch += 1
        if 'EPOCH1' in self.mut:
            return                           # the flawed alternative: nothing is marked; responses are told apart by parity
        if self.req and self.req['owner'] in ('F', 'NC', 'WF') and not self.req['killed']:
            self.req['killed'] = True
        if self.walker and self.walker['side'] == 'F':
            if self.walker['state'] == 'wait': self.walker['killed'] = True
            else: self.walker = None
        if self.refill:
            if self.refill['state'] == 'wait': self.refill['killed'] = True
            else: self.refill = None

    def flush_front(self, target):
        self.F1 = self.F2 = None; self.FB = []
        self.kill_front()
        self.fetch_w, self.fetch_slot = target // 2, target % 2
        self.fe_next_pc = target
        self.fe_stopped = False

    def flush_all(self, target):
        """WB trap / serialiser: everything younger than WB."""
        if self.req and self.req['owner'] in ('M', 'WM') and not self.req['fired'] and 'MEM_SPEC' not in self.mut:
            self.V("a data-side request was pending at a WB flush (I4 should have prevented it)")
        if self.walker and self.walker['side'] == 'M' and 'EPOCH1' not in self.mut:
            if self.walker['state'] == 'wait': self.walker['killed'] = True
            else: self.walker = None
        self.MEM = self.EX = self.ID = None
        self.flush_front(target)
        self.irq_inflight = False

    def fmt(self, t):
        if t is None: return '.'
        s = f"{t['pc']}{t['kind'][0].upper()}"
        if t.get('irq'): s += '!'
        if t.get('mstate') and t['kind'] in MEMK:
            s += ':' + {'xlate': 'tlb', 'needwalk': 'nw', 'walking': 'walk', 'issue': 'iss', 'wait': 'wait', 'done': 'done'}[t['mstate']]
        return s

    # ---------------------------------------------------------------- one cycle
    def step(self):
        cfg, mut, c = self.cfg, self.mut, self.c
        ev = []
        start = dict(F1=self.F1, F2=self.F2, ID=self.ID, EX=self.EX, MEM=self.MEM, WB=self.WB)
        snap = {k: (dict(v) if v is not None else None) for k, v in start.items()}   # the row shows start-of-cycle state
        fb_start = [dict(e) for e in self.FB]
        port_start = None
        if self.req:
            r = self.req
            port_start = f"{r['owner']}{'k' if r['killed'] else ''}{'F' if r['fired'] else 'v'}"
        if cfg.irq_at is not None and c == cfg.irq_at: self.irq = True; ev.append('IRQ↑')

        # ---- port: response, then handshake (inputs of this cycle)
        resp = None
        if self.req and self.req['fired'] and self.req['resp_at'] == c:
            resp, self.req = self.req, None
            ev.append(f"resp {resp['owner']}{'(killed)' if resp['killed'] else ''}")
        if self.req and not self.req['fired'] and c >= self.req['ready_at']:
            self.req['fired'] = True; self.req['resp_at'] = c + cfg.T
            ev.append(f"fire {self.req['owner']}")
            if self.req['owner'] == 'M': self.data_reqs.append(self.req['pc'])

        data_resp = False
        if resp:
            o = resp['owner']
            if o == 'M':
                data_resp = True; self.last_data_pc = resp['pc']
                t = self.MEM
                if t is None or t['seq'] != resp['seq']:
                    self.V(f"data response for pc {resp['pc']} has no requester in MEM (I3)")
                else:
                    t['mstate'] = 'done'
                    if t.get('berr'): t['fault'] = 'berr'
            elif o in ('WF', 'WM'):
                self.walker_response(resp, ev)
            elif o == 'F':
                self.refill_response(resp, ev)
            elif o == 'NC':
                ok = (not resp['killed']) if 'EPOCH1' not in mut else (resp['ep'] % 2 == self.fe_epoch % 2)
                if ok and self.F2 is not None and self.F2['state'] == 'ncwait':
                    self.F2['data'] = resp['word']; self.F2['state'] = 'ready'
                    if resp['word'] != self.F2['w']: self.V("uncached fetch data from another word accepted (I3)")

        # ---- WB: the only commit point; always fires
        wb_start = self.WB
        flush = None; retired = None; wb_normal = False
        t = self.WB
        if t:
            retired = t
            if t.get('irq'):
                self.events.append(('T', t['pc'], 'irq')); ev.append(f"TRAP irq epc={t['pc']}")
                self.epc, self.epc_ret = t['pc'], 0; self.irq = False; self.in_handler = True
                flush = cfg.H
            elif t.get('fault') or t['kind'] == 'ecall':
                cause = t.get('fault') or 'ecall'
                self.events.append(('T', t['pc'], cause)); ev.append(f"TRAP {cause} epc={t['pc']}")
                self.epc, self.epc_ret = t['pc'], 1; self.in_handler = True
                flush = cfg.H
            else:
                if t.get('bad'): self.V(f"pc {t['pc']} committed a value read before its producer load answered")
                self.events.append(('C', t['pc'])); ev.append(f"COMMIT {t['pc']}")
                if t['kind'] in SERIAL:
                    flush = (self.epc + self.epc_ret) if t['kind'] == 'mret' else t['pc'] + 1
                    if t['kind'] == 'mret': self.in_handler = False
                else:
                    wb_normal = True
                if t['kind'] == 'halt': self.halted = True
            self.last_retire_c = c
            keep = ('NO_ONESHOT' in mut and self.MEM is not None and self.MEM.get('mstate') not in (None, 'done'))
            if not keep: self.WB = None
            t['retired'] = t.get('retired', 0) + 1
            if t['retired'] > 1: self.V(f"pc {t['pc']} retired {t['retired']} times (I8)")

        # I7: the SoC's awaitingRetire (set on a data response, cleared by any commit/trap; clear wins)
        if retired is not None and (self.ar or data_resp):
            if retired['pc'] != self.last_data_pc:
                self.V(f"awaitingRetire cleared by pc {retired['pc']}, not by the data requester pc {self.last_data_pc} (I7)")
            self.ar = False
        elif data_resp:
            self.ar = True

        mem_before_flush = self.MEM
        if flush is not None:
            self.flush_all(flush); ev.append(f"FLUSH→{flush}")

        # ---- MEM
        oldest_ok = (wb_start is None) or wb_normal
        t = self.MEM
        if t and t['kind'] in MEMK:
            if t['mstate'] == 'xlate':               # first MEM cycle: the data TLB lookup
                if t.get('pf'): t['fault'] = 'pf'; t['mstate'] = 'done'
                elif t.get('dmiss') and not t.get('walked'): t['mstate'] = 'needwalk'
                else: t['mstate'] = 'issue'
            if t['mstate'] == 'needwalk' and oldest_ok:
                if self.walker is None:
                    self.walker = dict(side='M', seq=t['seq'], left=cfg.levels, state='need', killed=False, ep=self.fe_epoch)
                    t['mstate'] = 'walking'
                elif self.walker['side'] == 'F' and self.walker['state'] == 'need' and 'NONPREEMPT' not in mut:
                    ev.append('abandon F-walk (MEM needs the walker)')
                    self.walker = None
                    if self.F1 is not None and self.F1['state'] in ('walk', 'waitns'): self.F1['state'] = 'look'
                    self.walker = dict(side='M', seq=t['seq'], left=cfg.levels, state='need', killed=False, ep=self.fe_epoch)
                    t['mstate'] = 'walking'

        # ---- arbitration for the ONE port: walker(M) > MEM > walker(F) > refill > uncached fetch
        self.arbitrate(oldest_ok, mem_before_flush if flush is not None else None, ev)

        mem_fire = False
        t = self.MEM
        if t is not None and self.WB is None:
            if t['kind'] not in MEMK or t['mstate'] == 'done':
                self.WB = t; self.MEM = None; mem_fire = True

        # ---- EX
        t = self.EX
        self.frozen = False
        if t:
            go = True
            if t['kind'] in SERIAL:
                self.frozen = True
                self.abandon_idle_engines(ev)
                drained = (start['MEM'] is None and start['WB'] is None and self.MEM is None and self.WB is None
                           and self.req is None and self.walker is None and self.refill is None)
                go = drained
            elif t['kind'] == 'mul':
                if t['mleft'] > 0: t['mleft'] -= 1
                go = t['mleft'] == 0
            # load-use: the producer must already be IN WB at the start of this cycle (the MEM/WB register is the
            # forwarding source); a response arriving this cycle is not forwarded combinationally into the ALU
            prod = start['MEM'] if (start['MEM'] is not None and start['MEM']['seq'] == t['seq'] - 1) else None
            if prod is None and self.MEM is not None and self.MEM['seq'] == t['seq'] - 1: prod = self.MEM
            if t.get('dep') and prod is not None and prod['kind'] in MEMK:
                if 'NO_LOADUSE' in mut: t['bad'] = True
                else: go = False                      # load-use: the producer has not reached WB
            if go and t['kind'] == 'br' and t.get('taken'):
                n = self.redirects.get(t['seq'], 0)
                if n == 0 or 'NO_REDIR_ONESHOT' in mut:
                    self.redirects[t['seq']] = n + 1
                    if n >= 1: self.V(f"branch pc {t['pc']} redirected {n + 1} times (I8)")
                    self.ID = None; self.flush_front(t['target']); ev.append(f"REDIRECT→{t['target']}")
            if go and self.MEM is None:
                if t['kind'] in SERIAL and not (self.req is None and self.walker is None and self.refill is None):
                    self.V(f"serialiser pc {t['pc']} left EX before the port/walker/refill drained (I9)")
                self.MEM = t; self.EX = None
            elif (t['kind'] == 'br' and t.get('taken') and 'NO_REDIR_ONESHOT' in mut
                  and self.redirects.get(t['seq'], 0) >= 1 and not go):
                pass

        # ---- ID -> EX
        t = self.ID
        if t is not None and self.EX is None:
            self.EX = t; self.ID = None

        # ---- F2 lookup (the I-cache is read in the F2 cycle; a hit is usable by the bypass this cycle)
        t = self.F2
        if t is not None and t['state'] == 'look':
            w = t['w']
            if w in cfg.nc_words: t['state'] = 'ncwait'
            elif w in self.icache or w not in cfg.icache_miss: t['state'] = 'ready'; t['data'] = w
            else:
                t['state'] = 'refill'
                if self.refill is None and not self.frozen:
                    self.refill = dict(word=w, beat=1, state='need', killed=False, ep=self.fe_epoch)
        if t is not None and t['state'] == 'refill' and self.refill is None and not self.frozen:
            self.refill = dict(word=t['w'], beat=1, state='need', killed=False, ep=self.fe_epoch)

        # ---- ID load: FB head, else bypass from a ready F2; interrupt attachment
        if self.ID is None and not self.fe_stopped:
            src = None
            if self.FB: src = self.FB[0]
            elif self.F2 is not None and self.F2['state'] == 'ready': src = self.F2
            can_irq = self.irq and not self.irq_inflight and not self.in_handler and not self.serial_in_flight()
            if src is not None:
                pc = src['data'] * 2 + src['slot']
                tok = self.mk_tok(pc)
                src['slot'] += 1
                if src is not self.F2 and src['slot'] > 1: self.FB.pop(0)
                self.fe_next_pc = pc + 1
                if can_irq:
                    tok['irq'] = True; self.irq_inflight = True; ev.append(f"irq→token pc={pc}")
                    self.F1 = self.F2 = None; self.FB = []; self.kill_front(); self.fe_stopped = True
                self.ID = tok
            elif can_irq:
                # no instruction to attach to: synthesise a token at the architectural next pc
                epc = self.fe_next_pc
                if 'IRQ_EPC_FE' in mut:
                    epc = (self.F1['w'] * 2 if self.F1 is not None else self.fetch_w * 2)
                tok = self.mk_tok(epc); tok.update(kind='irqtok', irq=True)
                self.irq_inflight = True; ev.append(f"irq→synthetic token epc={epc}")
                self.F1 = self.F2 = None; self.FB = []; self.kill_front(); self.fe_stopped = True
                self.ID = tok

        # ---- F2 -> FB (what the bypass did not take)
        t = self.F2
        if t is not None and t['state'] == 'ready':
            if t['slot'] > 1: self.F2 = None
            elif len(self.FB) < 2:
                self.FB.append(dict(data=t['data'], slot=t['slot'])); self.F2 = None

        # ---- F1
        t = self.F1
        if t is not None:
            if t['state'] == 'waitns' and self.nonspec_f1(): t['state'] = 'look'
            if t['state'] == 'look':
                if t['w'] in self.itlb or t['w'] not in cfg.itlb_miss:
                    t['state'] = 'ready'; t['pa'] = t['w']
                elif self.walker is None and not self.frozen:
                    self.walker = dict(side='F', word=t['w'], left=cfg.levels, state='need', killed=False,
                                       ep=self.fe_epoch, nc=t['w'] in cfg.pte_nc)
                    t['state'] = 'walk'
            if t['state'] == 'ready' and self.F2 is None:
                self.F2 = dict(w=t['pa'], slot=t['slot'], state='look'); self.F1 = None
        if (self.F1 is None and not self.frozen and not self.fe_stopped and not self.halted):
            self.F1 = dict(w=self.fetch_w, slot=self.fetch_slot, state='look')
            self.fetch_w += 1; self.fetch_slot = 0

        # ---- bookkeeping
        if c - self.last_retire_c > cfg.stall_limit and not self.halted:
            self.V(f"no retirement for {cfg.stall_limit} cycles: deadlock (I5)"); self.halted = True
        port = port_start or '.'
        self.rows.append((c, snap, [dict(e) for e in fb_start], port, ev))
        self.c += 1

    def walker_response(self, resp, ev):
        w = self.walker
        if w is None:
            if not resp['killed'] and 'EPOCH1' not in self.mut: self.V("walker response with no walker (I3)")
            return
        if 'EPOCH1' not in self.mut and w['killed']:
            self.walker = None; ev.append('killed walk drained, no fill'); return
        w['left'] -= 1
        if w['left'] > 0:
            w['state'] = 'need'; return
        self.walker = None
        if w['side'] == 'M':
            t = self.MEM
            if t is not None and t['seq'] == w['seq']: t['walked'] = True; t['mstate'] = 'issue'
            return
        accept = True
        if 'EPOCH1' in self.mut: accept = (w['ep'] % 2 == self.fe_epoch % 2)
        if not accept:
            ev.append('stale walk dropped (epoch differs)'); return
        self.itlb.add(w['word'])
        waiting = ('walk', 'look') if 'EPOCH1' in self.mut else ('walk',)
        if self.F1 is not None and self.F1['state'] in waiting and (self.F1['state'] == 'walk' or self.F1['w'] not in self.itlb or self.F1['w'] != w['word']):
            if self.F1['w'] != w['word']: ev.append(f"STALE walk for word {w['word']} delivered to F1 word {self.F1['w']}")
            self.F1['pa'] = w['word']; self.F1['state'] = 'ready'

    def refill_response(self, resp, ev):
        r = self.refill
        if r is None:
            if not resp['killed'] and 'EPOCH1' not in self.mut: self.V("refill response with no refill (I3)")
            return
        if 'EPOCH1' not in self.mut and r['killed']:
            self.refill = None; ev.append('killed refill drained, no fill'); return
        if r['beat'] == 1:
            r['beat'] = 2; r['state'] = 'need'; return
        self.refill = None
        if 'EPOCH1' in self.mut and r['ep'] % 2 != self.fe_epoch % 2:
            ev.append('stale refill dropped (epoch differs)'); return
        self.icache.add(r['word'])
        if self.F2 is not None and self.F2['state'] in (('refill', 'look') if 'EPOCH1' in self.mut else ('refill',)):
            if self.F2['w'] != r['word']: ev.append(f"STALE refill of word {r['word']} delivered to F2 word {self.F2['w']}")
            self.F2['data'] = r['word']; self.F2['state'] = 'ready'

    def abandon_idle_engines(self, ev):
        """Serialisation freeze: an engine with no request outstanding is abandoned; an outstanding one drains."""
        if self.walker and self.walker['side'] == 'F' and self.walker['state'] == 'need':
            self.walker = None; ev.append('freeze: idle F-walk abandoned')
            if self.F1 is not None and self.F1['state'] == 'walk': self.F1['state'] = 'look'
        if self.refill and self.refill['state'] == 'need':
            self.refill = None; ev.append('freeze: idle refill abandoned')
            if self.F2 is not None and self.F2['state'] == 'refill': self.F2['state'] = 'look'

    def arbitrate(self, oldest_ok, mem_flushed, ev):
        cfg, mut = self.cfg, self.mut
        if self.req is not None: return
        w = self.walker
        # MEM_SPEC: the decision of a MEM instruction that the same cycle's WB flush removed is not gated
        if (mem_flushed is not None and 'MEM_SPEC' in mut and mem_flushed['kind'] in MEMK and not mem_flushed.get('pf')
                and mem_flushed['mstate'] in ('xlate', 'issue')):
            self.alloc('M', pc=mem_flushed['pc'], seq=mem_flushed['seq']); ev.append(f"req M pc={mem_flushed['pc']} (flushed!)")
            return
        if w is not None and w['side'] == 'M' and w['state'] == 'need':
            self.alloc('WM'); w['state'] = 'wait'; return
        t = self.MEM
        if t is not None and t['kind'] in MEMK and t['mstate'] == 'issue' and (oldest_ok or 'MEM_SPEC' in mut):
            if not oldest_ok: ev.append('MEM issued while WB not committing (I4)')
            self.alloc('M', pc=t['pc'], seq=t['seq']); t['mstate'] = 'wait'; ev.append(f"req M pc={t['pc']}"); return
        if w is not None and w['side'] == 'F' and w['state'] == 'need':
            first = (w['left'] == cfg.levels)
            if first and w['nc'] and not self.nonspec_f1():
                if 'NONPREEMPT' in mut:
                    return                                   # holds the walker, waiting to become non-speculative
                self.walker = None; ev.append('F-walk to non-cacheable PTE released (speculative)')
                if self.F1 is not None: self.F1['state'] = 'waitns'
                return
            if first and w['nc'] and not self.nonspec_f1():
                self.V("speculative PTE read from non-cacheable space (I6)")
            self.alloc('WF', word=w['word']); w['state'] = 'wait'; return
        if self.frozen: return
        r = self.refill
        if r is not None and r['state'] == 'need':
            self.alloc('F', word=r['word']); r['state'] = 'wait'; return
        t = self.F2
        if t is not None and t['state'] == 'ncwait' and not t.get('issued'):
            ns = self.nonspec_f2()
            if ns or 'SPEC_NC' in mut:
                if not ns: self.V(f"uncached fetch of word {t['w']} issued speculatively (I6)")
                self.alloc('NC', word=t['w']); t['issued'] = True

    def run(self):
        while self.c < self.cfg.max_cycles and not self.halted:
            self.step()
        return self


# ---------------------------------------------------------------------------- golden checks
def golden(prog, cfg, sim):
    pc = cfg.entry; epc = None; ret = 0; want_data = []
    for i, e in enumerate(sim.events):
        if e[0] == 'T' and e[2] == 'irq':
            if e[1] != pc: return f"event {i}: interrupt epc {e[1]} != architectural next pc {pc} (I1)", want_data
            epc, ret, pc = pc, 0, cfg.H; continue
        ins = prog.get(pc, {'kind': 'alu'})
        if ins['kind'] in MEMK and not ins.get('pf'): want_data.append(pc)
        if ins['kind'] == 'ecall' or ins.get('pf') or ins.get('berr'):
            cause = 'ecall' if ins['kind'] == 'ecall' else ('pf' if ins.get('pf') else 'berr')
            exp = ('T', pc, cause); epc, ret = pc, 1; nxt = cfg.H
        else:
            exp = ('C', pc)
            nxt = (ins['target'] if ins['kind'] == 'br' and ins.get('taken') else
                   (epc + ret) if ins['kind'] == 'mret' else pc + 1)
        if e != exp: return f"event {i}: got {e}, architecture says {exp} (I1)", want_data
        pc = nxt
    if not sim.events or sim.events[-1] != ('C', max(p for p, v in prog.items() if v['kind'] == 'halt')):
        return "the run did not end at the halt instruction", want_data
    return None, want_data


def check(prog, cfg, mut=()):
    s = Sim(prog, cfg, mut).run()
    g, want = golden(prog, cfg, s)
    fails = list(s.viol)
    if g: fails.append(g)
    if not g and s.data_reqs != want:
        fails.append(f"data requests {s.data_reqs} != retired memory instructions {want} (I2)")
    return s, fails


# ---------------------------------------------------------------------------- scenarios
def P(**kw):
    return kw

def prog_of(d, H=60):
    p = dict(d)
    p.setdefault(H, P(kind='alu')); p.setdefault(H + 1, P(kind='mret'))
    return p

SCEN = {}
def scen(name, desc, prog, cfg, mutations):
    SCEN[name] = (desc, prog, cfg, mutations)

# S1: WB commits once while MEM waits; the EX branch behind the waiting load redirects once
scen('wb-once', 'a load waits in MEM (T=6); the older ALU commits in WB exactly once and WB then stays empty; the taken branch behind the load redirects once while it is held in EX',
     prog_of({0: P(kind='alu'), 1: P(kind='load'), 2: P(kind='br', taken=True, target=8),
              3: P(kind='alu'), 8: P(kind='alu'), 9: P(kind='halt')}),
     Cfg(T=6), ['NO_ONESHOT', 'NO_REDIR_ONESHOT'])
# S2: two flushes while ONE fetch-side walk is outstanding (Codex item 1)
scen('two-flush', 'a speculative fetch walk is outstanding (valid raised before its handshake: RD=3); the younger EX branch redirects (flush 1) and the older MEM load page-faults at WB (flush 2); the handler word also misses the TLB',
     prog_of({0: P(kind='alu'), 1: P(kind='alu'), 2: P(kind='load', pf=True), 3: P(kind='br', taken=True, target=20),
              20: P(kind='alu'), 21: P(kind='alu'), 22: P(kind='halt')}),
     Cfg(T=6, RD=3, itlb_miss={2, 30}), ['EPOCH1'])
# S3: the walker deadlock (Codex item 3)
scen('walker-deadlock', 'a wrong-path fetch walk needs a non-cacheable first PTE (must wait to be non-speculative) while the older MEM load misses the data TLB and needs the walker',
     prog_of({0: P(kind='load', dmiss=True), 1: P(kind='alu'), 2: P(kind='alu'), 3: P(kind='halt')}),
     Cfg(T=3, itlb_miss={1}, pte_nc={1}), ['NONPREEMPT'])
# S4: interrupt with no instruction to attach to (Codex item 4)
scen('irq-no-input', 'the line rises while the front end waits on an I-cache refill (T=10) and ID..WB are empty: a synthetic token carries epc = the next architectural pc',
     prog_of({0: P(kind='alu'), 1: P(kind='alu'), 2: P(kind='alu'), 3: P(kind='alu'), 4: P(kind='halt')}),
     Cfg(T=10, icache_miss={1}, irq_at=6), ['IRQ_EPC_FE'])
# S5: interrupt pending while an older instruction faults
scen('irq-vs-older-fault', 'the line rises when the page-faulting load is already in EX: the token attaches to the YOUNGER instruction, the older synchronous trap wins at WB and flushes it; the handler runs with interrupts off; after mret the token re-attaches and the interrupt is taken exactly once',
     prog_of({0: P(kind='alu'), 1: P(kind='load', pf=True), 2: P(kind='alu'), 3: P(kind='alu'), 4: P(kind='halt')}),
     Cfg(T=2, irq_at=5), [])
# S6: front-end throughput: 4 ALU hits, a taken branch, a load with a data-TLB miss
scen('frontend', 'four ALU instructions on I-cache/TLB hits retire one per cycle; then a taken branch (3 bubbles) and a load that misses the data TLB',
     prog_of({0: P(kind='alu'), 1: P(kind='alu'), 2: P(kind='alu'), 3: P(kind='alu'), 4: P(kind='br', taken=True, target=10),
              10: P(kind='alu'), 11: P(kind='load', dmiss=True), 12: P(kind='alu', dep=True), 13: P(kind='halt')}),
     Cfg(T=2), [])
# S7: serialisation drain cost depends on what is in flight
for T in (2, 6, 18):
    scen(f'serial-drain-T{T}', f'a CSR reaches EX while a fetch refill is outstanding (T={T}): freeze, drain, then execute; cost varies with T',
         prog_of({0: P(kind='alu'), 1: P(kind='csr'), 2: P(kind='alu'), 3: P(kind='alu'), 4: P(kind='alu'), 5: P(kind='halt')}),
         Cfg(T=T, icache_miss={1, 2}), [])
# S8: a store directly behind an older trapping instruction (Codex R2)
scen('store-under-trap', 'ecall (older) reaches WB in the cycle the younger store is ready to issue: the store must not go out',
     prog_of({0: P(kind='alu'), 1: P(kind='ecall'), 2: P(kind='store'), 3: P(kind='alu'), 4: P(kind='halt')}),
     Cfg(T=2), ['MEM_SPEC'])
# S9: load-use with back-pressure
scen('load-use', 'a consumer directly behind a load (T=5, RD=2) waits until the load reaches WB',
     prog_of({0: P(kind='load'), 1: P(kind='alu', dep=True), 2: P(kind='store'), 3: P(kind='halt')}),
     Cfg(T=5, RD=2), ['NO_LOADUSE'])
# S10: speculative uncached fetch
scen('spec-uncached-fetch', 'the fall-through words behind a taken branch are in uncached space: they may be requested only when non-speculative',
     prog_of({0: P(kind='alu'), 1: P(kind='br', taken=True, target=8), 8: P(kind='alu'), 9: P(kind='halt')}),
     Cfg(T=4, nc_words={1, 2}), ['SPEC_NC'])
# S11: an ALU commit in the same cycle as a data response must not clear the SoC's awaitingRetire
scen('retire-assoc', 'a store behind a flushed younger path; checks that every data response is retired by its own requester (the SoC rule of RD2Soc.scala:371-372)',
     prog_of({0: P(kind='alu'), 1: P(kind='store'), 2: P(kind='alu'), 3: P(kind='load'), 4: P(kind='alu', dep=True), 5: P(kind='halt')}),
     Cfg(T=3), [])


def table(name, s, lo=0, hi=None):
    desc = SCEN[name][0]
    out = [f"### {name}: {desc}", '', '| cyc | F1 | F2 | FB | ID | EX | MEM | WB | port | events |', '|---|---|---|---|---|---|---|---|---|---|']
    for (c, st, fb, port, ev) in s.rows[lo:hi]:
        f1 = '.' if st['F1'] is None else f"w{st['F1']['w']}:{st['F1']['state'][:2]}"
        f2 = '.' if st['F2'] is None else f"w{st['F2']['w']}:{st['F2']['state'][:2]}"
        fbs = ','.join(f"w{e['data']}.{e['slot']}" for e in fb) or '.'
        out.append(f"| {c} | {f1} | {f2} | {fbs} | {s.fmt(st['ID'])} | {s.fmt(st['EX'])} | {s.fmt(st['MEM'])} | {s.fmt(st['WB'])} | {port} | {'; '.join(ev)} |")
    return '\n'.join(out)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--table'); ap.add_argument('--mut', default='')
    ap.add_argument('--hi', type=int, default=None); a = ap.parse_args()
    if a.table:
        d, prog, cfg, _ = SCEN[a.table]
        s, fails = check(prog, cfg, [m for m in a.mut.split(',') if m])
        print(table(a.table, s, 0, a.hi)); print()
        print('retirements:', s.events); print('data requests:', s.data_reqs)
        print('RESULT', 'PASS' if not fails else 'FAIL'); [print('  ', f) for f in fails]
        return
    surprises = 0
    print('| scenario | design | result | first reason |'); print('|---|---|---|---|')
    for name, (d, prog, cfg, muts) in SCEN.items():
        s, fails = check(prog, copy.deepcopy(cfg))
        ok = not fails; surprises += (not ok)
        print(f"| {name} | correct | {'PASS' if ok else 'FAIL (unexpected)'} | {fails[0] if fails else f'{len(s.events)} retirements, {s.c} cycles'} |")
        for m in muts:
            s2, f2 = check(prog, copy.deepcopy(cfg), [m])
            caught = bool(f2); surprises += (not caught)
            print(f"| {name} | mutation {m} | {'FAIL (expected)' if caught else 'PASS (NOT CAUGHT)'} | {f2[0] if f2 else '-'} |")
    print(f"\nMODEL_DONE surprises={surprises}")
    sys.exit(1 if surprises else 0)


if __name__ == '__main__':
    main()
