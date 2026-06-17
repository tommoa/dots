#!/bin/sh

set -eu

PROXY_URL="${AIKEYS_PROXY_URL:-https://ai-proxy.infra.corp.arista.io}"
KEY_FILE="${AIKEYS_KEY_FILE:-$HOME/.ai-proxy-api-key}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/aikeys-tmux-status"
CACHE_FILE="$CACHE_DIR/spend"
CACHE_TTL_SECS="${AIKEYS_CACHE_TTL_SECS:-15}"
LOCK_DIR="$CACHE_DIR/refresh.lock"

case "$CACHE_TTL_SECS" in
	''|*[!0-9]*) CACHE_TTL_SECS=15 ;;
esac

PROXY_URL="${PROXY_URL%/}"

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
		def reset_epoch:
			first(
				.. | objects
				| (.budget_reset_at? // .reset_at? // .budget_reset?)
				| select(. != null)
				| tostring
				| sub("\\.[0-9]+"; "")
				| sub("\\+00:00$"; "Z")
				| fromdateiso8601?
			) // "";

		first(.. | objects | .spend? | select(. != null) | tonumber?) as $spend
		| select($spend != null)
		| [$spend, reset_epoch]
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
	elif [ "$seconds" -lt 86400 ]; then
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
	else
		days=$((seconds / 86400))
		hours=$(((seconds % 86400) / 3600))
		if [ "$hours" -gt 0 ]; then
			printf '%dd%02dh' "$days" "$hours"
		else
			printf '%dd' "$days"
		fi
	fi
}

format_status() {
	spend=$1
	reset_epoch=${2:-}

	printf '$%.2f' "$spend"
	if [ -n "$reset_epoch" ]; then
		remaining=$((reset_epoch - $(now_epoch)))
		if reset_in=$(format_duration "$remaining"); then
			printf ' %s' "$reset_in"
		fi
	fi
	printf '\n'
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
	if [ ! -r "$KEY_FILE" ]; then
		return
	fi

	api_key=$(tr -d '\r\n' < "$KEY_FILE")
	if [ -z "$api_key" ]; then
		return
	fi

	response=$(
		printf 'header = "Authorization: Bearer %s"\n' "$api_key" |
			curl -sf --max-time 10 -K - "$PROXY_URL/key/info" 2>/dev/null || true
	)

	if status=$(printf '%s\n' "$response" | extract_status); then
		tab=$(printf '\t')
		spend=${status%%"$tab"*}
		reset_epoch=
		case "$status" in
			*"$tab"*) reset_epoch=${status#*"$tab"} ;;
		esac

		tmp_file="$CACHE_FILE.$$"
		format_status "$spend" "$reset_epoch" > "$tmp_file"
		mv "$tmp_file" "$CACHE_FILE"
	fi
}

if [ "$(cache_age_secs)" -ge "$CACHE_TTL_SECS" ] && acquire_lock; then
	if [ "$(cache_age_secs)" -ge "$CACHE_TTL_SECS" ]; then
		refresh_cache
	fi
fi

print_cache || true
