---
name: architectural-decision-record
description: >-
  Create, review, or supersede repository architecture decision records (ADRs),
  or decide whether a durable architectural choice warrants one.
---

# Architecture Decision Records

Before ADR work, locate repository guidance and nearby records. Establish the
applicable directory, template, numbering, status, link, and index conventions;
follow them rather than introducing a new format.

Use an ADR for a durable choice that is structurally significant, costly to
reverse, or establishes an important boundary or invariant—especially when a
future maintainer will need the rationale for a non-obvious choice or settled
trade-off. Put implementation detail, temporary state, obvious defaults, and
easily reversible choices in code, tests, documentation, plans, or issues.

Load every reference whose branch applies:

- Draft, revise, shorten, split, or write a superseding ADR: read
  [references/authoring.md](references/authoring.md).
- Critique, evaluate, or assess acceptance readiness: read
  [references/review.md](references/review.md).
- Change status, supersede, number, update an index, or validate file edits: read
  [references/lifecycle.md](references/lifecycle.md).

Review and planning are read-only unless the user explicitly requests repository
edits; return a requested draft in the response when edits are not authorised.
Apply status changes only through local conventions and an explicit decision.
Implementation, wording approval, or positive review never establishes
acceptance.
