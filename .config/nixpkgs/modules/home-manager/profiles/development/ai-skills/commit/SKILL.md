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
  untracked names. If the worktree is clean, report that and stop.
- For staged-only or path-scoped requests, inspect index and worktree state,
  placing `--` before paths. Read relevant untracked files, but identify likely
  secret or key files by name without opening them.
- Treat revisions and ranges as read-only history reviews. Use `git show` or
  `git log -p`, return complete replacement messages, and do not stage or commit.

Ask a focused question if scope or operation is ambiguous.

## Draft the plan and messages

Prefer one reason per commit. Split unrelated behavior, refactoring, formatting,
or generated changes even within one file; identify partial hunks as needed.

Match the deliverable to the request:

- For message-only requests or revisions, return the complete message and
  approved trailers in one block.
- For commit proposals, also identify the exact files or hunks and relevant
  exclusions, assumptions, and validation gaps.
- For split plans, provide a complete message and scope for each commit in
  execution order. Keep each split coherent.

Request values the user reserved for later instead of filling them. Never
invent issue references, sign-offs, co-authors, or trailers.

Follow explicit user requirements, then compatible repository conventions.
Otherwise use `<type>(<scope>): <imperative description>` without a trailing
period.

For drafting-only work, use available validation evidence; disclose relevant
gaps when proposing commits or split plans. Do not construct intermediate
commit states to test a proposed split.

### Write the body

The body's purpose is to explain why someone would want to merge the change.
Lead with the problem, unmet need, or constraint and its consequences, then
explain how the change improves the situation. The rationale must stand alone
inside the message; a reader should understand the value of merging without
reading the diff or the surrounding conversation.

Before drafting the rationale, gather relevant context from repository
guidance, surrounding code, tests, recent history, and the conversation.
Distinguish supported reasons from assumptions. If the motivation remains
uncertain or clarification would materially affect the message, ask the user a
focused question before finalizing it. Do not invent a rationale to fill the gap.
External sources may verify public facts; disclose no private repository data
or credentials.

- Use declarative prose throughout the body. Only the header is imperative;
  the body must not read as instructions or a to-do list.
- Use Markdown in the body: backticks for code, APIs, commands, and paths;
  links for relevant references; and lists when they make distinct reasons or
  trade-offs easier to read. Prefer flowing paragraphs when they suffice.
  Wrap prose at 72 characters without breaking inline code or link targets.
- Include what changed or how it works only when that detail explains the
  rationale, a trade-off, or a non-obvious consequence. Avoid file-by-file
  summaries and narration of the diff.
- Mention alternatives, risks, and scope constraints only when they help assess
  the reason for merging.

For example, assuming filenames containing spaces caused failures, a body such
as "Quote the path passed to the formatter" merely repeats the implementation
and uses the imperative. A useful body would be:

```text
Files with spaces in their names cannot be formatted because the shell
splits the path into multiple arguments. This blocks the formatting
workflow for otherwise valid filenames.

Quoting the path passed to `formatter` keeps each filename as one argument
so those files can use the same workflow.
```

Before presenting a message, check that its body answers "Why is this change
worth merging?" rather than merely "What did the diff do?", uses declarative
prose, and applies Markdown formatting where appropriate.

## Execute an approved commit

After the approval gate above:

1. If unrelated changes are staged, preserve them and stop until the user
   includes them or authorizes an isolation method.
2. Stage only the approved scope, including partial hunks.
3. Inspect `git diff --cached --stat`, `git diff --cached --check`, and the full
   `git diff --cached`; abort and report any unexpected file or hunk.
4. Run meaningful checks for the approved commit's state within the authorized
   scope. Disclose any untested state or checks that exercised only the combined
   working tree; those checks do not establish that each split passes on its own.
5. Pass the complete message through `git commit -F -` or a temporary file.
6. Report the commit SHA and remaining staged, unstaged, and untracked changes.

Repeat the approval and index checks for every commit in a split plan.
