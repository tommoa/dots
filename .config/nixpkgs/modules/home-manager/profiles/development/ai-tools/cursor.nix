{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.cursor;
  localRoot = config.my.aiTools.localStateRoot;
  localStateEnabled = localRoot != null;
  cursorHome = "${config.home.homeDirectory}/.cursor";
  localPaths = {
    "${cursorHome}" = "${localRoot}/.cursor";
    "${config.xdg.configHome}/cursor" = "${localRoot}/.config/cursor";
    "${config.xdg.cacheHome}/cursor-compile-cache" = "${localRoot}/.cache/cursor-compile-cache";
  };
  manifest = (pkgs.formats.json {}).generate "cursor-shared-plugin.json" {
    name = "shared-ai-tools";
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
    mkdir -p "$out/.cursor-plugin" "$out/rules"
    cp ${manifest} "$out/.cursor-plugin/plugin.json"
    cp ${instructions} "$out/rules/context.mdc"
  '';
  skillsSource = pkgs.runCommandLocal "cursor-skills" {} ''
    mkdir -p "$out"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: source: ''
        cp -RL ${lib.escapeShellArg "${source}"} "$out/"${lib.escapeShellArg name}
      '')
      cfg.skills)}
  '';
  # T3's Cursor SDK ignores symlinked skills, so publish regular copies. Only
  # names in the manifest (or a pending list from an interrupted run) are
  # replaced or removed; any other skill in the way is backed up first. Work
  # files live outside the skills tree so Cursor never loads a partial copy.
  skillsSync = pkgs.writeShellApplication {
    name = "cursor-skills-sync";
    runtimeInputs = [pkgs.coreutils pkgs.flock];
    text = ''
      shopt -s nullglob
      root=${lib.escapeShellArg "${cursorHome}/skills"}
      work=${lib.escapeShellArg "${cursorHome}/.skills-sync"}
      manifest="$root/.nix-managed"
      source=${skillsSource}
      names=("$source"/*)
      names=("''${names[@]##*/}")
      current() {
        [ -f "$manifest" ] && [ "$(head -n 1 "$manifest")" = "$source" ] || return 1
        local name
        for name in "''${names[@]}"; do [ -d "$root/$name" ] || return 1; done
      }
      if current; then exit 0; fi
      mkdir -p "$root" "$work"
      exec 9> "$work/lock"
      flock 9
      if current; then exit 0; fi
      trap 'rm -rf -- "$work/stage" "$work/old"' EXIT
      managed=()
      for list in "$manifest" "$work/pending"; do
        if [ -f "$list" ]; then mapfile -t -O "''${#managed[@]}" managed < <(tail -n +2 "$list"); fi
      done
      is_managed() {
        local entry
        for entry in "''${managed[@]}"; do [ "$entry" = "$1" ] && return 0; done
        return 1
      }
      for name in "''${managed[@]}"; do
        case "$name" in "" | .* | */*) continue ;; esac
        if [ ! -e "$source/$name" ]; then rm -rf -- "''${root:?}/$name"; fi
      done
      present() { [ -e "$1" ] || [ -L "$1" ]; }
      # Back up before recording pending names, or a retry would treat a
      # user's skill as ours and replace it.
      for name in "''${names[@]}"; do
        target="$root/$name"
        if present "$target" && ! is_managed "$name"; then
          mkdir -p "$work/backup"
          backup="$work/backup/$name.$(date +%s)"
          mv -T "$target" "$backup"
          echo "cursor-skills-sync: moved unmanaged $target to $backup" >&2
        fi
      done
      printf '%s\n' "$source" "''${names[@]}" > "$work/pending"
      for name in "''${names[@]}"; do
        target="$root/$name"
        rm -rf -- "$work/stage" "$work/old"
        cp -R "$source/$name" "$work/stage"
        chmod -R u+w "$work/stage"
        if present "$target"; then mv -T "$target" "$work/old"; fi
        mv -T "$work/stage" "$target"
      done
      mv -f "$work/pending" "$manifest"
    '';
  };
  package = pkgs.symlinkJoin {
    name = "cursor-agent-configured";
    inherit (cfg.package) meta;
    version = lib.getVersion cfg.package;
    paths = [cfg.package];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/cursor-agent \
        --set CURSOR_CONFIG_DIR ${lib.escapeShellArg cursorHome} \
        --prefix PATH : ${lib.makeBinPath [pkgs.python3 pkgs.tmux]} \
        --add-flags ${lib.escapeShellArg (lib.escapeShellArgs (["--disable-auto-update"] ++ lib.concatMap (plugin: ["--plugin-dir" (toString plugin)]) ([sharedPlugin] ++ cfg.plugins)))} \
        ${lib.optionalString localStateEnabled "--run ${lib.escapeShellArg "${pkgs.coreutils}/bin/mkdir -p -m 700 ${lib.escapeShellArgs (builtins.attrValues localPaths)}"}"} \
        --run ${lib.escapeShellArg (lib.getExe skillsSync)}
    '';
  };
in {
  options.my.cursor = {
    enable = lib.mkOption {
      type = lib.types.bool;
      # Cursor is licensed for work use only.
      default = config.my.modelSelection.profile == "work";
      defaultText = lib.literalExpression ''config.my.modelSelection.profile == "work"'';
      description = "Enable Cursor Agent with shared AI skills and plugins";
    };
    package = lib.mkPackageOption pkgs "cursor-agent" {};
    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      description = "Skill directories published to the user-level Cursor skills directory";
    };
    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [];
      description = "Native Cursor plugin directories loaded at launch";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.my.modelSelection.profile == "work";
        message = "Cursor is licensed for work use only; enable it only with the work profile.";
      }
    ];
    home.packages = [package];
    my.aiTools.localStatePaths = lib.mkIf localStateEnabled localPaths;
    home.activation.cursorSkills = lib.hm.dag.entryAfter ["linkGeneration"] ''
      run ${lib.getExe skillsSync}
    '';
  };
}
