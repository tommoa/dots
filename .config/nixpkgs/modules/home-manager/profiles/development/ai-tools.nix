{
  pkgs,
  lib,
  config,
  ...
}: {
  options.my.opencode.disablePythonFormatters = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether to disable Python formatters (ruff, uv) in opencode";
  };

  config = {
    # AI tool packages
    # Secrets are defined in secrets/ai.nix or secrets/ai-vertex.nix
    home.packages = with pkgs;
      [
        google-cloud-sdk # This is required for using Vertex AI.
        # ollama is broken on darwin with 25.11
        # https://github.com/NixOS/nixpkgs/issues/463131
      ]
      ++ (
        if pkgs.stdenv.isLinux
        then [ollama]
        else []
      );

    programs.opencode = {
      enable = true;
      package = pkgs.opencode;
      settings = {
        theme = "one-dark";
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
    };

    # TODO: Replace with programs.opencode.skills.commit when on home-manager >= 26.05
    xdg.configFile."opencode/skill/commit/SKILL.md".source = ./opencode/commit/SKILL.md;
  };
}
