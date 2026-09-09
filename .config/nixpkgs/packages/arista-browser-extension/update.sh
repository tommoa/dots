#!/usr/bin/env bash

set -euo pipefail

repository="ssh://gerrit.corp.arista.io:29418/tools/arista-browser-extension"
gitiles_url="https://gerrit.corp.arista.io/plugins/gitiles/tools/arista-browser-extension"
requested_rev=""

usage() {
    cat <<'EOF'
Usage: update-arista-browser-extension [--rev COMMIT]

Build, test, sign, and register a pinned Arista Browser Extension XPI.
Without --rev, the current Gerrit main revision is selected.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --rev)
            [ "$#" -ge 2 ] || {
                printf '%s\n' '--rev requires a commit' >&2
                exit 2
            }
            requested_rev="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

find_flake_dir() {
    if [ -n "${ARISTA_EXTENSION_FLAKE_DIR:-}" ]; then
        printf '%s\n' "$ARISTA_EXTENSION_FLAKE_DIR"
        return
    fi

    if [ -f "$PWD/packages/arista-browser-extension/metadata.json" ]; then
        printf '%s\n' "$PWD"
        return
    fi

    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$repo_root" ] && [ -f "$repo_root/.config/nixpkgs/packages/arista-browser-extension/metadata.json" ]; then
        printf '%s\n' "$repo_root/.config/nixpkgs"
        return
    fi

    printf '%s\n' 'Run this command from the dotfiles repository, the Nix flake directory,' >&2
    printf '%s\n' 'or set ARISTA_EXTENSION_FLAKE_DIR.' >&2
    exit 1
}

require_amo_credentials() {
    if [ ! -s "$api_key_file" ] || [ ! -s "$api_secret_file" ]; then
        printf 'AMO credentials are missing from %s.\n' "${api_key_file%/*}" >&2
        return 1
    fi
}

fetch_signed_xpi() {
    local version="$1"
    local output_file="$2"

    node - "$addon_id" "$version" "$output_file" "$api_key_file" "$api_secret_file" <<'NODE'
const crypto = require("node:crypto"); const fs = require("node:fs");
const [addonId, version, outputFile, apiKeyFile, apiSecretFile] = process.argv.slice(2);
const apiKey = fs.readFileSync(apiKeyFile, "utf8").trim();
const apiSecret = fs.readFileSync(apiSecretFile, "utf8").trim();
const now = Math.floor(Date.now() / 1000);
const encode = value => Buffer.from(JSON.stringify(value)).toString("base64url");
const unsignedToken = `${encode({alg: "HS256", typ: "JWT"})}.${encode({iss: apiKey, iat: now, exp: now + 300})}`;
const signature = crypto.createHmac("sha256", apiSecret).update(unsignedToken).digest("base64url");
const headers = {Authorization: `JWT ${unsignedToken}.${signature}`, Accept: "application/json"};

(async () => {
  const path = `/api/v5/addons/addon/${encodeURIComponent(addonId)}/versions/v${encodeURIComponent(version)}/`;
  const versionUrl = new URL(path, "https://addons.mozilla.org");
  const versionResponse = await fetch(versionUrl, {headers});
  if (versionResponse.status === 404) process.exit(44);
  if (!versionResponse.ok) throw new Error(`AMO version lookup returned HTTP ${versionResponse.status}`);

  const data = await versionResponse.json();
  if (data.version !== version || data.channel !== "unlisted")
    throw new Error(`AMO returned unexpected metadata for version ${version}`);
  const fileStatus = data.file?.status ?? "missing";
  if (fileStatus !== "public" || typeof data.file?.url !== "string")
    throw new Error(`AMO version ${version} exists with file status ${fileStatus}; refusing to resubmit`);

  const downloadUrl = new URL(data.file.url);
  if (downloadUrl.protocol !== "https:" || downloadUrl.hostname !== "addons.mozilla.org")
    throw new Error(`AMO returned an unexpected download URL for version ${version}`);

  const fileResponse = await fetch(downloadUrl, {headers});
  if (!fileResponse.ok) throw new Error(`AMO XPI download returned HTTP ${fileResponse.status}`);
  fs.writeFileSync(outputFile, Buffer.from(await fileResponse.arrayBuffer()), {mode: 0o600});
})().catch(error => {
  console.error(error.message);
  process.exit(2);
});
NODE
}

retain_signed_artifact() {
    local source_file="$1"
    local version="$2"
    local expected_hash="${3:-}"
    local actual_hash

    if ! unzip -tq "$source_file" >/dev/null; then
        printf 'The signed XPI is not a valid archive: %s\n' "$source_file" >&2
        return 1
    fi
    actual_hash="$(nix hash file --type sha256 "$source_file")"
    if [ -n "$expected_hash" ] && [ "$actual_hash" != "$expected_hash" ]; then
        printf 'Signed XPI hash mismatch for version %s.\n' "$version" >&2
        return 1
    fi

    artifact_path="$artifact_dir/arista-browser-extension-$version.xpi"
    mkdir -p "$artifact_dir"
    cp "$source_file" "$artifact_path.new"
    chmod 0444 "$artifact_path.new"
    mv "$artifact_path.new" "$artifact_path"
    signed_xpi_hash="$actual_hash"
    store_path="$(nix-store --add-fixed sha256 "$artifact_path")"
}

flake_dir="$(find_flake_dir)"
package_dir="$flake_dir/packages/arista-browser-extension"
metadata_file="$package_dir/metadata.json"
addon_id="$(jq -r .addonId "$metadata_file")"
current_rev="$(jq -r '.rev // empty' "$metadata_file")"
current_version="$(jq -r '.upstreamVersion // empty' "$metadata_file")"
current_signed_hash="$(jq -r '.signedXpiHash // empty' "$metadata_file")"
artifact_dir="$HOME/.local/share/arista-browser-extension"
current_artifact="$artifact_dir/arista-browser-extension-$current_version.xpi"
upload_state="$artifact_dir/.amo-upload-uuid"
api_key_file="$HOME/.config/amo/api-key"
api_secret_file="$HOME/.config/amo/api-secret"

if [ -n "$requested_rev" ]; then
    rev="$requested_rev"
else
    rev="$(git ls-remote "$repository" refs/heads/main | sed -n '1s/[[:space:]].*//p')"
fi

case "$rev" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *)
        printf 'Could not resolve a full Gerrit commit: %s\n' "$rev" >&2
        exit 1
        ;;
esac

tmp_dir="$(mktemp -d)"
metadata_backup="$tmp_dir/metadata.original.json"
restore_metadata=0
cleanup() {
    status=$?
    trap - EXIT INT TERM HUP
    if [ "$restore_metadata" -eq 1 ]; then
        cp "$metadata_backup" "$metadata_file"
    fi
    rm -rf "$tmp_dir"
    exit "$status"
}
trap cleanup EXIT INT TERM HUP

if [ "$rev" = "$current_rev" ] && [ -n "$current_version" ] && [ -n "$current_signed_hash" ]; then
    if [ -e "$current_artifact" ] \
        && retain_signed_artifact "$current_artifact" "$current_version" "$current_signed_hash"; then
        printf 'Arista Browser Extension %s is already current.\n' "$current_version"
        printf 'Nix store: %s\n' "$store_path"
        exit 0
    fi

    printf 'The retained XPI is unavailable; checking AMO for version %s.\n' "$current_version" >&2
    require_amo_credentials
    recovered_xpi="$tmp_dir/arista-browser-extension-$current_version-recovered.xpi"
    if fetch_signed_xpi "$current_version" "$recovered_xpi"; then
        retain_signed_artifact "$recovered_xpi" "$current_version" "$current_signed_hash"
    else
        amo_status=$?
        if [ "$amo_status" -eq 44 ]; then
            printf 'AMO does not have signed version %s.\n' "$current_version" >&2
        fi
        exit 1
    fi

    printf 'Recovered Arista Browser Extension %s from AMO.\n' "$current_version"
    printf 'Signed XPI: %s\n' "$artifact_path"
    printf 'Nix store: %s\n' "$store_path"
    exit 0
fi

archive_url="$gitiles_url/+archive/$rev.tar.gz"
prefetch_json="$(nix store prefetch-file --json --unpack "$archive_url")"
source_hash="$(printf '%s' "$prefetch_json" | jq -r .hash)"
source_path="$(printf '%s' "$prefetch_json" | jq -r .storePath)"

upstream_version="$(sed -n 's/^[[:space:]]*version:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$source_path/src/manifest.ts" | head -n 1)"
if [ -z "$upstream_version" ]; then
    printf '%s\n' 'Could not read the upstream version from src/manifest.ts.' >&2
    exit 1
fi

if [ -n "$current_signed_hash" ]; then
    newest_version="$(printf '%s\n%s\n' "$current_version" "$upstream_version" | sort -V | tail -n 1)"
    if [ "$newest_version" != "$upstream_version" ] || [ "$current_version" = "$upstream_version" ]; then
        printf 'Upstream version %s does not advance signed version %s.\n' \
            "$upstream_version" "$current_version" >&2
        printf '%s\n' 'Select a revision with a newer manifest version before submitting to AMO.' >&2
        exit 1
    fi
fi

npm_deps_hash="$(prefetch-npm-deps "$source_path/package-lock.json")"
# Build through the normal flake output, restoring metadata unless the complete update succeeds.
cp "$metadata_file" "$metadata_backup"
jq \
    --arg npmDepsHash "$npm_deps_hash" \
    --arg rev "$rev" \
    --arg sourceHash "$source_hash" \
    --arg version "$upstream_version" \
    '.npmDepsHash = $npmDepsHash
     | .rev = $rev
     | .signedXpiHash = null
     | .sourceHash = $sourceHash
     | .upstreamVersion = $version' \
    "$metadata_backup" > "$metadata_file.new"
mv "$metadata_file.new" "$metadata_file"
restore_metadata=1

unsigned_path="$(nix build --no-link --print-out-paths "path:$flake_dir#arista-browser-extension")"
unpacked="$unsigned_path/unpacked"

require_amo_credentials
existing_xpi="$tmp_dir/arista-browser-extension-$upstream_version-existing.xpi"
if fetch_signed_xpi "$upstream_version" "$existing_xpi"; then
    printf 'AMO already has signed version %s; recovering it.\n' "$upstream_version"
    signed_source="$existing_xpi"
else
    amo_status=$?
    if [ "$amo_status" -ne 44 ]; then
        exit 1
    fi

    source_archive="$unsigned_path/source.zip"
    artifacts_dir="$tmp_dir/signed"
    signing_source="$tmp_dir/signing-source"
    mkdir -p "$artifacts_dir"
    cp -R "$unpacked" "$signing_source"
    chmod -R u+w "$signing_source"
    if [ -s "$upload_state" ]; then
        cp "$upload_state" "$signing_source/.amo-upload-uuid"
    fi

    set +e
    WEB_EXT_API_KEY="$(cat "$api_key_file")" \
    WEB_EXT_API_SECRET="$(cat "$api_secret_file")" \
        web-ext sign \
            --source-dir "$signing_source" \
            --artifacts-dir "$artifacts_dir" \
            --channel unlisted \
            --ignore-files .amo-upload-uuid \
            --upload-source-code "$source_archive" \
            --no-input
    sign_status=$?
    set -e

    if [ -s "$signing_source/.amo-upload-uuid" ]; then
        mkdir -p "$artifact_dir"
        cp "$signing_source/.amo-upload-uuid" "$upload_state.new"
        chmod 0600 "$upload_state.new"
        mv "$upload_state.new" "$upload_state"
    fi
    if [ "$sign_status" -ne 0 ]; then
        exit "$sign_status"
    fi

    shopt -s nullglob
    signed_files=("$artifacts_dir"/*.xpi)
    shopt -u nullglob
    if [ "${#signed_files[@]}" -ne 1 ]; then
        printf 'Expected one signed XPI, found %s.\n' "${#signed_files[@]}" >&2
        exit 1
    fi
    signed_source="${signed_files[0]}"
fi

signed_payload="$tmp_dir/signed-payload"
mkdir -p "$signed_payload"
unzip -qq "$signed_source" -d "$signed_payload"
rm -rf "$signed_payload/META-INF"
if ! diff -rq "$signed_payload" "$unpacked" >/dev/null; then
    printf '%s\n' 'The signed XPI payload does not match the locally built extension.' >&2
    exit 1
fi

retain_signed_artifact "$signed_source" "$upstream_version"
jq \
    --arg signedXpiHash "$signed_xpi_hash" \
    '.signedXpiHash = $signedXpiHash' \
    "$metadata_file" > "$metadata_file.new"
mv "$metadata_file.new" "$metadata_file"

if ! nix build --no-link \
    "path:$flake_dir#arista-browser-extension" \
    "path:$flake_dir#darwinConfigurations.apollo.system"; then
    printf '%s\n' 'Targeted validation failed; restored the previous metadata.' >&2
    exit 1
fi

restore_metadata=0
printf 'Updated Arista Browser Extension to %s (%s).\n' "$upstream_version" "$rev"
printf 'Signed XPI: %s\n' "$artifact_path"
printf 'Nix store: %s\n' "$store_path"
printf '%s\n' 'Review the metadata diff, then rebuild the work configuration.'
