{pkgs, ...}: {
  nixpkgs.hostPlatform = "x86_64-linux";

  imports = [
    ../modules/nixos/hardware/james.nix
    ../modules/nixos/profiles/base.nix
    ../modules/nixos/profiles/desktop.nix
  ];

  networking.hostName = "james";

  users.users.tommoa = {
    isNormalUser = true;
    description = "Tom Hill Almeida";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    shell = pkgs.zsh;
    packages = [];
  };

  # Auto login
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "tommoa";

  # Workaround for GNOME autologin.
  # TODO(james): Check on James whether nixpkgs still needs this. Local eval
  # suggests GDM autologin no longer starts getty/autovt on tty1, but this
  # should be verified on the actual NixOS host before removing it.
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;
}
