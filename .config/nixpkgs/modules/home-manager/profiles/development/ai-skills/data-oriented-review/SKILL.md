---
name: data-oriented-review
description: >-
  Review runtime implementations, diffs, or designs where data representation
  or access paths may materially affect performance, scale, or resource use.
---

# Data-Oriented Review

Review runtime data shape and access paths. Consider ownership and lifecycle
only as they affect data lifetime, sharing, reuse, placement, or movement.

## Evidence gate

Establish the workload/access path, current or candidate representation, and
materiality target (metric, resource limit, scale, or data cost) from the request
and available evidence. Before declaring an input missing, perform bounded,
read-only inspection of relevant code, callers, tests, or documentation within
the authorised scope. If an essential input remains unresolved, report supported
observations, name the smallest missing input, and stop conclusions that depend
on it; do not claim the evidence gate passed. Exploratory designs may leave the
baseline **Unknown**; alternatives remain hypotheses. Implementation/diff
findings require a baseline or explicit workload model; otherwise report
hypotheses only.

## Lenses

Apply every lens. Mark irrelevant ones N/A with a reason and keep clean ones
brief. For relevant lenses report **Observation** (evidence), **Inference**
(mechanism/impact), and **Unknowns** (missing evidence).

1. **Workload/access:** hot, repeated, filtered, traversed, or conditional
   reads/writes; co-access, volume, selectivity, metric, and baseline.
2. **Representation/movement:** layout, density, indirection, allocation,
   copying, conversion, and materialization against those paths.
3. **Ownership/locality:** lifetime, mutation, sharing, reuse, working set,
   cache/bandwidth behavior, prefetchability, and placement.
4. **Partitioning/concurrency:** when sharing or concurrency is present or
   proposed, assess contention, synchronization, false sharing, skew, ordering,
   and load balance where representation or partitioning is the mechanism.
   Exclude standalone scheduling/concurrency.

## Findings

Evidence may be a workload description, profile, benchmark, trace, or test.
Familiarity alone does not justify layout, indirection, batching, or sharding;
require co-access or workload evidence.

A finding needs evidence or an explicit workload model linking mechanism to the
materiality target. Otherwise report a **Hypothesis** with missing evidence and
a disconfirming test. For each material finding state: access path; smallest
proportionate alternative; confidence (low/medium/high); trade-offs; validation
metric, workload, baseline (or reason absent), and confirming/disconfirming
result or decision rule. Recommend only review/design-level changes.

If the evidence gate passes and no material finding exists, state exactly:

**No material data-oriented finding; representation and access paths are
proportionate to the available evidence.** Then list only hypotheses that could
change the conclusion.
