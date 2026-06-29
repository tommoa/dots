#!/bin/sh

set -eu

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_AUTH_FILE="${CODEX_AUTH_FILE:-$CODEX_HOME/auth.json}"
OPENCODE_AUTH_FILE="${OPENCODE_AUTH_FILE:-${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json}"
AUTH_SOURCE="${CODEX_RESET_AUTH_SOURCE:-auto}"
USAGE_URL="${CODEX_USAGE_URL:-https://chatgpt.com/backend-api/wham/usage}"
RESET_URL="${CODEX_RATE_LIMIT_RESET_URL:-https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume}"
CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/codex-subscription-usage/usage.json"

ASSUME_YES=0
DRY_RUN=0

usage() {
	cat <<'EOF'
Usage: reset-codex [--yes] [--dry-run]

Consume one Codex rate-limit reset credit for the signed-in ChatGPT account.

Options:
  -y, --yes      Do not prompt before consuming a reset credit.
      --dry-run  Show current reset-credit state without consuming one.
  -h, --help     Show this help text.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		-y|--yes)
			ASSUME_YES=1
			;;
		--dry-run)
			DRY_RUN=1
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			printf 'reset-codex: unknown option: %s\n' "$1" >&2
			usage >&2
			exit 2
			;;
	esac
	shift
done

auth_file_for_source() {
	case "$1" in
		codex) printf '%s\n' "$CODEX_AUTH_FILE" ;;
		opencode) printf '%s\n' "$OPENCODE_AUTH_FILE" ;;
		*) return 1 ;;
	esac
}

auth_has_token() {
	auth_source="$1"
	auth_file="$(auth_file_for_source "$auth_source")" || return 1
	[ -r "$auth_file" ] || return 1

	case "$auth_source" in
		codex)
			jq -e '(.tokens.access_token // "") != ""' "$auth_file" >/dev/null 2>&1
			;;
		opencode)
			jq -e '(.openai.type == "oauth") and ((.openai.access // "") != "")' "$auth_file" >/dev/null 2>&1
			;;
		*) return 1 ;;
	esac
}

select_auth_source() {
	case "$AUTH_SOURCE" in
		codex|opencode)
			if auth_has_token "$AUTH_SOURCE"; then
				SELECTED_AUTH_SOURCE="$AUTH_SOURCE"
				SELECTED_AUTH_FILE="$(auth_file_for_source "$AUTH_SOURCE")"
				return 0
			fi
			return 1
			;;
		auto)
			for candidate_source in codex opencode; do
				if auth_has_token "$candidate_source"; then
					SELECTED_AUTH_SOURCE="$candidate_source"
					SELECTED_AUTH_FILE="$(auth_file_for_source "$candidate_source")"
					return 0
				fi
			done
			return 1
			;;
		*) return 1 ;;
	esac
}

load_token_field() {
	jq -er "$1 // empty" "$SELECTED_AUTH_FILE" 2>/dev/null
}

load_access_token() {
	case "$SELECTED_AUTH_SOURCE" in
		codex) load_token_field '.tokens.access_token' ;;
		opencode) load_token_field '.openai.access' ;;
		*) return 1 ;;
	esac
}

extract_account_id_from_json() {
	printf '%s\n' "$1" | jq -er '
		def jwt_claims:
			try (
				split(".")[1] as $payload
				| ($payload | gsub("-"; "+") | gsub("_"; "/")) as $base64
				| ($base64 + ("===="[0:((4 - ($base64 | length % 4)) % 4)]))
				| @base64d
				| fromjson
			) catch empty;

		def account_id:
			.chatgpt_account_id
			// ."https://api.openai.com/auth".chatgpt_account_id
			// .organizations[0].id
			// empty;

		(.id_token? | jwt_claims | account_id)
		// (.access_token? | jwt_claims | account_id)
		// empty
	' 2>/dev/null
}

load_account_id() {
	account_id=''
	case "$SELECTED_AUTH_SOURCE" in
		codex) account_id_path='.tokens.account_id' ;;
		opencode) account_id_path='.openai.accountId' ;;
		*) account_id_path='' ;;
	esac
	if [ -n "$account_id_path" ]; then
		account_id="$(load_token_field "$account_id_path" || true)"
	fi
	if [ -z "$account_id" ]; then
		access_token="$(load_access_token || true)"
		if [ -n "$access_token" ]; then
			account_id="$(extract_account_id_from_json "$(jq -n --arg access_token "$access_token" '{access_token: $access_token}')" || true)"
		fi
	fi

	printf '%s\n' "$account_id"
}

curl_with_auth() {
	method="$1"
	url="$2"
	body="${3:-}"

	{
		printf 'header = "Authorization: Bearer %s"\n' "$ACCESS_TOKEN"
		if [ -n "$ACCOUNT_ID" ]; then
			printf 'header = "ChatGPT-Account-Id: %s"\n' "$ACCOUNT_ID"
		fi
		printf 'header = "Accept: application/json"\n'
		printf 'header = "Content-Type: application/json"\n'
	} | if [ -n "$body" ]; then
		curl -sS --max-time 15 -X "$method" -K - --data "$body" -w '\n%{http_code}' "$url"
	else
		curl -sS --max-time 15 -X "$method" -K - -w '\n%{http_code}' "$url"
	fi
}

request_json() {
	method="$1"
	url="$2"
	body="${3:-}"

	response_with_status="$(curl_with_auth "$method" "$url" "$body")"
	status="$(printf '%s\n' "$response_with_status" | tail -n 1)"
	response_body="$(printf '%s\n' "$response_with_status" | sed '$d')"

	case "$status" in
		2??)
			printf '%s\n' "$response_body"
			;;
		*)
			printf 'reset-codex: request failed with HTTP %s\n' "$status" >&2
			if [ -n "$response_body" ]; then
				printf '%s\n' "$response_body" >&2
			fi
			exit 1
			;;
	esac
}

print_usage_summary() {
	printf '%s\n' "$1" | jq -r '
		def window($name):
			.rate_limit[$name] // {};

		def pct:
			(.used_percent // 0) | round;

		def reset:
			.reset_after_seconds // 0;

		[
			"primary: " + ((window("primary_window") | pct) | tostring) + "%, reset in " + ((window("primary_window") | reset) | tostring) + "s",
			"secondary: " + ((window("secondary_window") | pct) | tostring) + "%, reset in " + ((window("secondary_window") | reset) | tostring) + "s",
			"reset credits: " + ((.rate_limit_reset_credits.available_count // 0) | tostring)
		]
		| .[]
	'
}

confirm_reset() {
	if [ "$ASSUME_YES" -eq 1 ]; then
		return 0
	fi

	if [ ! -t 0 ]; then
		printf 'reset-codex: refusing to consume a reset credit without --yes in a non-interactive shell\n' >&2
		exit 1
	fi

	printf 'Consume one Codex rate-limit reset credit? [y/N] ' >&2
	read -r answer
	case "$answer" in
		y|Y|yes|YES)
			return 0
			;;
		*)
			printf 'No reset credit consumed.\n'
			exit 0
			;;
	esac
}

generate_idempotency_key() {
	if command -v uuidgen >/dev/null 2>&1; then
		uuidgen | tr '[:upper:]' '[:lower:]'
		return
	fi

	random_hex="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
	printf 'reset-codex-%s-%s-%s\n' "$(date +%s)" "$$" "$random_hex"
}

select_auth_source || {
	printf 'reset-codex: no Codex or OpenCode ChatGPT access token found\n' >&2
	exit 1
}

ACCESS_TOKEN="$(load_access_token || true)"
ACCOUNT_ID="$(load_account_id || true)"
if [ -z "$ACCESS_TOKEN" ]; then
	printf 'reset-codex: selected auth source has no access token\n' >&2
	exit 1
fi

usage_json="$(request_json GET "$USAGE_URL")"
print_usage_summary "$usage_json"

available_count="$(printf '%s\n' "$usage_json" | jq -r '.rate_limit_reset_credits.available_count // 0')"
case "$available_count" in
	''|*[!0-9]*) available_count=0 ;;
esac

if [ "$DRY_RUN" -eq 1 ]; then
	exit 0
fi

if [ "$available_count" -le 0 ]; then
	printf 'reset-codex: no reset credits are currently available\n' >&2
	exit 1
fi

confirm_reset

idempotency_key="$(generate_idempotency_key)"
request_body="$(jq -n --arg redeem_request_id "$idempotency_key" '{redeem_request_id: $redeem_request_id}')"
reset_json="$(request_json POST "$RESET_URL" "$request_body")"

outcome_code="$(printf '%s\n' "$reset_json" | jq -r '.outcome.code // .code // .outcome // empty')"
case "$outcome_code" in
	reset)
		printf 'Codex rate limit reset applied.\n'
		;;
	nothing_to_reset)
		printf 'No reset was needed; no rate limit window was reset.\n'
		;;
	no_credit)
		printf 'No reset credit was available.\n'
		;;
	already_redeemed)
		printf 'This reset request was already redeemed.\n'
		;;
	*)
		printf 'Reset response:\n'
		printf '%s\n' "$reset_json" | jq .
		;;
esac

rm -f "$CACHE_FILE"
printf 'Cleared Codex usage cache; tmux will refresh on its next status update.\n'
