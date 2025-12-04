{ config, ... }:

{
  # Vertex AI keys only (for server configurations)
  age.secrets = {
    vertex-key.file = "${config.my.secretsPath}/ai/vertex.age";
    vertex-project.file = "${config.my.secretsPath}/ai/vertex-project.age";
  };
}
