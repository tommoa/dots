---
name: arena-loop
description: >-
  Repeatedly challenge and improve a consequential artifact through bounded
  arena rounds when the user explicitly requests sustained iteration toward
  evidence-based convergence.
---

# Arena Loop

Run a resumable programme of targeted `arena` rounds. The `arena` skill owns
candidate generation, within-round judging, synthesis, and verification; this
skill owns the incumbent, cross-round evidence, advancement, backlog, budget,
and stopping.
Keep domain workflows authoritative for domain-specific evidence and vetoes.

## State machine

Maintain a durable ledger (and return it) with the programme input, immutable
artifact paths and hashes, round records, actor records, advancement evidence,
verification, backlog, and terminal state.

`INPUT → [SEED] → SELECT → ARENA → GATE → RECORD → (CONVERGED | STOP | SELECT)`

- **INPUT.** Freeze intended outcome, user scope and permissions, domain
  invariants/non-goals, selected-model policy and round budget. Apply the
  `arena` skill's framing rules once to freeze the candidate contract, judge
  metadata, required evidence, advancement rubric, fixed execution-policy
  fields and any applicable domain evaluation for the whole programme. Default
  to two targeted challenger rounds. Record whether an incumbent exists and the
  stopping rules. Classify design-space coverage as `required`, `already
  evidenced`, or `not material`, with evidence or reason; freeze this
  disposition before running rounds.
- **SEED.** If there is no incumbent, invoke the `arena` skill once on the full
  task. Keep its verified artifact as round-zero incumbent; this establishes an
  incumbent, never convergence. If seeding cannot produce a verified artifact,
  fail closed.
- **SELECT.** Pick exactly one highest-materiality, untested backlog hypothesis,
  ordered by blocker severity, user impact, evidence, and regression risk. State
  the falsifiable expected improvement, retained invariants, non-goals,
  affected scenario, required evidence, and the frozen incumbent. A hypothesis
  must be in scope, distinct, and testable; disposition optional/low-value ideas
  (`deferred` or `rejected`, with reason) instead of using them to force rounds.
  If design-space coverage is `required`, select a blind broad challenge before
  claiming convergence. Otherwise use a broad arena only when new evidence
  shows the design space remains materially underexplored.
- **ARENA.** Invoke the `arena` skill with the frozen incumbent and one
  hypothesis, using targeted-challenger mode for focused tests and blind-
  exploration mode for required design-space coverage. Pass the frozen
  candidate contract and judge metadata unchanged. It must return a complete
  verified challenger and provenance.
  Its candidates remain isolated children or temporary artifacts. Do not
  simulate actors, self-judge, or mutate the incumbent. Preserve challenger and
  all round evidence. If required delegation, isolation, verification, or
  actors fail, stop the round and fail closed.
- **GATE.** After the `arena` round drains, normalize incumbent/challenger to
  neutral labels and send both complete artifacts, fixed facts/rubric, and
  identical evidence to a separate, read-only advancement judge. The arena
  winner is not an advancement decision. Read both artifacts and the verdict.
  Advance only
  when the challenger is preferred under the fixed rule, has no verified
  blocker or material regression, satisfies every required criterion with
  non-unknown evidence, and passes domain vetoes. Applicable domain evaluation
  may require specialist lenses, stronger evidence, additional vetoes or a
  stricter threshold, but cannot weaken this gate. Ties, split specialist
  verdicts, unknown required evidence, or failed verification preserve the
  incumbent. Record blockers, regressions, unknowns, compatible borrow ideas,
  and recommendation even when rejecting.
- **RECORD.** Preserve both immutable artifacts and append the round, actor
  identities/roles/models/destinations/statuses, hypothesis, evidence, verdict,
  and verification. Adopt only the gated challenger; otherwise retain the
  incumbent. Update each backlog item as `untested`, `adopted`, `rejected`,
  `incompatible`, or `deferred` with evidence and reason. Record remaining
  weaknesses, design-space coverage and the next eligible hypothesis. A new
  requirement makes affected evidence stale and requires reframing before
  another round.
- **CONVERGED.** Claim convergence only if the incumbent has no verified
  blocker or required unknown; its highest-priority known weakness received a
  focused challenge; every material compatible item has a reasoned disposition;
  required design-space coverage received a blind broad challenge (or remains
  supported as `already evidenced` or `not material`); and the latest
  independent evidence identifies no further material, in-scope,
  evidence-supported hypothesis.
- **STOP.** Stop without a convergence claim when budget is exhausted, state
  repeats, two properly formed challenges fail on the same hypothesis,
  verification/evidence/required actors are unavailable, or unresolved
  user-owned policy needs the `grilling` skill or other guidance. Return the
  best verified incumbent and unmet convergence conditions; if none exists,
  return blockers and programme state only.

## Actor and permission rules

Freeze criteria within each comparison. If unresolved user preference or policy
would change the contract, invoke the `grilling` skill before spawning actors;
do not guess. Propagate an explicitly user-selected model exactly to every
`arena` actor, advancement judge, and nested delegation in every round;
otherwise record model choices. Never let chronology, identity, model, or
lineage leak into neutral comparison labels. Required actors are genuinely
independent executions: no internal passes, simulated candidates, or
coordinator self-judgment.

The loop never broadens the user's goal, writable scope, permissions, or
verification authority. In read-only work, all proposals and ledger records go
to temporary/isolated destinations. Incumbents and challengers are immutable;
never patch an incumbent in place before a gate. If delegation or isolation is
not available, stop before synthesis or advancement rather than silently
continuing.

## Return contract

Return the best verified incumbent (or only blockers if none was established),
convergence status (explicitly distinguish “best verified” from “converged”),
complete resumable ledger and backlog dispositions, round/actor records,
advancement evidence, verification, stopping reason, remaining uncertainty,
and unmet convergence conditions. Include compatible borrow ideas and the next
hypothesis when useful. Do not reduce domain evidence to generic score
arithmetic or claim convergence from a winning streak.
