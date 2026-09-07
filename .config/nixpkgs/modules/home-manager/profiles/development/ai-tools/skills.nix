{
  pkgs,
  lib,
  config,
  ...
}: let
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
  modelSelectionSkill = {
    harness,
    profile,
    codexCliProxy ? false,
    liteLLM ? false,
  }:
    pkgs.runCommandLocal "model-selection-${harness}-${profile}" {nativeBuildInputs = [pkgs.bun];} ''
      workdir="$TMPDIR/model-selection"
      mkdir -p "$out" "$workdir/snapshots"
      cp ${../ai-skills/model-selection/SKILL.md} "$workdir/SKILL.md"
      cp ${../ai-skills/model-selection/generator.ts} "$workdir/generator.ts"
      cp ${../ai-skills/model-selection/policy.ts} "$workdir/policy.ts"
      cp ${../ai-skills/model-selection/snapshots/deepswe-v1.1.json} "$workdir/snapshots/deepswe-v1.1.json"
      cp ${../ai-skills/model-selection/snapshots/terminal-bench-2.1.json} "$workdir/snapshots/terminal-bench-2.1.json"
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
  # Every harness gets the same shared skill directories. Only model-selection
  # varies because its provider guidance is generated for the target harness.
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
    description = "Model-selection profile used to generate installed skills";
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
