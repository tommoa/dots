#!/usr/bin/env bash
set -euo pipefail

menu_directory=${1:?Expected the Elephant menus directory}
mkdir -p "$menu_directory"
for menu_file in "@MENUS_DIR@"/*.toml; do
  [[ ${menu_file##*/} == devices.toml ]] || cp "$menu_file" "$menu_directory/"
done
cp "@DEVICES_MENU@" "$menu_directory/devices.toml"
chmod u+w "$menu_directory/devices.toml"

# The daemon advertises only profiles supported by the current platform.
if powerprofilesctl list 2>/dev/null | grep -Eq '^[[:space:]]*\*?[[:space:]]*performance:'; then
  cat "@PERFORMANCE_MENU_ENTRY@" >> "$menu_directory/devices.toml"
fi
