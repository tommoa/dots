---
name: obscurity-review
description: >-
  Use when reviewing a system-level change or operational decision for hidden
  contracts, assumptions, lifecycle hazards, duplicated knowledge, or missing
  evidence across boundaries.
metadata:
  short-description: Review system-level discoverability
---

# Obscurity Review

Review from a maintainer’s point of view: what must be discoverable to make a
concrete system decision safely? Work read-only by default; propose probes and
run only demonstrably non-mutating probes when authorized. Unknown unknowns
cannot be enumerated: inspect reachable discovery paths and label remaining
gaps as unknowns. Keep this system-level; do not turn it into local
readability, caller-facing API, history, or general architecture review.

State the decision and relevant boundary. If neither can be grounded, report
insufficient evidence and stop. Follow only boundaries, variants, and evidence
paths that could change the decision. Apply all four lenses:

1. **Contracts and assumptions:** preconditions, defaults, dependencies,
   configuration, and variants.
2. **Lifecycle and failure:** startup, reload, shutdown, partial failure,
   recovery, rollback, and degradation.
3. **Ownership and duplicated knowledge:** sources of truth, copied policies,
   leaked boundaries, and non-local change surfaces.
4. **Evidence and observability:** tests, documentation, logs, metrics, traces,
   alerts, and diagnostic paths.

For each lens, give a concise observation, consequence, and unknowns; keep clean
lenses brief. For each material concern, give evidence, consequence, relevant
unknowns, and the smallest discriminating probe or proportionate remedy. A
probe must state confirming and disconfirming signals, its safety boundary, and
its stop condition. Report exclusions, unresolved evidence, and whether more
investigation is needed. A missing preferred artifact is not a finding without
a concrete discovery consequence.

If no material issue exists, say: **No material discoverability finding; the
boundary is proportionate to the available evidence.**
