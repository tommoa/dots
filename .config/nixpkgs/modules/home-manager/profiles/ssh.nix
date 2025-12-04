{ config, ... }:

{
  # Ensure the config.d directory exists
  home.file.".ssh/config.d/.keep".text = "";

  # Base SSH configuration via home-manager
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [ "~/.ssh/config.d/*" ];

    # Non-sensitive hosts
    matchBlocks = {
      "*" = {
        addKeysToAgent = "yes";
      };
      motsugo = {
        hostname = "motsugo.ucc.asn.au";
        user = "tommoa";
      };
    };
  };

  # NOTE: id_ed25519 is NOT managed by agenix because it's used as the identity
  # to decrypt other secrets (chicken-and-egg problem). It remains in ~/.secrets
  # and is symlinked by setup.sh, or must be manually copied on new machines.

  # Sensitive SSH config fragments (agenix-managed)
  age.secrets = {
    ssh-config-work = {
      file = "${config.my.secretsPath}/ssh/config-work.age";
      path = "${config.home.homeDirectory}/.ssh/config.d/work";
      mode = "0600";
    };
    ssh-config-servers = {
      file = "${config.my.secretsPath}/ssh/config-servers.age";
      path = "${config.home.homeDirectory}/.ssh/config.d/servers";
      mode = "0600";
    };
    ssh-config-arista-bus = {
      file = "${config.my.secretsPath}/ssh/config-arista-bus.age";
      path = "${config.home.homeDirectory}/.ssh/config.d/00-arista-bus";
      mode = "0600";
    };
  };
}
