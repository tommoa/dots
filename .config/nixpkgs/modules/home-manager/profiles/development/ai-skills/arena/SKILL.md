---
name: arena
description: >-
  Compare or choose between materially different approaches to a consequential
  architecture, API, workflow, interface, implementation, or other artifact
  when competing shapes could materially affect the outcome.
---

# Arena

Run one frozen, auditable comparison, then return a verified artifact and round
record. The workflow ends after this round.

## Guardrails

- Candidates are separate subagent executions. Judges are different, read-only
  subagent executions. Coordinator passes, role-play, and separate prompts are
  not independent evidence.
- If independent actors or isolated writable destinations are unavailable,
  stop before synthesis and return the framing and blocker. For read-only work,
  candidates write only to isolated temporary destinations.
- Preserve the user's goal, permissions, and writable scope. If the user chose
  a model, pass that exact model to every actor and nested delegation;
  otherwise choose suitable models. Record each choice and propagate it through
  nested calls.
- Drain every candidate before judging. Judges receive complete outputs only.
- Record each actor's ID, role, model, destination, terminal status, and
  evidence paths.

## 1. Frame

Use an arena only when alternatives could materially change an
expensive-to-reverse structure, interface, workflow, argument, or artifact.
Before spawning, freeze:

1. **Candidate contract (visible):** artifact and output format, outcome, every
   requirement, invariants, scenarios, non-goals, permissions, shared facts,
   and required checks.
2. **Judge metadata (judge-only):** three to six observable, non-duplicative
   criteria; weights or tie-breakers; probes; and blocker rules. Requirements
   belong in the candidate contract, not hidden here.
3. **Execution policy:** candidate count and models, isolation, arena mode,
   synthesis policy, verification, and round budget. Default to three
   candidates; two is the minimum.

Preserve caller-supplied frozen inputs unchanged. Otherwise apply the evidence
requirements, criteria, and vetoes from any relevant domain-evaluation skill;
derive them from the task when none applies. Domain skills strengthen
evaluation but do not orchestrate the arena.

Discover facts yourself. If a user-owned choice could change the contract,
rubric, or policy, use `grilling` and wait for confirmation before freezing.

Choose one mode:

- **Ordinary:** provide the full artifact. Use identical hypotheses to test
  agreement, or predeclare materially different hypotheses. Cosmetic variation
  is not diversity.
- **Blind exploration:** provide identical requirements and sanitized facts;
  withhold incumbent presentation, implementation, lineage, votes, and prior
  structural evidence. Require distinct hypotheses, redirect duplicates before
  implementation, and record exactly what each candidate received.
- **Targeted challenger:** freeze one incumbent and one falsifiable hypothesis.
  Give each candidate the unchanged incumbent and an isolated child retaining
  its invariants and excluding unrelated cleanup.

Give every candidate the same contract, facts, and repository rules, plus only
its hypothesis and destination. Hide judge metadata and actor identity, model,
and chronology. After spawning, a new requirement or criterion invalidates
every affected comparison: return **reframing-required**, or rerun all affected
candidates only when the frozen budget permits. Never patch or regrade a
favored subset.

**Frame complete:** contract, judge metadata, execution policy, mode, and all
material preferences are frozen.

## 2. Spawn and drain

Launch candidates as separate calls, concurrently where possible. Each returns:

- the complete artifact at its isolated destination;
- concise rationale and rejected alternatives;
- checks, evidence, and unknowns; and
- assumptions, limitations, and unresolved decisions.

Drain every call and record dropouts. With fewer than two independent usable
candidates, stop before judging or synthesis.

**Generation complete:** every candidate finished or dropped out, and at least
two independent usable candidates remain.

## 3. Judge

Normalize candidates to neutral labels, removing lineage, model, and chronology
cues. Spawn one or more independent, read-only judges, scaling topology with
risk and required domain lenses. Prefer a different model family when the user
did not fix one. Judges receive the frozen contract, judge metadata, and every
complete artifact and rationale.

Judges support every criterion with concrete evidence; mark each required item
**supported**, **contradicted**, or **unknown**; identify blockers and missing
verification; recommend a whole-artifact base; and name compatible borrow
ideas. Required unknowns and verified blockers prevent selection. Unequal facts
are a grounding failure, not a quality difference. Domain rules may strengthen
evidence, vetoes, or thresholds, never weaken them.

The coordinator reads every artifact and rationale, reconciles disagreements
against evidence, and records the verdict.

**Judging complete:** every criterion has an evidence-backed disposition,
blockers and unknowns are recorded, and the verdict is reconciled.

## 4. Synthesize

Select the strongest whole artifact as base, then apply the frozen policy:

- **Composable:** graft compatible ideas while preserving one mental model.
- **Coupled/judgment-sensitive:** create an attributable child of the unchanged
  base and compare it directly with its parent.
- **Indivisible:** choose one whole candidate, or report that none is usable.

Attribute every material graft and explain every rejection. Exclude conflicting
assumptions and source blockers. A shared defect may receive the same neutral
repair in isolated copies, but that repair is not evidence of superiority.

**Synthesis complete:** one artifact is selected and every graft or
rejection is recorded under the chosen policy.

## 5. Verify and return

Verify with real domain evidence: examples, invariants, callers, and failure or
extension checks. Candidate self-report is not verification. Compare with the
unchanged base when synthesis risks coupled or subjective regressions. For
design-only work, keep implementation out of scope and mark runtime claims
unverified.

Return the verified artifact plus a compact record of the frozen inputs,
actors/dropouts and neutral labels, criterion evidence and verdict, selected
base, grafts and rejections, verification, blockers, unknowns, remaining
uncertainty, and useful borrow ideas or next hypotheses. If stopped before
synthesis, return only framing, evidence, actor/dropout records, and blockers.
Do not advance an incumbent or claim convergence.

**Round complete:** the verified artifact and round record are returned, or the
relevant blocker and evidence are returned instead.
