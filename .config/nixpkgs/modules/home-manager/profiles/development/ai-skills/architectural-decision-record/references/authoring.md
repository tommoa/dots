# Authoring ADRs

Before drafting, identify the proposed decision, any credible alternatives, and
any assumption or condition that could justify reconsideration. When constraints
leave no credible alternative, state that constraint rather than manufacturing a
straw option. If the architectural choice is not yet clear, continue exploration
or recommend a more appropriate record instead of manufacturing an ADR.

Keep one decision per record. Split choices when either could change while the
other remains valid, when they have materially different alternatives, or when
they need different review conditions. Keep an invariant with the main decision
when it is necessary to make that decision meaningful.

When no local template requires more, a single paragraph can be enough when it
preserves all material reasoning. Usually that means the context, decision, and
core rationale, plus alternatives, consequences, or reconsideration conditions
when they materially affect the choice. Add structure only when it preserves
information worth revisiting.

Follow the repository template. Use these as internal authoring lenses, not as
headings to add:

- **Context and constraints:** Explain the driving problem, material evidence,
  uncertainty, and forces that make a decision necessary.
- **Decision and boundaries:** State the selected architecture, its scope, and
  durable invariants without turning replaceable implementation detail into an
  architectural commitment. Record explicit exclusions when they protect the
  boundary from future accidental expansion.
- **Credible alternatives:** When alternatives exist, compare approaches that
  could satisfy the need and state their material advantages before their costs.
- **Consequences and reconsideration:** Record benefits, costs, and conditions
  that would challenge an assumption or trade-off.

Treat relevant non-technical policy or authority as a context constraint; do not
turn the policy itself into an architectural decision.

Keep a paragraph only when it constrains scope, explains a credible trade-off,
identifies material uncertainty or a safeguard, or states a useful condition for
reconsideration. Move implementation progress, procedure, research summaries,
and speculative future designs elsewhere.
