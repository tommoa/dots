{
  config,
  lib,
  pkgs,
  ...
}: let
  proxyPackage = pkgs.llm-agents.cli-proxy-api;
  proxyBinary = "${proxyPackage}/bin/cli-proxy-api";
  proxyHome = "${config.home.homeDirectory}/.cli-proxy-api";
  proxyConfig = "${proxyHome}/config.yaml";
  # This key authenticates only the local client-to-proxy hop. It is not an
  # OpenAI credential and is safe to keep in the declarative client config.
  clientApiKey = "sk-local-cliproxyapi";
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
      exec ${proxyBinary} -config "${proxyConfig}" -codex-login "$@"
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

    home.file.".cli-proxy-api/config.yaml".text = ''
      # Keep the proxy local: the OAuth tokens are subscription credentials and
      # the downstream API is intentionally not exposed to the network.
      host: "127.0.0.1"
      port: ${toString config.my.cliProxyApi.port}
      auth-dir: "${proxyHome}"
      api-keys:
        - "${clientApiKey}"
      debug: false
      logging-to-file: true
      remote-management:
        allow-remote: false
        secret-key: ""
      routing:
        strategy: "fill-first"
      ws-auth: true
    '';

    home.activation.cliProxyApiDirectories = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run mkdir -p "${proxyHome}/logs"
      run chmod 700 "${proxyHome}" "${proxyHome}/logs"
    '';

    programs.codex.settings = {
      model_provider = "cli_proxy_api";
      model_providers.cli_proxy_api = {
        name = "CLIProxyAPI (Codex subscriptions)";
        base_url = "http://127.0.0.1:${toString config.my.cliProxyApi.port}/v1";
        experimental_bearer_token = clientApiKey;
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
        apiKey = clientApiKey;
      };
      models = lib.genAttrs proxyModels (model: {name = model;});
    };

    launchd.agents.cli-proxy-api = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [proxyBinary "-config" proxyConfig];
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
        ExecStart = "${proxyBinary} -config ${proxyConfig}";
        Restart = "on-failure";
        RestartSec = 5;
        WorkingDirectory = proxyHome;
      };
      Install.WantedBy = ["default.target"];
    };
  };
}
