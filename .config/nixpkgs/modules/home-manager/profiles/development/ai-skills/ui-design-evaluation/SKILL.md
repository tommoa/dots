---
name: ui-design-evaluation
description: >-
  Evaluate, plan, compare, or review user interfaces using rendered task
  evidence, accessibility and recovery safeguards, and blocker-based acceptance
  criteria.
---

# UI Design Evaluation

Evaluate whether people can complete real work through a truthful, accessible,
coherent, and recoverable interface. This domain contract supplies criteria;
callers own orchestration, judging, advancement, and convergence.

## Ground in tasks and evidence

Build a product-specific **task matrix** from goals, roles, capabilities,
fixtures, and applicable cases: routine and repeated work; lifecycle and
recovery; long or empty content; narrow and intermediate widths; keyboard and
touch; and validation, loading, and error states. For comparisons, hold the
matrix, theme, viewport, input method, permissions, and available behavior
constant. Material priorities and product policy remain user-owned.

For each scenario, record its expected result and observed path, including
hesitation, wrong turns, recovery, and outcome. Require rendered evidence for
visual, geometry, focus, reflow, and interaction claims; source only
corroborates semantics or validation. Classify unavailable evidence
**incomplete**, unsupported capabilities **not comparable**, and infrastructure
failures **non-design evidence**.

## Apply the domain lenses

Cover every applicable lens as a criterion bundle, not an actor role.

- **Operations and recovery:** task identification, decision cost, preserved
  context, truthful state, predictable lifecycle actions, recovery, destructive
  confirmation, and unsaved-change safety.
- **Accessibility and targets:** semantics and announcements, contextual names,
  keyboard use, focus order/visibility/return, honest target geometry, size and
  spacing, contrast and color-independent state, reflow, zoom, and explanations
  for disabled states.
- **Visual and information architecture:** hierarchy, grouping, density and
  context, action and destination clarity, responsive and long-content
  composition, and coherent extensibility.
- **Interaction consistency:** stable rules across surfaces, entities, states,
  widths, and input methods. Compare recurring controls by visible and
  accessible labels, affordance, scope, outcome, risk, destination/return path,
  state, and responsiveness.

Like-looking or like-labelled controls should behave alike; different outcomes
should look and read differently. Keep selection, information, navigation,
disclosure, and mutation distinct. Equivalent rows and cards need predictable
targets; actionable lifecycle state must remain consistent.

## Apply blocker-based acceptance

Blockers are inaccessible critical paths, unusable reflow or focus order,
misleading targets, unsafe destructive behavior, unpredictable action scope,
and state or input inconsistencies that create stale assumptions. Blockers
outrank aggregate scores and visual polish. Callers may add stronger evidence
requirements, specialist vetoes, or thresholds.

Return evidence, defects, trade-offs, incomplete evidence, and blockers. A
standalone comparative preference does not advance a tournament or establish
convergence.
