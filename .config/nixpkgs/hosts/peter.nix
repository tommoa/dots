{
  config,
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
    ../modules/nixos/profiles/kanata.nix
  ];

  # Keep this machine's SSH host key on persistent storage for initrd agenix.
  services.openssh.hostKeys = [
    {
      type = "ed25519";
      path = "/persist/etc/agenix/identity";
    }
  ];
  age.identityPaths = ["/persist/etc/agenix/identity"];

  age.secrets.peter-login-hash.file = ../secrets/misc/peter-login-hash.age;
  users.mutableUsers = false;
  users.users.tommoa.hashedPasswordFile = config.age.secrets.peter-login-hash.path;

  networking.hostName = "peter";
  time.timeZone = "Australia/Perth";

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

  # Auto login
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "tommoa";
  services.displayManager.defaultSession = "hyprland-uwsm";
}
