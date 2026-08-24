---
name: simplification-loop
description: Iteratively simplify a specified change and review the result for defects.
---

# Simplification Loop

## Setup

1. Define the target state or diff, intended outcome, and scope. Default to
   read-only proposals; permit edits only when implementation was explicitly
   requested.
2. Select each delegation independently using the cheapest, fastest model with
   sufficient capability. Escalate only for a concrete capability gap or risk.

## Simplify to convergence

1. Give a proposal subagent the current state or diff, outcome, and repository
   guidance. Ask it to apply `$rethink` and rank concrete simplifications.
2. Reject scope expansion and proposals that merely relocate complexity without
   improving ownership or reducing total complexity. If removing compatibility,
   validation, error handling, or tests changes support policy, ask the user
   before implementing it.
3. In read-only mode, report the accepted proposals and continue to review.
4. Otherwise, ask the proposal subagent to implement the accepted proposals.
   Review and adopt its resulting state, then run proportionate verification.
5. Repeat until a proposal pass yields no accepted simplification.

## Review and repair

1. Have an independent subagent perform a defect-first review and validate its
   findings.
2. Stop when no in-scope defect is confirmed.
3. In read-only mode, report confirmed defects and stop.
4. Otherwise, ask the reviewing subagent to fix its confirmed defects. Review
   and adopt its resulting state, verify it, then return to
   **Simplify to convergence**.

Stop if a simplification would reintroduce a previously repaired defect, the
same state recurs, progress requires unresolved user guidance, or verification
fails.
