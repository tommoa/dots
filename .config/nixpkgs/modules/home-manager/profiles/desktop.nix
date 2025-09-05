{ pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    # Terminal applications
    alacritty
    
    # Desktop applications
    bitwarden
    obsidian
    spotify
    
    # Messaging
    caprine
    discord
    (if pkgs.stdenv.isLinux then whatsapp-for-linux else whatsapp-for-mac)
  ];

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
}
