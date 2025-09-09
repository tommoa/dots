{ pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    # Desktop applications
    bitwarden
    obsidian
    spotify
    
    # Messaging
    caprine
    discord
    (if pkgs.stdenv.isLinux then whatsapp-for-linux else whatsapp-for-mac)
  ] ++ (if pkgs.stdenv.isLinux
          then [
            swaybg
            grim
            pavucontrol
            playerctl
            wl-clipboard
          ] else []);

  programs.alacritty.enable = true;

  programs.zen-browser = {
    enable = true;
    nativeMessagingHosts = [
      pkgs.bitwarden
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
  services.wlsunset = {
    enable = pkgs.stdenv.isLinux;
    temperature.night = 3500;
    latitude = -33.9;
    longitude = 151.2;
  };
}
