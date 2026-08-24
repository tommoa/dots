---
name: simplification-loop
description: >-
  Repeatedly simplify, verify, and independently review an explicitly writable
  implementation when the user requests the loop and authorizes changes.
---

# Simplification Loop

## Setup

1. Require an explicitly writable target and user-authorized implementation.
   Otherwise stop: invoking this implementation loop in read-only work is a
   user error, not a request for a proposal-only fallback.
2. Define the target state or diff, intended outcome, and scope.
3. Select each delegation independently using the cheapest, fastest model with
   sufficient capability. Escalate only for a concrete capability gap or risk.

## Simplify to convergence

1. Give a proposal subagent the current state or diff, outcome, and repository
   guidance. Ask it to apply the `rethink` skill and rank concrete
   simplifications.
2. Reject scope expansion and proposals that merely relocate complexity without
   improving ownership or reducing total complexity. If removing compatibility,
   validation, error handling, or tests changes support policy, ask the user
   before implementing it.
3. Ask the proposal subagent to implement the accepted proposals.
   Review and adopt its resulting state, then run proportionate verification.
4. Repeat until a proposal pass yields no accepted simplification, then review.

## Review and repair

1. Have an independent subagent perform a defect-first review and validate its
   findings.
2. Stop when no in-scope defect is confirmed.
3. Ask the reviewing subagent to fix its confirmed defects. Review
   and adopt its resulting state, verify it, then return to
   **Simplify to convergence**.

Stop if a simplification would reintroduce a previously repaired defect, the
same state recurs, progress requires unresolved user guidance, or verification
fails.
