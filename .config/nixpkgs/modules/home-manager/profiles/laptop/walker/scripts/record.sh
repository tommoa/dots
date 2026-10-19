set -euo pipefail

if [[ $# != 1 || ! $1 =~ ^(full|region)$ ]]; then
  echo "Usage: walker-record {full|region}" >&2
  exit 2
fi

geometry_args=()
if [[ $1 == region ]]; then
  # Status 1 can mean cancellation or a display error; preserve Slurp's failure.
  geometry=$(slurp)
  geometry_args=(-g "$geometry")
fi

directory="$(xdg-user-dir VIDEOS)/Recordings"
mkdir -p "$directory"
# Keep the recorder's process name for Waybar and the menu's SIGINT stop action.
exec wf-recorder "${geometry_args[@]}" -f "$directory/recording-$(date +%Y-%m-%d_%H-%M-%S).mp4" >/dev/null 2>&1
