{
  lib,
  pkgs,
  ...
}: let
  actionTools = with pkgs; [
    # Elephant executes menu actions with `sh -c` using this restricted PATH.
    bash
    blueman
    brightnessctl
    cliphist
    coreutils
    ghostty
    gnused
    grim
    hyprland
    hyprpicker
    jq
    mako
    networkmanager
    pavucontrol
    playerctl
    power-profiles-daemon
    procps
    rofimoji
    slurp
    swaylock
    systemd
    uwsm
    wf-recorder
    wofi
    wl-clipboard
  ];
  elephant = pkgs.elephant.override {
    enabledProviders = ["clipboard" "desktopapplications" "menus" "symbols"];
  };
  generateWalkerDevicesMenu = pkgs.writeShellApplication {
    name = "generate-walker-devices-menu";
    runtimeInputs = with pkgs; [coreutils gnugrep power-profiles-daemon];
    text =
      builtins.replaceStrings
      ["@MENUS_DIR@" "@DEVICES_MENU@" "@PERFORMANCE_MENU_ENTRY@"]
      [(toString ./laptop/walker/menus) (toString ./laptop/walker/menus/devices.toml) (toString ./laptop/performance-profile-menu-entry.toml)]
      (builtins.readFile ./laptop/generate-walker-devices-menu.sh);
  };
in {
  home.packages = [pkgs.walker elephant];

  xdg.configFile = {
    "walker/config.toml".source = ./laptop/walker/config.toml;
    "walker/themes/one-dark/style.css".source = ./laptop/walker/themes/one-dark/style.css;
  };

  systemd.user.services.elephant = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "Elephant provider service for Walker";
      PartOf = ["graphical-session.target"];
    };
    Service = {
      RuntimeDirectory = "elephant";
      ExecStartPre = "${generateWalkerDevicesMenu}/bin/generate-walker-devices-menu %t/elephant/menus";
      ExecStart = "${elephant}/bin/elephant --config %t/elephant";
      Environment = ["PATH=${lib.makeBinPath actionTools}"];
      Restart = "on-failure";
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  systemd.user.services.walker = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "Walker application launcher service";
      PartOf = ["graphical-session.target"];
      Requires = ["elephant.service"];
      After = ["elephant.service"];
    };
    Service = {
      ExecStart = "${pkgs.walker}/bin/walker --gapplication-service";
      Restart = "on-failure";
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  # Track text clips during the graphical session; image clipboard data is not recorded.
  systemd.user.services.cliphist = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "Clipboard history watcher";
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
