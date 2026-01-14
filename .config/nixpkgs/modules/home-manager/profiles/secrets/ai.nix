{ config, ... }:
{
  # Import Vertex AI keys (shared with ai-vertex.nix)
  imports = [ ./ai-vertex.nix ];

  # AI API keys - decrypted to ~/.config/ai-keys/ for use by profile
  age.secrets = {
    anthropic-key = {
      file = "${config.my.secretsPath}/ai/anthropic.age";
      path = "${config.home.homeDirectory}/.config/ai-keys/anthropic";
    };
    gemini-key = {
      file = "${config.my.secretsPath}/ai/gemini.age";
      path = "${config.home.homeDirectory}/.config/ai-keys/gemini";
    };
    openai-key = {
      file = "${config.my.secretsPath}/ai/openai.age";
      path = "${config.home.homeDirectory}/.config/ai-keys/openai";
    };
    opencode-zen-key = {
      file = "${config.my.secretsPath}/ai/opencode-zen.age";
      path = "${config.home.homeDirectory}/.config/ai-keys/opencode-zen";
    };
    openrouter-key = {
      file = "${config.my.secretsPath}/ai/openrouter.age";
      path = "${config.home.homeDirectory}/.config/ai-keys/openrouter";
    };

    # Search engine keys - decrypted to ~/.config/search-engines/
    google-api-key = {
      file = "${config.my.secretsPath}/search-engines/google-api-key.age";
      path = "${config.home.homeDirectory}/.config/search-engines/google-api-key";
    };
    google-engine-id = {
      file = "${config.my.secretsPath}/search-engines/google-engine-id.age";
      path = "${config.home.homeDirectory}/.config/search-engines/google-engine-id";
    };
    tavily-api-key = {
      file = "${config.my.secretsPath}/search-engines/tavily-api-key.age";
      path = "${config.home.homeDirectory}/.config/search-engines/tavily-api-key";
    };
  };
}
