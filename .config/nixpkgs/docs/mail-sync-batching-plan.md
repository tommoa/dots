# Plan: batch mail notifications and reduce sync time

Status: proposed; no runtime changes or activation performed for this plan.
Date: 22 October 2026.

This extends the implemented account-lock design in the
[mail updater](../modules/home-manager/profiles/mail/update-mail.sh). The decision to defer
coalescing is revisited because notification callbacks have now been observed
performing repeated, expensive full-account updates.

## Goal and scope

Let imapnotify record work quickly, combine notifications received together,
and avoid running a full scan for every notification. Then measure and reduce
the cost of each scan. Keep the existing POSIX-sh updater and Notmuch hooks.

The first rollout still syncs the whole account. Recording notified folders
does not yet mean that they are a complete selection: the hooks also prepare
local archive/delete changes, and Notmuch writes read flags into other folders.
Reducing remote folder selection without accounting for those local changes is
a separate change. It is not a prerequisite for coalescing notifications.

Deferred: a replacement for the tag/folder reconciliation model, per-message
baselines, editor-maintained pending tags, afew, and upstream notifier changes.
Faster updates reduce the duration of the existing concurrent-edit race; they
do not make that race correct.

## Evidence and expected benefit

- goimapnotify 2.5.5 executes a callback synchronously. A long callback prevents
  its event loop from dispatching further notifications. It has a buffered
  event queue and generates an initial event for each watched mailbox.
- The callback currently runs a complete `update-mail` for every delivered
  event. Recent work updates took roughly 106–150 seconds, with some longer
  runs. Time waiting inside the notifier is additional to these update times.
- Alternating live work-account scans measured sequential updates at 38.7 and
  39.7 seconds, versus 51.0 and 49.2 seconds with four one-folder workers.
  Sequential used one authentication; parallel used 20 workers plus discovery.
  These scans did not measure a controlled bulk download.
- The pre-new hook uses one mbsync process per account update, reusing its
  connection. The Gmail credential helper refreshes a token on each invocation.

For example, seven startup notifications can become one account update instead
of seven successive updates. Events arriving after a batch starts may still
require a follow-up. Batching cannot promise that `w` disappears if genuine
changes continue arriving faster than the account can be synced.

## 1. Keep the command boundary small

Keep `update-mail` responsible for account selection, account locks, queue paths,
and update execution. Add an explicit `--enqueue` mode for notification
callbacks, plus a private worker entry point. Do not change behaviour merely
because the diagnostic source says `imapnotify`.

The mailbox metadata and event diagnostics below are proposed additions; the
current updater does not collect them.

The callback becomes approximately:

```sh
account=work mail_sync_source=imapnotify \
  mail_sync_mailbox_hex=... /nix/store/.../bin/update-mail --enqueue
```

Keep the existing safe Go-template hex encoding. A queued notification requires
one valid account. With no mailbox supplied, enqueue a full-account request;
this also supplies a simple way to request another background attempt.
Malformed mailbox metadata must fail visibly rather than silently lose work.

Ordinary `update-mail`, account selection, and `--status` remain available.
Aerc and terminal updates remain synchronous and return their own result.
Different accounts remain independent. Every update uses the full channel
patterns; mailbox metadata describes notifications, not a folder selection.

## 2. Store pending and unfinished work separately

Use a private directory beneath the existing mail-sync state directory for
each account. Its files are:

| File | Meaning |
| --- | --- |
| `pending` | Notification records received since the previous batch was taken |
| `inflight` | Records claimed by an update but not yet successfully completed |
| `queue.lock` | A brief lock for appending, claiming, acknowledging, and handoff |
| `worker.lock` | Ownership of the one background coordinator for this account |

Retain the existing top-level `<account>.lock` for actual account updates and
tmux status. Nested queue locks must not appear as additional active accounts.
Stable lock files are never removed to represent unlocking.

Store one hex-encoded mailbox per line, with a distinct full-account marker.
This reuses notifier metadata and keeps whitespace and shell punctuation out
of the queue protocol. Append records without deduplicating on every callback;
deduplicate once when taking a batch. The queue records folder work, not a list
of shell commands or a second message database.

Under the queue lock, append the complete record and check the write result.
Queue persistence is required, unlike best-effort diagnostic logging. This is
process-crash recovery using normal filesystem operations, not a promise of
transactional durability across power loss.

The callback then starts a small worker candidate and returns. A candidate
tries `worker.lock` without waiting and exits successfully if a coordinator
already owns it. Distinguish an occupied lock from an operational error. Thus
there is at most one background coordinator waiting for an account, rather
than one long-lived updater waiting for every notification.

Use a short-lived shell worker, not a new permanent service. Redirect its
stdin, stdout, and stderr explicitly to `/dev/null` and private per-account
logs as appropriate. In particular, it must not inherit the pipes used by
Go's `Command.Output()`, which would keep the supposedly short callback open
until the background sync finished. Close inherited queue descriptors too.
Use the packaged runtime for worker re-entry; do not depend on an interactive
PATH. A worker launch failure must be reported while leaving the record queued.

## 3. Take, run, and acknowledge batches

The first coordinator waits a fixed one second before taking its first batch.
This gives adjacent startup callbacks time to append without adding an
indefinitely reset debounce timer. Do not add another delay between batches
when work is already pending.

For each batch:

1. Acquire the existing account lock, without holding the queue lock while
   waiting. This also batches notifications that arrive behind a manual update.
2. Under the queue lock, combine any unfinished `inflight` records and current
   `pending` records into an atomic replacement for `inflight`. Clear only the
   pending records included in that replacement. Retain recoverable originals
   if writing or renaming fails. An empty batch needs no account update.
3. Release the queue lock, and run the normal full-account update while keeping
   the account lock. Appends continue independently throughout the sync.
4. Only after the complete Notmuch command succeeds, acknowledge `inflight`
   under the queue lock. A successful mbsync alone is not sufficient.
5. Release the account lock. If more requests accumulated, take another batch;
   otherwise finish the coordinator handoff below.

The account lock protects ownership of `inflight` as well as mail execution.
Never take the account lock while holding the queue lock. This lets foreground
updates use the same batch operations without taking coordinator ownership.

On normal shutdown, check the queue and release `worker.lock` while still
holding the queue lock. Only then release the queue lock and exit. A callback
must therefore either leave its record for the existing coordinator to see,
or append after coordinator ownership was released and start a replacement.
Do not rely on an unlocked empty-check followed by process exit.

Keep `worker.lock` in the coordinator only: close its descriptor in actual
update subprocesses. Conversely, preserve inheritance of the account lock in
Notmuch, its hooks, and mbsync. If a coordinator is killed but its old mail
children remain, a replacement can own coordination and wait for the old
account update to finish without allowing overlapping mail work.

## 4. Foreground updates, failure, and cancellation

A normal foreground full-account update takes its account lock and claims any
queued records using the same operations. Its successful full update can
acknowledge those records. A background coordinator already waiting for that
lock will then find no work unless more notifications have arrived. The
foreground invocation still runs its own one update even if there was no queue.

On failure or interruption, retain `inflight` and any newer `pending` records.
The failing background coordinator exits with an error and does not launch its
own retry. A later notification, explicit enqueue, or foreground full update
can make another attempt. Notifications already queued at failure are retained
but do not force an immediate retry loop. A notifier restart normally generates
fresh startup notifications that also wake recovery.

SIGKILL requires no trap to preserve an already-written `inflight` batch.
Recovery waits for the account lock before touching it. A record appended just
before its callback is killed may need a later enqueue to start a worker; this
design does not add a permanent supervisor to guarantee an immediate wakeup
after every process crash.

Ctrl-C of a foreground update affects that invocation and retains its ordinary
exit status. It does not cancel independently requested background work. The
account stays busy until its mail children release the account lock. Already
committed filesystem, Notmuch, and server changes are not rolled back.

Background failures belong in the worker log and event diagnostics, since the
enqueue callback has already returned successfully. Tmux continues to show
actual account-lock ownership, not queued work, the batching delay, or a
persistent error marker. No new aerc status machinery is needed.

## 5. Measure and improve transport separately

Land queueing before changing concurrency, so its effect can be measured on
its own. Add enough request-source and batch information
to distinguish received notifications from actual account-update attempts:
batch identity, notification count, unique notified folders, actual selection,
queue wait, update duration, and exit status. Do not describe a notified folder as the
actual selection when the batch still performs a full update.

Add focused timings for discovery and folder transfers. Avoid raw protocol
debug logs or message contents for routine measurement. Use the resulting
timings to distinguish connection overhead, one slow folder, and hook/indexing
cost rather than attributing the whole duration to mbsync.

The baseline is one mbsync process for the full channel. If representative
incoming-mail batches show a transport bottleneck, compare it with a small
number of processes handling several folders each. Measure connection and
credential-command reuse, elapsed time, failures, and aggregate transferred
messages and bytes before adopting parallelism. Grouping can strand folders
behind a slow folder, and connections have provider-specific limits. Prefer a
fixed simple grouping if it provides a measured benefit; do not add a
persistent access-token cache here.

Keep work's 120-second inactivity timeout. Do not shorten it to improve apparent
latency, skip folders, change flags/expunge behaviour, or recreate sync state.
Run one experiment at a time, allowing its current batch to finish before
changing arrangements. Compare repeated idle scans and normal incoming-mail
batches; different live workloads make a single before/after run inconclusive.

## Validation and rollout

Use temporary state directories and stub mail commands for deterministic tests:

- A burst of callbacks returns before a gated sync finishes, combines duplicate
  folders, and produces one claimed batch rather than one scan per callback.
- A notification after the claim remains for a second batch, including another
  notification for a folder already in the current batch.
- Appending during the final empty-check/handoff cannot strand normal work.
- At most one background coordinator waits; different accounts remain independent.
- Foreground full updates satisfy their claimed queue. Status probes cannot
  strand queued requests.
- Failed, interrupted, and killed batches retain their records. A later wakeup
  recovers them; ordinary failures do not cause an internal retry loop.
- Killing a coordinator releases its ownership lock while actual mail children
  still retain the account lock. A replacement waits without overlapping them.
- Queue IO and launch failures are visible. Literal folder names remain data.
- Queued batches sync the full account; diagnostic source labels alone never
  select queueing behaviour.
- Actual Go-template/callback execution returns promptly with a gated background
  worker, proving that inherited output pipes do not block `Command.Output()`.
- Existing account selection, full-channel sync, tagging, draft, and cancellation checks
  still pass with the packaged mail utilities and flock.

Build the runtime and affected Home Manager/Darwin configurations before
activation. Evaluate the Linux configuration and validate the queue lifecycle
there too before claiming cross-platform runtime support.

For the handoff, temporarily stop notification services, let active account
updates finish, install the new runtime/callbacks, and restart notification
services. Inspect the first startup burst, queue files, worker errors, request
counts, and actual successful updates. Roll out queueing with the existing
sequential transport first; run transport experiments as a separate step.

Rollback requires stopping notifiers and new coordinators, letting mail children
finish, and preserving queue files before restoring the old callbacks. Run a
successful full-account update to cover retained requests before retiring queue
state. Old callbacks cannot interpret the new queue by themselves.

## Later gate for selective notification updates

Use the accumulated folder data to decide whether selective syncing would buy
enough to justify tracking local work. Before enabling it, account for source
and destination folders of copies/prunes/moves, locally written drafts, read
and other Maildir flags, and previously unfinished uploads. Recording hook
copy destinations alone is insufficient. Preserve a full-update path for
unwatched folders and recovery.

This plan does not introduce that bookkeeping or claim that the queue is a
complete dirty-folder set. Make that decision after measuring coalescing and
transport improvements.
