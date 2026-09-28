{
  lib,
  pkgs,
  ...
}: let
  settings = import ./waybar/settings.nix {
    inherit lib pkgs;
  };
in {
  programs.waybar = {
    enable = true;
    settings.mainBar = settings;
    style = ./waybar/style.css;
    systemd = {
      enable = true;
      targets = ["wayland-session@hyprland.desktop.target"];
    };
  };
}
