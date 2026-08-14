# Shared CLIProxyAPI credential discovery.  The output is deliberately a
# tab-separated internal format: account ID, email and credential file.

cli_proxy_active_accounts() {
  for account_file in "$CLI_PROXY_AUTH_DIR"/codex-*.json; do
    [ -r "$account_file" ] || continue
    jq -er '
      select(.type == "codex")
      | select((.access_token // "") != "")
      | select((.account_id // "") != "")
      | select((.email // "") != "")
      | select((.disabled // false) | not)
      | [.account_id, .email, input_filename] | @tsv
    ' "$account_file" 2>/dev/null || true
  done | LC_ALL=C sort -t "$(printf '\t')" -k3,3
}

cli_proxy_account_count() {
  cli_proxy_active_accounts | sed -n '$='
}

# Sets SELECTED_AUTH_SOURCE, SELECTED_AUTH_FILE, SELECTED_ACCOUNT_ID and
# SELECTED_ACCOUNT_EMAIL.  Return 2 when a selector remains ambiguous.
cli_proxy_select_account() {
  selector="${1:-}"
  matches=0
  selected_row=''
  while IFS="$(printf '\t')" read -r account_id email account_file; do
    [ -n "$account_file" ] || continue
    if [ -z "$selector" ] || [ "$selector" = "$account_id" ] || [ "$selector" = "$email" ]; then
      if [ "$matches" -eq 0 ]; then
        matches=1
        selected_row="$account_id	$email	$account_file"
      else
        matches=$((matches + 1))
      fi
    fi
  done <<EOF
$(cli_proxy_active_accounts)
EOF
  case "$matches" in
    1)
      IFS="$(printf '\t')" read -r SELECTED_ACCOUNT_ID SELECTED_ACCOUNT_EMAIL SELECTED_AUTH_FILE <<EOF
$selected_row
EOF
      SELECTED_AUTH_SOURCE=cli-proxy
      export SELECTED_AUTH_SOURCE SELECTED_AUTH_FILE SELECTED_ACCOUNT_ID SELECTED_ACCOUNT_EMAIL
      return 0
      ;;
    0) return 1 ;;
    *) return 2 ;;
  esac
}
