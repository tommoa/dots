{config, ...}: {
  # Vertex AI keys only (for server configurations)
  # Decrypted to ~/.config/ai-keys/ for use by profile
  age.secrets = {
    vertex-key = {
      file = "${config.my.secretsPath}/ai/vertex.age";
      path = "${config.home.homeDirectory}/.config/ai-keys/vertex";
      symlink = false;
    };
    vertex-project = {
      file = "${config.my.secretsPath}/ai/vertex-project.age";
      path = "${config.home.homeDirectory}/.config/ai-keys/vertex-project";
      symlink = false;
    };
  };
}
