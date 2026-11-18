{
  pkgs,
  config,
  lib,
  ...
}: let
  providerID =
    if config.my.pi.provider == "cli-proxy-api"
    then "cli_proxy_api"
    else config.my.pi.provider;
  # Old desktop processes can retain these after their shell exports disappear.
  # Pi discovers providers from its environment independently of enabledModels.
  retiredEnvironment = [
    "ANTHROPIC_API_KEY"
    "GEMINI_API_KEY"
    "GOOGLE_API_KEY"
    "GOOGLE_CLOUD_LOCATION"
    "GOOGLE_CLOUD_PROJECT"
    "OPENAI_API_KEY"
    "OPENCODE_API_KEY"
    "OPENROUTER_API_KEY"
  ];
  piLauncher = pkgs.writeShellScriptBin "pi" ''
    exec ${pkgs.coreutils}/bin/env ${lib.concatMapStringsSep " " (name: "-u ${name}") retiredEnvironment} \
      ${lib.getExe config.my.pi.package} "$@"
  '';
  piLiteLLMProviderSource = pkgs.runCommandLocal "pi-litellm-provider" {} ''
    mkdir -p "$out/pi/litellm-provider" "$out/ai-providers"
    cp -R ${../pi/litellm-provider}/. "$out/pi/litellm-provider/"
    cp ${../ai-providers/routing.ts} "$out/ai-providers/routing.ts"
  '';
  piLiteLLMProviderDir = "${piLiteLLMProviderSource}/pi/litellm-provider";
  corporateSettings = {
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
in {
  options.my.pi = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the pi coding-agent package";
    };
    package = lib.mkPackageOption pkgs "pi-coding-agent" {};
    provider = lib.mkOption {
      type = lib.types.enum ["none" "litellm" "cli-proxy-api"];
      default = "none";
      description = "Custom model provider for Pi";
    };
  };
  config = {
    assertions = [
      {
        assertion = config.my.aiTools.localStateRoot == null || !config.my.pi.enable;
        message = "Pi must remain disabled on NFS-home servers until its PI_CODING_AGENT_DIR adapter also supplies managed settings, skills and writable local state.";
      }
    ];
    home.packages = lib.optionals config.my.pi.enable [piLauncher];
    home.file = lib.mkIf (config.my.pi.enable && config.my.pi.provider != "none") {
      ".pi/agent/settings.json".source = (pkgs.formats.json {}).generate "pi-coding-agent-settings.json" ({
          extensions = [piLiteLLMProviderDir];
          defaultProvider = providerID;
          defaultModel = config.my.codex.defaultModel;
          defaultThinkingLevel = config.programs.codex.settings.model_reasoning_effort;
          enabledModels = ["${providerID}/**" "openai-codex/*"];
        }
        // (
          if config.my.pi.provider == "cli-proxy-api"
          then {
            cliProxyProvider.baseUrl = "http://127.0.0.1:${toString config.my.cliProxyApi.port}/v1";
          }
          else {
            litellmProvider = corporateSettings;
          }
        ));
    };
  };
}
