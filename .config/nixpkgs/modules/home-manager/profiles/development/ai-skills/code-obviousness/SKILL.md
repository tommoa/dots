---
name: code-obviousness
description: >-
  Review a concrete implementation or diff when behavior is hard to infer
  locally.
---

# Code Obviousness

Review concrete code or diffs along a maintainer's reading path. Use current
code, callers, tests, and local conventions; exclude history. A finding requires
concrete reader burden or risk: formatting, taste, unfamiliarity, and
non-uniformity alone are insufficient.

For every lens, give a compact **Observation** (evidence), **Inference**
(reader consequence), and **Unknowns** (missing evidence). Keep clean lenses
brief and each concern independently actionable.

1. **Local meaning:** Do names, types, scopes, and nearby expressions reveal
   domain meaning, units, ownership, and effects?
2. **Control and state:** Trace branches, mutation, ordering, lifetimes,
   failures, callbacks, and hidden effects. Identify behavior that is not
   locally inferable or forces needless state simulation.
3. **Comments and intent:** Non-trivial functions or blocks need concise comments
   explaining what and why, including constraints or invariants. Skip
   self-explanatory statements and line-by-line narration.
4. **Semantic consistency:** Compare related code, callers, tests, and
   conventions for conflicting terminology, defaults, error meaning, lifecycle,
   or equivalent behavior. Compare only peers sharing a domain and contract;
   preserve intentional differences in meaning, policy, or lifecycle.

Expand each material finding with evidence, reader consequence, the smallest
viable alternative, trade-offs, and a check that would confirm or disconfirm the
concern. State what would resolve each unknown. If there is no material finding,
state exactly:

**No material code-obviousness finding; the implementation is proportionate to the available evidence.**
