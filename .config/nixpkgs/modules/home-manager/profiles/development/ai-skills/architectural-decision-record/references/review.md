# Reviewing ADRs

Lead with findings that could change the decision's acceptance, scope, or future
supersession. Distinguish substantive defects from concise editorial improvements.

Check whether the ADR:

- records one architectural decision at the appropriate level;
- separates durable boundaries and invariants from replaceable implementation;
- compares credible alternatives rather than straw options;
- states material costs, uncertainty, consequences, and important interactions;
- connects reconsideration conditions to actual assumptions or trade-offs; and
- avoids duplicated reasoning and current-state narration, makes intentional
  relationships to other ADRs explicit, and does not present policy as
  architecture.

Challenge an omitted section only when local conventions require it or the
omission hides material reasoning. Offer exact replacement wording when it makes
a recommendation easier to judge, but do not rewrite the record during a
review-only request.

Assessing readiness is not acceptance. Report unresolved assumptions, evidence,
consultation, or authority questions; status changes follow the lifecycle
guidance.

When the user explicitly requests a status change only if the review passes,
state the readiness result first. Change status only when the condition is
satisfied and no blocking finding remains; otherwise leave it unchanged.
