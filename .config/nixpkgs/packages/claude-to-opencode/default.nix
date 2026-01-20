# claude-to-opencode: Transform Claude Code plugins to OpenCode format
#
# This package provides:
# - A CLI tool for transforming plugins
# - A library function for use in Nix derivations
#
# Usage (CLI):
#   nix run .#claude-to-opencode -- /path/to/plugins
#
# Usage (Nix):
#   let
#     plugin = pkgs.claude-to-opencode.lib.transformPlugin {
#       src = ./my-plugins;
#       plugin = "my-plugin";
#     };
#   in {
#     # plugin.derivation - the transformed plugin derivation
#     # plugin.commands   - { "my-plugin.cmd" = "file content..."; }
#     # plugin.skills     - { "my-plugin-skill" = /nix/store/.../skill/; }
#     # plugin.agents     - { "my-plugin.agent" = "file content..."; }
#
# Note: commands and agents return file content (via IFD) for compatibility
# with home-manager's programs.opencode module. Skills return paths since
# they are directories that need recursive symlinking.
#   }
{
  lib,
  python3,
  runCommand,
  writeShellScriptBin,
  symlinkJoin,
}: let
  pythonWithDeps = python3.withPackages (ps: [ps.pyyaml]);
  transformScript = ./transform-plugins.py;

  # CLI package
  package = symlinkJoin {
    name = "claude-to-opencode";
    paths = [
      (writeShellScriptBin "claude-to-opencode" ''
        exec ${pythonWithDeps}/bin/python3 ${transformScript} "$@"
      '')
    ];
    meta = {
      description = "Transform Claude Code plugins to OpenCode format";
      mainProgram = "claude-to-opencode";
    };
  };

  # Library: transform a single plugin and return { derivation, commands, skills, agents }
  transformPlugin = {
    src,
    plugin,
    pluginsSubdir ? "",
  }: let
    pluginSrcDir =
      if pluginsSubdir == ""
      then "${src}/${plugin}"
      else "${src}/${pluginsSubdir}/${plugin}";

    transformed =
      runCommand "opencode-plugin-${plugin}" {
        inherit pluginSrcDir;
        nativeBuildInputs = [pythonWithDeps];
      } ''
        mkdir -p $out/${plugin}
        cp -r $pluginSrcDir/* $out/${plugin}/
        chmod -R u+w $out
        ${pythonWithDeps}/bin/python3 ${transformScript} $out
      '';

    # Discovery helpers
    safeReadDir = path:
      if builtins.pathExists path
      then builtins.readDir path
      else {};

    isMdFile = name: type: type == "regular" && lib.hasSuffix ".md" name;
    isDirectory = name: type: type == "directory";

    # Discover commands: plugin/commands/*.md -> { "plugin.cmd" = "content"; }
    # Uses builtins.readFile (IFD) to return file content for home-manager compatibility
    cmdDir = transformed + "/${plugin}/commands";
    cmdFiles = lib.filterAttrs isMdFile (safeReadDir cmdDir);
    commands =
      lib.mapAttrs' (
        name: _:
          lib.nameValuePair
          "${plugin}.${lib.removeSuffix ".md" name}"
          (builtins.readFile (cmdDir + "/${name}"))
      )
      cmdFiles;

    # Discover skills: plugin/skills/*/ -> { "plugin-skill" = path; }
    # Note: skill directories are renamed by transform script to include plugin prefix
    skillsDir = transformed + "/${plugin}/skills";
    skillDirs = lib.filterAttrs isDirectory (safeReadDir skillsDir);
    skills =
      lib.mapAttrs' (
        name: _:
          lib.nameValuePair name (skillsDir + "/${name}")
      )
      skillDirs;

    # Discover agents: plugin/agents/*.md -> { "plugin.agent" = "content"; }
    # Uses builtins.readFile (IFD) to return file content for home-manager compatibility
    agentsDir = transformed + "/${plugin}/agents";
    agentFiles = lib.filterAttrs isMdFile (safeReadDir agentsDir);
    agents =
      lib.mapAttrs' (
        name: _:
          lib.nameValuePair
          "${plugin}.${lib.removeSuffix ".md" name}"
          (builtins.readFile (agentsDir + "/${name}"))
      )
      agentFiles;
  in {
    derivation = transformed;
    inherit commands skills agents;
  };
in {
  inherit package;
  lib = {
    inherit transformPlugin;
  };
}
