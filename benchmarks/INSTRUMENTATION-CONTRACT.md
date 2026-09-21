# Instrumentation contract

**Nothing here is implemented.** This is the meaning any future counters must have, written before they
exist so that the first implementation is not also the definition. B0 is built from the counters the core
already has (`mcycle`, `minstret`) and needs no new ones.

## 1. State occupancy must be a partition

If per-state cycle counters are added for the core FSM, they must be **mutually exclusive and exhaustive
over the ROI**:

```
sum(state_cycles[s] for s in states) == roi_cycles
```

exactly, not approximately. A counter set that does not sum to the ROI is measuring something else, and
the check must be part of the counter's own self-test rather than a property anyone is asked to trust.
When a state can be entered more than once per instruction (`S_XLATE`, `S_IF2_WAIT`), occupancy is the
total across entries and a separate *entry count* is kept.

## 2. Event counters may overlap, and must say so

Event counters (requests issued, responses taken, walks started, parcels fetched) count occurrences and
may overlap in time with each other and with state occupancy. They are **not** a partition, must never be
summed against ROI cycles, and each must declare its overlap class.

## 3. Three latencies, not one

"Memory latency" is not one quantity and must not be reported as one:

| name | from | to |
| --- | --- | --- |
| **offer latency** | request valid asserted | request accepted (`ready` high with `valid`) |
| **backpressure** | cycles where `valid` is high and `ready` is low | — |
| **handshake-to-response** | request accepted | response valid |

A single "latency" number silently mixes queueing behind other traffic with the time the target took.
B0's `L` is the *whole* round-trip as seen by the FSM and is labelled model-derived precisely because it
cannot separate these.

## 4. Counters must not perturb what they measure

A counter read inside an ROI is part of the ROI (see `metrics.md` §2). Counters must be readable without
stalling the FSM, or the cost of reading must be measured and stated. If reading is not free, the read
overhead belongs in `metrics.md`, not in a footnote.

## 5. Identity

New counters change the RTL, therefore the bitstream, therefore the configuration identity. Results from
an instrumented build are **not** comparable to B0 without showing that instrumentation did not move the
uninstrumented numbers — which requires running the B0 workloads on both.
