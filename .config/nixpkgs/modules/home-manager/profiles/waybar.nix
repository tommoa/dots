{
  config,
  lib,
  pkgs,
  ...
}: let
  statusPalette = import ../../../themes/one-dark.nix;
  palette = import ../../../themes/palenight.nix;
  waybarWithIdleInhibitorSignal = pkgs.waybar.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or []) ++ [./waybar/idle-inhibitor-signal.patch];
  });
  settings = import ./waybar/settings.nix {
    inherit lib pkgs;
    batteryEnabled = config.my.waybar.battery.enable;
    powerProfilesEnabled = config.my.waybar.powerProfiles.enable;
  };
in {
  options.my.waybar = {
    battery.enable = lib.mkEnableOption "the Waybar battery status module";

    powerProfiles.enable = lib.mkEnableOption "the Waybar power profiles daemon module";
  };

  config.programs.waybar = {
    enable = true;
    package = waybarWithIdleInhibitorSignal;
    settings.mainBar = settings;
    style =
      builtins.replaceStrings
      ["@background@" "@muted@" "@red@" "@yellow@" "@white@"]
      [palette.background palette.muted statusPalette.red statusPalette.yellow palette.white]
      (builtins.readFile ./waybar/style.css);
    systemd = {
      enable = true;
      targets = ["wayland-session@hyprland.desktop.target"];
    };
  };
}
