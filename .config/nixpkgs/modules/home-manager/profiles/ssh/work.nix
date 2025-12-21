{config, ...}: {
  # Work-specific SSH config fragments (agenix-managed)
  age.secrets = {
    ssh-config-work = {
      file = "${config.my.secretsPath}/ssh/config-work.age";
      path = "${config.home.homeDirectory}/.ssh/config.d/work";
      mode = "0600";
    };
    ssh-config-home-bus = {
      file = "${config.my.secretsPath}/ssh/config-home-bus.age";
      path = "${config.home.homeDirectory}/.ssh/config.d/00-home-bus";
      mode = "0600";
    };
  };
}
