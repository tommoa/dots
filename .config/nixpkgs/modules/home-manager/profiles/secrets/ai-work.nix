{config, ...}: {
  # Work-specific AI keys and provider configuration
  # Only imported by profiles that can reach corp infrastructure
  age.secrets = {
    litellm-key = {
      file = "${config.my.secretsPath}/ai/litellm.age";
      path = "${config.home.homeDirectory}/.config/ai-keys/litellm";
      symlink = false;
    };
    ai-proxy-api-key = {
      file = "${config.my.secretsPath}/ai/litellm.age";
      path = "${config.home.homeDirectory}/.ai-proxy-api-key";
      symlink = false;
    };
  };

  home.sessionVariables = {
    OPENCODE_CONFIG = "${config.home.homeDirectory}/.config/opencode/litellm-models.json";
  };

  # Set LITELLM_API_KEY from the decrypted secret for opencode's {env:VAR} syntax
  programs.zsh.initContent = ''
    [ -f ~/.config/ai-keys/litellm ] && export LITELLM_API_KEY="$(cat ~/.config/ai-keys/litellm)"
  '';

  # LiteLLM provider skeleton for opencode
  # Models are fetched at runtime by update-litellm-models and written to
  # ~/.config/opencode/litellm-models.json, which opencode deep-merges via OPENCODE_CONFIG.
  # Run: ./update-nix --litellm  (or ./update-litellm-models directly)
  programs.opencode.settings.provider.litellm = {
    npm = "@ai-sdk/openai-compatible";
    name = "LiteLLM";
    options = {
      baseURL = "https://ai-proxy.infra.corp.arista.io/v1";
      apiKey = "{env:LITELLM_API_KEY}";
      litellmProxy = true;
    };
  };
}
