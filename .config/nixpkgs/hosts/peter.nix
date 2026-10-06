{
  lib,
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

  # Use a One Dark ANSI palette on the virtual console so tuigreet's named
  # colors render with the corresponding One Dark shades.
  console.colors = [
    "282c34"
    "e06c75"
    "98c379"
    "e5c07b"
    "61afef"
    "c678dd"
    "56b6c2"
    "abb2bf"
    "5c6370"
    "e06c75"
    "98c379"
    "e5c07b"
    "61afef"
    "c678dd"
    "56b6c2"
    "d7dae0"
  ];

  # Greetd prompts for the account password, then starts the same UWSM-managed
  # Hyprland session that was the default in GDM.
  services.displayManager.gdm.enable = lib.mkForce false;
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = ''
        ${pkgs.tuigreet}/bin/tuigreet \
          --time \
          --remember \
          --cmd "uwsm start hyprland.desktop" \
          --theme "border=lightblue;text=gray;prompt=lightmagenta;time=lightcyan;action=lightred;button=lightblue;container=black;input=gray;greet=lightgreen"
      '';
      user = "greeter";
    };
  };

  security.pam.services.greetd.enableGnomeKeyring = true;
}
