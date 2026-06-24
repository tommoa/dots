{
  config,
  pkgs,
  ...
}: let
  aiKey = pkgs.writeShellApplication {
    name = "ai-key";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
    ];
    text = builtins.readFile ./ai-key.sh;
  };

  aiKeyTmuxSegment = pkgs.writeShellApplication {
    name = "ai-key-tmux";
    runtimeInputs = [
      aiKey
    ];
    text = ''
      ai_spend="$(ai-key 2>/dev/null || true)"
      if [ -n "$ai_spend" ]; then
        printf '#[fg=yellow] %s #[fg=white,nobold,noitalics,nounderscore]|' "$ai_spend"
      fi
    '';
  };
in {
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

  home.packages = [
    aiKey
  ];

  home.file = {
    ".codex/codex-api-key-helper" = {
      executable = true;
      text = ''
        #!/bin/sh
        printf '%s\n' "$LITELLM_API_KEY"
      '';
    };

    ".tmux-work.conf".text = ''
      set -g @work_ai_spend_segment "#(${aiKeyTmuxSegment}/bin/ai-key-tmux)"
    '';
  };

  # Set LITELLM_API_KEY from the decrypted secret for opencode's {env:VAR} syntax
  programs.zsh.initContent = ''
    [ -f ~/.config/ai-keys/litellm ] && export LITELLM_API_KEY="$(cat ~/.config/ai-keys/litellm)"
  '';

  my.pi.litellm.enable = true;

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

  programs.codex.settings = {
    model_providers.ai_proxy = {
      name = "Arista AI Proxy";
      base_url = "https://ai-proxy.infra.corp.arista.io/";
      auth = {
        command = "${config.home.homeDirectory}/.codex/codex-api-key-helper";
        timeout_ms = 5000;
        refresh_interval_ms = 300000;
      };
      wire_api = "responses";
      supports_websockets = false;
    };
  };
}
