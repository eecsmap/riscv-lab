#!/usr/bin/env python3
"""Re-derive an M3 result from the per-transaction event log, strictly.

The previous version of this script accepted four mutated logs that it should have rejected: a duplicated
response, a response with no request, a log with the AXI statistics removed, and a log with the MRET
retirement removed. It kept requests and responses in dictionaries keyed by sequence number, so a duplicate
simply overwrote its twin; it compared only requests-minus-responses, so an orphan response was invisible;
it never looked at the AXI line at all; and it never checked that the boot actually returned through MRET.

This version walks the events as a state machine with one outstanding transaction, and every conclusion is
tied to an event it can point at.

  check-m3.py <log> <boot|illegal> [--exit=N] [--assert-free] [--host-ok]
              [--exit-store-pc=HEX --tohost=HEX] [--marker=TEXT] [--min-wait=N]
              [--sync-traps=N] [--sync-cause=N --sync-epc=HEX --sync-tval=HEX]
              [--irqs=N] [--axi-min-reads=N --axi-min-writes=N]
"""
import re, sys

if len(sys.argv) < 3: sys.exit(__doc__)
log_path, expect = sys.argv[1], sys.argv[2]
opt = {}
for a in sys.argv[3:]:
    k, _, v = a.partition("=")
    opt[k] = v
fails, notes = [], []
def bad(m): fails.append(m)

ROM_HANG, ROM_ENTRY, DRAM_BASE = 0x10040, 0x10000, 0x80000000
WAIT_PC, MRET_INSN = 0x1005c, 0x30200073

raw = open(log_path, errors="replace").read().splitlines()
# EV lines come from the design and share its cycle counter; EVH lines come from the host-side driver and
# carry its own count. They are kept apart rather than ordered against each other.
events, host_events, console, axi_line, host_ok, asserts = [], [], [], None, False, 0
for line in raw:
    if line.startswith("AXI "): axi_line = line; continue
    if "Completed after" in line: host_ok = True
    if "Assertion" in line: asserts += 1
    # EVA lines are the AXI channel record, checked by check-axi.py; they are neither CPU events nor console
    if re.match(r"\s*EVA\s+\d", line): continue
    ma = line.find("EVA ")
    if ma > 0 and re.match(r"EVA\s+\d", line[ma:]):
        if ma: console.append(line[:ma])
        continue
    mh = re.search(r"EVH\s+(\d+)\s+(\S+)(.*)", line)
    if mh:
        host_events.append((int(mh.group(1)), mh.group(2), mh.group(3)))
        if mh.start(): console.append(line[:mh.start()])
        continue
    # CPU-A: the atomic backend's trace ("AT <cycle> TAG ...") and the bridge's own ("RD2 <cycle> TAG ...")
    # are event streams too, not console output. Without this the console characters that happen to be
    # printed on the same line as one of them get the whole event text appended, and a marker the program
    # really did write stops being a contiguous string. A configuration that prints neither is unaffected.
    mt = re.search(r"(AT|RD2)\s+\d+\s+[A-Z][A-Z0-9_]*", line)
    if mt:
        if mt.start(): console.append(line[:mt.start()])
        continue
    m = re.search(r"EV\s+(\d+)\s+(\S+)(.*)", line)
    if m:
        cyc = int(m.group(1))
        if cyc > 10**9: bad(f"an event carries cycle {cyc}: logging is not gated on reset"); continue
        events.append((cyc, m.group(2), m.group(3)))
        if m.start(): console.append(line[:m.start()])
    elif not line.startswith(("CYCLES ", "*** ")):
        console.append(line)
console = "".join(console)
if not events: bad("no events: the log carries no evidence")

# Records the source emits at most once must appear at most once. Reading them with a first-match search
# lets a second, contradictory copy sit in the log unnoticed -- the same shape of defect as a duplicate
# response that a dictionary absorbs.
for kind, limit in (("HOSTDONE", 1), ("SETTLED", 1), ("DUTRESET", 1)):
    n = sum(1 for _, k, _ in host_events if k == kind)
    if n > limit: bad(f"{n} {kind} records, the source emits at most {limit}")
n_axi = sum(1 for l in raw if l.startswith("AXI "))
if n_axi > 1: bad(f"{n_axi} AXI summary lines, the run emits one")
n_done = sum(1 for l in raw if "Completed after" in l)
if n_done > 1: bad(f"{n_done} completion lines, the run emits one")

# ---- 1. the transaction state machine -------------------------------------------
outstanding = None        # (seq, cycle, fields) or None
next_seq = 0
n_req = n_resp = 0
last_cycle = -1
resp_of = {}              # seq -> (resp cycle, fields), for later ordering checks
req_of = {}
for cyc, kind, rest in events:
    if cyc < last_cycle: bad(f"events are out of order: cycle {cyc} follows {last_cycle}")
    last_cycle = cyc
    if kind == "REQ":
        m = re.search(r"seq=\s*(\d+)", rest)
        if not m: bad(f"REQ at {cyc} has no sequence number"); continue
        s = int(m.group(1))
        if outstanding is not None:
            bad(f"REQ seq={s} at cycle {cyc} while seq={outstanding[0]} was still outstanding")
        if s != next_seq:
            bad(f"REQ sequence jumped: got {s} at cycle {cyc}, expected {next_seq}")
        next_seq = s + 1
        if s in req_of: bad(f"REQ seq={s} appears more than once")
        req_of[s] = (cyc, rest); outstanding = (s, cyc, rest); n_req += 1
    elif kind == "RESP":
        m = re.search(r"seq=\s*(\d+)", rest)
        if not m: bad(f"RESP at {cyc} has no sequence number"); continue
        s = int(m.group(1))
        if outstanding is None:
            bad(f"RESP seq={s} at cycle {cyc} with nothing outstanding")
            continue
        if s != outstanding[0]:
            bad(f"RESP seq={s} at cycle {cyc} does not match the outstanding seq={outstanding[0]}")
            continue
        if cyc <= outstanding[1]:
            bad(f"RESP seq={s} at cycle {cyc} is not later than its request at {outstanding[1]}")
        if s in resp_of: bad(f"RESP seq={s} appears more than once")
        resp_of[s] = (cyc, rest); outstanding = None; n_resp += 1
if outstanding is not None:
    bad(f"the run ended with seq={outstanding[0]} still outstanding, requested at cycle {outstanding[1]}")
if n_req == 0: bad("no bus requests at all")
if n_req != n_resp: bad(f"{n_req} requests but {n_resp} responses")
else: notes.append(f"{n_req} requests, each unique, each answered exactly once, never more than one in flight")

def firsts(kind, pat=None):
    return [(c, r) for c, k, r in events if k == kind and (pat is None or re.search(pat, r))]

# ---- 2. process, host and assertions --------------------------------------------
if "--exit" in opt:
    want = int(opt["--exit"])
    try: got = int(open(log_path.rsplit(".log", 1)[0] + ".exit").read().strip())
    except Exception: got = None
    if got is None: bad("no recorded exit code beside the log")
    elif got != want: bad(f"the process exited {got}, expected {want}")
    else: notes.append(f"the process exited {got}")
if "--assert-free" in opt and asserts: bad(f"{asserts} assertion messages in the log")
if "--host-ok" in opt and not host_ok: bad("the host never reported a completed run")

# ---- 3. the boot chain, as causally ordered events -------------------------------
msip = firsts("IRQLEVEL", r"msip=1")
irq  = firsts("TRAP", r"interrupt=1")
mret = firsts("COMMIT", rf"insn=0x0*{MRET_INSN:x}")
dram = firsts("COMMIT", rf"pc=0x0*{DRAM_BASE:x}\b")
waits = firsts("COMMIT", rf"pc=0x0*{WAIT_PC:x}\b")
illegal = firsts("TRAP", r"interrupt=0 cause=0x0*2 epc=0x0*10054")

if events:
    c0, r0 = events[0][0], events[0][2]
    if events[0][1] != "REQ" or f"addr=0x{ROM_HANG:08x}" not in r0:
        bad(f"the first event is not a fetch of 0x{ROM_HANG:x}: {events[0][1]} {r0.strip()[:70]}")
    else: notes.append(f"first event at cycle {c0} is a fetch of 0x{ROM_HANG:x}")

if expect == "boot":
    if illegal: bad(f"an illegal-instruction trap at 0x10054 at cycle {illegal[0][0]}")
    if not msip: bad("MSIP never came up")
    if not irq: bad("no interrupt was taken")
    if not mret: bad("no MRET retired: the boot never returned from the ROM's handler")
    if not dram: bad(f"nothing retired at 0x{DRAM_BASE:x}")
    if msip and irq and mret and dram:
        m_c, i_c, r_c, d_c = msip[0][0], irq[0][0], mret[0][0], dram[0][0]
        if not (m_c < i_c < r_c < d_c):
            bad(f"boot order violated: MSIP {m_c}, interrupt {i_c}, MRET {r_c}, DRAM entry {d_c}")
        else: notes.append(f"boot chain: MSIP {m_c} -> interrupt {i_c} -> MRET {r_c} -> 0x{DRAM_BASE:x} at {d_c}")
        if "cause=0x8000000000000003" not in irq[0][1]:
            bad(f"the boot interrupt is not a machine software interrupt: {irq[0][1].strip()[:60]}")
        # the wait loop is `wfi` at 0x1005c followed by `j` at 0x10060; an interrupt taken at either
        # instruction boundary is correct, so mepc must be one of the two, not one particular one
        if not any(f"epc=0x{a:016x}" in irq[0][1] for a in (WAIT_PC, WAIT_PC + 4)):
            bad(f"the interrupt's mepc is not in the ROM wait loop: {irq[0][1].strip()[:60]}")
        else: notes.append(f"the interrupt's mepc is inside the ROM wait loop")
        # the machine must have waited, and waited *before* the interrupt
        before = [c for c, _ in waits if c < i_c]
        need = int(opt.get("--min-wait", 2))
        if len(before) < need:
            bad(f"the ROM wait loop retired {len(before)} times before the interrupt, needed {need}")
        else: notes.append(f"the ROM wait loop retired {len(before)} times before the interrupt")
        # the first DRAM retirement must be the entry point itself, not somewhere inside
        any_dram = [c for c, r in firsts("COMMIT", r"pc=0x0*8[0-9a-f]{7}\b")]
        if any_dram and any_dram[0] != d_c:
            bad(f"the first DRAM retirement was at cycle {any_dram[0]}, not the entry point at {d_c}")
elif expect == "illegal":
    if not illegal: bad("the original ROM did not raise an illegal-instruction trap at 0x10054")
    else:
        if "tval=0x0000000030301073" not in illegal[0][1]:
            bad(f"the trap's mtval is not the mideleg encoding: {illegal[0][1].strip()[:60]}")
        notes.append(f"illegal-instruction trap at cycle {illegal[0][0]}, cause 2, epc 0x10054, mtval 0x30301073")
    d = firsts("COMMIT", r"pc=0x0*8[0-9a-f]{7}\b")
    if not d: bad("the run never reached DRAM, so the boot-order violation cannot be shown")
    elif msip and d[0][0] < msip[0][0]:
        notes.append(f"boot order violated as expected: DRAM at {d[0][0]}, before MSIP at {msip[0][0]}")
    elif not irq:
        notes.append(f"boot order violated as expected: DRAM at {d[0][0]} with no interrupt ever taken")
    else: bad("the original ROM produced a correct boot order, which contradicts the trap")
else:
    bad(f"unknown expectation {expect}")

# ---- 4. interrupts and synchronous exceptions, per program -----------------------
if "--irqs" in opt:
    want = int(opt["--irqs"])
    if len(irq) != want: bad(f"{len(irq)} interrupts, expected {want}")
    else: notes.append(f"{len(irq)} interrupts taken")
sync = [(c, r) for c, r in firsts("TRAP", r"interrupt=0")]
if "--sync-traps" in opt:
    want = int(opt["--sync-traps"])
    if len(sync) != want:
        bad(f"{len(sync)} synchronous exceptions, expected {want}" +
            (f" (first: {sync[0][1].strip()[:60]})" if sync else ""))
    else: notes.append(f"{len(sync)} synchronous exceptions, as expected")
    if want and sync:
        for key, label in (("--sync-cause", "cause"), ("--sync-epc", "epc"), ("--sync-tval", "tval")):
            if key in opt:
                v = int(opt[key], 0)
                if f"{label}=0x{v:016x}" not in sync[0][1]:
                    bad(f"the synchronous exception's {label} is not 0x{v:x}: {sync[0][1].strip()[:70]}")
                else: notes.append(f"synchronous exception {label} = 0x{v:x}")

# ---- 5. the exit store: issued, answered, retired, and the last one --------------
if "--exit-store-pc" in opt and "--tohost" in opt:
    epc_, th = int(opt["--exit-store-pc"], 16), int(opt["--tohost"], 16)
    writes = [(c, r) for c, r in firsts("REQ", rf"pc=0x0*{epc_:x} .*addr=0x0*{th:x} write=1")]
    if not writes: bad(f"no exit store from pc 0x{epc_:x} to 0x{th:x}")
    else:
        c, r = writes[-1]
        s = int(re.search(r"seq=\s*(\d+)", r).group(1))
        if s not in resp_of: bad("the exit store was never answered")
        else:
            rc = resp_of[s][0]
            if "error=1" in resp_of[s][1]:
                bad("the exit store's response carried error: the run may not be judged a pass")
            com = [cc for cc, _ in firsts("COMMIT", rf"pc=0x0*{epc_:x}\b") if cc > rc]
            if not com: bad("the exit store never retired after its response")
            else:
                notes.append(f"exit store: request {c} -> response {rc} -> retirement {com[0]}")
                later = [cc for cc, rr in firsts("REQ", r"write=1") if cc > c]
                if later: bad(f"{len(later)} writes were issued after the exit store, first at cycle {later[0]}")
    if not [1 for _, k, _ in host_events if k == "SETTLED"]:
        bad("the run did not report a settled tail")
    if [1 for _, k, _ in host_events if k == "TRAP-AFTER-HOSTDONE"]:
        bad("a trap was taken after the host reported a result")
    # the transaction the intercept selected, when one was selected, must be the exit store itself
    hits = firsts("TAILHIT")
    if hits:
        if len(hits) != 1: bad(f"{len(hits)} transactions were intercepted, expected one")
        h = hits[0][1]
        if f"pc=0x{epc_:016x}" not in h or f"addr=0x{th:08x}" not in h:
            bad(f"the intercept did not land on the exit store: {h.strip()[:80]}")
        elif "wdata=0x0000000000000001" not in h and not re.search(r"wdata=0x[0-9a-f]*[13579bdf]\b", h):
            bad(f"the intercepted write does not carry an HTIF exit payload: {h.strip()[:80]}")
        else: notes.append(f"the intercept landed on the exit store: {h.strip()[:70]}")

# ---- 6. AXI closure ---------------------------------------------------------------
if axi_line is None:
    bad("the AXI statistics line is missing: bus closure cannot be checked")
else:
    v = dict(re.findall(r"(\w+)=(\d+)", axi_line))
    need = ["ar", "r", "rlast", "aw", "w", "wlast", "b"]
    if any(k not in v for k in need): bad(f"the AXI line is incomplete: {axi_line}")
    else:
        ar, r_, rl, aw, w, wl, b = (int(v[k]) for k in need)
        minr = int(opt.get("--axi-min-reads", 1)); minw = int(opt.get("--axi-min-writes", 1))
        if ar < minr: bad(f"only {ar} AXI read bursts, expected at least {minr}")
        if aw < minw: bad(f"only {aw} AXI write bursts, expected at least {minw}")
        if ar != rl: bad(f"AXI reads not closed: {ar} AR against {rl} R-LAST")
        if aw != wl: bad(f"AXI writes not closed: {aw} AW against {wl} W-LAST")
        if aw != b:  bad(f"AXI writes not acknowledged: {aw} AW against {b} B")
        if r_ < ar: bad(f"fewer R beats ({r_}) than AR bursts ({ar})")
        if w < aw: bad(f"fewer W beats ({w}) than AW bursts ({aw})")
        if not fails or True:
            notes.append(f"AXI closed: ar={ar} rlast={rl}, aw={aw} wlast={wl} b={b}, beats r={r_} w={w}")

# ---- 7. the console marker --------------------------------------------------------
if "--marker" in opt:
    if opt["--marker"] in console: notes.append(f"the console carried {opt['--marker']!r}")
    else: bad(f"the console did not carry {opt['--marker']!r}; it had {console[:60]!r}")

for n in notes: print("  note:", n)
for f in fails: print("  FAIL:", f)
print(f"CHECK_DONE fails={len(fails)}")
sys.exit(1 if fails else 0)
