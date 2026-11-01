{
  pkgs,
  lib,
  config,
  timeZone ? "Australia/Sydney",
  ...
}: let
  palette = import ../../../themes/palenight.nix;
  wallpaper = "/Users/toma/Pictures/image30.jpg";
  timezoneWlsunset = pkgs.callPackage ../../../packages/wlsunset-timezone {inherit timeZone;};
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
      t3code-desktop

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
        wlsunset
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
  # The launcher resolves coordinates during its build. Home Manager's wlsunset
  # module requires coordinates during evaluation, so retain its session binding
  # here while using the configured timezone as the only location input.
  systemd.user.services.wlsunset = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "Day/night gamma adjustments for Wayland compositors.";
      After = [config.wayland.systemd.target];
      PartOf = [config.wayland.systemd.target];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service.ExecStart = "${timezoneWlsunset}/bin/wlsunset -t 4500 -T 6500 -g 1.0";
    Install = {
      WantedBy = [config.wayland.systemd.target];
    };
  };
}
