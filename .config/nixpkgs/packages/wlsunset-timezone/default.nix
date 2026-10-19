{
  lib,
  runCommand,
  python3,
  bash,
  tzdata,
  wlsunset,
  timeZone,
}: let
  args =
    [
      "--shell"
      "${bash}/bin/bash"
      "--wlsunset"
      "${wlsunset}/bin/wlsunset"
    ]
    ++ lib.optionals (timeZone != null) [
      "--zone-tab"
      "${tzdata}/share/zoneinfo/zone.tab"
      "--timezone"
      timeZone
    ];
in
  runCommand "wlsunset-timezone" {nativeBuildInputs = [python3];} ''
    mkdir -p "$out/bin"
    python ${./generate-launcher.py} ${lib.escapeShellArgs args} > "$out/bin/wlsunset"
    chmod +x "$out/bin/wlsunset"
  ''
