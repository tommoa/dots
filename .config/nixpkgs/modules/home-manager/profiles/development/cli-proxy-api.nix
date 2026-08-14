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
  clientApiKeyFile = "${config.home.homeDirectory}/.config/ai-keys/cli-proxy-api-key";
  managementPasswordFile = "${config.home.homeDirectory}/.config/ai-keys/cli-proxy-management-password";
  proxyConfigBase = (pkgs.formats.yaml {}).generate "cli-proxy-api-config.yaml" {
    # Keep the proxy local: the OAuth tokens are subscription credentials and
    # the downstream API is intentionally not exposed to the network.
    host = "127.0.0.1";
    port = config.my.cliProxyApi.port;
    auth-dir = proxyHome;
    debug = false;
    logging-to-file = true;
    logs-max-total-size-mb = 100;
    remote-management = {
      allow-remote = false;
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
  proxyWrapper = pkgs.writeShellApplication {
    name = "cli-proxy-api-with-secrets";
    runtimeInputs = [pkgs.coreutils pkgs.jq];
    text = ''
      umask 077
      MANAGEMENT_PASSWORD="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "${managementPasswordFile}")"
      export MANAGEMENT_PASSWORD
      ${pkgs.coreutils}/bin/install -m 600 "${proxyConfigBase}" "${proxyConfig}"
      printf '\napi-keys:\n  - %s\n' \
        "$(${pkgs.coreutils}/bin/tr -d '\r\n' < "${clientApiKeyFile}" | ${pkgs.jq}/bin/jq -Rs .)" \
        >>"${proxyConfig}"
      exec ${proxyBinary} -config "${proxyConfig}" "$@"
    '';
  };
  codexLogin = pkgs.writeShellApplication {
    name = "cli-proxy-api-codex-login";
    text = ''
      exec ${proxyWrapper}/bin/cli-proxy-api-with-secrets -codex-login "$@"
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
    age.secrets = {
      cli-proxy-api-key = {
        file = "${config.my.secretsPath}/ai/cli-proxy-api-key.age";
        path = clientApiKeyFile;
        symlink = false;
      };
      cli-proxy-management-password = {
        file = "${config.my.secretsPath}/ai/cli-proxy-management-password.age";
        path = managementPasswordFile;
        symlink = false;
      };
    };

    home.packages = [
      proxyPackage
      codexLogin
    ];

    home.activation.cliProxyApiDirectories = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run mkdir -p "${proxyHome}/logs"
      run chmod 700 "${proxyHome}" "${proxyHome}/logs"
    '';

    programs.codex.settings = {
      model_provider = "cli_proxy_api";
      model_providers.cli_proxy_api = {
        name = "CLIProxyAPI (Codex subscriptions)";
        base_url = "http://127.0.0.1:${toString config.my.cliProxyApi.port}/v1";
        auth = {
          command = "${pkgs.coreutils}/bin/cat";
          args = [clientApiKeyFile];
          timeout_ms = 5000;
          refresh_interval_ms = 300000;
        };
        wire_api = "responses";
        supports_websockets = true;
      };
    };

    programs.opencode.settings.provider.cli_proxy_api = {
      npm = "@ai-sdk/openai-compatible";
      name = "CLIProxyAPI (Codex subscriptions)";
      options = {
        baseURL = "http://127.0.0.1:${toString config.my.cliProxyApi.port}/v1";
        apiKey = "{file:${clientApiKeyFile}}";
      };
      models = lib.genAttrs proxyModels (model: {name = model;});
    };

    launchd.agents.cli-proxy-api = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = {
        ProgramArguments = ["${proxyWrapper}/bin/cli-proxy-api-with-secrets"];
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
        After = ["agenix.service" "network-online.target"];
      };
      Service = {
        ExecStart = "${proxyWrapper}/bin/cli-proxy-api-with-secrets";
        Restart = "on-failure";
        RestartSec = 5;
        WorkingDirectory = proxyHome;
      };
      Install.WantedBy = ["default.target"];
    };
  };
}
