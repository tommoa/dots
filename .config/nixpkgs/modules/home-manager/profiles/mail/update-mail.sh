#!/bin/sh

# When this script is called from aerc or imapnotify, $account is set to
# the name of the account, and that can be used to grab the notmuch config.
# Otherwise, if $account is not set, then go through every available
# notmuch config.
#
# --status lists every account currently updating, regardless of $account.
# It only checks the locks and doesn't start an update.

# The lock files stay here between runs. Their presence doesn't mean
# anything is running; holding the lock does.
state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/mail-sync"

# Managed Notmuch configs live in ~/.config. XDG_CONFIG_DIR can override it.
config_dir="${XDG_CONFIG_DIR:-${HOME}/.config}/notmuch"

case "$#:${1-}" in
    0:) ;;
    1:--status)
        # If no updates have run yet, there's nothing to check.
        [ -e "$state_dir" ] || exit 0
        if [ ! -d "$state_dir" ] || [ ! -r "$state_dir" ] || [ ! -x "$state_dir" ]; then
            printf 'Cannot read mail sync state: %s\n' "$state_dir" >&2
            exit 1
        fi
        result=0
        for lock_file in "$state_dir"/*.lock; do
            [ -f "$lock_file" ] || continue
            # If we can take a shared lock, this account isn't updating. An
            # update holds an exclusive lock, which makes flock return 75.
            # Other failures mean we couldn't check; they shouldn't make the
            # account look idle.
            code=0
            (flock -s -n -E 75 9) 9<"$lock_file" || code=$?
            case "$code" in
                0) ;;
                75)
                    name=${lock_file##*/}
                    printf '%s\n' "${name%.lock}"
                    ;;
                *)
                    printf 'Cannot inspect mail sync lock: %s\n' "$lock_file" >&2
                    result=1
                    ;;
            esac
        done
        exit "$result"
        ;;
    *)
        printf 'Usage: update-mail [--status]\n' >&2
        exit 2
        ;;
esac

# If we're interrupted, don't carry on with the remaining accounts.
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# If $account is set, then use ${config_dir}/${account}.
if [ -n "${account-}" ]; then
    # An account is the name of a config file, not a path.
    case "$account" in
        */*|.|..) printf 'Invalid mail account: %s\n' "$account" >&2; exit 2 ;;
    esac
    if [ ! -f "${config_dir}/${account}" ]; then
        printf 'No Notmuch configuration for account: %s\n' "$account" >&2
        exit 1
    fi
    set -- "${config_dir}/${account}"
else
    # No account selected, so use each config. Keep filenames separate in
    # case the config path contains spaces.
    set -- "${config_dir}"/*
fi

# Only the user running the updates needs access to these locks.
umask 077
mkdir -p "$state_dir" || exit 1
result=0
for name do
    [ -f "$name" ] || continue
    # Wait for this account's previous update. flock passes its lock to
    # Notmuch and its children, so they keep it even if this shell exits.
    # Leave the file in place: another updater may already be waiting on it.
    flock -x "$state_dir/${name##*/}.lock" notmuch --config="$name" new
    code=$?
    # Try the other accounts after an ordinary failure, but stop if this
    # update was interrupted. A later notification can retry failed work;
    # retrying here would loop forever if a server stays unavailable.
    case "$code" in
        129|130|143) exit "$code" ;;
        0) ;;
        *) result=$code ;;
    esac
done
exit "$result"
