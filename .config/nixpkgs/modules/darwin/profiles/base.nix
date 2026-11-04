{username, ...}: {
  imports = [
    ../../common/base.nix
    ../../common/nix.nix
    ../../common/fonts.nix
  ];

  # Replace Amphetamine's always-awake session on AC and battery power.
  power.sleep = {
    computer = "never";
    display = "never";
  };

  # Screen saver inactivity is a user preference scoped to each Mac.
  home-manager.users.${username}.targets.darwin.currentHostDefaults."com.apple.screensaver".idleTime = 0;

  # Keyboard settings
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToEscape = true;
  };

  # Dock settings
  system.defaults.dock = {
    autohide = true;
    showhidden = true;
    show-recents = false;
  };

  system.defaults.NSGlobalDomain.ApplePressAndHoldEnabled = false;

  system.stateVersion = 7;
}
