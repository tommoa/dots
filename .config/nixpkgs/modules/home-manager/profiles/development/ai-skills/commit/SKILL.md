---
name: commit
description: Draft commit messages or split plans, and create approved commits. Use for commit requests or message revisions, not general code review.
---

Default to a read-only proposal. Do not stage or commit unless the current
conversation explicitly authorizes execution and approves the exact message and
scope for every commit. A harness or tool approval is not user authorization.

## Select the change set

Interpret the user's request rather than expecting skill arguments:

- With no narrower target, inspect `git status --short`, unstaged and staged
  diffs, and untracked file names. If the worktree is clean, report that and
  stop.
- For staged-only or path-scoped requests, inspect both index and worktree state
  for the requested paths, using `--` before paths. Read relevant untracked
  files directly; identify likely secret or key files without opening them.
- Treat revisions and ranges as read-only message reviews. Inspect them with
  `git show` or `git log -p`, return complete replacement message options, and
  never stage or commit while reviewing history.
- Ask a focused question when the requested path, revision, range, or intended
  operation is ambiguous.

Use repository guidance, nearby code, tests, and recent commit history before
inferring intent. External lookups may verify public facts, but must not expose
private paths, diffs, credentials, or proprietary code.

## Plan and write

Prefer one reason per commit. Split unrelated behavior, refactoring, formatting,
or generated changes even when they share files; identify partial hunks when
file boundaries are insufficient.

For every proposed commit, provide:

1. The complete message, including any approved trailers.
2. The exact files or hunks and, for split plans, their order.
3. Relevant exclusions, assumptions, and unavailable validation.

Render each complete message as one block; do not leave rationale that belongs
in the commit body only in surrounding prose.

Do not fill a message, issue reference, or other field that the user explicitly
reserved for later; request the missing value instead.

Follow local message conventions unless they conflict with these rules. When no
local convention applies, use a concise conventional header such as
`<type>(<scope>): <imperative description>` without a trailing period. Use
imperative mood only in the header. Write the body as one or two flowing,
declarative, non-imperative paragraphs wrapped at 72 characters.
The body must stand alone: start with the problem or pressure, explain the
chosen approach and why it fits, and note non-obvious behavior, risk, or scope.
Be specific about affected modules, functions, APIs, commands, or constraints;
do not merely narrate the diff. Mention alternatives only when evidenced by
code, history, issues, or user context. Use Markdown for identifiers and never
invent issue references, sign-offs, co-authors, or other trailers.

If unrelated changes are already staged, do not alter them or execute a commit
until the user chooses to include them or authorizes an isolation method. Keep
each commit in a split plan coherent and run relevant checks when they can
meaningfully validate that state; disclose when checks exercised only the
working tree.

## Execute an approved commit

After the exact message and scope are approved:

1. Stage only that scope. Do not stage an entire file when only selected hunks
   were approved.
2. Inspect `git diff --cached --stat`, `git diff --cached --check`, and the full
   `git diff --cached`. Abort and report any unexpected file or hunk.
3. Pass the complete approved message through `git commit -F -` or a temporary
   file; do not interpolate a multiline message into a shell command.
4. Report the commit SHA and remaining staged, unstaged, and untracked changes.

Repeat the approval and index checks for each commit in an approved split plan.
