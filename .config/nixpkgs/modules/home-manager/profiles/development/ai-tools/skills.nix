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
  piCliProxyEnabled = config.my.pi.enable && config.my.pi.provider == "cli-proxy-api";
  codexAIProxyAvailable =
    config.my.aiProxy.enable
    && (config.programs.codex.settings.model_provider or null) == "cli_proxy_api";
  codexNoImplicitInvocationPolicy = pkgs.writeText "codex-skill-openai.yaml" ''
    policy:
      allow_implicit_invocation: false
  '';
  providerGuidance = {
    codexAIProxy = ''
      ## Provider continuity

      CLIProxyAPI serves both corporate `ai-proxy/*` models and unprefixed
      subscription models. Identify the active parent model's upstream route
      before selecting a subagent: preserve `ai-proxy/` for a corporate parent
      and use the unprefixed route for a subscription parent. The shared
      `cli_proxy_api` provider name alone does not identify the upstream.
      Inspect the active session's model when available; `~/.codex/config.toml`
      provides defaults, which may differ from the active session.

      Check the configured subagent default as well: it may point to a different
      upstream from the active parent. Select the matching supported model ID
      explicitly when necessary and permitted by the harness. If continuity
      cannot be established or enforced, ask before delegating. Proprietary
      work must stay on an approved corporate provider.

    '';
    opencodeAIProxy = ''
      ## Provider continuity

      CLIProxyAPI serves both corporate `ai-proxy/*` models and unprefixed
      subscription models under the same `cli_proxy_api` provider. Inspect the
      active parent model and available models in the current harness; preserve
      the parent's upstream route when selecting a subagent.
      The provider name alone does not identify the upstream. Check any configured
      subagent default before relying on it, and select a matching supported ID
      when necessary and permitted. If continuity cannot be established or
      enforced, ask before delegating. Proprietary work must stay on an approved
      corporate provider.

    '';
    liteLLM = ''
      ## Provider continuity

      Identify the active parent model's provider before selecting a subagent.
      If it uses LiteLLM, choose a supported model ID discovered from that same
      corporate provider. Otherwise, preserve the parent's provider and do not
      introduce a LiteLLM model ID. Check any configured subagent default before
      relying on it. If continuity cannot be established or enforced, ask before
      delegating. Proprietary work must stay on an approved corporate provider.

    '';
  };
  modelDefaults = config.my.modelSelection.defaults.${config.my.modelSelection.profile};
  modelDefaultsGuidance = ''
    - **Ordinary subagent:** `${modelDefaults.subagentModel}`, **high** effort.
    - **New coordination subagent:** `${modelDefaults.coordinatorModel}`, **high** effort.
  '';
  coordinatorGuidance = ''
    For an existing coordinator, preserve Sol and its current effort in the work
    profile, or Astra or Sol and its current effort in the personal profile.
    Astra is unavailable for work; do not select or retain it for work coordination.
  '';
  modelSelectionSkill = {guidance ? ""}:
    builtins.replaceStrings
    ["@profile@" "@model-defaults@\n" "@provider-guidance@\n" "@coordinator-guidance@\n"]
    [config.my.modelSelection.profile modelDefaultsGuidance guidance coordinatorGuidance]
    (builtins.readFile ../ai-skills/model-selection/SKILL.md);
  codexModelSelectionSkill = modelSelectionSkill {
    guidance = lib.optionalString codexAIProxyAvailable providerGuidance.codexAIProxy;
  };
  opencodeModelSelectionSkill = modelSelectionSkill {
    guidance =
      lib.optionalString opencodeAIProxyAvailable providerGuidance.opencodeAIProxy
      + lib.optionalString opencodeLiteLLMEnabled providerGuidance.liteLLM;
  };
  piModelSelectionSkill = modelSelectionSkill {
    guidance =
      lib.optionalString piCliProxyEnabled providerGuidance.opencodeAIProxy
      + lib.optionalString piLiteLLMEnabled providerGuidance.liteLLM;
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
    cursor = withModelSelection (pkgs.writeTextDir "SKILL.md" (modelSelectionSkill {}));
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
          coordinatorModel = "gpt-6.1-sol";
        };
      };
      description = "Model defaults shared by generated skills and harness settings";
    };
  };

  config = {
    my.cursor.skills = skillSourcesByHarness.cursor // explicitSkills;
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
