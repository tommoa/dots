#!/bin/sh

set -eu

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_AUTH_FILE="${CODEX_AUTH_FILE:-$CODEX_HOME/auth.json}"
OPENCODE_AUTH_FILE="${OPENCODE_AUTH_FILE:-${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json}"
CLI_PROXY_AUTH_DIR="${CODEX_CLI_PROXY_AUTH_DIR:-$HOME/.cli-proxy-api}"
AUTH_SOURCE="${CODEX_RESET_AUTH_SOURCE:-auto}"
USAGE_URL="${CODEX_USAGE_URL:-https://chatgpt.com/backend-api/wham/usage}"
RESET_URL="${CODEX_RATE_LIMIT_RESET_URL:-https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume}"
CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/codex-subscription-usage/usage.json"

ASSUME_YES=0
DRY_RUN=0
ACCOUNT_SELECTOR="${CODEX_RESET_ACCOUNT:-}"

usage() {
  cat <<'EOF'
Usage: reset-codex [--yes] [--dry-run] [--account EMAIL_OR_ACCOUNT_ID]

Consume one Codex rate-limit reset credit.

Authentication sources (CODEX_RESET_AUTH_SOURCE): auto, cli-proxy, codex, opencode.
With auto, one active CLIProxyAPI account is selected; zero falls back to
Codex/OpenCode; multiple active accounts require --account.  Disabled and
incomplete CLIProxyAPI credentials are ignored.

Options:
  -y, --yes      Do not prompt before consuming a reset credit.
      --dry-run  Show reset-credit state without consuming a credit.
      --account  Select a CLIProxyAPI account by email or account ID.
  -h, --help     Show this help text.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --account)
      shift
      [ "$#" -gt 0 ] || { printf '%s\n' 'reset-codex: --account requires an email or account ID' >&2; exit 2; }
      ACCOUNT_SELECTOR="$1"
      ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'reset-codex: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

auth_file_for_source() { case "$1" in codex) printf '%s\n' "$CODEX_AUTH_FILE" ;; opencode) printf '%s\n' "$OPENCODE_AUTH_FILE" ;; *) return 1 ;; esac; }
auth_has_token() {
  auth_file="$(auth_file_for_source "$1")" || return 1
  [ -r "$auth_file" ] || return 1
  case "$1" in
    codex) jq -e '(.tokens.access_token // "") != ""' "$auth_file" >/dev/null 2>&1 ;;
    opencode) jq -e '(.openai.type == "oauth") and ((.openai.access // "") != "")' "$auth_file" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

select_standard_source() {
  case "$AUTH_SOURCE" in
    codex|opencode) auth_has_token "$AUTH_SOURCE" || return 1; SELECTED_AUTH_SOURCE="$AUTH_SOURCE" ;;
    auto) for source in codex opencode; do auth_has_token "$source" || continue; SELECTED_AUTH_SOURCE="$source"; break; done; [ -n "${SELECTED_AUTH_SOURCE:-}" ] || return 1 ;;
    *) return 1 ;;
  esac
  SELECTED_AUTH_FILE="$(auth_file_for_source "$SELECTED_AUTH_SOURCE")"
}

select_auth() {
  case "$AUTH_SOURCE" in auto|cli-proxy|codex|opencode) ;; *) printf 'reset-codex: invalid auth source: %s\n' "$AUTH_SOURCE" >&2; exit 2 ;; esac
  if [ -n "$ACCOUNT_SELECTOR" ] || [ "$AUTH_SOURCE" = cli-proxy ]; then
    if cli_proxy_select_account "$ACCOUNT_SELECTOR"; then
      selection=0
    else
      selection=$?
    fi
    case "$selection" in 0) return ;; 2) printf '%s\n' 'reset-codex: --account matched more than one CLIProxyAPI account' >&2; exit 2 ;; *) printf '%s\n' 'reset-codex: no matching active CLIProxyAPI account found' >&2; exit 1 ;; esac
  fi
  if [ "$AUTH_SOURCE" = auto ]; then
    count="$(cli_proxy_account_count)"
    case "$count" in 1) cli_proxy_select_account '' ; return ;; 0) ;; *) printf '%s\n' 'reset-codex: multiple CLIProxyAPI accounts found; rerun with --account EMAIL_OR_ACCOUNT_ID' >&2; exit 2 ;; esac
  fi
  select_standard_source || { printf '%s\n' 'reset-codex: no Codex or OpenCode ChatGPT access token found' >&2; exit 1; }
}

load_access_token() { case "$SELECTED_AUTH_SOURCE" in codex) jq -er '.tokens.access_token // empty' "$SELECTED_AUTH_FILE" ;; opencode) jq -er '.openai.access // empty' "$SELECTED_AUTH_FILE" ;; cli-proxy) jq -er '.access_token // empty' "$SELECTED_AUTH_FILE" ;; esac; }
extract_account_id_from_json() { printf '%s\n' "$1" | jq -er 'def claims: try (split(".")[1] as $payload | ($payload | gsub("-"; "+") | gsub("_"; "/")) as $base64 | ($base64 + ("===="[0:((4 - ($base64 | length % 4)) % 4)])) | @base64d | fromjson) catch empty; def account_id: .chatgpt_account_id // ."https://api.openai.com/auth".chatgpt_account_id // .organizations[0].id // empty; (.id_token? | claims | account_id) // (.access_token? | claims | account_id) // empty' 2>/dev/null; }
load_account_id() {
  case "$SELECTED_AUTH_SOURCE" in codex) account_id="$(jq -er '.tokens.account_id // empty' "$SELECTED_AUTH_FILE" 2>/dev/null || true)" ;; opencode) account_id="$(jq -er '.openai.accountId // empty' "$SELECTED_AUTH_FILE" 2>/dev/null || true)" ;; cli-proxy) account_id="$SELECTED_ACCOUNT_ID" ;; esac
  if [ -z "$account_id" ]; then access_token="$(load_access_token || true)"; [ -z "$access_token" ] || account_id="$(extract_account_id_from_json "$(jq -n --arg access_token "$access_token" '{access_token: $access_token}')" || true)"; fi
  printf '%s\n' "$account_id"
}

curl_with_auth() {
  method="$1" url="$2" body="${3:-}"
  { printf 'header = "Authorization: Bearer %s"\n' "$ACCESS_TOKEN"; [ -z "$ACCOUNT_ID" ] || printf 'header = "ChatGPT-Account-Id: %s"\n' "$ACCOUNT_ID"; printf 'header = "Accept: application/json"\nheader = "Content-Type: application/json"\n'; } | if [ -n "$body" ]; then curl -sS --max-time 15 -X "$method" -K - --data "$body" -w '\n%{http_code}' "$url"; else curl -sS --max-time 15 -X "$method" -K - -w '\n%{http_code}' "$url"; fi
}
request_json() {
  method="$1" url="$2" body="${3:-}"
  response="$(curl_with_auth "$method" "$url" "$body")"
  status="$(printf '%s\n' "$response" | tail -n 1)" body="$(printf '%s\n' "$response" | sed '$d')"
  case "$status" in 2??) printf '%s\n' "$body" ;; *) printf 'reset-codex: request failed with HTTP %s\n' "$status" >&2; [ -z "$body" ] || printf '%s\n' "$body" >&2; return 1 ;; esac
}

print_usage_summary() { printf '%s\n' "$1" | jq -r 'def window($name): .rate_limit[$name] // {}; def pct: (.used_percent // 0) | round; def reset: .reset_after_seconds // 0; ["primary: " + ((window("primary_window") | pct) | tostring) + "%, reset in " + ((window("primary_window") | reset) | tostring) + "s", "secondary: " + ((window("secondary_window") | pct) | tostring) + "%, reset in " + ((window("secondary_window") | reset) | tostring) + "s", "reset credits: " + ((.rate_limit_reset_credits.available_count // 0) | tostring)] | .[]'; }
confirm_reset() { [ "$ASSUME_YES" -eq 1 ] && return; [ -t 0 ] || { printf '%s\n' 'reset-codex: refusing to consume a reset credit without --yes in a non-interactive shell' >&2; exit 1; }; printf 'Consume one Codex rate-limit reset credit? [y/N] ' >&2; read -r answer; case "$answer" in y|Y|yes|YES) ;; *) printf '%s\n' 'No reset credit consumed.'; exit 0 ;; esac; }
generate_idempotency_key() { if command -v uuidgen >/dev/null 2>&1; then uuidgen | tr '[:upper:]' '[:lower:]'; return; fi; random_hex="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"; printf 'reset-codex-%s-%s-%s\n' "$(date +%s)" "$$" "$random_hex"; }

select_auth
ACCESS_TOKEN="$(load_access_token || true)" ACCOUNT_ID="$(load_account_id || true)"
[ -n "$ACCESS_TOKEN" ] || { printf '%s\n' 'reset-codex: selected auth source has no access token' >&2; exit 1; }
usage_json="$(request_json GET "$USAGE_URL")" || exit 1
print_usage_summary "$usage_json"
available_count="$(printf '%s\n' "$usage_json" | jq -r '.rate_limit_reset_credits.available_count // 0')"
case "$available_count" in ''|*[!0-9]*) available_count=0 ;; esac
[ "$DRY_RUN" -eq 1 ] && exit 0
[ "$available_count" -gt 0 ] || { printf '%s\n' 'reset-codex: no reset credits are currently available' >&2; exit 1; }
confirm_reset
request_body="$(jq -n --arg redeem_request_id "$(generate_idempotency_key)" '{redeem_request_id: $redeem_request_id}')"
reset_json="$(request_json POST "$RESET_URL" "$request_body")" || exit 1
outcome_code="$(printf '%s\n' "$reset_json" | jq -r '.outcome.code // .code // .outcome // empty')"
case "$outcome_code" in
  reset) printf '%s\n' 'Codex rate limit reset applied.' ;;
  nothing_to_reset) printf '%s\n' 'No reset was needed; no rate limit window was reset.' ;;
  no_credit) printf '%s\n' 'No reset credit was available.' ;;
  already_redeemed) printf '%s\n' 'This reset request was already redeemed.' ;;
  *) printf '%s\n' 'Reset response:'; printf '%s\n' "$reset_json" | jq . ;;
esac
rm -f "$CACHE_FILE"
printf '%s\n' 'Cleared Codex usage cache; tmux will refresh on its next status update.'
