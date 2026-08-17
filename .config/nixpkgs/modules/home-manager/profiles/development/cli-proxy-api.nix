{
  config,
  lib,
  pkgs,
  ...
}: let
  proxyPackage = pkgs.llm-agents.cli-proxy-api;
  proxyBinary = "${proxyPackage}/bin/cli-proxy-api";
  proxyHome = "${config.home.homeDirectory}/.cli-proxy-api";
  proxyConfigBase = (pkgs.formats.yaml {}).generate "cli-proxy-api-config.yaml" {
    # Keep the proxy local: the OAuth tokens are subscription credentials and
    # the unauthenticated downstream API is intentionally not exposed to the
    # network. Client authentication would not isolate applications running as
    # the same user, but would duplicate a secret into their environments.
    host = "127.0.0.1";
    port = config.my.cliProxyApi.port;
    auth-dir = proxyHome;
    debug = false;
    logging-to-file = true;
    logs-max-total-size-mb = 100;
    remote-management = {
      allow-remote = false;
      # The service environment supplies the public management key "local".
      # Keeping it out of this field avoids CLIProxyAPI rewriting the read-only
      # Nix-store config with a bcrypt hash at startup.
      secret-key = "";
    };
    routing.strategy = "fill-first";
    ws-auth = true;
  };
  proxyModels = lib.unique (
    [
      "gpt-5.6-sol"
      "gpt-5.6-terra"
      "gpt-5.6-luna"
      config.my.codex.defaultModel
    ]
    ++ config.my.cliProxyApi.models
  );
  codexLogin = pkgs.writeShellApplication {
    name = "cli-proxy-api-codex-login";
    text = ''
      exec ${proxyBinary} -config "${proxyConfigBase}" -codex-login "$@"
    '';
  };
in {
  options.my.cliProxyApi = {
    port = lib.mkOption {
      type = lib.types.port;
      default = 8317;
      description = "Local port for CLIProxyAPI";
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional model IDs exposed to OpenCode through CLIProxyAPI";
    };
  };

  config = {
    home.packages = [
      proxyPackage
      codexLogin
    ];

    home.activation.cliProxyApiDirectories = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run mkdir -p "${proxyHome}/logs"
      run chmod 700 "${proxyHome}" "${proxyHome}/logs"
    '';

    # Agenix does not remove old direct-path secrets when their declarations
    # disappear, so clean up the credentials used by the previous configuration.
    home.activation.cliProxyApiRemoveLegacySecrets = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run ${pkgs.coreutils}/bin/rm -f \
        "${config.home.homeDirectory}/.config/ai-keys/cli-proxy-api-key" \
        "${config.home.homeDirectory}/.config/ai-keys/cli-proxy-management-password"
    '';

    programs.codex.settings = {
      model_provider = "cli_proxy_api";
      model_providers.cli_proxy_api = {
        name = "CLIProxyAPI (Codex subscriptions)";
        base_url = "http://127.0.0.1:${toString config.my.cliProxyApi.port}/v1";
        # Keep ChatGPT authentication active for account identity and Remote.
        # The loopback-only proxy uses its own upstream OAuth credentials.
        requires_openai_auth = true;
        wire_api = "responses";
        supports_websockets = true;
      };
    };

    programs.opencode.settings.provider.cli_proxy_api = {
      npm = "@ai-sdk/openai-compatible";
      name = "CLIProxyAPI (Codex subscriptions)";
      options = {
        baseURL = "http://127.0.0.1:${toString config.my.cliProxyApi.port}/v1";
        # The SDK requires a value even though the loopback proxy does not
        # authenticate local clients.
        apiKey = "local";
      };
      models = lib.genAttrs proxyModels (model: {name = model;});
    };

    launchd.agents.cli-proxy-api = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [proxyBinary "-config" "${proxyConfigBase}"];
        EnvironmentVariables.MANAGEMENT_PASSWORD = "local";
        WorkingDirectory = proxyHome;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 5;
        StandardOutPath = "${proxyHome}/logs/stdout.log";
        StandardErrorPath = "${proxyHome}/logs/stderr.log";
      };
    };

    systemd.user.services.cli-proxy-api = lib.mkIf pkgs.stdenv.isLinux {
      Unit = {
        Description = "CLIProxyAPI local subscription proxy";
        After = ["network-online.target"];
      };
      Service = {
        Environment = ["MANAGEMENT_PASSWORD=local"];
        ExecStart = "${proxyBinary} -config ${proxyConfigBase}";
        Restart = "on-failure";
        RestartSec = 5;
        WorkingDirectory = proxyHome;
      };
      Install.WantedBy = ["default.target"];
    };
  };
}
