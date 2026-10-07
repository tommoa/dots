{
  config,
  pkgs,
  ...
}: let
  palette = import ../themes/one-dark.nix;
in {
  nixpkgs.hostPlatform = "x86_64-linux";

  imports = [
    ../modules/nixos/hardware/peter.nix
    ../modules/nixos/profiles/base.nix
    ../modules/nixos/profiles/desktop.nix
    ../modules/nixos/profiles/laptop.nix
    ../modules/nixos/profiles/impermanence.nix
    ../modules/nixos/profiles/kanata.nix
  ];

  # Enable deletion after the live layout and legacy roots have been inspected.
  my.impermanence = {
    enable = true;
    resetRoot = true;
    cleanup.enable = false;
  };

  age.secrets.peter-login-hash.file = ../secrets/misc/peter-login-hash.age;
  users.mutableUsers = false;
  users.users.tommoa.hashedPasswordFile = config.age.secrets.peter-login-hash.path;

  networking.hostName = "peter";
  time.timeZone = "Australia/Sydney";

  # Test the touchpad's alternate bus to see whether it removes input lag.
  boot.kernelParams = ["psmouse.synaptics_intertouch=1"];

  # Apply the shared Feral-derived layout to this laptop's built-in keyboard.
  services.kanata.keyboards.laptop.devices = [
    "/dev/input/by-path/platform-i8042-serio-0-event-kbd"
  ];

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

  # Apply the selected ANSI palette so tuigreet's named colours use its shades.
  console.colors = with palette; [
    background
    red
    green
    yellow
    blue
    magenta
    cyan
    foreground
    brightBlack
    red
    green
    yellow
    blue
    magenta
    cyan
    brightWhite
  ];

  security.pam.services.greetd.enableGnomeKeyring = true;
}
