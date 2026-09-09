#!/bin/sh

set -eu

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_AUTH_FILE="${CODEX_AUTH_FILE:-$CODEX_HOME/auth.json}"
OPENCODE_AUTH_FILE="${OPENCODE_AUTH_FILE:-${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json}"
CLI_PROXY_AUTH_DIR="${CODEX_CLI_PROXY_AUTH_DIR:-$HOME/.cli-proxy-api}"
AUTH_SOURCE="${CODEX_USAGE_AUTH_SOURCE:-auto}"
USAGE_URL="${CODEX_USAGE_URL:-https://chatgpt.com/backend-api/wham/usage}"
RESET_CREDITS_URL="${CODEX_RATE_LIMIT_RESET_CREDITS_URL:-https://chatgpt.com/backend-api/wham/rate-limit-reset-credits}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/codex-subscription-usage"
CACHE_FILE="$CACHE_DIR/usage.json"
CACHE_TTL_SECS="${CODEX_USAGE_CACHE_TTL_SECS:-15}"
LOCK_DIR="$CACHE_DIR/refresh.lock"

usage() {
  cat <<'EOF'
Usage: codex-subscription-usage [--help]

Print cached Codex rate-limit usage for the tmux status line.
Authentication sources (CODEX_USAGE_AUTH_SOURCE): auto, cli-proxy, codex, opencode.
In auto mode all active CLIProxyAPI accounts are aggregated.  If none are
active, the Codex then OpenCode OAuth credentials are tried. Disabled or
incomplete CLIProxyAPI credential files are ignored. Cache refreshes are
atomic; a failed refresh keeps the prior valid version-1 cache document.
Additional limit pools include their model suffix when one is available.
EOF
}

case "${1:-}" in '') ;; -h|--help) usage; exit 0 ;; *) printf 'codex-subscription-usage: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;; esac
case "$AUTH_SOURCE" in auto|cli-proxy|codex|opencode) ;; *) printf 'codex-subscription-usage: invalid auth source: %s\n' "$AUTH_SOURCE" >&2; exit 2 ;; esac
case "$CACHE_TTL_SECS" in ''|*[!0-9]*) CACHE_TTL_SECS=15 ;; esac

now_epoch() { date +%s; }
file_mtime_epoch() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf 0; }
cache_age_secs() { [ -f "$CACHE_FILE" ] || { printf 999999; return; }; now="$(now_epoch)"; mtime="$(file_mtime_epoch "$CACHE_FILE")"; [ "$mtime" -gt "$now" ] && printf 0 || printf '%s' "$((now - mtime))"; }
cache_is_valid() { jq -e '.version == 1 and (.accounts | type == "array")' "$CACHE_FILE" >/dev/null 2>&1; }
acquire_lock() { mkdir -p "$CACHE_DIR"; if mkdir "$LOCK_DIR" 2>/dev/null; then trap 'release_lock' EXIT HUP INT TERM; return 0; fi; return 1; }
release_lock() { rmdir "$LOCK_DIR" 2>/dev/null || true; }

format_seconds() {
  seconds="${1:-0}"
  case "$seconds" in ''|*[!0-9]*) seconds=0 ;; esac
  if [ "$seconds" -le 0 ]; then
    printf now
  elif [ "$seconds" -ge 259200 ]; then
    printf '%dd' "$((seconds / 86400))"
  elif [ "$seconds" -ge 3600 ]; then
    hours=$((seconds / 3600))
    minutes=$(((seconds % 3600) / 60))
    if [ "$minutes" -gt 0 ]; then
      printf '%dh%dm' "$hours" "$minutes"
    else
      printf '%dh' "$hours"
    fi
  else
    printf '%dm' "$((seconds / 60))"
  fi
}

normalize_usage_json() {
  jq -ce '
    def number_or($default): if . == null then $default elif type == "number" then . elif type == "string" then (tonumber? // $default) else $default end;
    def reset_secs: ((.reset_after_seconds // ((.reset_at // null) as $at | if $at == null then null elif ($at | type) == "number" then ($at - now | floor) elif ($at | type) == "string" then (($at | tonumber?) // ($at | fromdateiso8601?)) as $epoch | if $epoch == null then null else ($epoch - now | floor) end else null end)) | number_or(0) | if . < 0 then 0 else . end);
    def meaningful: type == "object" and (has("limit_window_seconds") or has("reset_at") or ((.reset_after_seconds | number_or(0)) > 0) or ((.used_percent | number_or(0)) > 0));
    def normalize_limit($limits): {allowed:(if ($limits | has("allowed")) then $limits.allowed else null end),limit_reached:(if ($limits | has("limit_reached")) then $limits.limit_reached else null end),windows:(if ($limits.windows | type) == "array" then $limits.windows else [$limits | to_entries[] | select(.key | endswith("_window")) | .value] end | map(select(meaningful) | {name:(.name // "window"),used_percent:(.used_percent | number_or(0)),reset_after_seconds:reset_secs,limit_window_seconds:(.limit_window_seconds | number_or(null))}))};
    .rate_limit as $limits | if $limits == null then empty else {credits:{balance:(.credits.balance // null),has_credits:(.credits.has_credits // null)},rate_limit_reset_credits:(.rate_limit_reset_credits // {}),rate_limit:normalize_limit($limits),additional_rate_limits:[.additional_rate_limits[]? | . as $additional | ($additional.rate_limit // null) as $additional_limits | select($additional_limits != null) | {limit_id:($additional.metered_feature // null),limit_name:($additional.limit_name // $additional.metered_feature // "additional"),normal_model_slug:($additional.normal_model_slug // null),rate_limit:normalize_limit($additional_limits)}]} end'
}

normalize_reset_credits_json() {
  jq -ce '
    def number_or($default): if . == null then $default elif type == "number" then . elif type == "string" then (tonumber? // $default) else $default end;
    def expiry_epoch: if . == null then null elif type == "number" then . elif type == "string" then (fromdateiso8601? // (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601?)) else null end;
    if ((.credits? | type) != "array") and ((.available_count | number_or(null)) == null) then empty else [.credits[]? | select((.status // "") == "available") | (.expires_at | expiry_epoch) as $expires | select($expires == null or $expires > now) | if $expires == null then null else ($expires - now | floor | if . < 0 then 0 else . end) end] as $expires | ($expires | map(select(. != null)) | sort) as $expiring | ($expires | map(select(. == null)) | length) as $no_expiry | {available_count:(.available_count | number_or($expires | length)),next_expiry_after_seconds:($expiring[0] // null),expiry_after_seconds:$expiring,no_expiry_count:$no_expiry,has_no_expiry:($no_expiry > 0)} end'
}

fetch() {
  token="$1" account_id="$2" endpoint="$3"
  { printf 'header = "Authorization: Bearer %s"\n' "$token"; [ -z "$account_id" ] || printf 'header = "ChatGPT-Account-Id: %s"\n' "$account_id"; printf 'header = "Accept: application/json"\n'; } | curl -sS --max-time 10 -K - "$endpoint"
}

auth_file_for_source() { case "$1" in codex) printf '%s\n' "$CODEX_AUTH_FILE" ;; opencode) printf '%s\n' "$OPENCODE_AUTH_FILE" ;; *) return 1 ;; esac; }
standard_token() { file="$(auth_file_for_source "$1")" || return 1; [ -r "$file" ] || return 1; case "$1" in codex) jq -er '.tokens.access_token // empty' "$file" ;; opencode) jq -er 'select(.openai.type == "oauth") | .openai.access // empty' "$file" ;; esac; }
standard_account_id() { file="$(auth_file_for_source "$1")" || return 1; case "$1" in codex) jq -er '.tokens.account_id // empty' "$file" ;; opencode) jq -er '.openai.accountId // empty' "$file" ;; esac; }

account_document() {
  account_id="$1" email="$2" token="$3"
  usage_json="$(fetch "$token" "$account_id" "$USAGE_URL" 2>/dev/null || true)"
  normalized="$(printf '%s\n' "$usage_json" | normalize_usage_json 2>/dev/null || true)"
  [ -n "$normalized" ] || return 1
  credits_json="$(fetch "$token" "$account_id" "$RESET_CREDITS_URL" 2>/dev/null || true)"
  credits="$(printf '%s\n' "$credits_json" | normalize_reset_credits_json 2>/dev/null || true)"
  [ -n "$credits" ] || credits='{}'
  jq -cn --arg account_id "$account_id" --arg email "$email" --argjson usage "$normalized" --argjson credits "$credits" '{account_id: $account_id, email: $email, usage: ($usage | .rate_limit_reset_credits += $credits)}'
}

refresh_cli_proxy() {
  rows="$(cli_proxy_active_accounts)"
  [ -n "$rows" ] || return 1
  documents=''
  while IFS="$(printf '\t')" read -r account_id email auth_file; do
    [ -n "$auth_file" ] || continue
    token="$(jq -er '.access_token // empty' "$auth_file" 2>/dev/null || true)"
    [ -n "$token" ] || return 1
    if document="$(account_document "$account_id" "$email" "$token")"; then
      documents="${documents}${document}\n"
    else
      # A partial aggregate would hide an account's current status.  Keep the
      # previous complete cache until all active accounts refresh together.
      return 1
    fi
  done <<EOF
$rows
EOF
  [ -n "$documents" ] || return 1
  printf '%b' "$documents" | jq -sc '{version: 1, accounts: ., refreshed_at: now}'
}

refresh_standard() {
  for source in "$@"; do
    token="$(standard_token "$source" 2>/dev/null || true)"; [ -n "$token" ] || continue
    account_id="$(standard_account_id "$source" 2>/dev/null || true)"
    document="$(account_document "$account_id" "$source" "$token" || true)"; [ -n "$document" ] || continue
    jq -cn --argjson account "$document" '{version: 1, accounts: [$account], refreshed_at: now}'
    return 0
  done
  return 1
}

refresh_cache() {
  case "$AUTH_SOURCE" in
    cli-proxy) refresh_cli_proxy ;;
    codex|opencode) refresh_standard "$AUTH_SOURCE" ;;
    auto) refresh_cli_proxy || refresh_standard codex opencode ;;
  esac
}

write_cache() {
  document="$1" tmp="$CACHE_FILE.$$"
  jq -e '.version == 1 and (.accounts | type == "array") and length > 0' >/dev/null <<EOF
$document
EOF
  if ! (umask 077; printf '%s\n' "$document" > "$tmp"); then rm -f "$tmp"; return 1; fi
  if ! mv "$tmp" "$CACHE_FILE"; then rm -f "$tmp"; return 1; fi
  rm -f "$CACHE_DIR"/account-*.json
}

format_reset_credits_summary_json() {
  usage_json="$1"
  available_count="$(printf '%s\n' "$usage_json" | jq -er '.rate_limit_reset_credits.available_count // 0' 2>/dev/null || printf 0)"
  case "$available_count" in ''|*[!0-9]*) return 1 ;; esac
  [ "$available_count" -gt 0 ] || return 1
  expiry_rows="$(printf '%s\n' "$usage_json" | jq -er '.rate_limit_reset_credits.expiry_after_seconds // [] | .[]' 2>/dev/null || true)"
  no_expiry="$(printf '%s\n' "$usage_json" | jq -er '.rate_limit_reset_credits.no_expiry_count // 0' 2>/dev/null || printf 0)"
  case "$no_expiry" in ''|*[!0-9]*) no_expiry=0 ;; esac
  visible=0 total=0 summary=''
  if [ -n "$expiry_rows" ]; then while IFS= read -r expiry; do [ -n "$expiry" ] || continue; total=$((total + 1)); if [ "$visible" -lt 4 ]; then item="$(format_seconds "$expiry")"; summary="${summary:+$summary·}$item"; visible=$((visible + 1)); fi; done <<EOF
$expiry_rows
EOF
  fi
  while [ "$no_expiry" -gt 0 ]; do total=$((total + 1)); if [ "$visible" -lt 4 ]; then summary="${summary:+$summary·}noexp"; visible=$((visible + 1)); fi; no_expiry=$((no_expiry - 1)); done
  [ "$total" -gt 0 ] || return 1
  [ "$total" -le "$visible" ] || summary="${summary}·+$((total - visible))"
  printf '%s\n' "$summary"
}

print_usage_text_from_json() {
  usage_json="$1"
  credits_balance="$(printf '%s\n' "$usage_json" | jq -r '.credits.balance // empty | if type == "number" then . elif type == "string" then (tonumber? // empty) else empty end | if . >= 100 then round | tostring elif . >= 10 then (. * 10 | round / 10 | tostring) else (. * 100 | round / 100 | tostring) end' 2>/dev/null || true)"
  rows="$(printf '%s\n' "$usage_json" | jq -er '.rate_limit.windows[]? | [(.reset_after_seconds // 0 | tostring), (.used_percent // 0 | round | tostring), (if (.used_percent // 0) >= 100 then "1" else "0" end)] | @tsv' 2>/dev/null || true)"
  [ -n "$rows" ] || return 1
  output=''
  while IFS="$(printf '\t')" read -r reset pct hit; do
    if [ "$hit" = 1 ] && [ -n "$credits_balance" ]; then item="$(format_seconds "$reset"):${credits_balance}cr"; else item="$(format_seconds "$reset"):${pct}%"; fi
    output="${output:+$output }$item"
  done <<EOF
$rows
EOF
  additional_rows="$(printf '%s\n' "$usage_json" | jq -er '
    def model_suffix: (.normal_model_slug // "") as $slug | if $slug == "" then "" else ($slug | split("-") | last) end;
    .additional_rate_limits[]? | . as $limit | (($limit.limit_name // $limit.limit_id // "additional") + (model_suffix as $model | if $model == "" then "" else "[\($model)]" end)) as $label | .rate_limit.windows[]? | [$label, (.reset_after_seconds // 0 | tostring), (.used_percent // 0 | round | tostring)] | @tsv' 2>/dev/null || true)"
  if [ -n "$additional_rows" ]; then
    while IFS="$(printf '\t')" read -r label reset pct; do
      item="${label}=$(format_seconds "$reset"):${pct}%"
      output="${output:+$output }$item"
    done <<EOF
$additional_rows
EOF
  fi
  credits="$(printf '%s\n' "$usage_json" | jq -er '.rate_limit_reset_credits.available_count // empty' 2>/dev/null || true)"
  if [ -n "$credits" ]; then
    if summary="$(format_reset_credits_summary_json "$usage_json")"; then output="$output ($summary)"; else output="$output ($credits)"; fi
  fi
  printf '%s\n' "$output"
}

print_cache() {
  cache_is_valid || return 1
  output=''
  accounts="$(jq -c '.accounts[]' "$CACHE_FILE" 2>/dev/null || true)"
  while IFS= read -r account; do
    [ -n "$account" ] || continue
    account_usage="$(printf '%s\n' "$account" | jq -c '.usage')"
    text="$(print_usage_text_from_json "$account_usage" 2>/dev/null || true)"
    [ -n "$text" ] || continue
    output="${output:+$output | }$text"
  done <<EOF
$accounts
EOF
  [ -n "$output" ] || return 1
  printf '%s\n' "$output"
}

if [ "$(cache_age_secs)" -ge "$CACHE_TTL_SECS" ] && acquire_lock; then
  if [ "$(cache_age_secs)" -ge "$CACHE_TTL_SECS" ]; then
    document="$(refresh_cache 2>/dev/null || true)"
    [ -z "$document" ] || write_cache "$document" || true
  fi
  release_lock
fi
print_cache 2>/dev/null || true
