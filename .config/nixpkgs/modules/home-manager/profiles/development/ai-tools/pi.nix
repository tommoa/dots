{
  pkgs,
  config,
  lib,
  ...
}: let
  piLiteLLMEnabled = config.my.pi.enable && config.my.pi.litellm.enable;
  piLiteLLMProviderDir = "${config.home.homeDirectory}/.pi/agent/litellm-provider";
  piLiteLLMProviderSource = pkgs.runCommandLocal "pi-litellm-provider" {} ''
    mkdir -p "$out"
    cp -R ${../pi/litellm-provider}/. "$out/"
    rm -f "$out/routing.ts"
    cp ${../litellm/routing.ts} "$out/routing.ts"
  '';
in {
  options.my.pi = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the pi coding-agent package";
    };
    package = lib.mkPackageOption pkgs "pi-coding-agent" {};
    litellm.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the LiteLLM provider extension for pi";
    };
  };
  config = {
    home.packages = lib.optionals config.my.pi.enable [config.my.pi.package];
    home.file = lib.mkIf piLiteLLMEnabled {
      ".pi/litellm".source = ../litellm;
      ".pi/agent/litellm-provider".source = piLiteLLMProviderSource;
      ".pi/agent/settings.json".source = (pkgs.formats.json {}).generate "pi-coding-agent-settings.json" {
        extensions = [piLiteLLMProviderDir];
        litellmProvider = {
          baseUrl = config.my.aiProxy.baseUrl;
          apiKey = "env:${config.my.aiProxy.apiKeyEnv}";
          authHeaderName = "x-litellm-api-key";
          sendBearerAuth = true;
          routeOverrides = {
            responses = config.my.aiProxy.routeOverrides.responses;
            chat = config.my.aiProxy.routeOverrides.chat;
          };
          providerCompat = {
            supportsDeveloperRole = false;
            supportsReasoningEffort = true;
            maxTokensField = "max_tokens";
          };
          defaults = {
            input = config.my.aiProxy.defaults.input;
            contextWindow = config.my.aiProxy.defaults.context;
            maxTokens = config.my.aiProxy.defaults.output;
          };
          headers = config.my.aiProxy.headers;
        };
      };
    };
  };
}
