{
  pkgs,
  config,
  lib,
  ...
}: let
  opencodeLiteLLMEnabled = config.my.opencode.enable && config.my.opencode.litellm.enable;
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
    cp -R ${../opencode/litellm}/. "$out/"
    rm -f "$out/routing.ts"
    cp ${../litellm/routing.ts} "$out/routing.ts"
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
    litellm.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the LiteLLM provider integration for opencode";
    };
  };
  config = {
    home.file = lib.mkIf opencodeLiteLLMEnabled {
      ".config/opencode/litellm".source = opencodeLiteLLMSource;
      ".config/litellm".source = ../litellm;
    };
    programs.opencode = {
      enable = config.my.opencode.enable;
      enableMcpIntegration = true;
      package = config.my.opencode.package;
      tui.theme = "one-dark";
      settings = {
        lsp.vhdl-ls = {
          command = ["vhdl_ls"];
          extensions = [".vhd" ".vhdl"];
        };
        plugin = lib.mkIf opencodeLiteLLMEnabled [["${opencodeLiteLLMDir}/plugin.ts" opencodeLiteLLMOptions]];
        formatter =
          {
            alejandra = {
              command = ["${pkgs.alejandra}/bin/alejandra" "$FILE"];
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
      commands.rethink = ''
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
  };
}
