{
  inputs,
  pkgs,
  ...
}: {
  nixpkgs.hostPlatform = "x86_64-linux";

  imports = [
    ../modules/nixos/hardware/peter.nix
    ../modules/nixos/profiles/base.nix
    ../modules/nixos/profiles/desktop.nix
    ../modules/nixos/profiles/laptop.nix
    ../modules/nixos/profiles/impermanence.nix
    inputs.impermanence.nixosModules.impermanence
  ];

  networking.hostName = "peter";
  time.timeZone = "Australia/Perth";

  # Test the touchpad's alternate bus to see whether it removes input lag.
  boot.kernelParams = ["psmouse.synaptics_intertouch=1"];

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
  services.displayManager.defaultSession = "hyprland-uwsm";
}
