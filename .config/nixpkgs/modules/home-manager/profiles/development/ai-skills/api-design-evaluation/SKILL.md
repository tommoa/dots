---
name: api-design-evaluation
description: >-
  Use when a proposed or changed programmatic interface, module boundary, or
  caller-visible protocol needs evaluation.
---

# API Design Evaluation

Review the boundary from callers' point of view.

Use five diagnostic lenses. For each lens, give compact **Observation** (evidence), **Inference** (consequence), and **Unknowns** (missing evidence).

1. **Depth, ownership, and information hiding.** Ask whether a deep module
   hides substantial implementation complexity behind a simple boundary. Locate
   representation, policy, lifecycle, ordering, compatibility, error,
   dependency, and configuration ownership; inspect leakage through parameters,
   types, sequencing, wrappers, or duplicated knowledge.
   Flag split ownership or pass-through only when it burdens callers or makes
   change non-local.
2. **Caller burden and leaked complexity.** Trace what actual callers must know,
   decide, construct, sequence, retry, clean up, or synchronize. Examine
   option interactions, temporal coupling, preconditions, translations,
   incidental states, and reproduced dependencies/configuration. Call obscurity
   defective only when it creates material work or risk.
3. **Valid states and recovery.** Distinguish domain outcomes, misuse,
   exceptions, and operational failures. Check whether invalid states are
   unrepresentable or centrally handled where practical, and whether invariants,
   partial effects, cleanup, cancellation, retry, rollback, recovery ownership,
   and observability are explicit and testable.
4. **Generality and fit.** Treat an interface as general-purpose only when
   multiple real contexts share a stable concept and it removes duplicated
   decisions. Reject speculative generality and needless surface area, while
   retaining useful control and legitimate cross-cutting behavior.
5. **Strategic evolution.** Use plausible next changes and observed change
   amplification to test whether ownership, dependencies, configuration, or
   duplicated knowledge leak from their boundary. Recommend the smallest
   localization move and account for migration and compatibility. Leave history
   collection, ranked backlogs, and mechanical-prevention workflows to
   `change-amplification`; do not duplicate `rethink`'s workflow.

Expand material findings with the caller-boundary consequence, smallest durable
alternative, relevant trade-offs, and verification. Recommend change only for
   evidence-backed material accidental complexity, misplaced ownership, preventable
invalid states, or likely non-local change. State what would resolve
insufficient evidence; account for proportionality, state migration,
flexibility, performance, and operational trade-offs. Keep clean/control results
clean: interface size, unfamiliarity, essential complexity, or possible future
change alone are not findings. If no material issue exists, state exactly:
**No material API-design finding; the current boundary is proportionate to the available evidence.**
