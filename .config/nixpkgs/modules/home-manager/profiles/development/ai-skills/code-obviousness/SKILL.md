---
name: code-obviousness
description: >-
  Use when reviewing a concrete implementation or diff for behavior that is
  hard to infer locally.
---

# Code Obviousness

Audit concrete implementations and diffs using current code, diffs, callers,
tests, and local conventions. Follow a maintainer's reading path from local
meaning through behavior, intent, and peer comparison. Do not infer from
history. Report only concrete reader burden or risk; formatting, taste, and
unfamiliarity alone are not findings. Preserve clean/control behavior and state
unknowns rather than guessing.

For each lens, give compact **Observation** (evidence), **Inference**
(reader-facing consequence), and **Unknowns** (missing evidence). Keep each
concern independently actionable.

1. **Names and local meaning.** Check whether names, types, scopes, and nearby
   expressions reveal the actual domain meaning, units, ownership, and effects.
2. **Control flow and state.** Trace branches, mutation, ordering, lifetimes,
   failure paths, callbacks, and hidden effects. Flag behavior that cannot be
   inferred locally or makes a reader simulate needless state.
3. **Comments and intent.** Require concise comments for non-trivial functions
   or blocks: useful what and why, including constraints or invariants. Reject
   line-by-line narration and comments on self-explanatory statements.
4. **Semantic consistency and conventions.** Compare related code, callers,
   tests, and local conventions for conflicting terminology, defaults, error
   meaning, lifecycle, or equivalent behavior expressed inconsistently. First
   establish that peers share a domain and contract: preserve intentional
   differences in domain meaning, policy, or lifecycle, and do not turn
   non-uniformity into a style finding. Report a difference only when evidence
   shows it obscures or contradicts the relevant shared semantics.

Expand each material finding with evidence, reader-facing consequence, smallest
viable alternative, trade-offs, and verification. Use tests, targeted
inspection, or another observable check when relevant. Say what evidence would
resolve an Unknown. Keep clean lenses clean. If no material finding exists,
state exactly:

**No material code-obviousness finding; the implementation is proportionate to the available evidence.**
