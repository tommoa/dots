---
name: council
description: Trigger this if the user says 'council'.
metadata:
  upstream-source: https://github.com/t3dotgg/tstack/blob/main/skills/council/SKILL.md
  upstream-revision: 11e37a74d0a6868c121cd0910ab2b3bd9873b92a
  upstream-license: https://github.com/t3dotgg/tstack/blob/11e37a74d0a6868c121cd0910ab2b3bd9873b92a/LICENSE
---

# Council

Before an audit, address outstanding PR comments, fix known issues, and run
relevant checks. Give council the updated implementation; do not defer known
fixes until reviews return. If the user wants to discard the implementation
and explore new ideas, skip fixes to code being replaced.

Bring in three delegates to help with the user's request, usually for review
or feedback, at high reasoning effort. If the user's instructions name council
members, use those, honoring their requested count, models, effort, and provider
route. Otherwise choose suitable models using `model-selection`. Different
models or providers can add perspectives but are not required; for example,
Sol and Terra may use the same provider.

In T3 Code, use `orchestrator_capabilities` to resolve the models, then
`delegate_task` to start one delegate per model in parallel. Elsewhere, use
the harness's subagent tools. If a required member is unavailable, report it
instead of substituting. Optional members do not block the panel.

Give each delegate the request and relevant context, using a fresh context
window and the same artifact snapshot. Do not reveal prior verdicts or the
user's target score. For review or feedback, keep their work read-only.
Collect their responses and summarize the useful findings, disagreements, and
recommended next steps.

Do not wait idle. When a result arrives, check its findings against the code
at once and decide what to fix while the other delegates run. Do not edit
files while a delegate still reviews the same checkout. If the user's
instructions mark a delegate as non-blocking, do not wait for it; treat a
late result as feedback and do not record its score.

For a review, ask each delegate for a score out of 10.
Count each full review pass as one round.
A fresh review after fixes starts a new round.

If the work ends in a pull request, put the results in the PR description.
Put this section before the model and harness line at the end:

```markdown
## Council review

Rounds: 2

| Delegate | Round 1 | Round 2 |
| --- | --- | --- |
| GPT Sol | 7/10 | 9/10 |
| GPT Terra | 8/10 | 10/10 |
| Gemini Flash | 7/10 | 9/10 |
```

If a delegate gives no score, write `no score`. Do not invent one.
If the PR is open, edit the description. Do not post a comment for this.
If there is no PR, put the same results in the final reply only.

If you agree with their recommendations, make the changes and request a fresh
review after. Continue this process until all delegates are satisfied with the
outcome.

Do not let repeated reviews result in scope creep. It is your job to fight to
keep scope limited.
