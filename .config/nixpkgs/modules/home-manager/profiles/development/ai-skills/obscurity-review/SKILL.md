---
name: obscurity-review
description: >-
  Review system-level changes or operational decisions for hidden contracts,
  lifecycle hazards, duplicated knowledge, or missing cross-boundary evidence.
metadata:
  short-description: Review system-level discoverability
---

# Obscurity Review

Review whether a maintainer can discover enough to assess the decision safely.
Establish the decision and boundary from the request and available evidence.
Before declaring either ungrounded, perform bounded, read-only inspection of
relevant code, configuration, tests, or documentation within the authorized
scope. If neither can be grounded, report supported observations and the
smallest missing input, then stop. If only one is grounded, report the remaining
unknown and limit conclusions to what the evidence supports. Stay read-only;
run only authorized, demonstrably non-mutating probes.

Trace only paths that could change the decision. Apply all four lenses:

1. **Contracts:** assumptions, preconditions, defaults, dependencies,
   configuration, variants.
2. **Lifecycle:** startup, reload, shutdown, failure, recovery, rollback.
3. **Ownership:** sources of truth, copies, leaks, non-local change surfaces.
4. **Evidence:** tests, documentation, telemetry, and diagnostics.

Under each lens, report evidence, consequence, and unknowns; keep clean lenses
brief. Findings require a concrete discovery consequence, not merely a missing
preferred artifact. Give the smallest remedy or discriminating probe. For a
probe, name confirming and disconfirming signals, its safety boundary, and stop
condition.

Report exclusions, unresolved evidence, and whether more investigation is
needed. Gaps beyond reachable discovery paths remain unknown. Exclude local
readability, caller-facing API, history, and general architecture.

If no material issue exists, say: **No material discoverability finding; the
boundary is proportionate to the available evidence.**
