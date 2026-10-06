{
  pkgs,
  lib,
  config,
  ...
}: let
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
    # Codex mutates config.toml at runtime, while Home Manager manages it as a
    # read-only store link. Copy the freshly linked generation after linking so
    # Codex always gets the latest declarative settings in a writable file.
    home.activation.codexConfigWritable = lib.hm.dag.entryAfter ["linkGeneration"] ''
      codex_config="$HOME/.codex/config.toml"
      codex_config_tmp="$codex_config.tmp"

      run cp "$codex_config" "$codex_config_tmp"
      run chmod u+rw,go-rwx "$codex_config_tmp"
      run mv -f "$codex_config_tmp" "$codex_config"
    '';
    home.packages = [codexReset codexSubscriptionUsage];
    home.file = {
      ".codex/config.toml".force = true;
      ".tmux-codex.conf".text = ''
        set -g @codex_subscription_usage_segment "#(${codexTmuxSegment}/bin/codex-subscription-usage-tmux)"
      '';
    };
    programs.codex = {
      enable = true;
      enableMcpIntegration = true;
      package = pkgs.codex;
      settings = {
        model = config.my.codex.defaultModel;
        review_model = config.my.codex.reviewModel;
        model_reasoning_effort = "high";
        # The source-built Nix package does not provide the standalone package
        # layout required by Codex's managed background daemon.
        features.daemon_auto_start = false;
        agents = {
          default_subagent_model = config.my.codex.subagentModel;
          default_subagent_reasoning_effort = "high";
          max_concurrent_threads_per_session = 32;
        };
        # This needs to be disabled for now, as my work proxy rejects reasoning summaries
        # for codex-auto-review.
        # model_reasoning_summary = "auto";
        approval_policy = "on-request";
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
