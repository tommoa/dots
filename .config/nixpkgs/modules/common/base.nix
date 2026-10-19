{...}: {
  programs.zsh = {
    enable = true;
    # Disable slow promptinit - we set our own prompt in home-manager
    promptInit = "";
    # Disable system-level compinit - home-manager handles this
    enableGlobalCompInit = false;
  };

  # System GPG agent and its SSH agent integration.
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };
}
