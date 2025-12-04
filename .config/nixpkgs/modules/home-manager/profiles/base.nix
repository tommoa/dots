{ config, pkgs, ... }:

{
  # Agenix base configuration - just set the identity path
  # Secrets are defined in secrets/*.nix profiles
  age.identityPaths = [
    "${config.home.homeDirectory}/.ssh/id_ed25519"
  ];

  home.packages = with pkgs; [
    # Standard terminal tools
    bat
    eza
    fd
    git
    gnupg
    gnumake
    jq
    ripgrep
    tmux

    nix-your-shell

    # Terminal editing
    neovim
  ];

  programs.nix-your-shell = {
    enable = true;
    enableZshIntegration = true;
    package = pkgs.zsh;
  };

  home.stateVersion = "25.05";
  programs.home-manager.enable = true;
}
