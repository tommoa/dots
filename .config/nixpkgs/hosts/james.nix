{pkgs, ...}: {
  nixpkgs.hostPlatform = "x86_64-linux";

  imports = [
    ../modules/nixos/hardware/james.nix
    ../modules/nixos/profiles/base.nix
    ../modules/nixos/profiles/desktop.nix
    ../modules/nixos/profiles/impermanence.nix
  ];

  networking.hostName = "james";

  my.impermanence = {
    enable = true;
    resetRoot = true;
    cleanup.enable = true;
  };

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

  # Keep the existing desktop autologin behaviour.
  services.greetd.settings.initial_session = {
    user = "tommoa";
    command = "uwsm start hyprland.desktop";
  };
}
