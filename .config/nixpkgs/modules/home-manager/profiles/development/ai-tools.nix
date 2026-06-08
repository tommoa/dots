{
  pkgs,
  lib,
  config,
  ...
}: {
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

  config = {
    programs.mcp.enable = true;

    # AI tool packages
    # Secrets are defined in secrets/ai.nix.
    home.packages = with pkgs;
      [
        hunk # Review-first terminal diff viewer with agent skill integration
        # ollama is broken on darwin with 25.11
        # https://github.com/NixOS/nixpkgs/issues/463131
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [ollama]
      ++ lib.optionals config.my.opencode.desktop.enable [opencode-desktop];

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

        analytics.enabled = false;
        feedback.enabled = false;
        features.js_repl = false;

        projects.${config.home.homeDirectory}.trust_level = "trusted";

        tui = {
          theme = "one-dark";
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
