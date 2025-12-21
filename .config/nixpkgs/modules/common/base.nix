{pkgs, ...}: {
  programs.zsh = {
    enable = true;
    # Disable slow promptinit - we set our own prompt in home-manager
    promptInit = "";
    # Disable system-level compinit - home-manager handles this
    enableGlobalCompInit = false;
  };

  # Basic programs
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  environment.systemPackages = with pkgs; [
    neovim
  ];
}
