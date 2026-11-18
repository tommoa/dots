{
  pkgs,
  config,
  lib,
  ...
}: let
  providerID =
    if config.my.opencode.provider == "cli-proxy-api"
    then "cli_proxy_api"
    else config.my.opencode.provider;
  enabledProviders = ["openai"] ++ lib.optional (providerID != "none") providerID;
  retiredIntegrations = lib.filter (id: !(lib.elem id enabledProviders)) [
    "anthropic"
    "google"
    "google-vertex"
    "google-vertex-anthropic"
    "litellm"
    "opencode"
    "openrouter"
  ];
  localRoot = config.my.aiTools.localStateRoot;
  localStateEnabled = localRoot != null;
  localPaths = {
    "${config.home.homeDirectory}/.opencode" = "${localRoot}/.opencode";
    "${config.xdg.dataHome}/opencode" = "${localRoot}/.local/share/opencode";
    "${config.xdg.stateHome}/opencode" = "${localRoot}/.local/state/opencode";
    "${config.xdg.cacheHome}/opencode" = "${localRoot}/.cache/opencode";
  };
  package = config.my.opencode.package;
  localPackage = pkgs.symlinkJoin {
    name = "opencode-with-local-state";
    inherit (package) meta version;
    paths = [package];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      # App-specific links keep state local without changing child tools' XDG
      # roots (and consequently breaking a infra login's credential lookup).
      wrapProgram $out/bin/${package.meta.mainProgram or "opencode"} \
        --run ${lib.escapeShellArg "${pkgs.coreutils}/bin/mkdir -p -m 700 ${lib.escapeShellArgs (builtins.attrValues localPaths)}"}
    '';
  };
  opencodeLiteLLMEnabled = config.my.opencode.enable && config.my.opencode.provider == "litellm";
  opencodeLiteLLMSource = pkgs.runCommandLocal "opencode-litellm" {} ''
    mkdir -p "$out/opencode/litellm" "$out/ai-providers"
    cp -R ${../opencode/litellm}/. "$out/opencode/litellm/"
    cp ${../ai-providers/routing.ts} "$out/ai-providers/routing.ts"
    cp ${../opencode/models.ts} "$out/opencode/models.ts"
  '';
  opencodeLiteLLMDir = "${opencodeLiteLLMSource}/opencode/litellm";
in {
  options.my.opencode = {
    disablePythonFormatters = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to disable Python formatters (ruff, uv) in opencode";
    };
    package = lib.mkPackageOption pkgs "opencode2" {};
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the opencode package to be installed";
    };
    provider = lib.mkOption {
      type = lib.types.enum ["none" "litellm" "cli-proxy-api"];
      default = "none";
      description = "Custom model provider for OpenCode";
    };
  };
  config = {
    my.aiTools.localStatePaths = lib.mkIf (localStateEnabled && config.my.opencode.enable) localPaths;
    programs.opencode = {
      enable = config.my.opencode.enable;
      enableMcpIntegration = true;
      package =
        if localStateEnabled
        then localPackage
        else package;
      tui.theme = "one-dark";
      settings = {
        # Saved credentials and inherited API keys also activate built-in providers.
        # Keep direct ChatGPT available alongside the selected proxy.
        enabled_providers = enabledProviders;
        policies =
          lib.concatMap (resource: [
            {
              action = "integration.connect";
              inherit resource;
              effect = "deny";
            }
            {
              action = "integration.use";
              inherit resource;
              effect = "deny";
            }
            {
              action = "integration.use";
              resource = "${resource}#*";
              effect = "deny";
            }
          ])
          retiredIntegrations
          ++ [
            # Account-scoped access keeps stale OPENAI_API_KEY environments out.
            {
              action = "integration.use";
              resource = "openai";
              effect = "deny";
            }
            {
              action = "integration.use";
              resource = "openai#*";
              effect = "allow";
            }
          ];
        # An unset default can select a built-in provider such as OpenCode Go.
        model = "${
          if providerID == "none"
          then "openai"
          else providerID
        }/${config.my.codex.defaultModel}";
        plugins = lib.mkIf opencodeLiteLLMEnabled [
          {
            package = opencodeLiteLLMDir;
            options = {
              inherit (config.my.aiProxy) baseUrl apiKeyEnv keyFile headers defaults routeOverrides;
            };
          }
        ];
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
