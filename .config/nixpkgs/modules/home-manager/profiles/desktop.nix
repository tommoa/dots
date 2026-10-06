{
  pkgs,
  lib,
  timeZone ? "Australia/Sydney",
  ...
}: let
  palette = import ../../../themes/palenight.nix;
  wallpaper = "/Users/toma/Pictures/image30.jpg";
  zoneTab = builtins.readFile "${pkgs.tzdata}/share/zoneinfo/zone.tab";
  zoneEntries = builtins.filter (line: line != "" && builtins.substring 0 1 line != "#") (lib.splitString "\n" zoneTab);
  zoneEntry = lib.findFirst (line: builtins.elemAt (lib.splitString "\t" line) 2 == timeZone) null zoneEntries;

  digitsToInt = digits:
    lib.foldl' (value: digit: value * 10 + builtins.fromJSON digit) 0 (lib.stringToCharacters digits);

  decimalCoordinate = coordinate: let
    sign =
      if builtins.substring 0 1 coordinate == "-"
      then -1
      else 1;
    length = builtins.stringLength coordinate;
    degreeDigits =
      if length == 5 || length == 7
      then 2
      else 3;
    degrees = digitsToInt (builtins.substring 1 degreeDigits coordinate);
    minutes = digitsToInt (builtins.substring (1 + degreeDigits) 2 coordinate);
    seconds =
      if length == degreeDigits + 5
      then digitsToInt (builtins.substring (3 + degreeDigits) 2 coordinate)
      else 0;
  in
    sign * (degrees + minutes / 60.0 + seconds / 3600.0);

  roundOneDecimal = value: let
    magnitude =
      if value < 0
      then -value
      else value;
    rounded = builtins.floor (magnitude * 10.0 + 0.5) / 10.0;
  in
    if value < 0
    then -rounded
    else rounded;

  zoneCoordinates =
    if zoneEntry == null
    then throw "No representative coordinates found in tzdata for timezone ${timeZone}"
    else let
      fields = lib.splitString "\t" zoneEntry;
      encodedCoordinates = builtins.elemAt fields 1;
      coordinates = builtins.match "([+-][0-9]+)([+-][0-9]+)" encodedCoordinates;
      latitude = decimalCoordinate (builtins.elemAt coordinates 0);
      longitude = decimalCoordinate (builtins.elemAt coordinates 1);
    in {
      latitude = roundOneDecimal latitude;
      longitude = roundOneDecimal longitude;
    };
in {
  imports = [./zen-browser.nix];

  home.activation.setWallpaper = lib.mkIf pkgs.stdenv.isDarwin (
    lib.hm.dag.entryAfter ["linkGeneration"] ''
      /usr/bin/osascript -e 'tell application "Finder" to set desktop picture to POSIX file "${wallpaper}"'
    ''
  );

  home.packages = with pkgs;
    lib.optionals pkgs.stdenv.isLinux [
      # Desktop applications
      bitwarden-desktop
      chatgpt-desktop
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      # Desktop applications
      chatgpt
    ]
    ++ [
      # Desktop applications
      obsidian

      # Messaging
      caprine
      discord
    ]
    ++ (
      if pkgs.stdenv.isLinux
      then [
        blueman
        brightnessctl
        grim
        pavucontrol
        playerctl
        wl-clipboard
      ]
      else []
    );

  programs.ghostty = {
    enable = true;
    package =
      if pkgs.stdenv.isLinux
      then pkgs.ghostty
      else pkgs.ghostty-bin;
    systemd.enable = pkgs.stdenv.isLinux;
    settings = {
      # Set the theme to what I like (One Dark).
      theme = "One Half Dark";
      font-size = 15;
      font-family = "monospace";
      font-thicken = true;

      # Turn off window decoration.
      window-decoration = false;

      # macOS: Ensure that left-option gives "alt" values
      macos-option-as-alt = "left";

      # Always close ghostty when the last thing is closed.
      confirm-close-surface = false;

      keybind = [
        "global:super+enter=new_window"
      ];
    };
  };

  gtk = {
    enable = pkgs.stdenv.isLinux;
    colorScheme = "dark";
    iconTheme = {
      name = "Pop";
      package = pkgs.pop-icon-theme;
    };
    cursorTheme = {
      name = "Pop";
      package = pkgs.pop-icon-theme;
    };
    theme = {
      name = "Pop-dark";
      package = pkgs.pop-gtk-theme;
    };
    gtk4.theme = null;
  };

  home.pointerCursor = lib.mkIf pkgs.stdenv.isLinux {
    gtk.enable = true;
    package = pkgs.pop-icon-theme;
    name = "Pop";
  };

  systemd.user.services.swaybg = lib.mkIf pkgs.stdenv.isLinux {
    # UWSM's compositor-specific target keeps the wallpaper scoped to Hyprland.
    # The graphical-session target could also start it in unrelated Wayland sessions.
    Unit = {
      Description = "Wayland wallpaper background";
      PartOf = ["wayland-session@hyprland.desktop.target"];
      After = ["wayland-session@hyprland.desktop.target"];
      # The selected image lives outside the flake and may be absent on a new host.
      ConditionPathExists = "%h/img/wallpapers/current";
    };
    Service = {
      ExecStart = "${pkgs.swaybg}/bin/swaybg -i %h/img/wallpapers/current -m fill";
      Restart = "on-failure";
    };
    Install.WantedBy = ["wayland-session@hyprland.desktop.target"];
  };

  services.swayidle = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    systemdTargets = ["wayland-session@hyprland.desktop.target"];
    timeouts = [
      {
        timeout = 300;
        command = "${pkgs.swaylock}/bin/swaylock -f";
      }
      {
        timeout = 600;
        command = "${pkgs.hyprland}/bin/hyprctl dispatch dpms off";
        resumeCommand = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
      }
    ];
    events."before-sleep" = "${pkgs.swaylock}/bin/swaylock -f";
  };

  # wayland.windowManager.hyprland = {
  #   enable = pkgs.stdenv.isLinux;
  #   package = null;
  #   portalPackage = null;
  # };

  programs.swaylock = {
    enable = pkgs.stdenv.isLinux;
    settings = {
      color = palette.background;
      ring-color = palette.muted;
      inside-color = palette.cyan;
      key-hl-color = palette.blue;
      inside-wrong-color = palette.red;
      bs-hl-color = palette.magenta;
      ring-ver-color = palette.green;
      inside-ver-color = palette.green;
      inside-clear-color = palette.yellow;
    };
  };
  programs.wofi = {
    enable = pkgs.stdenv.isLinux;
    settings = {
      run-always_parse_args = true;
      insensitive = true;
    };
    style =
      builtins.replaceStrings
      ["@background@" "@red@" "@muted@" "@white@"]
      [palette.background palette.red palette.muted palette.white]
      (builtins.readFile ./desktop/wofi/style.css);
  };

  # Home Manager owns these generated files. Replace the former regular
  # dotfiles on activation so later settings and palette changes update them.
  xdg.configFile = lib.mkIf pkgs.stdenv.isLinux {
    "swaylock/config".force = true;
    "wofi/config".force = true;
    "wofi/style.css".force = true;
  };

  services.mako = {
    enable = pkgs.stdenv.isLinux;
    settings = {
      default-timeout = 10000;
      border-color = "#${lib.toUpper palette.magenta}";
      text-color = "#${palette.foreground}";
      background-color = "#${palette.background}";
      "mode=do-not-disturb" = {
        invisible = true;
      };
    };
  };
  services.swayosd = {
    enable = pkgs.stdenv.isLinux;
  };
  services.wlsunset = {
    # Automatic timezone mode has no build-time location; keep the former
    # 06:00–19:00 schedule until a fixed timezone provides coordinates.
    enable = pkgs.stdenv.isLinux;
    latitude =
      if timeZone == null
      then null
      else zoneCoordinates.latitude;
    longitude =
      if timeZone == null
      then null
      else zoneCoordinates.longitude;
    sunrise =
      if timeZone == null
      then "06:00"
      else null;
    sunset =
      if timeZone == null
      then "19:00"
      else null;
    temperature = {
      day = 6500;
      night = 4500;
    };
  };
}
