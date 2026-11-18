{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.cursor;
  localRoot = config.my.aiTools.localStateRoot;
  localStateEnabled = localRoot != null;
  localPaths = {
    "${config.home.homeDirectory}/.cursor" = "${localRoot}/.cursor";
    "${config.xdg.configHome}/cursor" = "${localRoot}/.config/cursor";
    "${config.xdg.cacheHome}/cursor-compile-cache" = "${localRoot}/.cache/cursor-compile-cache";
  };
  manifest = (pkgs.formats.json {}).generate "cursor-shared-plugin.json" {
    name = "shared-ai-tools";
    skills = "./skills/";
    rules = ["./rules/context.mdc"];
  };
  instructions = pkgs.writeText "cursor-context.mdc" ''
    ---
    alwaysApply: true
    ---

    ${builtins.readFile ../context.md}
  '';
  # Keep managed inputs in the store so every container can load them without
  # copying settings or credentials into its writable runtime directory.
  sharedPlugin = pkgs.runCommandLocal "cursor-shared-ai-tools" {} ''
    mkdir -p "$out/.cursor-plugin" "$out/skills" "$out/rules"
    cp ${manifest} "$out/.cursor-plugin/plugin.json"
    cp ${instructions} "$out/rules/context.mdc"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: source: ''
        mkdir -p "$out/skills/"${lib.escapeShellArg name}
        cp -R ${lib.escapeShellArg "${source}/."} "$out/skills/"${lib.escapeShellArg name}
      '')
      cfg.skills)}
  '';
  package = pkgs.symlinkJoin {
    name = "cursor-agent-configured";
    inherit (cfg.package) meta;
    version = lib.getVersion cfg.package;
    paths = [cfg.package];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/cursor-agent \
        --set CURSOR_CONFIG_DIR ${lib.escapeShellArg "${config.home.homeDirectory}/.cursor"} \
        --prefix PATH : ${lib.makeBinPath [pkgs.python3 pkgs.tmux]} \
        --add-flags ${lib.escapeShellArg (lib.escapeShellArgs (["--disable-auto-update"] ++ lib.concatMap (plugin: ["--plugin-dir" (toString plugin)]) ([sharedPlugin] ++ cfg.plugins)))} \
        ${lib.optionalString localStateEnabled "--run ${lib.escapeShellArg "${pkgs.coreutils}/bin/mkdir -p -m 700 ${lib.escapeShellArgs (builtins.attrValues localPaths)}"}"}
    '';
  };
in {
  options.my.cursor = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Cursor Agent with shared AI skills and plugins";
    };
    package = lib.mkPackageOption pkgs "cursor-agent" {};
    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      description = "Skill directories included in the managed Cursor plugin";
    };
    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [];
      description = "Native Cursor plugin directories loaded at launch";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [package];
    my.aiTools.localStatePaths = lib.mkIf localStateEnabled localPaths;
  };
}
