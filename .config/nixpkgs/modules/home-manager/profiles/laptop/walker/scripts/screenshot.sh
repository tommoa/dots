set -euo pipefail

if [[ $# != 2 || ! $1 =~ ^(full|region)$ || ! $2 =~ ^(copy|save)$ ]]; then
  echo "Usage: walker-screenshot {full|region} {copy|save}" >&2
  exit 2
fi

geometry_args=()
if [[ $1 == region ]]; then
  # Status 1 can mean cancellation or a display error; preserve Slurp's failure.
  geometry=$(slurp)
  geometry_args=(-g "$geometry")
fi

if [[ $2 == copy ]]; then
  # Report capture failures even when wl-copy succeeds.
  grim "${geometry_args[@]}" - | wl-copy --type image/png
else
  directory="$(xdg-user-dir PICTURES)/Screenshots"
  mkdir -p "$directory"
  grim "${geometry_args[@]}" "$directory/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png"
fi
