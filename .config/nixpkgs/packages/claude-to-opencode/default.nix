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
#     # plugin.derivation  - the transformed plugin derivation
#     # plugin.commands    - { "my-plugin.cmd" = "file content..."; }
#     # plugin.skills      - { "my-plugin-skill" = /nix/store/.../skill/; }
#     # plugin.agents      - { "my-plugin.agent" = "file content..."; }
#     # plugin.mcpServers  - { "server-name" = { type = "local"; command = [...]; }; }
#
# Note: commands and agents return file content (via IFD) for compatibility
# with home-manager's programs.opencode module. Skills return paths since
# they are directories that need recursive symlinking. MCP servers return
# attrsets ready for programs.opencode.settings.mcp.
#   }
{
  lib,
  python3,
  runCommand,
  writeShellScriptBin,
  symlinkJoin,
  buildNpmPackage,
  nodejs,
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

  # Build MCP server dependencies for a plugin using buildNpmPackage.
  # Returns a derivation containing node_modules/ and servers/.
  buildMcpServerDeps = {
    pluginSrcDir,
    plugin,
    npmDepsHash,
    npmRoot ? null,
  }:
    buildNpmPackage {
      pname = "mcp-server-${plugin}";
      version = "0.0.0";
      src = pluginSrcDir;
      inherit npmDepsHash;
      # When the npm project lives in a subdirectory (npmRoot), copy its
      # package.json and lock file to the source root so that fetchNpmDeps
      # (which doesn't support npmRoot) can find them.
      postPatch = lib.optionalString (npmRoot != null) ''
        cp ${npmRoot}/package.json .
        cp ${npmRoot}/package-lock.json .
      '';
      dontNpmBuild = true;
      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -r node_modules $out/
        cp -r servers $out/
        runHook postInstall
      '';
    };

  # Parse plugin.json and resolve MCP server entries into OpenCode format.
  # Returns { "server-name" = { type = "local"; command = [...]; }; }
  resolveMcpServers = {
    pluginSrcDir,
    plugin,
    npmDepsHash,
    npmRoot ? null,
  }: let
    pluginJsonPath = pluginSrcDir + "/.claude-plugin/plugin.json";
    hasPluginJson = builtins.pathExists pluginJsonPath;
    pluginJson =
      if hasPluginJson
      then builtins.fromJSON (builtins.readFile pluginJsonPath)
      else {};
    rawServers = pluginJson.mcpServers or {};
    hasServers = rawServers != {};

    builtDeps =
      if hasServers && npmDepsHash != null
      then
        buildMcpServerDeps {
          inherit pluginSrcDir plugin npmDepsHash npmRoot;
        }
      else null;

    # Resolve ${CLAUDE_PLUGIN_ROOT}/... paths to the built derivation
    resolveArg = arg:
      builtins.replaceStrings
      ["\${CLAUDE_PLUGIN_ROOT}/"]
      ["${builtDeps}/"]
      arg;

    # Map well-known commands to their Nix store paths for hermeticity
    resolveCommand = cmd:
      if cmd == "node"
      then "${nodejs}/bin/node"
      else cmd;

    resolveServer = name: server: {
      type = "local";
      command =
        [(resolveCommand server.command)]
        ++ map resolveArg (server.args or []);
      enabled = true;
    };
  in
    if hasServers && npmDepsHash != null
    then lib.mapAttrs resolveServer rawServers
    else if hasServers && npmDepsHash == null
    then
      lib.warn
      "Plugin '${plugin}' defines MCP servers but no npmDepsHash was provided; servers will be skipped"
      {}
    else {};

  # Library: transform a single plugin and return { derivation, commands, skills, agents, mcpServers }
  transformPlugin = {
    src,
    plugin,
    pluginsSubdir ? "",
    npmDepsHash ? null,
    npmRoot ? null,
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

    # Discover MCP servers from .claude-plugin/plugin.json
    # Builds Node.js dependencies and resolves paths for OpenCode config
    mcpServers = resolveMcpServers {
      inherit pluginSrcDir plugin npmDepsHash npmRoot;
    };
  in {
    derivation = transformed;
    inherit commands skills agents mcpServers;
  };
in {
  inherit package;
  lib = {
    inherit transformPlugin;
  };
}
