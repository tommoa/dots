{
  pkgs,
  lib,
  config,
  ...
}: let
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
      default = "gpt-5.6-sol";
      description = "The default model for codex to use";
    };
    reviewModel = lib.mkOption {
      type = lib.types.str;
      default = "gpt-5.6-sol";
      description = "The model to use for the /review command";
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
        agents = {
          default_subagent_model = "gpt-5.6-luna";
          default_subagent_reasoning_effort = "high";
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
            accent = "#4d78cc";
            contrast = 60;
            fonts = {
              code = "monospace";
              ui = "monospace";
            };
            ink = "#fafafa";
            surface = "#282c34";
            opaqueWindows = true;
            semanticColors = {
              diffAdded = "#40c977";
              diffRemoved = "#fa423e";
              skill = "#ad7bf9";
            };
          };
        };
        tui.theme = "one-half-dark";
      };
    };
  };
}
