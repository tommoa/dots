#!/bin/sh

set -eu

package_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
flake_dir="$(CDPATH= cd -- "${package_dir}/../.." && pwd)"

version="${1:-}"
if [ -z "$version" ]; then
    version="$(npm view obsidian-headless version)"
fi

current="$(jq -r '.dependencies["obsidian-headless"]' "${package_dir}/package.json")"
if [ "$current" = "$version" ]; then
    printf 'obsidian-headless is already at %s\n' "$version"
else
    printf 'Updating obsidian-headless from %s to %s\n' "$current" "$version"
fi

cd "$package_dir"

tmp_dir="$(mktemp -d)"
cp package.json package-lock.json default.nix "$tmp_dir"/

cleanup() {
    rm -rf "$tmp_dir"
}

rollback() {
    status=$?
    trap - EXIT INT TERM HUP
    if [ "$status" -ne 0 ]; then
        cp "$tmp_dir/package.json" package.json
        cp "$tmp_dir/package-lock.json" package-lock.json
        cp "$tmp_dir/default.nix" default.nix
    fi
    cleanup
    exit "$status"
}

trap rollback EXIT INT TERM HUP

npm pkg set \
    "version=${version}" \
    "dependencies.obsidian-headless=${version}" \
    >/dev/null
npm install --package-lock-only --ignore-scripts --save-exact "obsidian-headless@${version}"

perl -0pi -e "s/version = \"[^\"]+\";/version = \"${version}\";/" default.nix
perl -0pi -e 's/npmDepsHash = "[^"]+";/npmDepsHash = lib.fakeHash;/' default.nix

build_expr="
let
  flake = builtins.getFlake \"git+file://${HOME}?dir=.config/nixpkgs\";
  pkgs = import flake.inputs.nixpkgs {
    system = builtins.currentSystem;
    config.allowUnfree = true;
    overlays = [ (import ${flake_dir}/overlays) ];
  };
in
  pkgs.obsidian-headless
"

set +e
build_output="$(nix build --no-link --impure --expr "$build_expr" 2>&1)"
build_status=$?
set -e

if [ "$build_status" -eq 0 ]; then
    printf '%s\n' "$build_output"
    printf 'Expected fake npmDepsHash build to fail, but it succeeded.\n' >&2
    exit 1
fi

npm_deps_hash="$(printf '%s\n' "$build_output" | sed -n 's/.*got:[[:space:]]*\(sha256-[A-Za-z0-9+\/=]*\).*/\1/p' | tail -n 1)"
if [ -z "$npm_deps_hash" ]; then
    printf '%s\n' "$build_output" >&2
    printf 'Could not find npmDepsHash in Nix build output.\n' >&2
    exit 1
fi

NPM_DEPS_HASH="$npm_deps_hash" perl -0pi -e \
    's/npmDepsHash = lib\.fakeHash;/npmDepsHash = "$ENV{NPM_DEPS_HASH}";/' \
    default.nix

nix build --no-link --impure --expr "$build_expr"

trap - EXIT INT TERM HUP
cleanup

printf 'obsidian-headless updated to %s with npmDepsHash %s\n' "$version" "$npm_deps_hash"
