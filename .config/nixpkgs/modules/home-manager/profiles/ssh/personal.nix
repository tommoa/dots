{config, ...}: {
  # Personal SSH config fragments (agenix-managed)
  age.secrets = {
    ssh-config-servers = {
      file = "${config.my.secretsPath}/ssh/config-servers.age";
      path = "${config.home.homeDirectory}/.ssh/config.d/servers";
      mode = "0600";
    };
  };
}
