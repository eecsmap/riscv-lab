# Experiment: <one line, in the form "does X change Y">

Copy this file to `experiments/<id>/PLAN.md`. Fill it in **before** running anything. An experiment whose
hypothesis is written afterwards is a description of a result, not a test of an idea.

## Hypothesis

One sentence, falsifiable, with a direction and ideally a magnitude.
State what result would make it **wrong**. If no result could, it is not a hypothesis.

## Baseline

Which baseline identity this is measured against (e.g. `B0`), and the exact runs and manifests.
A baseline taken on a different configuration is not a baseline for this experiment.

## The single variable

Exactly one thing changes. Name it, and name the RTL/software/config identity before and after.
If two things must change together, say why, and expect the result to be attributable to neither alone.

## Invariants

What must stay identical: bitstream (or the fact that it changed and why), kernel, disk image, frequency,
workload binaries, sample policy, transport, boot session type.
Anything that could not be held constant goes here, explicitly, as a limit on the conclusion.

## Correctness gates

What must still pass for a performance result to count at all. A faster wrong answer is not a result.
For this CPU the minimum is: the eight startup probes, and the four-command xv6 session where applicable.
Record the gate outcomes with the performance data, not separately.

## Measures

Which metrics, which ROIs, which statistic, how many samples, what timeout, and how failures are treated.
Reference `benchmarks/metrics.md` rather than restating it.

## Limits

What this experiment cannot establish even if it succeeds. Be specific: "this does not show X" is more
useful later than a general disclaimer.
