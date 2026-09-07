---
name: commit
description: >-
  Draft commit messages or split plans, and create approved commits. Use for
  commit requests or message revisions, not general code review.
---

# Commit

Default to a read-only proposal. Stage or commit only when the current
conversation explicitly authorizes execution and approves the exact message and
scope of each commit. Tool or harness approval does not satisfy this gate.

## Inspect the change set

- With no target, inspect `git status --short`, staged and unstaged diffs, and
  untracked names. Report a clean worktree and stop.
- For staged-only or path-scoped requests, inspect index and worktree state,
  placing `--` before paths. Read relevant untracked files, but identify likely
  secret or key files by name without opening them.
- Treat revisions and ranges as read-only history reviews. Use `git show` or
  `git log -p`, return complete replacement messages, and do not stage or commit.

Ask a focused question if scope or operation is ambiguous. Infer intent from
repository guidance, relevant code, tests, and recent history. External sources
may verify public facts; disclose no private repository data or credentials.

## Draft the plan and messages

Prefer one reason per commit. Split unrelated behavior, refactoring, formatting,
or generated changes even within one file; identify partial hunks as needed.

For every proposed commit, provide:

1. The complete message and approved trailers in one block.
2. The exact files or hunks, ordered for a split plan.
3. Exclusions, assumptions, and unavailable validation.

Keep rationale that belongs in the body inside the message. Request values the
user reserved for later instead of filling them.

Follow local message conventions unless they conflict. Otherwise use
`<type>(<scope>): <imperative description>` without a trailing period. Only the
header is imperative. Write one or two flowing, declarative body paragraphs
wrapped at 72 characters. The body must stand alone: state the problem, explain
the approach and why it fits, then note non-obvious behavior, risk, or scope.
Name affected code, APIs, commands, or constraints in Markdown instead of
narrating the diff. Mention alternatives only with evidence. Never invent issue
references, sign-offs, co-authors, or trailers.

Keep each split coherent. Run meaningful checks for its state and disclose
checks that exercised only the working tree.

## Execute an approved commit

After the approval gate above:

1. If unrelated changes are staged, preserve them and stop until the user
   includes them or authorizes an isolation method.
2. Stage only the approved scope, including partial hunks.
3. Inspect `git diff --cached --stat`, `git diff --cached --check`, and the full
   `git diff --cached`; abort and report any unexpected file or hunk.
4. Pass the complete message through `git commit -F -` or a temporary file.
5. Report the commit SHA and remaining staged, unstaged, and untracked changes.

Repeat the approval and index checks for every commit in a split plan.
