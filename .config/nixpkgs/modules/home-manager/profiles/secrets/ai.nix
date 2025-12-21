{config, ...}: {
  # Import Vertex AI keys (shared with ai-vertex.nix)
  imports = [./ai-vertex.nix];

  # Additional AI API keys and search engine keys
  age.secrets = {
    anthropic-key.file = "${config.my.secretsPath}/ai/anthropic.age";
    gemini-key.file = "${config.my.secretsPath}/ai/gemini.age";
    openai-key.file = "${config.my.secretsPath}/ai/openai.age";
    openrouter-key.file = "${config.my.secretsPath}/ai/openrouter.age";

    # Search engine keys (used by AI tools)
    google-api-key.file = "${config.my.secretsPath}/search-engines/google-api-key.age";
    google-engine-id.file = "${config.my.secretsPath}/search-engines/google-engine-id.age";
    tavily-api-key.file = "${config.my.secretsPath}/search-engines/tavily-api-key.age";
  };
}
