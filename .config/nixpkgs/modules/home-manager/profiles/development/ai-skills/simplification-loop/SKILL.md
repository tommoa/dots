---
name: simplification-loop
description: >-
  Iteratively simplify, verify, and independently review an implementation to
  convergence.
---

# Simplification Loop

Define the current state or diff, intended outcome, and scope. For each
delegation, choose the least-cost sufficient model, breaking ties by speed.

## Loop

1. Give a simplifier the current state or diff, outcome, scope, and repository
   guidance. Have it apply `rethink` and rank concrete proposals.
2. Accept only in-scope proposals that improve ownership or reduce total
   complexity. Ask the user before removing compatibility, validation, error
   handling, or tests if that changes support policy.
3. Have the simplifier implement accepted proposals. Review and adopt the
   result, verify proportionately, and repeat until none are accepted.
4. Have a different subagent conduct a defect-first review; validate its
   findings. If no in-scope defect is confirmed, the loop has converged.
5. Otherwise, have the reviewer repair confirmed defects. Review and adopt the
   result, verify it, then return to step 1.

Stop without convergence if the state repeats, verification fails, user
guidance remains unresolved, or a simplification would reintroduce a repaired
defect.
