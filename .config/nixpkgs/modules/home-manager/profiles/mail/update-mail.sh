#!/bin/sh

# When this script is called from aerc, $account is set to the name of
# the account in aerc, and that can be used to grab the notmuch config.
# Otherwise, if $account is not set, then go through every available
# notmuch config.

# Update emails using various notmuch config files
# Managed configs live under ~/.config; retain the existing explicit override.
config_dir="${XDG_CONFIG_DIR:-${HOME}/.config}/notmuch"

# If $account is set, then set it to ${config_dir}/${account}
if [ -n "${account}" ]; then
    set -- "${config_dir}/${account}"
else
    # Preserve paths with spaces when selecting all account configs.
    set -- "${config_dir}"/*
fi

for name do
    if [ -f "${name}" ]; then
        while ! notmuch --config="${name}" new; do :; done
    fi
done
