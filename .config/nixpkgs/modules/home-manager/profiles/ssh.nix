{ ... }:

{
  # Ensure the config.d directory exists
  home.file.".ssh/config.d/.keep".text = "";

  # Base SSH configuration via home-manager
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [ "~/.ssh/config.d/*" ];

    matchBlocks = {
      "*" = {
        addKeysToAgent = "yes";
      };
    };
  };

  # NOTE: id_ed25519 is NOT managed by agenix because it's used as the identity
  # to decrypt other secrets (chicken-and-egg problem). It remains in ~/.secrets
  # and is symlinked by setup.sh, or must be manually copied on new machines.
}
