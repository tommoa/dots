auth_dir="${1:-$default_auth_dir}"
[ -d "$auth_dir" ] || exit 0
# Let the running gateway serialize updates with token refreshes.
# An explicit directory is for offline credentials (including fixtures).
if [ "$#" -eq 0 ]; then
  if accounts=$(curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 \
    -H 'Authorization: Bearer local' "$management_url/auth-files" 2>/dev/null); then
    patches=$(jq -c --argjson priorities "$priorities" '
      .files[] | select(.provider == "codex")
      | select(.email | type == "string")
      | .email as $email
      | select($priorities | has($email))
      | select(.priority != $priorities[$email])
      | {name, priority: $priorities[$email]}
    ' <<< "$accounts")
    while IFS= read -r patch; do
      [ -n "$patch" ] || continue
      curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 \
        -X PATCH -H 'Authorization: Bearer local' -H 'Content-Type: application/json' \
        --data-binary "$patch" "$management_url/auth-files/fields" >/dev/null
    done <<< "$patches"
    exit 0
  else
    status=$?
    # Only connection refusal means it is safe to edit offline files.
    if [ "$status" -ne 7 ]; then
      echo "cli-proxy-api-apply-priorities: management API failed (curl $status)" >&2
      exit "$status"
    fi
  fi
fi
temporary_file=""
trap 'if [ -n "$temporary_file" ]; then rm -f -- "$temporary_file"; fi' EXIT
umask 077

for account_file in "$auth_dir"/*.json; do
  [ -f "$account_file" ] || continue
  # Only inspect credential metadata; never print tokens or rewrite
  # configuration files, unknown accounts, or unchanged credentials.
  if ! jq -e --argjson priorities "$priorities" '
    select(type == "object" and .type == "codex")
    | select(.email | type == "string")
    | .email as $email
    | ($priorities | has($email)) and (.priority != $priorities[$email])
  ' "$account_file" >/dev/null 2>&1; then
    continue
  fi
  temporary_file=$(mktemp "$auth_dir/.priority-XXXXXX")
  jq --argjson priorities "$priorities" '.priority = $priorities[.email]' \
    "$account_file" > "$temporary_file"
  mv -f -- "$temporary_file" "$account_file"
  temporary_file=""
done
