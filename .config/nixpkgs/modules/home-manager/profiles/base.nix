{ pkgs, ... }:

{
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
