# Self-audit: the same defect class, in gates that were already accepted

Codex has now found the same shape of defect in my checkers twice: a total or a set standing in for a
timeline, and a record read with a first-match search so that a duplicate is absorbed rather than noticed.
Rather than wait to be told a third time, I turned its method on my own accepted work.

`selfaudit/probe-accepted-gates.py` copies an accepted run directory, mutates one artefact, and re-runs the
checker. `selfaudit/probe-single-records.py` does the same for a single log. Both are here with their output.

## What the probes found

Three of six mutations were accepted by `check-m2-3-events.py`, which was accepted at M2-3:

| mutation | was | why |
|---|---|---|
| a second FIRE record appended | accepted | the record was read with `re.search`, so the copy was invisible |
| the reported retirement count inflated | accepted | nothing checked that number for the `chain-p*` runs |
| a commit record duplicated in the trace | accepted | the trace was not read at all for those runs |

And three of five were accepted by `check-m3.py`, which was accepted this week:

| mutation | was |
|---|---|
| a second HOSTDONE record | accepted |
| a second SETTLED record | accepted |
| a second AXI summary line | accepted |

The M2-3 companion checker, `check-m2-3.py`, did catch the inflated count and the duplicated commit for the
`min`/`fixed`/`random` runs, because it compares those traces across timing profiles. It does not read the
`chain-p*` runs, which is why the hole was there and not elsewhere.

## What changed

Two rules, both narrow:

- a record the source emits once must appear once. Applied to FIRE and CHAIN in the M2-3 events checker, and
  to HOSTDONE, SETTLED, DUTRESET, the AXI summary and the completion line in the M3 checker.
- the recorded commit trace and the retirement count the design reports are two accounts of the same thing,
  so they must agree. This is what gives the `retired=` field a purpose: on its own neither number was
  checkable, which is how both mutations went unnoticed.

After the change all eleven mutations are rejected, each by its own rule.

## Finishing the audit: the three earlier gates had it too

Having found the defect in two checkers, stopping there would have been the wrong place to stop.
`selfaudit/probe-gates.py` runs the same mutations against every checker I have delivered. All three earlier
gates — `check-m2-1.py`, `check-m2-2.py`, `check-m2-3.py` — shared the same three holes:

| mutation | was |
|---|---|
| a second STATS line | accepted |
| a second TOHOST result line | accepted |
| a trap event appended to a log that should have none | accepted |

The third is the same mistake once more: traps were counted from the summary line the driver prints, so an
added trap *event* changed nothing the checker looked at. Two accounts of the same thing now have to agree —
the trap events against the reported count, in M2-2 and M2-3. M2-1's logs predate that summary field and
have no second account, so it uses the invariant that is available instead: that driver returns 4 at the
first trap, so a run which reached a passing tohost cannot also have printed one.

All eight mutations are now rejected against all three.

**A note on how the first attempt at this failed.** My first patch to `check-m2-1.py` silently did nothing:
the string it was supposed to replace did not match, so the file kept the generic rule and the probe kept
reporting the hole. The second attempt asserts the anchor is present before writing. A replacement that
quietly matches nothing is the same failure mode as a gate that quietly checks nothing.

## What did not change

No accepted result moves. Every accepted artefact still passes:

    check-m2-1.py       on m2/run-f             fails=0
    check-m2-2.py       on m2-2/run-c           fails=0
    check-m2-3.py       on m2-3-events/gate     fails=0
    check-m2-3-events.py on m2-3-events/run-a   fails=0
    run-m3-fixes.sh     regate                  M3FIX_DONE fails=0
    run-axi-review.sh   replay2                 AXI_REVIEW_DONE fails=0

So the hardware evidence stands. What was wrong was my description of how strongly it was gated: I had said
those gates verified things they could not actually tell apart from a tampered log. That claim is corrected
here rather than left standing.

No RTL, Chisel or C++ changed; only the five checker scripts. Nothing was rebuilt, and no accepted
evidence directory was written to.
