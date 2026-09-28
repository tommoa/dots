{
  pkgs,
  lib,
  ...
}: let
  wallpaper = "/Users/toma/Pictures/image30.jpg";
in {
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
        hyprsunset
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

      keybind = [
        "global:super+enter=new_window"
      ];
    };
  };

  programs.zen-browser = {
    enable = true;
    darwin.packageMode = "wrapped";
    policies = let
      mkExtensionSettings = builtins.mapAttrs (
        _: pluginId: {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/${pluginId}/latest.xpi";
          installation_mode = "force_installed";
        }
      );
    in {
      ExtensionSettings = mkExtensionSettings {
        "uBlock0@raymondhill.net" = "ublock-origin";
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = "bitwarden-password-manager";
        "@testpilot-containers" = "multi-account-containers";
        "@contain-facebook" = "facebook-container";
        "{04188724-64d3-497b-a4fd-7caffe6eab29}" = "rust-search-extension";
        "enhancerforyoutube@maximerf.addons.mozilla.org" = "enhancer-for-youtube";
        "{c49b13b1-5dee-4345-925e-0c793377e3fa}" = "youtube-enhancer-vc";
      };
    };
    nativeMessagingHosts =
      [
        (lib.mkIf pkgs.stdenv.isLinux pkgs.firefoxpwa)
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [pkgs.bitwarden-desktop];
  };

  gtk = {
    enable = pkgs.stdenv.isLinux;
    iconTheme = {
      name = "Pop-dark";
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
    gtk4.theme = {
      name = "Pop-dark";
      package = pkgs.pop-gtk-theme;
    };
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

  # wayland.windowManager.hyprland = {
  #   enable = pkgs.stdenv.isLinux;
  #   package = null;
  #   portalPackage = null;
  # };

  programs.swaylock = {
    enable = pkgs.stdenv.isLinux;
  };
  programs.wofi = {
    enable = pkgs.stdenv.isLinux;
  };

  services.mako = {
    enable = pkgs.stdenv.isLinux;
    settings = {
      default-timeout = 10000;
      border-color = "#C792EA";
      text-color = "#959dcb";
      background-color = "#292d3e";
      "mode=do-not-disturb" = {
        invisible = true;
      };
    };
  };
  services.swayosd = {
    enable = pkgs.stdenv.isLinux;
  };
  services.hyprsunset = {
    enable = pkgs.stdenv.isLinux;
    settings = {
      profile = [
        {
          time = "06:00";
          temperature = 6500;
        }
        {
          time = "19:00";
          temperature = 4500;
        }
      ];
    };
  };
}
