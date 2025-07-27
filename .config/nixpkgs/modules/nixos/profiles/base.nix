{ pkgs, ... }:

{
  imports = [
    ../../common/base.nix
    ../../common/nix.nix
    ../../common/fonts.nix
  ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;

  # Use latest kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Networking/interconnectivity
  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;

  # Timezone and locale
  time.timeZone = "Australia/Sydney";
  i18n.defaultLocale = "en_AU.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_AU.UTF-8";
    LC_IDENTIFICATION = "en_AU.UTF-8";
    LC_MEASUREMENT = "en_AU.UTF-8";
    LC_MONETARY = "en_AU.UTF-8";
    LC_NAME = "en_AU.UTF-8";
    LC_NUMERIC = "en_AU.UTF-8";
    LC_PAPER = "en_AU.UTF-8";
    LC_TELEPHONE = "en_AU.UTF-8";
    LC_TIME = "en_AU.UTF-8";
  };

  # Keyboard configuration
  services.xserver.xkb = {
    layout = "us";
    variant = "colemak";
    options = "caps:escape";
  };
  console.useXkbConfig = true;

  # Turn on QMK for keyboards.
  hardware.keyboard.qmk.enable = true;

  # Default shell
  users.defaultUserShell = pkgs.zsh;

  environment.loginShellInit = ''
	if [ -e $HOME/.profile ]
	then
		. $HOME/.profile
	fi
  '';

  system.stateVersion = "25.05";
}
