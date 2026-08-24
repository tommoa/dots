---
name: architectural-decision-record
description: >-
  Create, review, or supersede repository architecture decision records (ADRs).
  Use when asked to work on an ADR or decide whether a choice warrants one, not
  for general architecture work alone.
---

# Architecture Decision Records

Before drafting, reviewing, or changing an ADR, locate the relevant repository
guidance and nearby records. Inspect directory, template, numbering, and index
conventions when the task requires them. Follow local conventions rather than
introducing a new format.

Use an ADR for a durable architectural choice that is structurally significant,
costly to reverse, or establishes an important boundary or invariant. Prefer
code, tests, ordinary documentation, plans, or issue tracking for implementation
details and temporary project state.

An ADR is especially useful when a future maintainer would otherwise question
why the obvious path was not taken or when recording a real trade-off prevents
settled alternatives from being reopened. Skip obvious defaults and easily
reversible details.

Review and planning do not authorise file changes. A draft may be returned in the
response; modify repository files only when explicitly requested. Follow local
status conventions, and never infer acceptance from implementation, wording
approval, or positive review.

The warranting criteria above need no additional reference. Load the references
relevant to the requested work; compound tasks may require more than one:

- For drafting, revising, shortening, or splitting an ADR, read
  [references/authoring.md](references/authoring.md).
- For critique, evaluation of an existing ADR, or acceptance-readiness review, read
  [references/review.md](references/review.md).
- For status changes, supersession, numbering, index maintenance, or validation
  after file edits, read [references/lifecycle.md](references/lifecycle.md).
- For a superseding ADR, read both authoring and lifecycle guidance.
- For a review with a conditional status change, read both review and lifecycle
  guidance.
