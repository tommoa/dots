---
name: change-amplification
description: Review PR or commit history for change amplification that reveals missing architectural boundaries.
---

# Change Amplification

Review change history as architecture evidence. Find conceptual changes that
spread across separate concerns because the system lacks one clear owner,
contract, or boundary. Produce a backlog of missing boundaries, not a critique
of individual changes.

## Evidence set

Accept four modes: `prs` uses merged PRs; `commits` uses an explicit revision
range; `range` infers PR or commit units from available metadata; and `auto`
prefers merged PRs, then commits from an explicit range. With no requested
scope, review the last 50 merged PRs. If neither PR metadata nor a revision
range is available, ask for the evidence set.

Treat each PR or commit as one change unit. Inspect its title and body, changed
files, tests, configuration, documentation, prompts, and compatibility paths.

## Review

For each plausible candidate:

1. State the intended conceptual change.
2. Cite the paths changed across conceptually separate concerns.
3. Distinguish missing-boundary amplification from legitimate cross-cutting
   work or a refactor; reject the latter and record why.
4. Name the missing owner, contract, or boundary.
5. Propose the smallest architectural change that would localize the next
   similar change, plus a test, type, lint, or contract check that would catch
   future drift.

Rank accepted candidates by expected future leverage: repeated edits,
regressions, and inconsistent behavior that the boundary would prevent.

## Output

Return a **Change Amplification Backlog** ranked by expected leverage. For each
item include:

- the missing boundary or owner;
- PR title and link, or commit hash and subject;
- intended change and path-level amplification evidence;
- why the breadth is architectural;
- the smallest localizing change and mechanical prevention;
- the deletion criterion for any temporary compatibility path, or `None`;
- expected leverage.

End with **Rejected Breadth**, listing broad changes excluded as genuinely
cross-cutting or refactors and the reason for each exclusion.
