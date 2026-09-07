---
name: api-design-evaluation
description: >-
  Use when a proposed or changed programmatic interface, module boundary, or
  caller-visible protocol needs evaluation.
---

# API Design Evaluation

Review the boundary from callers' point of view. For each lens, give a compact
**Observation** (evidence), **Inference** (consequence), and **Unknowns**
(missing evidence); keep clean lenses brief.

1. **Depth and ownership.** Does the boundary hide implementation complexity?
   Locate ownership of representation, policy, lifecycle, ordering,
   compatibility, errors, dependencies, and configuration. Flag leakage through
   types, parameters, sequencing, wrappers, or duplicated knowledge only when
   it burdens callers or makes change non-local.
2. **Caller burden.** Trace what callers must know, decide, construct, sequence,
   retry, clean up, or synchronize. Check option interactions, temporal
   coupling, preconditions, translations, incidental states, and reproduced
   dependencies or configuration. Obscurity is defective only when it creates
   material work or risk.
3. **Valid states and recovery.** Distinguish domain outcomes, misuse,
   exceptions, and operational failures. Check practical prevention or central
   handling of invalid states, plus explicit and testable invariants, partial
   effects, cleanup, cancellation, retry, rollback, recovery ownership, and
   observability.
4. **Generality and fit.** A general-purpose interface needs multiple real
   contexts sharing a stable concept and must remove duplicated decisions.
   Reject speculative surface area while preserving useful control and
   legitimate cross-cutting behavior.
5. **Evolution.** Test plausible next changes and observed change amplification
   for leaked ownership, dependencies, configuration, or duplicated knowledge.
   Prefer the smallest localization move, including migration and compatibility.

For each material finding, include evidence, caller-visible consequence, the
smallest durable alternative, trade-offs, and verification. Recommend change
only for evidence-backed accidental complexity, misplaced ownership,
preventable invalid states, or likely non-local change. Name the evidence needed
to resolve an unknown. Account for proportionality, state migration,
flexibility, performance, and operational trade-offs.

If no material issue exists, state exactly:

**No material API-design finding; the current boundary is proportionate to the available evidence.**
