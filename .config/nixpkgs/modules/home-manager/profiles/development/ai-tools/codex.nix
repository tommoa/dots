{
  pkgs,
  lib,
  config,
  ...
}: let
  localRoot = config.my.aiTools.localStateRoot;
  localStateEnabled = localRoot != null;
  localHome = "${localRoot}/.codex";
  localSqliteHome = "${localHome}/sqlite";
  localBootstrap = pkgs.writeShellApplication {
    name = "codex-local-bootstrap";
    runtimeInputs = [pkgs.coreutils pkgs.util-linux];
    text = builtins.readFile ./codex-local-bootstrap.sh;
    derivationArgs = {
      nativeBuildInputs = [pkgs.python3];
      postCheck = ''
        CODEX_LOCAL_BOOTSTRAP="$target" python3 ${../../../../../tests/test_codex_local_bootstrap.py} -v
      '';
    };
  };
  localPackage = pkgs.symlinkJoin {
    name = "codex-with-local-state";
    inherit (pkgs.codex) meta;
    version = lib.getVersion pkgs.codex;
    paths = [pkgs.codex];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/codex \
        --set CODEX_HOME ${lib.escapeShellArg localHome} \
        --set CODEX_SQLITE_HOME ${lib.escapeShellArg localSqliteHome} \
        --run ${lib.escapeShellArg "${localBootstrap}/bin/codex-local-bootstrap \"$0\""} \
        ${lib.optionalString (config.programs.codex.settings ? model_provider) "--add-flags ${lib.escapeShellArg "-c model_provider=${config.programs.codex.settings.model_provider}"}"}
    '';
  };
  palette = import ../../../../../themes/one-dark.nix;
  modelDefaults = config.my.modelSelection.defaults.${config.my.modelSelection.profile};
  codexSubscriptionAccounts = builtins.readFile ../codex-cli-proxy-accounts.sh;
  codexReset = pkgs.writeShellApplication {
    name = "reset-codex";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gnused
      jq
    ];
    text = codexSubscriptionAccounts + builtins.readFile ../reset-codex.sh;
  };
  codexSubscriptionUsage = pkgs.writeShellApplication {
    name = "codex-subscription-usage";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
      gnused
    ];
    text = codexSubscriptionAccounts + builtins.readFile ../codex-subscription-usage.sh;
  };
  codexTmuxSegment = pkgs.writeShellApplication {
    name = "codex-subscription-usage-tmux";
    runtimeInputs = [codexSubscriptionUsage];
    text = ''
      codex_usage="$(codex-subscription-usage 2>/dev/null || true)"
      if [ -n "$codex_usage" ]; then
        printf '#[fg=cyan] %s #[fg=white,nobold,noitalics,nounderscore]|\n' "$codex_usage"
      fi
    '';
  };
in {
  options.my.codex = {
    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = modelDefaults.coordinatorModel;
      description = "The default model for codex to use";
    };
    reviewModel = lib.mkOption {
      type = lib.types.str;
      default = modelDefaults.coordinatorModel;
      description = "The model to use for the /review command";
    };
    subagentModel = lib.mkOption {
      type = lib.types.str;
      default = modelDefaults.subagentModel;
      description = "The default model for Codex subagents";
    };
  };
  config = {
    # Desktop's SSH launcher reads these before invoking our wrapped binary.
    home.sessionVariables = lib.mkIf (localStateEnabled && config.programs.codex.enable) {
      CODEX_HOME = localHome;
      CODEX_SQLITE_HOME = localSqliteHome;
    };
    # Codex mutates config.toml at runtime, while Home Manager manages it as a
    # read-only store link. Copy the freshly linked generation after linking so
    # Codex always gets the latest declarative settings in a writable file.
    home.activation.codexConfigWritable = lib.mkIf (!localStateEnabled) (lib.hm.dag.entryAfter ["linkGeneration"] ''
      codex_config="$HOME/.codex/config.toml"
      codex_config_tmp="$codex_config.tmp"

      run cp "$codex_config" "$codex_config_tmp"
      run chmod u+rw,go-rwx "$codex_config_tmp"
      run mv -f "$codex_config_tmp" "$codex_config"
    '');
    home.packages = [codexReset codexSubscriptionUsage];
    home.file = {
      # Keep managed input shared; only the wrapper's per-container copy is
      # writable. Include Home Manager's final config and plugin settings.
      ".codex/server-config.toml" = lib.mkIf localStateEnabled {
        source = config.home.file.".codex/config.toml".source;
        force = true;
      };
      ".codex/config.toml".force = true;
      # `codex remote-control start` currently requires the installer-managed
      # standalone layout. Keep that compatibility path declarative while
      # pointing it at the exact package selected by programs.codex. This is
      # important for hosts that wrap Codex to relocate its runtime state.
      ".codex/packages/standalone/current/codex" = {
        source = "${config.programs.codex.package}/bin/codex";
        force = true;
      };
      ".tmux-codex.conf".text = ''
        set -g @codex_subscription_usage_segment "#(${codexTmuxSegment}/bin/codex-subscription-usage-tmux)"
      '';
    };
    programs.codex = {
      enable = true;
      enableMcpIntegration = true;
      package =
        if localStateEnabled
        then localPackage
        else pkgs.codex;
      settings = {
        model = config.my.codex.defaultModel;
        review_model = config.my.codex.reviewModel;
        model_reasoning_effort = "high";
        # The source-built Nix package does not provide the standalone package
        # layout required by Codex's managed background daemon.
        features.daemon_auto_start = false;
        mcp_servers.cua_repl = lib.mkIf pkgs.stdenv.isDarwin {
          # Reuse the installed desktop integration's environment and launch
          # settings without pinning its changing cache version or copying them.
          command = lib.getExe pkgs.python3;
          args = [
            "-c"
            ''
              import json
              import os
              from pathlib import Path

              home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
              configs = list((home / "plugins/cache/openai-bundled/unified-computer-use").glob("*/.mcp.json"))
              if not configs:
                  raise SystemExit("Codex desktop computer-use integration is not installed.")
              config = max(configs, key=lambda path: path.stat().st_mtime)
              server = json.loads(config.read_text())["mcpServers"]["cua_repl"]
              env = dict(os.environ, **server.get("env", {}))
              os.execvpe(server["command"], [server["command"], *server.get("args", [])], env)
            ''
          ];
          # Codex filters MCP environments before the launcher can read them.
          env_vars = [
            "CODEX_HOME"
            "BROWSER_USE_ACCESS_EXECUTOR_ID"
            "BROWSER_USE_ACCESS_PIPE_PATH"
            "BROWSER_USE_ACCESS_VERIFYING_IDENTITY"
          ];
          enabled_tools = ["js" "js_reset" "turn_ended"];
          startup_timeout_sec = 120;
        };
        agents = {
          default_subagent_model = config.my.codex.subagentModel;
          default_subagent_reasoning_effort = "high";
          max_concurrent_threads_per_session = 32;
        };
        # This needs to be disabled for now, as my work proxy rejects reasoning summaries
        # for codex-auto-review.
        # model_reasoning_summary = "auto";
        approval_policy = "on-request";
        sandbox_mode = "workspace-write";
        approvals_reviewer = "auto_review";
        analytics.enabled = false;
        feedback.enabled = false;
        projects.${config.home.homeDirectory}.trust_level = "trusted";
        # The desktop app reads these from config.toml's [desktop] table,
        # rather than from the top-level CLI/TUI settings.
        desktop = {
          dock-icon-preference = "codex-system";
          sansFontSize = 15;
          codeFontSize = 15;
          appearanceTheme = "dark";
          appearanceDarkCodeThemeId = "one";
          appearanceDarkChromeTheme = {
            accent = "#${palette.blue}";
            contrast = 60;
            fonts = {
              code = "monospace";
              ui = "monospace";
            };
            ink = "#${palette.white}";
            surface = "#${palette.background}";
            opaqueWindows = true;
            semanticColors = {
              diffAdded = "#${palette.green}";
              diffRemoved = "#${palette.red}";
              skill = "#${palette.magenta}";
            };
          };
        };
        tui.theme = "one-half-dark";
      };
    };
  };
}
