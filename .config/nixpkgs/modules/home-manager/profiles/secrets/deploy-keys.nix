{config, ...}: {
  # SSH deploy keys for GitHub and SourceHut
  # Only include on non-server configurations
  age.secrets = {
    github-deploy = {
      file = "${config.my.secretsPath}/ssh/github-deploy.age";
      path = "${config.home.homeDirectory}/.ssh/github-deploy";
      mode = "0600";
    };
    github-deploy-pub = {
      file = "${config.my.secretsPath}/ssh/github-deploy-pub.age";
      path = "${config.home.homeDirectory}/.ssh/github-deploy.pub";
      mode = "0644";
    };
    srht-deploy = {
      file = "${config.my.secretsPath}/ssh/srht-deploy.age";
      path = "${config.home.homeDirectory}/.ssh/srht-deploy";
      mode = "0600";
    };
    srht-deploy-pub = {
      file = "${config.my.secretsPath}/ssh/srht-deploy-pub.age";
      path = "${config.home.homeDirectory}/.ssh/srht-deploy.pub";
      mode = "0644";
    };
  };
}
