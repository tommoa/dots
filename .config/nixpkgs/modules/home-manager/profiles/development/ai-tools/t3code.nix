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
  settings = pkgs.writeText "t3code-managed-settings.json" (builtins.toJSON {
    "client-settings.json" = {
      fontFamilySans = "DejaVu Sans Mono";
      fontFamilyCode = "";
      fontFamilyComposer = "";
      fontFamilyTerminal = "";
      fontSizeInterface = 16;
      fontSizePrompt = 14;
      fontSizeCode = 13;
      fontSizeTerminal = 12;
      fontSmoothing = true;
      notificationMode = "off";
      inAppNotificationsEnabled = false;
      panelAnimationDurationMs = 0;
    };
    "settings.json" =
      {
        defaultTheme = "one-dark";
        # Reapply palette changes once per client, without resetting on every rebuild.
        defaultThemeSetAt = builtins.hashString "sha256" (builtins.toJSON themeDefinition);
        defaultModelSelection = {
          instanceId = "codex";
          model = defaultModel;
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
        providerInstances.codex = {
          driver = "codex";
          config.customModels = [
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
      };
  });
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
in {
  home.packages = with pkgs; [t3code];

  # T3 writes these files itself. Merge only managed preferences into regular,
  # writable files, leaving provider configuration and UI state intact.
  # Close T3 before activation so its cached settings cannot overwrite the merge.
  home.activation.t3codeSettings = lib.hm.dag.entryAfter ["t3codeTheme"] ''
    run ${lib.getExe pkgs.python3} ${./t3code-settings.py} "$HOME/.t3/userdata" ${settings}
  '';

  # T3 rejects symlinked themes. Publish a regular file atomically instead.
  home.activation.t3codeTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    theme_dir="$HOME/.t3/userdata/themes"
    run mkdir -p "$theme_dir"
    run install -m 644 ${theme} "$theme_dir/.one-dark.json.tmp"
    run mv -f "$theme_dir/.one-dark.json.tmp" "$theme_dir/one-dark.json"
  '';
}
