{
  pkgs,
  lib,
  config,
  ...
}: let
  opencodeLiteLLMEnabled = config.my.opencode.enable && config.my.opencode.litellm.enable;
  piLiteLLMEnabled = config.my.pi.enable && config.my.pi.litellm.enable;
  codexAIProxyAvailable =
    config.my.aiProxy.enable
    && (config.programs.codex.settings.model_provider or null) == "cli_proxy_api";
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
      pkgs.runCommandLocal "codex-skill-${name}" {} ''
        mkdir -p "$out"
        cp -R ${source}/. "$out/"
        if [ -e "$out/agents/openai.yaml" ]; then
          echo "${name} already provides agents/openai.yaml; merge its policy explicitly" >&2
          exit 1
        fi
        mkdir -p "$out/agents"
        cp ${codexNoImplicitInvocationPolicy} "$out/agents/openai.yaml"
      '';
  providerGuidance = {
    codexAIProxy = ''
      ## Provider continuity

      This configuration exposes corporate models through CLIProxyAPI under
      `ai-proxy/*`. Use those slugs or other approved corporate models for
      proprietary work. Inspect `~/.codex/config.toml` when the active model or
      subagent provider matters.

    '';
    liteLLM = ''
      ## Provider continuity

      Use model IDs discovered from the configured corporate AI proxy. If the
      selected model uses LiteLLM, choose alternatives from that same provider.
      If it does not use LiteLLM, do not introduce a LiteLLM model ID.

    '';
  };
  modelSelectionSkill = {guidance ? ""}:
    pkgs.writeTextDir "SKILL.md" (
      builtins.replaceStrings
      ["@profile@" "@provider-guidance@\n"]
      [config.my.modelSelection.profile guidance]
      (builtins.readFile ../ai-skills/model-selection/SKILL.md)
    );
  codexModelSelectionSkill = modelSelectionSkill {
    guidance = lib.optionalString codexAIProxyAvailable providerGuidance.codexAIProxy;
  };
  opencodeModelSelectionSkill = modelSelectionSkill {
    guidance = lib.optionalString opencodeLiteLLMEnabled providerGuidance.liteLLM;
  };
  piModelSelectionSkill = modelSelectionSkill {
    guidance = lib.optionalString piLiteLLMEnabled providerGuidance.liteLLM;
  };
  sharedSkillSources = {
    api-design-evaluation = ../ai-skills/api-design-evaluation;
    architectural-decision-record = ../ai-skills/architectural-decision-record;
    arena = ../ai-skills/arena;
    arena-loop = ../ai-skills/arena-loop;
    change-amplification = ../ai-skills/change-amplification;
    code-obviousness = ../ai-skills/code-obviousness;
    commit = ../ai-skills/commit;
    data-oriented-review = ../ai-skills/data-oriented-review;
    grilling = ../ai-skills/grilling;
    obscurity-review = ../ai-skills/obscurity-review;
    rethink = ../ai-skills/rethink;
    simplification-loop = ../ai-skills/simplification-loop;
    ui-design-evaluation = ../ai-skills/ui-design-evaluation;
  };
  withModelSelection = modelSelection: sharedSkillSources // {model-selection = modelSelection;};
  # Provider guidance depends on both the harness and the integrations enabled
  # on this machine; the model and effort policy remains shared.
  skillSourcesByHarness = {
    codex = withModelSelection codexModelSelectionSkill;
    opencode = withModelSelection opencodeModelSelectionSkill;
    pi = withModelSelection piModelSelectionSkill;
  };
  codexSkills = lib.mapAttrs (name: source:
    mkCodexSkill {
      inherit name source;
      # Multi-round loops are intentional, comparatively expensive
      # workflows; keep them available only through `$skill`.
      allowImplicitInvocation = !builtins.elem name ["arena-loop" "simplification-loop"];
    })
  skillSourcesByHarness.codex;
  piSkillFiles =
    lib.mapAttrs' (
      name: source:
        lib.nameValuePair ".pi/agent/skills/${name}" {
          inherit source;
        }
    )
    skillSourcesByHarness.pi;
in {
  options.my.modelSelection.profile = lib.mkOption {
    type = lib.types.enum ["personal" "work"];
    default = "personal";
    description = "Work or personal policy embedded in the model-selection skill";
  };

  config = {
    home.file = lib.mkMerge [
      (lib.mkIf config.my.pi.enable ({".pi/agent/AGENTS.md".source = ../context.md;} // piSkillFiles))
      {
        ".codex/AGENTS.md" = {
          force = true;
          source = ../context.md;
        };
      }
    ];
    programs.opencode.skills = skillSourcesByHarness.opencode;
    programs.codex.skills = codexSkills;
    xdg.configFile."opencode/AGENTS.md".source = ../context.md;
  };
}
