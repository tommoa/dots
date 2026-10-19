{
  lib,
  pkgs,
  ...
}: let
  palette = import ../../../themes/one-dark.nix;
  screenshot = pkgs.writeShellApplication {
    name = "walker-screenshot";
    runtimeInputs = with pkgs; [coreutils grim slurp wl-clipboard xdg-user-dirs];
    text = builtins.readFile ./laptop/walker/scripts/screenshot.sh;
  };
  screenRecording = pkgs.writeShellApplication {
    name = "walker-record";
    runtimeInputs = with pkgs; [coreutils slurp wf-recorder xdg-user-dirs];
    text = builtins.readFile ./laptop/walker/scripts/record.sh;
  };
  windowPicker = pkgs.writeShellApplication {
    name = "walker-focus-window";
    runtimeInputs = with pkgs; [gnused hyprland jq wofi];
    text = builtins.readFile ./laptop/walker/scripts/focus-window.sh;
  };
  actionTools =
    [screenshot screenRecording windowPicker]
    ++ (with pkgs; [
      # Elephant executes menu actions with `sh -c` using this restricted PATH.
      bash
      blueman
      brightnessctl
      cliphist
      coreutils
      ghostty
      hyprland
      hyprpicker
      mako
      networkmanager
      pavucontrol
      playerctl
      # The standard client also supports TLP's compatible D-Bus interface.
      power-profiles-daemon
      procps
      rofimoji
      swaylock
      systemd
      uwsm
      wofi
      wl-clipboard
    ]);
  elephant = pkgs.elephant.override {
    enabledProviders = ["clipboard" "desktopapplications" "menus" "symbols"];
  };
  # Menus are static. Keeping their store path in ExecStart also makes menu
  # changes restart Elephant when Home Manager switches generations.
  elephantConfig = pkgs.linkFarm "elephant-config" [
    {
      name = "menus";
      path = ./laptop/walker/menus;
    }
  ];
in {
  services.elephant = {
    enable = pkgs.stdenv.isLinux;
    package = elephant;
  };

  services.walker = {
    enable = pkgs.stdenv.isLinux;
    systemd.enable = true;
  };

  xdg.configFile = {
    "walker/config.toml".source = ./laptop/walker/config.toml;
    "walker/themes/one-dark/style.css".text =
      builtins.replaceStrings
      ["@background@" "@foreground@" "@red@"]
      [palette.background palette.foreground palette.red]
      (builtins.readFile ./laptop/walker/themes/one-dark/style.css);
  };

  systemd.user.services.elephant = lib.mkIf pkgs.stdenv.isLinux {
    Unit.PartOf = ["graphical-session.target"];
    Service = {
      ExecStart = lib.mkForce "${lib.getExe elephant} --config ${elephantConfig}";
      Environment = ["PATH=${lib.makeBinPath actionTools}"];
    };
  };

  systemd.user.services.walker = lib.mkIf pkgs.stdenv.isLinux {
    Unit.PartOf = ["graphical-session.target"];
  };

  # Track text clips during the graphical session; image clipboard data is not recorded.
  systemd.user.services.cliphist = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "Clipboard history watcher";
      # UWSM imports WAYLAND_DISPLAY before reaching the Hyprland target.
      After = ["wayland-session@hyprland.desktop.target"];
      PartOf = ["wayland-session@hyprland.desktop.target"];
    };
    Service = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
    };
    Install.WantedBy = ["wayland-session@hyprland.desktop.target"];
  };
}
