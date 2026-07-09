{
  pkgs,
  lib,
  config,
  ...
}: let
  codexReset = pkgs.writeShellApplication {
    name = "reset-codex";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gnused
      jq
    ];
    text = builtins.readFile ./reset-codex.sh;
  };

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

  opencodeLiteLLMOptions =
    {
      baseUrl = config.my.opencode.litellm.baseUrl;
      apiKeyEnv = config.my.opencode.litellm.apiKeyEnv;
      keyFile = config.my.opencode.litellm.keyFile;
      routeOverrides = {
        responses = config.my.opencode.litellm.routeOverrides.responses;
        chat = config.my.opencode.litellm.routeOverrides.chat;
      };
      defaults = {
        context = config.my.opencode.litellm.defaults.context;
        output = config.my.opencode.litellm.defaults.output;
        input = config.my.opencode.litellm.defaults.input;
      };
      headers = config.my.opencode.litellm.headers;
    }
    // lib.optionalAttrs (config.my.opencode.litellm.modelsUrl != null) {
      modelsUrl = config.my.opencode.litellm.modelsUrl;
    };

  opencodeLiteLLMDir = "${config.home.homeDirectory}/.config/opencode/litellm";
  opencodeLiteLLMSource = pkgs.runCommandLocal "opencode-litellm" {} ''
    mkdir -p "$out"
    cp -R ${./opencode/litellm}/. "$out/"
    rm -f "$out/routing.ts"
    cp ${./litellm/routing.ts} "$out/routing.ts"
  '';

  opencodeLiteLLMEnabled = config.my.opencode.enable && config.my.opencode.litellm.enable;
  piLiteLLMEnabled = config.my.pi.enable && config.my.pi.litellm.enable;
  piLiteLLMProviderDir = "${config.home.homeDirectory}/.pi/agent/litellm-provider";
  piLiteLLMProviderSource = pkgs.runCommandLocal "pi-litellm-provider" {} ''
    mkdir -p "$out"
    cp -R ${./pi/litellm-provider}/. "$out/"
    rm -f "$out/routing.ts"
    cp ${./litellm/routing.ts} "$out/routing.ts"
  '';
in {
  options.my.opencode = {
    disablePythonFormatters = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to disable Python formatters (ruff, uv) in opencode";
    };

    package = lib.mkPackageOption pkgs "opencode" {};

    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the opencode package to be installed";
    };

    litellm = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the LiteLLM provider integration for opencode";
      };

      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://ai-proxy.infra.corp.arista.io";
        description = "LiteLLM proxy base URL for opencode";
      };

      modelsUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional explicit LiteLLM model discovery URL";
      };

      apiKeyEnv = lib.mkOption {
        type = lib.types.str;
        default = "LITELLM_API_KEY";
        description = "Environment variable containing the LiteLLM API key";
      };

      keyFile = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/.config/ai-keys/litellm";
        description = "Fallback file containing the LiteLLM API key for model discovery";
      };

      headers = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
        description = "Additional headers to send during LiteLLM model discovery";
      };

      routeOverrides = {
        responses = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "LiteLLM model IDs to force through the OpenAI Responses route";
        };

        chat = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "LiteLLM model IDs to force through the OpenAI-compatible chat route";
        };
      };

      defaults = {
        input = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = ["text"];
          description = "Default input modalities for LiteLLM models without metadata";
        };

        context = lib.mkOption {
          type = lib.types.int;
          default = 128000;
          description = "Default context window for LiteLLM models without metadata";
        };

        output = lib.mkOption {
          type = lib.types.int;
          default = 16384;
          description = "Default output token limit for LiteLLM models without metadata";
        };
      };
    };
  };

  options.my.pi = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the pi coding-agent package";
    };

    package = lib.mkPackageOption pkgs "pi-coding-agent" {};

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

      routeOverrides = {
        responses = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "LiteLLM model IDs to force through the OpenAI Responses route in pi";
        };

        chat = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "LiteLLM model IDs to force through the OpenAI-compatible chat route in pi";
        };
      };
    };
  };

  config = {
    programs.mcp.enable = true;

    # AI tool packages
    # Secrets are defined in secrets/ai.nix.
    home.packages = with pkgs;
      [
        codexReset
        codexSubscriptionUsage
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [ollama]
      ++ lib.optionals config.my.pi.enable [config.my.pi.package];

    home.file = lib.mkMerge [
      (lib.mkIf opencodeLiteLLMEnabled {
        ".config/opencode/litellm".source = opencodeLiteLLMSource;
        ".config/litellm".source = ./litellm;
      })
      (lib.mkIf piLiteLLMEnabled {
        ".pi/litellm".source = ./litellm;
        ".pi/agent/litellm-provider".source = piLiteLLMProviderSource;
        ".pi/agent/settings.json".source =
          (pkgs.formats.json {}).generate "pi-coding-agent-settings.json"
          {
            extensions = [piLiteLLMProviderDir];
            litellmProvider = {
              baseUrl = config.my.pi.litellm.baseUrl;
              apiKey = "env:LITELLM_API_KEY";
              authHeaderName = "x-litellm-api-key";
              sendBearerAuth = true;
              routeOverrides = {
                responses = config.my.pi.litellm.routeOverrides.responses;
                chat = config.my.pi.litellm.routeOverrides.chat;
              };
              providerCompat = {
                supportsDeveloperRole = false;
                supportsReasoningEffort = true;
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
        ".codex/config.toml".force = true;
        ".tmux-codex.conf".text = ''
          set -g @codex_subscription_usage_segment "#(${codexTmuxSegment}/bin/codex-subscription-usage-tmux)"
        '';
      }
    ];

    programs.opencode = {
      enable = config.my.opencode.enable;
      enableMcpIntegration = true;
      package = config.my.opencode.package;
      tui = {
        theme = "one-dark";
        plugin = lib.mkIf opencodeLiteLLMEnabled [
          "${opencodeLiteLLMDir}/plugin-v2-tui.ts"
        ];
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
        plugin = lib.mkIf opencodeLiteLLMEnabled [
          [
            "${opencodeLiteLLMDir}/plugin-v2.ts"
            opencodeLiteLLMOptions
          ]
        ];
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
      };
    };

    programs.codex = {
      enable = true;
      enableMcpIntegration = true;
      package = pkgs.codex;
      settings = {
        model = "gpt-5.5";
        model_reasoning_effort = "high";
        # This needs to be disabled for now, as my work proxy rejects reasoning summaries
        # for codex-auto-review.
        # model_reasoning_summary = "auto";

        approval_policy = "on-request";
        approvals_reviewer = "auto_review";

        analytics.enabled = false;
        feedback.enabled = false;

        projects.${config.home.homeDirectory}.trust_level = "trusted";

        tui = {
          theme = "one-half-dark";
        };
      };
      skills = {
        commit = ./opencode/commit/SKILL.md;
        change-amplification = ./ai-skills/change-amplification/SKILL.md;
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
