{
  pkgs,
  lib,
  config,
  ...
}: let
  opencodeAIProxyAvailable =
    config.my.opencode.enable
    && config.my.aiProxy.enable
    && config.my.opencode.provider == "cli-proxy-api";
  opencodeLiteLLMEnabled = config.my.opencode.enable && config.my.opencode.provider == "litellm";
  piLiteLLMEnabled = config.my.pi.enable && config.my.pi.provider == "litellm";
  piAIProxyAvailable =
    config.my.pi.enable
    && config.my.aiProxy.enable
    && config.my.pi.provider == "cli-proxy-api";
  codexAIProxyAvailable =
    config.my.aiProxy.enable
    && (config.programs.codex.settings.model_provider or null) == "cli_proxy_api";
  # The work AI proxy is a LiteLLM deployment.
  codexLiteLLMEnabled = (config.programs.codex.settings.model_provider or null) == "ai_proxy";
  codexNoImplicitInvocationPolicy = pkgs.writeText "codex-skill-openai.yaml" ''
    policy:
      allow_implicit_invocation: false
  '';
  # Each section starts with a blank line so an empty guidance string leaves
  # the template's trailing newline intact.
  section = text: "\n" + text;
  # Only work machines enable the corporate AI proxy alongside CLIProxyAPI.
  routesGuidance = section ''
    ## Routes

    IDs containing `ai-proxy/` are corporate; others are personal subscriptions,
    for personal tasks only. A subagent matches its parent's route, but work
    never runs on a personal subscription. Check the session's actual model,
    not the configured default.
  '';
  liteLLMGuidance = section ''
    ## Provider

    All models here come from LiteLLM, an approved work provider.
  '';
  cursorGuidance = section ''
    ## Cursor

    Use Cursor for work tasks only. Native subagents cannot select these models;
    delegate via T3's `delegate_task` on the `cursor` instance, with IDs from
    `orchestrator_capabilities`: Haiku with `thinking: true` and
    `reasoning_effort: high`, Opus with `effort: high`. Without `delegate_task`,
    ask once per session how to delegate.
  '';
  cursorViaT3Guidance = lib.optionalString config.my.cursor.enable (section ''
    ## Cursor via T3

    Cursor, an approved work provider for work tasks only, is available through
    T3's `delegate_task` (`cursor` instance) when the user asks for it.
  '');
  modelDefaults = config.my.modelSelection.defaults.${config.my.modelSelection.profile};
  modelSelectionSkill = {
    guidance,
    defaults,
  }:
    builtins.replaceStrings
    ["@profile@" "@subagent-model@" "@coordinator-model@" "@provider-guidance@\n"]
    [config.my.modelSelection.profile defaults.subagentModel defaults.coordinatorModel guidance]
    (builtins.readFile ../ai-skills/model-selection/SKILL.md);
  # OpenCode and Pi list models under their provider ID; Codex does not.
  harnessSkill = {
    providerPrefix,
    corporateRoute,
    liteLLM,
  }:
    modelSelectionSkill {
      guidance =
        lib.optionalString corporateRoute routesGuidance
        + lib.optionalString liteLLM liteLLMGuidance
        + cursorViaT3Guidance;
      defaults =
        lib.mapAttrs (_: model: providerPrefix + lib.optionalString corporateRoute "ai-proxy/" + model)
        modelDefaults;
    };
  harnessPrefix = provider:
    if provider == "cli-proxy-api"
    then "cli_proxy_api/"
    else "${provider}/";
  cursorModelSelectionSkill = modelSelectionSkill {
    guidance = cursorGuidance;
    defaults = {
      subagentModel = "claude-haiku-5-5";
      coordinatorModel = "claude-opus-5-5";
    };
  };
  codexModelSelectionSkill = harnessSkill {
    providerPrefix = "";
    corporateRoute = codexAIProxyAvailable;
    liteLLM = codexLiteLLMEnabled;
  };
  opencodeModelSelectionSkill = harnessSkill {
    providerPrefix = harnessPrefix config.my.opencode.provider;
    corporateRoute = opencodeAIProxyAvailable;
    liteLLM = opencodeLiteLLMEnabled;
  };
  piModelSelectionSkill = harnessSkill {
    providerPrefix = harnessPrefix config.my.pi.provider;
    corporateRoute = piAIProxyAvailable;
    liteLLM = piLiteLLMEnabled;
  };
  sharedSkillSources = {
    api-design-evaluation = ../ai-skills/api-design-evaluation;
    architectural-decision-record = ../ai-skills/architectural-decision-record;
    arena = ../ai-skills/arena;
    arena-loop = ../ai-skills/arena-loop;
    change-amplification = ../ai-skills/change-amplification;
    code-obviousness = ../ai-skills/code-obviousness;
    commit = ../ai-skills/commit;
    council = ../ai-skills/council;
    data-oriented-review = ../ai-skills/data-oriented-review;
    grilling = ../ai-skills/grilling;
    obscurity-review = ../ai-skills/obscurity-review;
    rethink = ../ai-skills/rethink;
    simplification-loop = ../ai-skills/simplification-loop;
    socratic-tutor = ../ai-skills/socratic-tutor;
    ui-design-evaluation = ../ai-skills/ui-design-evaluation;
  };
  withModelSelection = modelSelection: sharedSkillSources // {model-selection = modelSelection;};
  # Provider guidance depends on both the harness and the integrations enabled
  # on this machine; the model and effort policy remains shared.
  skillSourcesByHarness = {
    codex = withModelSelection codexModelSelectionSkill;
    cursor = withModelSelection (pkgs.writeTextDir "SKILL.md" cursorModelSelectionSkill);
    opencode = withModelSelection opencodeModelSelectionSkill;
  };
  # Multi-round loops require explicit invocation in both Codex and Cursor.
  # Both harnesses can consume the same directory with their own metadata.
  explicitSkills = lib.genAttrs ["arena-loop" "simplification-loop"] (name:
    pkgs.runCommandLocal "explicit-skill-${name}" {} ''
      mkdir -p "$out"
      cp -R ${sharedSkillSources.${name}}/. "$out/"
      if [ -e "$out/agents/openai.yaml" ]; then
        echo "${name} already provides agents/openai.yaml; merge its policy explicitly" >&2
        exit 1
      fi
      mkdir -p "$out/agents"
      cp ${codexNoImplicitInvocationPolicy} "$out/agents/openai.yaml"
      chmod u+w "$out/SKILL.md"
      sed -i '1a disable-model-invocation: true' "$out/SKILL.md"
    '');
  codexSkillsDir =
    if config.home.preferXdgDirectories
    then lib.removePrefix "${config.home.homeDirectory}/" "${config.xdg.configHome}/codex/skills"
    else ".codex/skills";
  # The skill option inspects directory paths during evaluation. home.file can
  # link these complete build outputs without realizing them while evaluating.
  codexSkillFiles = lib.mapAttrs' (name: source:
    lib.nameValuePair "${codexSkillsDir}/${name}" {
      inherit source;
    })
  explicitSkills;
  piSkillFiles =
    lib.mapAttrs' (
      name: source:
        lib.nameValuePair ".pi/agent/skills/${name}" {
          inherit source;
        }
    )
    (sharedSkillSources // {model-selection = pkgs.writeTextDir "SKILL.md" piModelSelectionSkill;});
in {
  options.my.modelSelection = {
    profile = lib.mkOption {
      type = lib.types.enum ["personal" "work"];
      default = "personal";
      description = "Work or personal model defaults for the skill and harness";
    };
    # Keep the generated skill and harness defaults aligned.
    defaults = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      readOnly = true;
      default = {
        work = {
          subagentModel = "gpt-6-luna";
          coordinatorModel = "gpt-6.1-sol";
        };
        personal = {
          subagentModel = "gpt-6-luna";
          coordinatorModel = "gpt-6.2-sol";
        };
      };
      description = "Model defaults shared by generated skills and harness settings";
    };
  };

  config = {
    my.cursor.skills = lib.mkIf config.my.cursor.enable (skillSourcesByHarness.cursor // explicitSkills);
    home.file = lib.mkMerge [
      (lib.mkIf config.my.pi.enable ({".pi/agent/AGENTS.md".source = ../context.md;} // piSkillFiles))
      (lib.mkIf config.programs.codex.enable codexSkillFiles)
      {
        ".codex/AGENTS.md" = {
          force = true;
          source = ../context.md;
        };
      }
    ];
    programs.opencode.skills = skillSourcesByHarness.opencode;
    programs.codex.skills = builtins.removeAttrs skillSourcesByHarness.codex (builtins.attrNames explicitSkills);
    xdg.configFile."opencode/AGENTS.md".source = ../context.md;
  };
}
