#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
	echo "Usage: codex-local-bootstrap CODEX_WRAPPER" >&2
	exit 2
fi

codex_wrapper="$1"
shared_codex_home="$HOME/.codex"
managed_config="$shared_codex_home/server-config.toml"
applied_config_source="$CODEX_HOME/.managed-config-source"
CODEX_SQLITE_HOME="${CODEX_SQLITE_HOME:-$CODEX_HOME/sqlite}"

link_managed_input() {
	source_path="$1"
	local_path="$2"

	if [ ! -e "$source_path" ] && [ ! -L "$source_path" ]; then
		echo "Missing managed Codex input: $source_path" >&2
		exit 1
	fi

	install -d -m 700 "$(dirname "$local_path")"
	if [ -L "$local_path" ] && [ "$(readlink "$local_path")" = "$source_path" ]; then
		return
	fi

	# A Nix activation may change the wrapper target while multiple Codex
	# processes are starting. Publish the new link atomically so those starts
	# cannot race between removing and recreating the managed path.
	temporary_path="${local_path}.new.$$"
	ln -s "$source_path" "$temporary_path"
	if ! mv -Tf "$temporary_path" "$local_path"; then
		rm -f "$temporary_path"
		return 1
	fi
}

install_managed_config() {
	if [ ! -e "$managed_config" ]; then
		echo "Missing managed Codex config: $managed_config" >&2
		exit 1
	fi

	managed_config_source="$(readlink -f "$managed_config")"
	if [ -f "$CODEX_HOME/config.toml" ] &&
		[ -f "$applied_config_source" ] &&
		[ "$(cat "$applied_config_source")" = "$managed_config_source" ]; then
		return
	fi

	# Local changes survive ordinary launches. A new Home Manager generation
	# deliberately resets them to its new declarative baseline.
	temporary_config="$CODEX_HOME/config.toml.new.$$"
	temporary_source="$applied_config_source.new.$$"
	install -m 600 "$managed_config_source" "$temporary_config"
	printf '%s\n' "$managed_config_source" >"$temporary_source"
	chmod 600 "$temporary_source"
	mv -Tf "$temporary_config" "$CODEX_HOME/config.toml"
	mv -Tf "$temporary_source" "$applied_config_source"
}

install -d -m 700 \
	"$CODEX_HOME" \
	"$CODEX_SQLITE_HOME" \
	"$CODEX_HOME/packages/standalone/current"

# Serialize first-start and generation changes without holding the lock while
# Codex itself runs.
exec 9>"$CODEX_HOME/.bootstrap.lock"
flock 9

install_managed_config
# Resolve the immutable script before running it so an activation changing the
# shared link cannot make it record a generation different from its own code.
if [ -x "$shared_codex_home/install-plugins" ]; then
	"$(readlink -f "$shared_codex_home/install-plugins")"
fi
link_managed_input "$shared_codex_home/AGENTS.md" "$CODEX_HOME/AGENTS.md"
if [ -e "$shared_codex_home/codex-api-key-helper" ] || [ -L "$shared_codex_home/codex-api-key-helper" ]; then
	link_managed_input "$shared_codex_home/codex-api-key-helper" "$CODEX_HOME/codex-api-key-helper"
fi
link_managed_input "$shared_codex_home/skills" "$CODEX_HOME/skills"

link_managed_input \
	"$(readlink -f "$codex_wrapper")" \
	"$CODEX_HOME/packages/standalone/current/codex"
