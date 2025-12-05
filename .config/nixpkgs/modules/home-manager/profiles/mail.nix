{
  pkgs,
  config,
  lib,
  ...
}:

{
  # Import account and program configurations
  imports = [
    ./mail/aerc.nix
    ./mail/accounts/personal.nix
    ./mail/accounts/work.nix
    ./mail/accounts/tommoa.nix
  ];

  home.packages = with pkgs; [
    notmuch # Email indexing and tagging
    w3m # HTML email viewing in aerc
  ];

  # Configure base maildir path
  accounts.email.maildirBasePath = ".mail";

  # Enable mbsync with home-manager
  programs.mbsync = {
    enable = true;
    package = pkgs.isync.override {
      withCyrusSaslXoauth2 = true;
    };
  };

  # Enable msmtp with home-manager
  programs.msmtp = {
    enable = true;
  };

  # Enable imapnotify service for automatic mail sync
  services.imapnotify.enable = true;

  # Ensure mail directories exist
  home.file.".mail/.keep".text = "";
}
