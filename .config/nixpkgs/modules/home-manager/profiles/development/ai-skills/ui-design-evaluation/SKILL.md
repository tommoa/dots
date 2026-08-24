---
name: ui-design-evaluation
description: >-
  Apply UI-specific criteria, rendered evidence requirements, accessibility and
  recovery safeguards, and acceptance rubrics when evaluating, planning,
  comparing, or reviewing user interfaces.
---

# UI Design Evaluation

Evaluate whether people can understand and complete real work through a
truthful, accessible, coherent and recoverable interface. This skill supplies a
domain contract only: it does not choose candidate topology, dispatch judges,
advance a winner or claim convergence.

## Ground the evaluation

Use product-specific goals, roles, capabilities, scenarios and fixtures. Keep
them equal across alternatives, along with theme, viewport, input method,
permissions and available behavior. Resolve user-owned priorities when they
materially affect the criteria; do not invent product policy.

For each scenario, record the expected result and the observed path, including
hesitation, wrong turns, recovery and outcome. Use rendered evidence for visual,
geometry, focus, reflow and interaction claims. Source can corroborate semantics
or validation but cannot replace rendered behavior. Mark unavailable evidence
incomplete and unsupported capabilities not comparable; infrastructure failure
is not design evidence.

## Apply the domain lenses

Cover every applicable lens. They are criterion bundles, not mandatory actor
roles.

- **Operations and recovery:** task identification, decision cost, preserved
  context, truthful state, predictable lifecycle actions, correction and error
  recovery, destructive confirmation and unsaved-change safety.
- **Accessibility and targets:** semantic structure and announcements,
  contextual accessible names, keyboard operation, focus order/visibility and
  return focus, honest target geometry, target size and spacing, contrast and
  color-independent state, responsive reflow, zoom and disabled-state
  explanations.
- **Visual and information architecture:** hierarchy, grouping, density,
  context, action prediction, label and destination clarity, responsive and
  long-content composition, and credible extension without an undifferentiated
  dumping ground.
- **Interaction consistency:** stable rules across surfaces, entities, states,
  widths and input methods. For recurring controls, compare visible and
  accessible labels, affordance, scope, outcome, risk, destination/return path,
  state behavior and responsive/input behavior.

Equal-looking or equal-labelled controls should behave alike; materially
different outcomes should look and read differently. Selection, passive
information, navigation, disclosure and mutation must not masquerade as one
another. Equivalent rows and cards need predictable targets, and lifecycle
state must remain consistent wherever it affects action.

## Build relevant scenarios

Derive concrete scenarios from the product rather than a fixed application
catalogue. Consider routine work, repeated similar items, lifecycle transitions,
correction and recovery, long or empty histories, phone and intermediate widths,
keyboard and touch operation, and validation/loading/error states when relevant.

## Treat safety evidence as decisive

Inaccessible critical paths, unusable reflow or focus order, misleading targets,
unsafe destructive behavior, unpredictable action scope, and state or
input-method inconsistencies that can create stale assumptions are blockers.
Do not average them away or let visual polish outweigh them. A caller may impose
stronger evidence, specialist vetoes or thresholds, but must not weaken these
domain safeguards.

For a standalone evaluation, return concrete evidence, defects, trade-offs,
incomplete evidence and applicable blockers. Comparative preference is not a
tournament advancement or convergence decision.
