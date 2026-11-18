{
  config,
  lib,
  pkgs,
  ...
}: let
  palette = import ../../../../../themes/one-dark.nix;
  hex = color: "#${color}";
  defaultModel = config.my.codex.defaultModel;
  reasoningEffort = config.programs.codex.settings.model_reasoning_effort;
  localStateEnabled = config.my.aiTools.localStateRoot != null;
  localHome = "${config.my.aiTools.localStateRoot}/.t3";
  settingsScript =
    pkgs.runCommand "t3code-settings.py" {
      nativeBuildInputs = [pkgs.python3];
    } ''
      cp ${./t3code-settings.py} "$out"
      T3CODE_SETTINGS="$out" python3 ${../../../../../tests/test_t3code_settings.py} -v
    '';
  localBootstrap = pkgs.writeShellApplication {
    name = "t3code-local-bootstrap";
    runtimeInputs = [pkgs.python3];
    # The shared pointer avoids a closure cycle: managed settings name the
    # wrapped provider executables, which depend on this bootstrap.
    text = ''
      exec python3 ${settingsScript} --bootstrap \
        ${lib.escapeShellArg "${localHome}/userdata"} \
        ${lib.escapeShellArg "${config.xdg.configHome}/t3code/managed-settings.json"}
    '';
  };
  localPackage = pkgs.symlinkJoin {
    name = "t3code-with-local-state";
    inherit (pkgs.t3code) meta version;
    paths = [pkgs.t3code];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/t3 \
        --set T3CODE_HOME ${lib.escapeShellArg localHome} \
        --run ${lib.escapeShellArg "${localBootstrap}/bin/t3code-local-bootstrap"}
    '';
  };
  defaultModelSelection = {
    instanceId = "codex";
    model = defaultModel;
  };
  # Home Manager replaces arrays. Merge these by identity before its settings
  # activation so unrelated model options and custom models are retained.
  modelSettingsValue =
    {
      desktopSettings = lib.optionalAttrs (config.my.t3code.desktopLocalEnvironmentEnabled != null) {
        localEnvironmentEnabled = config.my.t3code.desktopLocalEnvironmentEnabled;
      };
      defaultModelSelection =
        defaultModelSelection
        // {
          options = [
            {
              id = "reasoningEffort";
              value = reasoningEffort;
            }
          ];
        };
    }
    # Corporate proxy IDs are absent from Codex's built-in model catalog.
    // lib.optionalAttrs (lib.hasPrefix "ai-proxy/" defaultModel) {
      customModels = [
        {
          slug = defaultModel;
          capabilities.optionDescriptors = [
            {
              id = "reasoningEffort";
              label = "Reasoning";
              type = "select";
              options = map (effort: {
                id = effort;
                label = effort;
                isDefault = effort == reasoningEffort;
              }) (lib.unique ["low" "medium" "high" "xhigh" reasoningEffort]);
            }
          ];
        }
      ];
    };
  modelSettings = pkgs.writeText "t3code-model-settings.json" (builtins.toJSON modelSettingsValue);
  themeDefinition = {
    name = "One Dark";
    appearance = "dark";
    canvas = hex palette.background;
    accent = hex palette.blue;
    colors = {
      text = hex palette.foreground;
      codeBackground = hex palette.background;
      codeForeground = hex palette.foreground;
      sidebar = "#21252b";
      sidebarForeground = hex palette.foreground;
      sidebarMutedForeground = "#7f848e";
      sidebarControlSurface = hex palette.background;
      sidebarRowHover = hex palette.background;
      sidebarRowActive = "#2c313c";
      sidebarRowSelected = "#3e4451";
      sidebarBorder = "#181a1f";
      terminalBackground = hex palette.background;
      terminalForeground = hex palette.foreground;
      terminalCursor = hex palette.blue;
      terminalSelection = "#3e4451";
      accentForeground = hex palette.background;
      error = hex palette.red;
      errorForeground = hex palette.red;
      warning = hex palette.yellow;
      warningForeground = hex palette.yellow;
    };
  };
  theme = pkgs.writeText "t3code-one-dark.json" (builtins.toJSON themeDefinition);
  managedSettings = pkgs.writeText "t3code-managed-settings.json" (builtins.toJSON {
    inherit (config.programs.t3code) userSettings clientSettings;
    modelSettings = modelSettingsValue;
    theme = themeDefinition;
  });
in {
  options.my.t3code.desktopLocalEnvironmentEnabled = lib.mkOption {
    type = lib.types.nullOr lib.types.bool;
    default = null;
    description = ''
      Whether the T3 desktop app starts its own local server. Null leaves the
      desktop preference unmanaged. Set false to use an independently running
      server, which must be paired with the desktop once outside Nix.
    '';
  };

  config = {
    my.aiTools.localStatePaths = lib.mkIf (localStateEnabled && config.programs.t3code.enable) {
      "${config.home.homeDirectory}/.t3" = localHome;
    };
    # Also opt out on hosts managed only by Home Manager.
    home.sessionVariables.T3CODE_TELEMETRY_ENABLED = "false";
    systemd.user.sessionVariables.T3CODE_TELEMETRY_ENABLED = lib.mkIf pkgs.stdenv.isLinux "false";
    home.sessionVariables.T3CODE_HOME = lib.mkIf (localStateEnabled && config.programs.t3code.enable) localHome;
    home.packages = lib.optional (localStateEnabled && config.programs.t3code.enable) localBootstrap;
    programs.t3code = {
      enable = true;
      package =
        if localStateEnabled
        then localPackage
        else pkgs.t3code;
      mutableUserSettings = true;
      mutableClientSettings = true;
      userSettings = {
        inherit defaultModelSelection;
        defaultTheme = "one-dark";
        # Reapply palette changes once per client, without resetting on every rebuild.
        defaultThemeSetAt = builtins.hashString "sha256" (builtins.toJSON themeDefinition);
        providerInstances = {
          codex = {
            driver = "codex";
            enabled = config.programs.codex.enable;
            config.binaryPath = lib.getExe config.programs.codex.package;
          };
          opencode = {
            driver = "opencode";
            enabled = config.programs.opencode.enable;
            config.binaryPath = lib.getExe config.programs.opencode.package;
          };
        };
      };
      clientSettings = {
        fontFamilySans = "monospace";
        fontFamilyCode = "monospace";
        fontFamilyComposer = "monospace";
        fontFamilyTerminal = "monospace";
        fontSizeInterface = 16;
        fontSizePrompt = 14;
        fontSizeCode = 13;
        fontSizeTerminal = 12;
        fontSmoothing = true;
        notificationMode = "off";
        inAppNotificationsEnabled = false;
        panelAnimationDurationMs = 0;
      };
    };

    # Merge desktop preferences, normalize legacy client settings, and merge model
    # arrays before Home Manager merges ordinary preferences. Close the desktop
    # first to avoid its cached settings overwriting activation's changes.
    home.activation.t3codeSettingsCompatibility = lib.mkIf (!localStateEnabled) (lib.hm.dag.entryBetween ["t3codeSettingsActivation" "t3codeClientSettingsActivation"] ["linkGeneration"] ''
      run ${lib.getExe pkgs.python3} ${settingsScript} "$HOME/.t3/userdata" ${modelSettings}
    '');

    # Home Manager's upstream module always merges into ~/.t3 on activation.
    # For shared homes, publish an immutable baseline instead and let each
    # container apply it once, preserving runtime edits between generations.
    xdg.configFile."t3code/managed-settings.json" = lib.mkIf localStateEnabled {
      source = managedSettings;
    };
    home.activation.t3codeLocalSettings = lib.mkIf (localStateEnabled && config.programs.t3code.enable) (lib.hm.dag.entryAfter ["linkGeneration"] ''
      run ${localBootstrap}/bin/t3code-local-bootstrap
    '');
    home.activation.t3codeSettingsActivation = lib.mkIf localStateEnabled (lib.mkForce (lib.hm.dag.entryAfter [] ""));
    home.activation.t3codeClientSettingsActivation = lib.mkIf localStateEnabled (lib.mkForce (lib.hm.dag.entryAfter [] ""));

    # T3 rejects symlinked themes. Publish a regular file atomically instead.
    home.activation.t3codeTheme = lib.mkIf (!localStateEnabled) (lib.hm.dag.entryAfter ["writeBoundary"] ''
      theme_dir="$HOME/.t3/userdata/themes"
      run mkdir -p "$theme_dir"
      run install -m 644 ${theme} "$theme_dir/.one-dark.json.tmp"
      run mv -f "$theme_dir/.one-dark.json.tmp" "$theme_dir/one-dark.json"
    '');
  };
}
