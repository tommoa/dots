{
  config,
  lib,
  osConfig ? {},
  pkgs,
  ...
}: let
  palette = import ../../../themes/one-dark.nix;
  devices = config.my.walker.devices;
  screenshot = pkgs.writeShellApplication {
    name = "walker-screenshot";
    runtimeInputs = with pkgs; [coreutils grim slurp wl-clipboard xdg-user-dirs];
    text = builtins.readFile ./walker/scripts/screenshot.sh;
  };
  screenRecording = pkgs.writeShellApplication {
    name = "walker-record";
    runtimeInputs = with pkgs; [coreutils slurp wf-recorder xdg-user-dirs];
    text = builtins.readFile ./walker/scripts/record.sh;
  };
  windowPicker = pkgs.writeShellApplication {
    name = "walker-focus-window";
    runtimeInputs = with pkgs; [gnused hyprland jq wofi];
    text = builtins.readFile ./walker/scripts/focus-window.sh;
  };
  actionTools =
    [screenshot screenRecording windowPicker]
    ++ (with pkgs; [
      # Elephant executes menu actions with `sh -c` using this restricted PATH.
      bash
      cliphist
      coreutils
      ghostty
      hyprland
      hyprpicker
      mako
      networkmanager
      pavucontrol
      playerctl
      procps
      rofimoji
      swaylock
      systemd
      uwsm
      wofi
      wl-clipboard
    ])
    ++ lib.optional devices.bluetooth.enable pkgs.blueman
    ++ lib.optional devices.brightness.enable pkgs.brightnessctl
    # The standard client also supports TLP's compatible D-Bus interface.
    ++ lib.optional devices.powerProfiles.enable pkgs.power-profiles-daemon;
  elephant = pkgs.elephant.override {
    enabledProviders = ["clipboard" "desktopapplications" "menus" "symbols"];
  };
  menus = pkgs.linkFarm "elephant-menus" (
    map (name: {
      inherit name;
      path = ./walker/menus + "/${name}";
    }) (builtins.attrNames (builtins.readDir ./walker/menus))
    ++ [
      {
        name = "devices.toml";
        path = (pkgs.formats.toml {}).generate "devices.toml" (import ./walker/devices.nix {
          inherit lib;
          bluetoothEnabled = devices.bluetooth.enable;
          brightnessEnabled = devices.brightness.enable;
          powerProfilesEnabled = devices.powerProfiles.enable;
        });
      }
    ]
  );
  # Menus are static. Keeping their store path in ExecStart also makes menu
  # changes restart Elephant when Home Manager switches generations.
  elephantConfig = pkgs.linkFarm "elephant-config" [
    {
      name = "menus";
      path = menus;
    }
  ];
in {
  options.my.walker.devices = {
    bluetooth.enable =
      lib.mkEnableOption "Walker Bluetooth controls"
      // {
        default = osConfig.hardware.bluetooth.enable or false;
      };
    brightness.enable = lib.mkEnableOption "Walker backlight controls";
    powerProfiles.enable =
      lib.mkEnableOption "Walker power profile controls"
      // {
        default =
          (osConfig.services.power-profiles-daemon.enable or false)
          || (osConfig.services.tlp.pd.enable or false);
      };
  };

  config = {
    services.elephant = {
      enable = pkgs.stdenv.isLinux;
      package = elephant;
    };

    services.walker = {
      enable = pkgs.stdenv.isLinux;
      systemd.enable = true;
    };

    xdg.configFile = {
      # Walker runs `elephant listproviders` with Elephant's default config path.
      # Keep discovery in sync with the service's immutable menu configuration.
      "elephant/menus".source = menus;
      "walker/config.toml".source = ./walker/config.toml;
      "walker/themes/one-dark/style.css".text =
        builtins.replaceStrings
        ["@background@" "@foreground@" "@red@"]
        [palette.background palette.foreground palette.red]
        (builtins.readFile ./walker/themes/one-dark/style.css);
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
  };
}
