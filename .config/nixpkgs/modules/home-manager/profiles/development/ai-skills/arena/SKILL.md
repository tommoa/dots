---
name: arena
description: >-
  Compare or choose between materially different approaches to a consequential
  architecture, API, workflow, interface, implementation, or other artifact
  when competing shapes could materially affect the outcome.
---

# Arena

Use this single-round workflow to make a consequential choice visible and
testable. It does not expand the user's request, permissions, or writable
scope. For read-only work, candidates write proposals in temporary
destinations, not the target. The `arena-loop` skill owns immutable incumbents,
cross-round advancement, backlog, repeated challenges, and convergence.

## Non-negotiables

- A candidate is a separate subagent execution. A judge is another separate,
  read-only subagent execution. Never simulate candidates, role-play a judge,
  or count your own passes as independent evidence.
- If delegation cannot create and run the required independent executions,
  stop before synthesis and report the framing plus the blocker. Do not
  silently continue with an internal or single-agent arena.
- If the user explicitly selected a model, pass that exact model to every
  candidate, judge, and nested delegation. Otherwise choose models appropriate
  to the task; record the choice and propagate it through nested calls.
- The order is strict: spawn all candidates concurrently where possible, drain
  or wait until each has finished or dropped out, then spawn the judge. Never
  judge partial outputs or synthesize before judging.
- Keep each candidate's writable state isolated in a worktree or unique
  temporary directory. Separate prompts or turn-taking do not provide
  isolation.
- Record each actor's ID, role, model, destination, terminal status, and
  evidence paths so claimed independence and completion remain auditable.

## 1. Frame

Run one arena round only when alternatives may change structure, interface,
workflow, argument, or another expensive-to-reverse decision. Before spawning,
freeze:

1. **Candidate contract (visible):** the artifact and output format; intended
   outcome; every real user requirement; invariants, scenarios, non-goals,
   scope/permission boundary, shared facts or snapshot, and required checks.
2. **Judge metadata (judge-only):** three to six observable criteria, weights
   or tie-breakers, diagnostic probes, and blocker rules. Do not hide a real
   requirement: candidates must see it in the contract.
3. **Execution policy:** candidate count, models, isolation, exploration mode,
   synthesis mode, verification, and budget for this round. Default to three
   candidates; two is the minimum useful comparison.

If a caller supplies a frozen candidate contract and judge metadata, preserve
them unchanged. Otherwise, before freezing, apply any relevant domain-evaluation
skill to the criteria, evidence requirements and vetoes. Do not hard-code
domain skills or let them take over candidate or judge orchestration. If no
domain skill applies, derive the rubric from the task and available evidence.

Before freezing, separate discoverable facts from user-owned choices. If an
unresolved choice could change the contract, rubric, or execution policy,
invoke the `grilling` skill and wait for the user's confirmation. Do not infer
preferences from suggestive wording or from your own recommendations.

Choose one mode:

- **Ordinary:** give candidates the full relevant artifact. Use identical
  hypotheses to test independent agreement, or predeclare materially different
  hypotheses when the decision space warrants them. Cosmetic variation is not
  diversity.
- **Blind exploration:** give candidates identical requirements and sanitized
  domain facts, but withhold incumbent presentation, implementation, lineage,
  votes and prior visual or structural evidence. Require materially different
  hypotheses and redirect duplicates before implementation. Record exactly what
  each candidate received.
- **Targeted challenger:** freeze the incumbent and one falsifiable hypothesis.
  Give every candidate the unchanged incumbent and create isolated children
  that retain stated invariants and avoid unrelated cleanup. When borrowing an
  idea, identify its source and exclude any source blocker that cannot be
  separated from it.

Audit the metadata for observable, non-duplicative criteria. At the end of
framing, record and freeze the candidate contract, judge metadata, and
execution policy for this round. After spawning, no actor may add a requirement
or criterion, silently alter the contract, or retroactively grade only some
candidates. If judging, synthesis, or verification reveals a genuinely new
requirement or criterion, invalidate the comparison for every affected
candidate: return a **reframing-required** blocked round, or rerun the entire
affected comparison under the revised framing only if the already frozen round
budget permits it. Never silently patch one artifact or claim cross-round
convergence. Give every candidate the same contract, grounding, and repository
rules, plus only its hypothesis and destination. Targeted candidates also
receive the unchanged incumbent; blind-exploration candidates must not receive
it or its presentation and implementation evidence. Do not reveal candidate
identity, model, chronology, or judge-only metadata.

## 2. Spawn and drain

Launch all candidates as separate subagent calls. Require each to return:

- the complete artifact at its isolated destination;
- a concise rationale, including alternatives rejected;
- checks performed, evidence and unknowns; and
- assumptions, limitations, and unresolved decisions.

Drain or wait for every call before proceeding. Record dropouts. If fewer than
two independent usable candidates remain for the intended comparison, stop
this round before judging or synthesis and report the blocker.

## 3. Judge

After the drain completes, normalize candidates to neutral labels and remove
lineage, model, and chronology cues. Spawn one or more separate, independent,
read-only judges; scale actor topology with risk and any required domain lenses,
and prefer a different model family when no user model was fixed. Every required
criterion still needs evidence when one judge covers several lenses. Judges
receive the contract, judge-only metadata, and complete candidate artifacts and
rationales—never partial outputs. Propagate the selected model to any nested
delegation.

The judge scores every criterion with concrete evidence, marks each required
item **supported**, **contradicted**, or **unknown**, identifies blockers and
missing verification, recommends a whole-artifact base, and names compatible
ideas worth borrowing. Unknown required evidence blocks selection; absence of
evidence is not a pass. Differences caused by unequal facts indicate grounding
failure, not quality. Domain evaluation may strengthen required evidence,
specialist vetoes or selection thresholds, but never weaken these rules.

Read every artifact and rationale yourself, reconcile disagreements against the
evidence, and record the verdict. Verified blockers prevent selection.

## 4. Synthesize

Select the strongest whole artifact as base, then use exactly one policy chosen
in framing:

- **Composable:** hand-graft compatible ideas while preserving one mental model.
- **Coupled/judgment-sensitive:** make an attributable child from the unchanged
  base and compare it directly with its parent.
- **Indivisible:** choose a whole candidate; if no candidate is usable, report
  the blocker without manufacturing a result.

Record each material graft with its source and each rejection with its reason.
Do not combine ideas with conflicting assumptions or inherit a blocker. When a
shared defect prevents fair comparison, apply only an identical neutral repair
to isolated copies and do not count that repair as evidence of superiority.

## 5. Verify and return

Verify the synthesized artifact using real domain evidence, examples,
invariants, callers, and failure or extension checks—not candidate self-report.
Compare against the unchanged base when synthesis could introduce coupled or
subjective regressions. Mark runtime claims unverified rather than implementing
merely to test a design-only request.

Return one verified artifact when established, plus a compact round record:
the frozen contract and judge-metadata summary; actor/dropout records and
neutral labels; judge verdict and criterion evidence; selected base; grafts and
rejections; verification; blockers, unknowns, and remaining uncertainty; and
compatible borrow ideas or next hypotheses for the caller. If stopped before
synthesis, return only framing, evidence, actor/dropout records, and blockers.
Do not claim cross-round convergence or advance an incumbent: the `arena-loop`
skill alone owns those decisions.
