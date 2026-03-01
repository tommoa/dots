{
  pkgs,
  lib,
  ...
}:
{
  home.packages =
    with pkgs;
    [
      # Desktop applications
      bitwarden-desktop
      obsidian

      # Messaging
      caprine
      discord
      (if pkgs.stdenv.isLinux then wasistlos else whatsapp-for-mac)
    ]
    ++ (
      if pkgs.stdenv.isLinux then
        [
          blueberry
          brightnessctl
          grim
          hyprsunset
          pavucontrol
          playerctl
          swaybg
          wl-clipboard
        ]
      else
        [ ]
    );

  programs.ghostty = {
    enable = true;
    package = if pkgs.stdenv.isLinux then pkgs.ghostty else pkgs.ghostty-bin;
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
    policies =
      let
        mkExtensionSettings = builtins.mapAttrs (
          _: pluginId: {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/${pluginId}/latest.xpi";
            installation_mode = "force_installed";
          }
        );
      in
      {
        Extensions = mkExtensionSettings {
          "uBlock0@raymondhill.net" = "ublock-origin";
          "{446900e4-71c2-419f-a6a7-df9c091e268b}" = "bitwarden-password-manager";
          "@testpilot-containers" = "multi-account-containers";
          "@contain-facebook" = "facebook-container";
          "{04188724-64d3-497b-a4fd-7caffe6eab29}" = "rust-search-extension";
        };
      };
    nativeMessagingHosts = [
      pkgs.bitwarden-desktop
      (lib.mkIf pkgs.stdenv.isLinux pkgs.firefoxpwa)
    ];
  };

  gtk = {
    enable = pkgs.stdenv.isLinux;
    iconTheme = {
      name = "Pop-dark";
      package = pkgs.pop-icon-theme;
    };
    cursorTheme = {
      name = "Pop";
      package = pkgs.pop-gtk-theme;
    };
    theme = {
      name = "Pop-dark";
      package = pkgs.pop-gtk-theme;
    };
  };

  home.pointerCursor = lib.mkIf pkgs.stdenv.isLinux {
    gtk.enable = true;
    package = pkgs.pop-gtk-theme;
    name = "Pop";
  };

  # wayland.windowManager.hyprland = {
  #   enable = pkgs.stdenv.isLinux;
  #   package = null;
  #   portalPackage = null;
  # };

  programs.waybar = {
    enable = pkgs.stdenv.isLinux;
  };
  # xdg.configFile."waybar/config.jsonc".source = ./waybar/config.jsonc;
  # xdg.configFile."waybar/style.css".source = ./waybar/style.css;
  programs.swaylock = {
    enable = pkgs.stdenv.isLinux;
  };
  programs.wofi = {
    enable = pkgs.stdenv.isLinux;
  };

  services.mako = {
    enable = pkgs.stdenv.isLinux;
  };
  services.swayidle = {
    enable = pkgs.stdenv.isLinux;
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
