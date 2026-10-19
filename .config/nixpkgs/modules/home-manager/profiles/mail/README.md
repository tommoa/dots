# Mail runtime

`mail.nix` packages the mail commands and Notmuch hooks together. The package
supplies Python, GnuPG, Notmuch, the configured OAuth-capable mbsync, and the
shell utilities used by the hooks. Darwin's `getconf`, `uuidgen`, and
`osascript` remain platform utilities; `getconf` is supplied by Nix and the
other two are available in the system path. Linux supplies `uuidgen` and
notifications through util-linux and libnotify.

IMAP notification callbacks, Aerc's update binding, and all password commands
use absolute package paths. They work without an interactive shell's PATH or
the development profile's `uv`. The repository's `~/bin/oauth2-gmail` launcher
finds the packaged command later on PATH, skipping itself and preserving its
arguments and exit status. It requires the Home Manager profile on PATH, with
no ambient Python dependency. The old update command and hook paths remain
symlinks to the shared sources for compatibility with existing checkouts.
Nix-managed Notmuch configs select the packaged hooks through
`~/.config/notmuch/runtime-hooks`.

## Credentials and startup

`mail-secret tommoa-password` resolves agenix's user runtime directory inside
Python and reads the iCloud password there. Home Manager treats
`passwordCommand` as an argv list and quotes its elements; a shell expression
embedded in `age.secrets.<name>.path` would otherwise become literal text.
The OAuth helper uses the same runtime-directory resolver. Credentials and
encrypted refresh tokens keep their existing locations and never enter the
package.

The mail GPG key import runs after creation of the GPG home and before service
reload. On Linux, notification services require the agenix oneshot service.
The secrets activation creates the Darwin agenix log directories before agent
setup, using the agent's configured stdout/stderr paths.
On Darwin, agenix and imapnotify are independent login agents; the existing
30-second restart policy allows imapnotify to recover if secrets are not yet
ready at login. Authentication errors are reported by the credential helper.

Darwin stdout/stderr logs live under `~/.local/state/imapnotify/`, in a directory
created with mode 0700 before the agents are installed. After applying a
configuration, inspect those logs and `launchctl print gui/$(id -u)/org.nix-community.home.imapnotify-personal`
to verify the process stays running. Process health alone does not establish a
successful authenticated IDLE session; check the log and actual notification
delivery when account operations are intended.

The update command's retry policy, hook copy/prune/move rules, and per-account
database layout are retained. Update serialization and retry-policy changes
remain separate work.

Managed Notmuch configs remain under `~/.config/notmuch`. The updater preserves
its existing `XDG_CONFIG_DIR` override; `XDG_CONFIG_HOME` does not relocate those
files. Generated configs select `runtime-hooks` without requiring an
evaluation-time build.
