{
  pkgs,
  lib,
  config,
  ...
}: let
  codexSubscriptionUsage = pkgs.writeShellApplication {
    name = "codex-subscription-usage";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
      gnused
    ];
    text = builtins.readFile ./codex-subscription-usage.sh;
  };

  codexTmuxSegment = pkgs.writeShellApplication {
    name = "codex-subscription-usage-tmux";
    runtimeInputs = [
      codexSubscriptionUsage
    ];
    text = ''
      codex_usage="$(codex-subscription-usage 2>/dev/null || true)"
      if [ -n "$codex_usage" ]; then
        printf '#[fg=cyan] %s #[fg=white,nobold,noitalics,nounderscore]|' "$codex_usage"
      fi
    '';
  };
in {
  options.my.opencode = {
    disablePythonFormatters = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to disable Python formatters (ruff, uv) in opencode";
    };

    desktop.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Install the opencode desktop app alongside the CLI/TUI";
    };

    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the opencode package to be installed";
    };
  };

  options.my.pi = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the pi coding-agent package";
    };

    package = lib.mkPackageOption pkgs "pi-coding-agent" {
      default = null;
    };

    litellm = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the LiteLLM provider extension for pi";
      };

      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://ai-proxy.infra.corp.arista.io/";
        description = "LiteLLM proxy base URL for pi";
      };
    };
  };

  config = {
    programs.mcp.enable = true;

    # AI tool packages
    # Secrets are defined in secrets/ai.nix.
    home.packages = with pkgs;
      [
        hunk # Review-first terminal diff viewer with agent skill integration
        codexSubscriptionUsage
        # ollama is broken on darwin with 25.11
        # https://github.com/NixOS/nixpkgs/issues/463131
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [ollama]
      ++ lib.optionals config.my.pi.enable [config.my.pi.package]
      ++ lib.optionals config.my.opencode.desktop.enable [opencode-desktop];

    home.file = lib.mkMerge [
      (lib.mkIf (config.my.pi.enable && config.my.pi.litellm.enable) {
        ".pi/agent/settings.json".source = (pkgs.formats.json {}).generate "pi-coding-agent-settings.json" {
          extensions = ["${./pi/litellm-provider}"];
          litellmProvider = {
            baseUrl = config.my.pi.litellm.baseUrl;
            apiKey = "env:LITELLM_API_KEY";
            authHeaderName = "x-litellm-api-key";
            sendBearerAuth = true;
            providerCompat = {
              supportsDeveloperRole = false;
              supportsReasoningEffort = false;
              maxTokensField = "max_tokens";
            };
            defaults = {
              input = ["text"];
              contextWindow = 128000;
              maxTokens = 16384;
            };
            headers = {};
          };
        };
      })
      {
        ".tmux-codex.conf".text = ''
          set -g @codex_subscription_usage_segment "#(${codexTmuxSegment}/bin/codex-subscription-usage-tmux)"
        '';
      }
    ];

    programs.opencode = {
      enable = config.my.opencode.enable;
      enableMcpIntegration = true;
      package = pkgs.opencode;
      tui = {
        theme = "one-dark";
      };
      settings = {
        lsp = {
          vhdl-ls = {
            command = ["vhdl_ls"];
            extensions = [
              ".vhd"
              ".vhdl"
            ];
          };
        };
        agent = {
          orchestrator = {
            description = "Orchestrates parallel subagents for multi-step remote data gathering";
            mode = "subagent";
            permission.task = "allow";
          };
        };
        formatter =
          {
            alejandra = {
              command = [
                "${pkgs.alejandra}/bin/alejandra"
                "$FILE"
              ];
              extensions = ["nix"];
            };
          }
          // lib.optionalAttrs config.my.opencode.disablePythonFormatters {
            # Ruff (and by extension uv) don't support configuration of the
            # formatting configuration. This can make it rather frustrating when
            # using it at (for example) my work, which follows a different style
            # guide.
            ruff.disabled = true;
            uv.disabled = true;
          };
      };
      commands = {
        rethink = ''
          ---
          description: Make sure that the agent rethinks its decisions for design
          ---
          Please carefully consider the following questions, then provide a thorough
          response for each of them to the user.

          - Is it the right way to solve this issue?
          - Will it be the most maintainable option?
          - Is this actually a bug in a different system that we should be fixing?
          - Is this the right interface to use?
          - What is the simplest interface that will cover all my current needs?
          - In how many situations will this method be used?
          - Is this API easy to use for my current needs?
          - Does any information get used in multiple places?
          - Will users be able to determine a better value than can be determined
            here? (for configuration)
          - Is there any code that needs to be written more than once?
          - Can you hide any special cases?
        '';
      };
      skills = {
        commit = ./opencode/commit/SKILL.md;
        change-amplification = ./ai-skills/change-amplification/SKILL.md;
        hunk-review = "${pkgs.hunk}/skills/hunk-review";
      };
    };

    programs.codex = {
      enable = true;
      enableMcpIntegration = true;
      package = pkgs.codex;
      settings = {
        model = "gpt-5.5";
        model_reasoning_effort = "high";

        approval_policy = "on-request";
        approvals_reviewer = "auto_review";

        analytics.enabled = false;
        feedback.enabled = false;
        features = {
          # Let spawned child-agent sessions receive Codex child-agent guidance files.
          child_agents_md = true;
          # Allow Codex to fan out suitable work across multiple child agents.
          enable_fanout = true;
          # Keep the removed JavaScript REPL tool disabled if older Codex builds see it.
          js_repl = false;
          # Enable the stable multi-agent tool surface for spawning child agents.
          multi_agent = true;
          # Opt into native multi-agent V2 and cap concurrent child-agent threads.
          multi_agent_v2 = {
            enabled = true;
            max_concurrent_threads_per_session = 20;
          };
        };

        projects.${config.home.homeDirectory}.trust_level = "trusted";

        tui = {
          theme = "one-half-dark";
          vim_mode_default = true;
        };
      };
      skills = {
        commit = ./opencode/commit/SKILL.md;
        change-amplification = ./ai-skills/change-amplification/SKILL.md;
        hunk-review = "${pkgs.hunk}/skills/hunk-review";
        rethink = ''
          ---
          name: rethink
          description: Make sure the agent rethinks its decisions for design
          ---

          Please carefully consider the following questions, then provide a thorough
          response for each of them to the user.

          - Is it the right way to solve this issue?
          - Will it be the most maintainable option?
          - Is this actually a bug in a different system that we should be fixing?
          - Is this the right interface to use?
          - What is the simplest interface that will cover all my current needs?
          - In how many situations will this method be used?
          - Is this API easy to use for my current needs?
          - Does any information get used in multiple places?
          - Will users be able to determine a better value than can be determined
            here? (for configuration)
          - Is there any code that needs to be written more than once?
          - Can you hide any special cases?
        '';
      };
    };
  };
}
