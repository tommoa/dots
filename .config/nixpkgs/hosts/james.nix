{ pkgs, ... }:

{
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
    extraGroups = [ "networkmanager" "wheel" ];
    shell = pkgs.zsh;
    packages = [ ];
  };

  # Auto login
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "tommoa";

  # Workaround for GNOME autologin
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;
}