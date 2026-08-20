{
  config,
  lib,
  pkgs,
  ...
}: let
  # Remove this override once CLIProxyAPI supports input-modalities on CodexModel upstream.
  proxyPackage = pkgs.llm-agents.cli-proxy-api.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./cli-proxy-api-codex-input-modalities.patch];
  });
  proxyBinary = "${proxyPackage}/bin/cli-proxy-api";
  proxyHome = "${config.home.homeDirectory}/.cli-proxy-api";
  proxyRuntimeBase = "${proxyHome}/base.json";
  proxyRuntimeConfig = "${proxyHome}/config.json";
  aiProxyRefreshInterval = 180;
  proxyConfigBase = (pkgs.formats.json {}).generate "cli-proxy-api-config.json" {
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
  aiProxyOptions =
    (pkgs.formats.json {}).generate "cli-proxy-api-ai-proxy-options.json"
    {
      inherit
        (config.my.aiProxy)
        apiKeyEnv
        baseUrl
        headers
        keyFile
        ;
      routeOverrides = {
        inherit (config.my.aiProxy.routeOverrides) chat responses;
      };
    };
  proxyConfigGeneratorSource = pkgs.runCommandLocal "cli-proxy-api-config-generator" {} ''
    mkdir -p "$out/litellm"
    cp ${./cli-proxy-api-config.ts} "$out/cli-proxy-api-config.ts"
    cp ${./litellm/routing.ts} "$out/litellm/routing.ts"
  '';
  proxyConfigRefresh = pkgs.writeShellApplication {
    name = "cli-proxy-api-refresh";
    runtimeInputs = [
      pkgs.bun
      pkgs.flock
    ];
    text = ''
      exec flock "${proxyRuntimeConfig}.lock" \
        bun run ${proxyConfigGeneratorSource}/cli-proxy-api-config.ts \
          "${proxyRuntimeBase}" ${aiProxyOptions} "${proxyRuntimeConfig}"
    '';
  };
  proxyConfig =
    if config.my.aiProxy.enable
    then proxyRuntimeConfig
    else proxyConfigBase;
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
    home.packages =
      [
        proxyPackage
        codexLogin
      ]
      ++ lib.optional config.my.aiProxy.enable proxyConfigRefresh;

    home.activation.cliProxyApiDirectories = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run mkdir -p "${proxyHome}/logs"
      run chmod 700 "${proxyHome}" "${proxyHome}/logs"
    '';

    # Preserve the last successful discovery across generations. The runtime
    # config is a cache of a network call, so clobbering it on every switch
    # would leave Codex with an empty ai-proxy provider for up to one refresh
    # interval. Only invalidate the cache when the declarative base itself
    # changed; the refresh service (RunAtLoad + StartInterval / OnBootSec)
    # then repopulates config.json from the new base.
    home.activation.cliProxyApiRuntimeConfig = lib.mkIf config.my.aiProxy.enable (
      lib.hm.dag.entryAfter ["cliProxyApiDirectories"] ''
        run ${pkgs.flock}/bin/flock "${proxyRuntimeConfig}.lock" sh -c '
          umask 077
          # Overwrite config.json only when the declarative base changed or
          # the cache is missing. Otherwise leave the previously-discovered
          # model list intact until the next successful refresh.
          if ! ${pkgs.coreutils}/bin/cmp -s ${proxyConfigBase} "${proxyRuntimeBase}" \
              || [ ! -s "${proxyRuntimeConfig}" ]; then
            ${pkgs.coreutils}/bin/cp ${proxyConfigBase} "${proxyRuntimeConfig}"
            ${pkgs.coreutils}/bin/chmod 600 "${proxyRuntimeConfig}"
          fi
          # base.json is the generator input; keep it in lock-step with the
          # active declarative config so the next refresh starts from truth.
          ${pkgs.coreutils}/bin/cp ${proxyConfigBase} "${proxyRuntimeBase}"
          ${pkgs.coreutils}/bin/chmod 600 "${proxyRuntimeBase}"
        '
      ''
    );

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
        name = "CLIProxyAPI (subscriptions + ai-proxy)";
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
        ProgramArguments = [proxyBinary "-config" proxyConfig];
        EnvironmentVariables = {
          MANAGEMENT_PASSWORD = "local";
          MANAGEMENT_STATIC_PATH = "${proxyHome}/static";
        };
        WorkingDirectory = proxyHome;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 5;
        StandardOutPath = "${proxyHome}/logs/stdout.log";
        StandardErrorPath = "${proxyHome}/logs/stderr.log";
      };
    };

    launchd.agents.cli-proxy-api-refresh = lib.mkIf (pkgs.stdenv.isDarwin && config.my.aiProxy.enable) {
      enable = true;
      config = {
        ProgramArguments = ["${proxyConfigRefresh}/bin/cli-proxy-api-refresh"];
        WorkingDirectory = proxyHome;
        RunAtLoad = true;
        StartInterval = aiProxyRefreshInterval;
        StandardOutPath = "${proxyHome}/logs/refresh-stdout.log";
        StandardErrorPath = "${proxyHome}/logs/refresh-stderr.log";
      };
    };

    systemd.user.services.cli-proxy-api = lib.mkIf pkgs.stdenv.isLinux {
      Unit = {
        Description = "CLIProxyAPI local subscription proxy";
        After = ["network-online.target"];
      };
      Service = {
        Environment = [
          "MANAGEMENT_PASSWORD=local"
          "MANAGEMENT_STATIC_PATH=${proxyHome}/static"
        ];
        ExecStart = "${proxyBinary} -config ${proxyConfig}";
        Restart = "on-failure";
        RestartSec = 5;
        WorkingDirectory = proxyHome;
      };
      Install.WantedBy = ["default.target"];
    };

    systemd.user.services.cli-proxy-api-refresh = lib.mkIf (pkgs.stdenv.isLinux && config.my.aiProxy.enable) {
      Unit.Description = "Refresh CLIProxyAPI ai-proxy models";
      Service = {
        Type = "oneshot";
        ExecStart = "${proxyConfigRefresh}/bin/cli-proxy-api-refresh";
        WorkingDirectory = proxyHome;
      };
    };

    systemd.user.timers.cli-proxy-api-refresh = lib.mkIf (pkgs.stdenv.isLinux && config.my.aiProxy.enable) {
      Unit.Description = "Periodically refresh CLIProxyAPI ai-proxy models";
      Timer = {
        OnBootSec = "0s";
        OnUnitActiveSec = "${toString aiProxyRefreshInterval}s";
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
    };
  };
}
