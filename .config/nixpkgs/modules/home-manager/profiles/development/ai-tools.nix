{
  pkgs,
  lib,
  config,
  ...
}: let
  codexSubscriptionAccounts = builtins.readFile ./codex-cli-proxy-accounts.sh;

  codexReset = pkgs.writeShellApplication {
    name = "reset-codex";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gnused
      jq
    ];
    text = codexSubscriptionAccounts + builtins.readFile ./reset-codex.sh;
  };

  codexSubscriptionUsage = pkgs.writeShellApplication {
    name = "codex-subscription-usage";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
      gnused
    ];
    text = codexSubscriptionAccounts + builtins.readFile ./codex-subscription-usage.sh;
  };

  codexTmuxSegment = pkgs.writeShellApplication {
    name = "codex-subscription-usage-tmux";
    runtimeInputs = [
      codexSubscriptionUsage
    ];
    text = ''
      codex_usage="$(codex-subscription-usage 2>/dev/null || true)"
      if [ -n "$codex_usage" ]; then
        printf '#[fg=cyan] %s #[fg=white,nobold,noitalics,nounderscore]|\n' "$codex_usage"
      fi
    '';
  };

  opencodeLiteLLMEnabled = config.my.opencode.enable && config.my.opencode.litellm.enable;
  piLiteLLMEnabled = config.my.pi.enable && config.my.pi.litellm.enable;
  codexCliProxyEnabled = (config.programs.codex.settings.model_provider or null) == "cli_proxy_api";
  modelSelectionProfile = config.my.modelSelection.profile;

  codexNoImplicitInvocationPolicy = (pkgs.formats.yaml {}).generate "codex-skill-openai.yaml" {
    policy.allow_implicit_invocation = false;
  };

  # Keep complete skill directories intact. Only copy a skill when Codex-specific
  # metadata must be overlaid without changing the source used by other harnesses.
  mkCodexSkill = {
    name,
    source,
    allowImplicitInvocation ? true,
  }:
    if allowImplicitInvocation
    then source
    else
      pkgs.runCommandLocal "codex-skill-${name}" {}
      ''
        mkdir -p "$out"
        cp -R ${source}/. "$out/"
        if [ -e "$out/agents/openai.yaml" ]; then
          echo "${name} already provides agents/openai.yaml; merge its policy explicitly" >&2
          exit 1
        fi
        mkdir -p "$out/agents"
        cp ${codexNoImplicitInvocationPolicy} "$out/agents/openai.yaml"
      '';

  modelSelectionSkill = {
    harness,
    profile,
    codexCliProxy ? false,
    liteLLM ? false,
  }:
    pkgs.runCommandLocal "model-selection-${harness}-${profile}" {nativeBuildInputs = [pkgs.bun];}
    ''
      workdir="$TMPDIR/model-selection"
      mkdir -p "$out" "$workdir/snapshots"
      cp ${./ai-skills/model-selection/SKILL.md} "$workdir/SKILL.md"
      cp ${./ai-skills/model-selection/generator.ts} "$workdir/generator.ts"
      cp ${./ai-skills/model-selection/policy.ts} "$workdir/policy.ts"
      cp ${./ai-skills/model-selection/snapshots/deepswe-v1.1.json} "$workdir/snapshots/deepswe-v1.1.json"
      cp ${./ai-skills/model-selection/snapshots/terminal-bench-2.1.json} "$workdir/snapshots/terminal-bench-2.1.json"
      bun run "$workdir/generator.ts" generate \
        --template "$workdir/SKILL.md" \
        --output "$out/SKILL.md" \
        --snapshot "$workdir/snapshots/deepswe-v1.1.json" \
        --terminal-snapshot "$workdir/snapshots/terminal-bench-2.1.json" \
        --harness ${harness} \
        --profile ${profile} \
        ${lib.optionalString codexCliProxy "--codex-cli-proxy"} \
        ${lib.optionalString liteLLM "--litellm"}
    '';

  codexModelSelectionSkill = modelSelectionSkill {
    harness = "codex";
    profile = modelSelectionProfile;
    codexCliProxy = codexCliProxyEnabled;
  };

  opencodeModelSelectionSkill = modelSelectionSkill {
    harness = "opencode";
    profile = modelSelectionProfile;
    liteLLM = opencodeLiteLLMEnabled;
  };

  piModelSelectionSkill = modelSelectionSkill {
    harness = "pi";
    profile = modelSelectionProfile;
    liteLLM = piLiteLLMEnabled;
  };

  sharedSkillSources = {
    api-design-evaluation = ./ai-skills/api-design-evaluation;
    architectural-decision-record = ./ai-skills/architectural-decision-record;
    arena = ./ai-skills/arena;
    arena-loop = ./ai-skills/arena-loop;
    change-amplification = ./ai-skills/change-amplification;
    code-obviousness = ./ai-skills/code-obviousness;
    commit = ./ai-skills/commit;
    grilling = ./ai-skills/grilling;
    rethink = ./ai-skills/rethink;
    simplification-loop = ./ai-skills/simplification-loop;
    ui-design-evaluation = ./ai-skills/ui-design-evaluation;
  };

  withModelSelection = modelSelection: sharedSkillSources // {model-selection = modelSelection;};

  # Every harness gets the same shared skill directories. Only model-selection
  # varies because its provider guidance is generated for the target harness.
  skillSourcesByHarness = {
    codex = withModelSelection codexModelSelectionSkill;
    opencode = withModelSelection opencodeModelSelectionSkill;
    pi = withModelSelection piModelSelectionSkill;
  };

  codexSkills =
    lib.mapAttrs (
      name: source:
        mkCodexSkill {
          inherit name source;
          # Multi-round loops are intentional, comparatively expensive
          # workflows; keep them available only through `$skill`.
          allowImplicitInvocation =
            !builtins.elem name [
              "arena-loop"
              "simplification-loop"
            ];
        }
    )
    skillSourcesByHarness.codex;

  piSkillFiles =
    lib.mapAttrs' (
      name: source:
        lib.nameValuePair ".pi/agent/skills/${name}" {
          inherit source;
        }
    )
    skillSourcesByHarness.pi;

  opencodeLiteLLMOptions = {
    baseUrl = config.my.aiProxy.baseUrl;
    apiKeyEnv = config.my.aiProxy.apiKeyEnv;
    keyFile = config.my.aiProxy.keyFile;
    routeOverrides = {
      responses = config.my.aiProxy.routeOverrides.responses;
      chat = config.my.aiProxy.routeOverrides.chat;
    };
    defaults = {
      context = config.my.aiProxy.defaults.context;
      output = config.my.aiProxy.defaults.output;
      input = config.my.aiProxy.defaults.input;
    };
    headers = config.my.aiProxy.headers;
  };

  opencodeLiteLLMDir = "${config.home.homeDirectory}/.config/opencode/litellm";
  opencodeLiteLLMSource = pkgs.runCommandLocal "opencode-litellm" {} ''
    mkdir -p "$out"
    cp -R ${./opencode/litellm}/. "$out/"
    rm -f "$out/routing.ts"
    cp ${./litellm/routing.ts} "$out/routing.ts"
  '';

  piLiteLLMProviderDir = "${config.home.homeDirectory}/.pi/agent/litellm-provider";
  piLiteLLMProviderSource = pkgs.runCommandLocal "pi-litellm-provider" {} ''
    mkdir -p "$out"
    cp -R ${./pi/litellm-provider}/. "$out/"
    rm -f "$out/routing.ts"
    cp ${./litellm/routing.ts} "$out/routing.ts"
  '';
in {
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
    };
  };

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

  options.my.modelSelection.profile = lib.mkOption {
    type = lib.types.enum [
      "personal"
      "work"
    ];
    default = "personal";
    description = "Model-selection profile used to generate installed skills";
  };

  config = {
    programs.mcp.enable = true;

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
      (lib.mkIf config.my.pi.enable (
        {
          ".pi/agent/AGENTS.md".source = ./context.md;
        }
        // piSkillFiles
      ))
      (lib.mkIf piLiteLLMEnabled {
        ".pi/litellm".source = ./litellm;
        ".pi/agent/litellm-provider".source = piLiteLLMProviderSource;
        ".pi/agent/settings.json".source =
          (pkgs.formats.json {}).generate "pi-coding-agent-settings.json"
          {
            extensions = [piLiteLLMProviderDir];
            litellmProvider = {
              baseUrl = config.my.aiProxy.baseUrl;
              apiKey = "env:${config.my.aiProxy.apiKeyEnv}";
              authHeaderName = "x-litellm-api-key";
              sendBearerAuth = true;
              routeOverrides = {
                responses = config.my.aiProxy.routeOverrides.responses;
                chat = config.my.aiProxy.routeOverrides.chat;
              };
              providerCompat = {
                supportsDeveloperRole = false;
                supportsReasoningEffort = true;
                maxTokensField = "max_tokens";
              };
              defaults = {
                input = config.my.aiProxy.defaults.input;
                contextWindow = config.my.aiProxy.defaults.context;
                maxTokens = config.my.aiProxy.defaults.output;
              };
              headers = config.my.aiProxy.headers;
            };
          };
      })
      {
        ".codex/AGENTS.md" = {
          force = true;
          source = ./context.md;
        };
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
            "${opencodeLiteLLMDir}/plugin.ts"
            opencodeLiteLLMOptions
          ]
        ];
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
          description: Make sure that the agent rethinks its architectural decisions
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
      skills = skillSourcesByHarness.opencode;
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

        tui = {
          theme = "one-half-dark";
        };
      };
      skills = codexSkills;
    };

    xdg.configFile."opencode/AGENTS.md".source = ./context.md;
  };
}
