{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../modules/nixos/hardware/james.nix
    ../modules/nixos/profiles/base.nix
    ../modules/nixos/profiles/desktop.nix
    ../modules/nixos/profiles/impermanence.nix
  ];

  config = {
    nixpkgs.hostPlatform = "x86_64-linux";
    networking.hostName = "james";

    my.impermanence = {
      enable = true;
      resetRoot = true;
      cleanup.enable = true;
    };

    age.secrets.login-hash.file = ../secrets/misc/peter-login-hash.age;
    users.mutableUsers = false;
    users.users.tommoa = {
      isNormalUser = true;
      description = "Tom Hill Almeida";
      hashedPasswordFile = config.age.secrets.login-hash.path;
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
  };
}
