#!/bin/sh

set -eu

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_AUTH_FILE="${CODEX_AUTH_FILE:-$CODEX_HOME/auth.json}"
OPENCODE_AUTH_FILE="${OPENCODE_AUTH_FILE:-${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json}"
AUTH_SOURCE="${CODEX_USAGE_AUTH_SOURCE:-auto}"
USAGE_URL="${CODEX_USAGE_URL:-https://chatgpt.com/backend-api/wham/usage}"
RESET_CREDITS_URL="${CODEX_RATE_LIMIT_RESET_CREDITS_URL:-https://chatgpt.com/backend-api/wham/rate-limit-reset-credits}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/codex-subscription-usage"
CACHE_FILE="$CACHE_DIR/usage.json"
CACHE_TTL_SECS="${CODEX_USAGE_CACHE_TTL_SECS:-60}"
LOCK_DIR="$CACHE_DIR/refresh.lock"

# This tmux helper only reads current access tokens. Refresh tokens are owned by
# Codex/OpenCode, and refreshing here can rotate and race with their auth caches.

case "$CACHE_TTL_SECS" in
	''|*[!0-9]*) CACHE_TTL_SECS=60 ;;
esac

now_epoch() {
	date +%s
}

file_mtime_epoch() {
	stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

cache_age_secs() {
	if [ ! -f "$CACHE_FILE" ]; then
		echo 999999
		return
	fi

	now=$(now_epoch)
	mtime=$(file_mtime_epoch "$CACHE_FILE")
	if [ "$mtime" -gt "$now" ]; then
		echo 0
	else
		echo $((now - mtime))
	fi
}

acquire_lock() {
	mkdir -p "$CACHE_DIR"
	if mkdir "$LOCK_DIR" 2>/dev/null; then
		trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT HUP INT TERM
		return 0
	fi

	return 1
}

format_seconds() {
	seconds="${1:-0}"
	case "$seconds" in
		''|*[!0-9]*) seconds=0 ;;
	esac

	if [ "$seconds" -le 0 ]; then
		printf 'now'
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
	jq '
		.rate_limit as $rate_limits
		| if $rate_limits == null then empty else

		def number_or($default):
			if . == null then $default
			elif type == "number" then .
			elif type == "string" then (tonumber? // $default)
			else $default end;

		def pct:
			.used_percent | number_or(0);

		def reset_secs:
			(
				.reset_after_seconds
				// (
					(.reset_at // null) as $reset_at
					| if $reset_at == null then null
					  elif ($reset_at | type) == "number" then ($reset_at - now | floor)
					  elif ($reset_at | type) == "string" then
						(($reset_at | tonumber?) // ($reset_at | fromdateiso8601?)) as $reset_epoch
						| if $reset_epoch == null then null else ($reset_epoch - now | floor) end
					  else null end
				)
			)
			| number_or(0)
			| if . < 0 then 0 else . end;

		def limit_secs:
			.limit_window_seconds | number_or(null);

		def meaningful_window:
			type == "object"
			and (
				has("limit_window_seconds")
				or has("reset_at")
				or ((.reset_after_seconds | number_or(0)) > 0)
				or ((.used_percent | number_or(0)) > 0)
			);

		def normalized_window($name):
			select(meaningful_window)
			| {
				name: (.name // $name),
				used_percent: pct,
				reset_after_seconds: reset_secs,
				limit_window_seconds: limit_secs
			};

		def windows:
			if (.rate_limit.windows | type) == "array" then
				.rate_limit.windows[]
				| normalized_window(.name // "window")
			else
				.rate_limit
				| to_entries[]
				| select(.key | endswith("_window"))
				| . as $entry
				| $entry.value
				| normalized_window($entry.key)
			end;

		def reset_credits_available_count:
			.rate_limit_reset_credits.available_count | number_or(null);

		def existing_reset_credits:
			.rate_limit_reset_credits // {};

		{
			credits: {
				balance: (.credits.balance // null),
				has_credits: (.credits.has_credits // null)
			},
			rate_limit_reset_credits: {
				available_count: reset_credits_available_count,
				next_expiry_after_seconds: (existing_reset_credits.next_expiry_after_seconds // null),
				expiry_after_seconds: (existing_reset_credits.expiry_after_seconds // []),
				no_expiry_count: (existing_reset_credits.no_expiry_count // 0),
				has_no_expiry: (existing_reset_credits.has_no_expiry // null)
			},
			rate_limit: {
				allowed: (if ($rate_limits | has("allowed")) then $rate_limits.allowed else null end),
				limit_reached: (if ($rate_limits | has("limit_reached")) then $rate_limits.limit_reached else null end),
				windows: [windows]
			}
		}
		end
	'
}

normalize_reset_credits_json() {
	jq -e '
		def number_or($default):
			if . == null then $default
			elif type == "number" then .
			elif type == "string" then (tonumber? // $default)
			else $default end;

		def expiry_epoch:
			if . == null then null
			elif type == "number" then .
			elif type == "string" then
				(fromdateiso8601? // (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601?))
			else null end;

		def available_credit:
			select((.status // "") == "available")
			| (.expires_at | expiry_epoch) as $expires_at
			| select($expires_at == null or $expires_at > now)
			| {
				expires_after_seconds: (
					if $expires_at == null then null
					else (($expires_at - now) | floor | if . < 0 then 0 else . end)
					end
				)
			};

		if ((.credits? | type) != "array") and ((.available_count | number_or(null)) == null) then
			empty
		else
			[.credits[]? | available_credit] as $available_credits
			| ($available_credits | map(.expires_after_seconds | select(. != null)) | sort) as $expiring_seconds
			| ($available_credits | map(select(.expires_after_seconds == null)) | length) as $no_expiry_count
			| {
				available_count: (.available_count | number_or($available_credits | length)),
				next_expiry_after_seconds: ($expiring_seconds[0] // null),
				expiry_after_seconds: $expiring_seconds,
				no_expiry_count: $no_expiry_count,
				has_no_expiry: ($no_expiry_count > 0)
			}
		end
	'
}

format_reset_credits_summary() {
	available_count="${1:-0}"
	case "$available_count" in
		''|*[!0-9]*) return 1 ;;
	esac
	[ "$available_count" -gt 0 ] || return 1

	visible_count=0
	total_count=0
	summary=''

	expiry_rows="$(jq -er '.rate_limit_reset_credits.expiry_after_seconds // [] | .[]' "$CACHE_FILE" 2>/dev/null || true)"
	if [ -n "$expiry_rows" ]; then
		while IFS= read -r expiry; do
			[ -n "$expiry" ] || continue
			total_count=$((total_count + 1))
			if [ "$visible_count" -lt 4 ]; then
				item="$(format_seconds "$expiry")"
				if [ -n "$summary" ]; then
					summary="${summary}·${item}"
				else
					summary="$item"
				fi
				visible_count=$((visible_count + 1))
			fi
		done <<EOF
$expiry_rows
EOF
	fi

	no_expiry_count="$(jq -er '.rate_limit_reset_credits.no_expiry_count // 0' "$CACHE_FILE" 2>/dev/null || printf '0')"
	case "$no_expiry_count" in
		''|*[!0-9]*) no_expiry_count=0 ;;
	esac
	while [ "$no_expiry_count" -gt 0 ]; do
		total_count=$((total_count + 1))
		if [ "$visible_count" -lt 4 ]; then
			if [ -n "$summary" ]; then
				summary="${summary}·noexp"
			else
				summary='noexp'
			fi
			visible_count=$((visible_count + 1))
		fi
		no_expiry_count=$((no_expiry_count - 1))
	done

	if [ "$total_count" -eq 0 ]; then
		return 1
	fi
	if [ "$total_count" -gt "$visible_count" ]; then
		hidden_count=$((total_count - visible_count))
		summary="${summary}·+${hidden_count}"
	fi
	printf '%s\n' "$summary"
}

print_usage_text() {
	reset_credits_available_count="$(jq -er '.rate_limit_reset_credits.available_count // empty' "$CACHE_FILE" 2>/dev/null || true)"
	reset_credits_next_expiry="$(jq -er '.rate_limit_reset_credits.next_expiry_after_seconds // empty' "$CACHE_FILE" 2>/dev/null || true)"
	reset_credits_has_no_expiry="$(jq -er '.rate_limit_reset_credits.has_no_expiry // empty' "$CACHE_FILE" 2>/dev/null || true)"
	credits_balance="$(jq -er '.credits.balance // empty' "$CACHE_FILE" 2>/dev/null || true)"
	if [ -n "$credits_balance" ]; then
		credits_balance="$(printf '%s\n' "$credits_balance" | jq -r '
			if type == "number" then .
			elif type == "string" then (tonumber? // empty)
			else empty end
			| if . >= 100 then round | tostring
			  elif . >= 10 then (. * 10 | round / 10 | tostring)
			  else (. * 100 | round / 100 | tostring)
			  end
		' 2>/dev/null || true)"
	fi

	usage_rows="$(jq -er '
		def number_or($default):
			if . == null then $default
			elif type == "number" then .
			elif type == "string" then (tonumber? // $default)
			else $default end;

		def meaningful_window:
			type == "object"
			and (
				has("limit_window_seconds")
				or has("reset_at")
				or ((.reset_after_seconds | number_or(0)) > 0)
				or ((.used_percent | number_or(0)) > 0)
			);

		.rate_limit // empty
		| if (.windows | type) == "array" then
			.windows
		  else
			[.primary_window, .secondary_window]
		  end
		| .[]
		| select(meaningful_window)
		| [
			((.reset_after_seconds | number_or(0)) | tostring),
			((.used_percent | number_or(0)) | round | tostring),
			(if (.used_percent | number_or(0)) >= 100 then "1" else "0" end)
		]
		| @tsv
	' "$CACHE_FILE")" || return 1
	[ -n "$usage_rows" ] || return 1

	usage_text=''
	while IFS="$(printf '\t')" read -r reset pct limit_hit; do
		if [ "$limit_hit" = 1 ] && [ -n "$credits_balance" ]; then
			usage_item="$(format_seconds "$reset"):${credits_balance}cr"
		else
			usage_item="$(format_seconds "$reset"):${pct}%"
		fi
		if [ -n "$usage_text" ]; then
			usage_text="${usage_text} ${usage_item}"
		else
			usage_text="$usage_item"
		fi
	done <<EOF
$usage_rows
EOF
	if [ -n "$reset_credits_available_count" ]; then
		case "$reset_credits_available_count" in
		''|*[!0-9]*) reset_credits_available_count='' ;;
		esac
	fi
	if [ -n "$reset_credits_available_count" ]; then
		if reset_credits_summary="$(format_reset_credits_summary "$reset_credits_available_count")"; then
			usage_text="${usage_text} (${reset_credits_summary})"
		elif [ "$reset_credits_available_count" -gt 0 ] && [ -n "$reset_credits_next_expiry" ]; then
			usage_text="${usage_text} ($(format_seconds "$reset_credits_next_expiry"):${reset_credits_available_count})"
		elif [ "$reset_credits_available_count" -gt 0 ] && [ "$reset_credits_has_no_expiry" = true ]; then
			usage_text="${usage_text} (noexp:${reset_credits_available_count})"
		else
			usage_text="${usage_text} (${reset_credits_available_count})"
		fi
	fi
	printf '%s\n' "$usage_text"
}

print_cache() {
	if [ -s "$CACHE_FILE" ]; then
		if print_usage_text 2>/dev/null; then
			return 0
		fi

		if normalized_json="$(normalize_usage_json < "$CACHE_FILE" 2>/dev/null)"; then
			[ -n "$normalized_json" ] || return 1
			write_normalized_usage_cache "$normalized_json" || return 1
			print_usage_text 2>/dev/null
			return $?
		fi
	fi

	return 1
}

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

select_specific_auth_source() {
	if auth_has_token "$1"; then
		SELECTED_AUTH_SOURCE="$1"
		SELECTED_AUTH_FILE="$(auth_file_for_source "$1")"
		return 0
	fi

	return 1
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

access_token_expired() {
	if [ "$SELECTED_AUTH_SOURCE" != opencode ]; then
		return 1
	fi

	expires_ms="$(load_token_field '.openai.expires' || true)"
	case "$expires_ms" in
		''|*[!0-9]*) return 1 ;;
	esac

	now_ms=$((($(now_epoch) * 1000) + 30000))
	[ "$expires_ms" -le "$now_ms" ]
}

fetch_usage() {
	access_token="${1:?missing access token}"
	account_id="${2:-}"

	{
		printf 'header = "Authorization: Bearer %s"\n' "$access_token"
		if [ -n "$account_id" ]; then
			printf 'header = "ChatGPT-Account-Id: %s"\n' "$account_id"
		fi
		printf 'header = "Accept: application/json"\n'
	} | curl -sS --max-time 10 -K - "$USAGE_URL"
}

fetch_reset_credits() {
	access_token="${1:?missing access token}"
	account_id="${2:-}"

	{
		printf 'header = "Authorization: Bearer %s"\n' "$access_token"
		if [ -n "$account_id" ]; then
			printf 'header = "ChatGPT-Account-ID: %s"\n' "$account_id"
		fi
		printf 'header = "Accept: application/json"\n'
		printf 'header = "OpenAI-Beta: codex-1"\n'
		printf 'header = "originator: Codex Desktop"\n'
	} | curl -sS --max-time 4 -K - "$RESET_CREDITS_URL"
}

response_status() {
	printf '%s\n' "$1" | jq -r '.statusCode // .status // empty' 2>/dev/null
}

write_normalized_usage_cache() {
	normalized_json="$1"
	[ -n "$normalized_json" ] || return 1

	tmp_file="$CACHE_FILE.$$"
	rm -f "$tmp_file"
	chmod 700 "$CACHE_DIR" 2>/dev/null || true
	if ! (umask 077; printf '%s\n' "$normalized_json" > "$tmp_file"); then
		rm -f "$tmp_file"
		return 1
	fi
	chmod 600 "$tmp_file" 2>/dev/null || true
	if ! mv "$tmp_file" "$CACHE_FILE"; then
		rm -f "$tmp_file"
		return 1
	fi
	chmod 600 "$CACHE_FILE" 2>/dev/null || true
}

write_usage_cache() {
	usage_json="$1"
	reset_credits_json="${2:-}"
	normalized_json="$(printf '%s\n' "$usage_json" | normalize_usage_json)" || return 1
	if [ -n "$reset_credits_json" ]; then
		reset_credits_normalized_json="$(printf '%s\n' "$reset_credits_json" | normalize_reset_credits_json 2>/dev/null || true)"
		if [ -n "$reset_credits_normalized_json" ]; then
			normalized_json="$(
				{
					printf '%s\n' "$normalized_json"
					printf '%s\n' "$reset_credits_normalized_json"
				} | jq -s '.[0] as $usage | .[1] as $reset_credits | $usage | .rate_limit_reset_credits = ((.rate_limit_reset_credits // {}) + $reset_credits)'
			)" || return 1
		fi
	fi
	write_normalized_usage_cache "$normalized_json"
}

refresh_cache_from_selected_source() {
	access_token="$(load_access_token || true)"
	account_id="$(load_account_id || true)"
	if [ -z "$access_token" ] || access_token_expired; then
		return 1
	fi

	usage_json="$(fetch_usage "$access_token" "$account_id" 2>/dev/null || true)"
	status="$(response_status "$usage_json")"
	if [ "$status" = 401 ]; then
		return 1
	fi

	reset_credits_json="$(fetch_reset_credits "$access_token" "$account_id" 2>/dev/null || true)"
	write_usage_cache "$usage_json" "$reset_credits_json"
}

refresh_cache_from_source() {
	select_specific_auth_source "$1" || return 1
	refresh_cache_from_selected_source
}

refresh_cache() {
	case "$AUTH_SOURCE" in
		codex|opencode)
			select_auth_source || return
			refresh_cache_from_selected_source || true
			;;
		auto)
			for candidate_source in codex opencode; do
				refresh_cache_from_source "$candidate_source" && return
			done
			;;
		*) return ;;
	esac
}

if [ "$(cache_age_secs)" -ge "$CACHE_TTL_SECS" ] && acquire_lock; then
	if [ "$(cache_age_secs)" -ge "$CACHE_TTL_SECS" ]; then
		refresh_cache || true
	fi
fi

print_cache || true
