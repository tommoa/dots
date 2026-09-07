---
name: arena-loop
description: >-
  Run bounded, resumable arena rounds when the user explicitly requests
  sustained iteration on a consequential artifact toward evidence-based
  convergence.
---

# Arena Loop

Orchestrate `arena` rounds against a frozen incumbent. `arena` owns each round;
this skill owns cross-round state, advancement, backlog, budget, and stopping.
Domain workflows own domain evidence and vetoes.

## Set up the programme

Create and return a durable ledger of programme input, immutable artifacts and
hashes, rounds, actors, evidence, verification, backlog, and terminal state.

Before any round:

1. Freeze the outcome, scope, permissions, invariants, non-goals, model policy,
   budget, incumbent, and stopping rules. Default to two targeted rounds.
2. Apply `arena` framing and preference audit. Freeze its contract, judge
   metadata, evidence, advancement rubric, execution policy, and domain
   evaluation programme-wide. Record decisions and any use of `grilling`.
3. Classify design-space coverage as `required`, `already evidenced`, or `not
   material`, with its evidence or reason.

On resume or a new requirement, repeat the audit; affected evidence stays stale
until reframing completes. Begin actors only after resolving framing and
user-owned choices.

## Run one round

1. **Seed if needed.** With no incumbent, invoke `arena` once on the full task
   and keep its verified artifact as round zero. Seeding establishes an
   incumbent, not convergence. Stop if it produces no verified artifact.
2. **Select one hypothesis.** Choose the highest-materiality in-scope,
   distinct, testable untested backlog item, ordered by blockers, user impact,
   evidence, and regression risk. Record its falsifiable improvement,
   invariants, non-goals, scenario, required evidence, and frozen incumbent.
   Mark low-value ideas `deferred` or `rejected` with reasons.
   When design-space coverage is `required`, select a blind broad challenge
   before convergence; otherwise use broad exploration only when evidence
   shows material underexploration.
3. **Run `arena`.** Use targeted-challenger mode for a focused hypothesis and
   blind-exploration mode for required coverage. Pass the frozen incumbent,
   candidate contract, and judge metadata unchanged. Preserve the verified
   challenger, provenance, and round evidence as complete, isolated, immutable
   artifacts. Failure of required delegation, isolation, verification, or
   actors ends the round without advancement.
4. **Gate advancement.** After the arena drains, give the neutrally labeled,
   complete artifacts, fixed facts and rubric, and identical evidence to a
   separate read-only judge. Advance only when the challenger is preferred,
   has no verified blocker or material regression, satisfies every required
   criterion with known evidence, and passes all domain vetoes. Domain
   evaluation may only strengthen this gate. Ties, split verdicts, unknowns,
   and failed verification retain the incumbent.
5. **Record and continue.** Append actors, models, destinations, statuses,
   hypothesis, evidence, verdict, recommendation, blockers, regressions,
   unknowns, borrow ideas, and verification. Adopt only the gated challenger.
   Mark each backlog item `untested`, `adopted`, `rejected`, `incompatible`, or
   `deferred` with evidence and reason. Record weaknesses, coverage, and the
   next eligible hypothesis.

## Preserve independence and authority

- Keep criteria fixed within each comparison. The arena winner is evidence,
  not the advancement decision.
- Use separate executions for actors and the advancement judge. Record their
  identity, role, model, destination, and status. Keep those details out of
  neutral labels.
- Propagate an explicitly user-selected model exactly to every arena actor,
  advancement judge, and nested delegation. Otherwise record the selected
  models.
- Preserve the user's goal, scope, permissions, and verification authority.
  Isolate read-only work in temporary destinations. Keep artifacts immutable
  until the gate completes.

## Finish

Claim **converged** only when all of these hold:

- the incumbent has no verified blocker or required unknown;
- its highest-priority known weakness received a focused challenge;
- every material compatible backlog item has a reasoned disposition;
- required broad coverage was tested, or remains evidenced as `already
  evidenced` or `not material`; and
- the latest independent evidence exposes no further material, in-scope,
  evidence-supported hypothesis.

Stop without convergence when the budget expires, state repeats, two valid
challenges fail on one hypothesis, evidence, verification, isolation, or actors
are unavailable, or a user-owned choice remains unresolved.

Return the best verified incumbent labeled `converged` or `best verified`;
resumable ledger and backlog; advancement and verification evidence; stopping
reason; uncertainty; and unmet conditions. Without an incumbent, return only
blockers and programme state. Include borrow ideas and the next hypothesis when
useful. Evaluate domain evidence directly: a winning streak is not convergence.
