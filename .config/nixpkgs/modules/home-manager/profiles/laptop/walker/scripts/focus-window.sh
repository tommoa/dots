set -euo pipefail

clients=$(hyprctl -j clients | jq -r '
  .[]
  | ((.title // .class // "Untitled") | gsub("[\t\r\n]+"; " ")) as $title
  | ((.class // "") | gsub("[\t\r\n]+"; " ")) as $class
  | "\($title) — \($class) [\(.address)]"
')
selection=$(printf '%s\n' "$clients" | wofi --dmenu --insensitive --prompt 'Focus window') || exit 0
address=$(printf '%s\n' "$selection" | sed -nE 's/.*\[(0x[[:xdigit:]]+)\]$/\1/p')
[[ -n "$address" ]] && hyprctl dispatch focuswindow "address:$address"
