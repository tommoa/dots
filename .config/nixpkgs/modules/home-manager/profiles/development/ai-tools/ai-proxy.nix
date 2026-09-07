{
  lib,
  config,
  ...
}: {
  options.my.aiProxy = {
    enable = lib.mkEnableOption "the shared ai-proxy connection";
    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://ai-proxy.infra.corp.arista.io";
      description = "Base URL of the shared LiteLLM ai-proxy";
    };
    apiKeyEnv = lib.mkOption {
      type = lib.types.str;
      default = "LITELLM_API_KEY";
      description = "Environment variable containing the ai-proxy API key";
    };
    keyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/ai-keys/litellm";
      description = "Fallback file containing the ai-proxy API key";
    };
    headers = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = ''
        Non-secret headers sent to ai-proxy (routing, tenant IDs, feature
        flags). API keys must go through apiKeyEnv/keyFile instead: values
        set here are baked into world-readable /nix/store paths, so anything
        secret-shaped placed in this attrset will leak. The refresh
        generator rejects an Authorization entry to prevent that mistake.
      '';
    };
    routeOverrides = {
      responses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "ai-proxy model IDs forced through the Responses API";
      };
      chat = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "ai-proxy model IDs forced through Chat Completions";
      };
    };
    defaults = {
      input = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["text"];
        description = "Default input modalities when ai-proxy omits metadata";
      };
      context = lib.mkOption {
        type = lib.types.int;
        default = 128000;
        description = "Default context window when ai-proxy omits metadata";
      };
      output = lib.mkOption {
        type = lib.types.int;
        default = 16384;
        description = "Default output limit when ai-proxy omits metadata";
      };
    };
  };
}
