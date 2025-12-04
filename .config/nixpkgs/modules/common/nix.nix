# The common settings for the nix.

{
  lib,
  config,
  pkgs,
  ...
}:

{
  # Allow unfree packages (e.g. Discord, Obsidian, Spotify, Steam, etc...).
  nixpkgs.config.allowUnfree = true;
  # Settings for nix itself.
  nix = {
    package = pkgs.lix;
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    gc = {
      automatic = true;
      options = "--delete-older-than 1w";
    }
    // (
      if pkgs.stdenv.isLinux then
        {
          # dates only exists on Linux.
          dates = "weekly";
        }
      else
        {
          # We need to manually specify when this occurs on macOS.
          # I want to run the GC every week.
          interval = {
            Weekday = 0;
            Hour = 0;
            Minute = 0;
          };
        }
    );
    optimise = {
      automatic = true;
    }
    // (
      if pkgs.stdenv.isLinux then
        {
          dates = [ "04:00" ];
        }
      else
        {
          # Optimise the store every day.
          interval = {
            Hour = 0;
            Minute = 0;
          };
        }
    );
  };
}
