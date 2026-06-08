---
name: change-amplification
description: Find architecture debt in change history by identifying change amplification and missing boundaries
---

# Change Amplification Architecture Review

Use this skill to review change history as architecture evidence. The goal is not
to criticize individual PRs or commits, but to identify missing module
boundaries, owners, contracts, or drift checks that repeatedly make one
conceptual change spread across scattered files.

## Inputs

Analyze change units. A change unit is the reviewable unit that best captures one
intended conceptual change.

Supported input modes:

1. `prs`: merged PRs. This is the default when PR metadata is available.
2. `commits`: commits in an explicit revision range.
3. `range`: a git revision range; infer PRs or commits from available metadata.
4. `auto`: prefer merged PRs, then fall back to commits.

If no input mode is specified, use the last 50 merged PRs when available. If PR
metadata is unavailable and no revision range is provided, ask for the evidence
set instead of guessing.

For each change unit, inspect the title or subject, description or body, changed
files, tests, configs, docs, prompts, and any compatibility paths added or
changed.

## Task

Review the change units as architecture evidence.

Find PRs that show change amplification: one intended change forced edits across
multiple conceptually separate places because the architecture did not name one
clear owner, contract, or boundary.

Reject change units where the breadth was justified by a genuinely cross-cutting
feature, or where the change unit was itself a refactor.

Rank candidates by expected future leverage: prioritize missing boundaries that
are likely to cause repeated future edits, regressions, or inconsistent behavior.

## Candidate Report

For each candidate, report:

1. Intended change: the single conceptual change, usually from the PR title and
   description or commit subject and body.
2. Amplification evidence: the files, tests, configs, docs, or prompts that had
   to change. Cite specific paths.
3. Why this is architectural: explain why this was not ordinary feature breadth.
   Name the missing boundary, owner, or contract.
4. Better architecture: the smallest change that would make the next similar PR
   local.
5. Mechanical prevention: the test, type, lint, or contract check that would
   catch drift next time.
6. Deletion criterion: the temporary compatibility path that should be removed
   once the new owner exists.

## Output

Output a ranked backlog of architectural debt with change-unit evidence.

Do not output a list of bad PRs or bad commits. Output a list of missing
boundaries.

Use this structure:

```markdown
# Change Amplification Backlog

## 1. <missing boundary or owner>

- Evidence: <PR title and link, or commit hash and subject>
- Intended change: <single conceptual change>
- Amplification evidence: <specific paths and why they are separate concerns>
- Why this is architectural: <missing boundary, owner, or contract>
- Better architecture: <smallest localizing change>
- Mechanical prevention: <test, type, lint, or contract check>
- Deletion criterion: <compatibility path to remove>
- Expected leverage: <why this should pay off>

## Rejected Breadth

- <PR title and link, or commit hash and subject>: <why the breadth was
  justified or why it was a refactor>
```
