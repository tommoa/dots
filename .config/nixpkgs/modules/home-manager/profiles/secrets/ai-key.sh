#!/bin/sh

set -eu
umask 077
export LC_ALL=C

KEY_FILE="${AIKEYS_KEY_FILE:-$HOME/.ai-proxy-api-key}"
CACHE_DIR="${AIKEYS_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/aikeys-tmux-status}"
USAGE_URL="${AIKEYS_BASE_URL:-https://aikeys.infra.corp.arista.io}"
USAGE_URL="${USAGE_URL%/}/api/v1/spend"
CACHE_TTL_SECS="${AIKEYS_CACHE_TTL_SECS:-5}"
CACHE_FILE="$CACHE_DIR/spend"
LOCK_DIR="$CACHE_DIR/refresh.lock"

case "$CACHE_TTL_SECS" in
	''|*[!0-9]*) CACHE_TTL_SECS=5;;
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

print_cache() {
	if [ -s "$CACHE_FILE" ]; then
		cat "$CACHE_FILE"
		return 0
	fi

	return 1
}

extract_status() {
	jq -er '
		def spend:
			if type == "number" and isfinite and . >= 0 then . else "?" end;
		.info
		| select(type == "object")
		| (.budget_reset_at // "" | sub("\\.[0-9]+"; "")
			| sub("\\+00:00$"; "Z") | fromdateiso8601? // "") as $reset
		# The top-level spend combines both providers. Keep their daily figures separate.
		# Preserve empty slots so a missing provider never changes the order.
		| [(.providers.litellm.spend | spend), (.providers.cursor.spend | spend), $reset]
		| @tsv
	' 2>/dev/null
}

format_duration() {
	seconds=$1
	case "$seconds" in
		''|*[!0-9-]*) return 1 ;;
	esac

	if [ "$seconds" -le 0 ]; then
		printf 'now'
	elif [ "$seconds" -lt 3600 ]; then
		printf '%dm' $(((seconds + 59) / 60))
	else
		hours=$((seconds / 3600))
		minutes=$(((seconds % 3600 + 59) / 60))
		if [ "$minutes" -eq 60 ]; then
			hours=$((hours + 1))
			minutes=0
		fi

		if [ "$minutes" -gt 0 ]; then
			printf '%dh%02dm' "$hours" "$minutes"
		else
			printf '%dh' "$hours"
		fi
	fi
}

format_status() {
	spend=$1
	cursor_spend=$2
	reset_epoch=${3:-}
	[ "$spend" != '?' ] || [ "$cursor_spend" != '?' ] || return 0

	if [ -n "$reset_epoch" ]; then
		remaining=$((reset_epoch - $(now_epoch)))
		if reset_in=$(format_duration "$remaining"); then
			printf '%s ' "$reset_in"
		fi
	fi
	printf '['
	format_spend "$spend"
	printf ', '
	format_spend "$cursor_spend"
	printf ']\n'
}

format_spend() {
	if [ "$1" = '?' ]; then
		printf '?'
	else
		printf '$%.2f' "$1"
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

refresh_cache() {
	[ -r "$KEY_FILE" ] || return 0
	api_key=$(tr -d '\r\n' < "$KEY_FILE")
	[ -n "$api_key" ] || return 0

	response=$(
		printf 'header = "Authorization: Bearer %s"\nheader = "Accept: application/json"\n' "$api_key" |
			curl -sf --max-time 10 -K - "$USAGE_URL" 2>/dev/null
	) || return 0

	if status=$(printf '%s\n' "$response" | extract_status); then
		tmp_file="$CACHE_FILE.$$"
		IFS="$(printf '\t')" read -r spend cursor_spend reset_epoch <<EOF
$status
EOF
		format_status "$spend" "$cursor_spend" "$reset_epoch" > "$tmp_file"
		mv "$tmp_file" "$CACHE_FILE"
	fi
}

if [ "$(cache_age_secs)" -ge "$CACHE_TTL_SECS" ] && acquire_lock; then
	if [ "$(cache_age_secs)" -ge "$CACHE_TTL_SECS" ]; then
		# Bound retries after failures while retaining the last spending value.
		touch "$CACHE_FILE"
		refresh_cache
	fi
fi

print_cache || true
