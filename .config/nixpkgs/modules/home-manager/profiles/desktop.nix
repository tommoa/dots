{ pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    # Terminal applications
    alacritty
    
    # Desktop applications
    obsidian
    spotify
    
    # Messaging
    caprine
    discord
    (if pkgs.stdenv.isLinux then whatsapp-for-linux else whatsapp-for-mac)
  ];

  programs.zen-browser.enable = true;

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
