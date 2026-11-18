# Read the portable components declared by upstream Codex manifests. Skill
# directories stay intact so relative references keep working without IFD.
{
  lib,
  pkgs,
  plugins,
}: let
  mergeUnique = kind: sets:
    lib.zipAttrsWith (name: values:
      if builtins.length values == 1
      then builtins.head values
      else throw "Duplicate OpenCode ${kind} '${name}' in Codex plugins")
    sets;

  loadPlugin = plugin: let
    root = toString plugin;
    manifest = builtins.fromJSON (builtins.readFile "${root}/.codex-plugin/plugin.json");
    name = manifest.name;
    componentPath = relative:
      if !builtins.isString relative || !lib.hasPrefix "./" relative || lib.elem ".." (lib.splitString "/" relative)
      then throw "Codex plugin '${name}' has an unsupported component path"
      else "${root}/${lib.removeSuffix "/" (lib.removePrefix "./" relative)}";
    skillsDir = componentPath manifest.skills;
    skillDirs =
      if manifest ? skills
      then lib.filterAttrs (entry: type: type == "directory" && builtins.pathExists "${skillsDir}/${entry}/SKILL.md") (builtins.readDir skillsDir)
      else {};
    skills = lib.mapAttrs (entry: _: "${skillsDir}/${entry}") skillDirs;

    replaceRoot = value:
      builtins.replaceStrings ["\${PLUGIN_ROOT}" "\${CLAUDE_PLUGIN_ROOT}"] [root root] value;
    runtimePath = value:
      if value == "."
      then root
      else if lib.hasPrefix "./" value
      then "${root}/${lib.removePrefix "./" value}"
      else replaceRoot value;
    resolveCommand = command:
      if lib.elem command ["python" "python3"]
      then "${pkgs.python3}/bin/python3"
      else if command == "node"
      then "${pkgs.nodejs}/bin/node"
      else replaceRoot command;
    rawServers =
      if manifest ? mcpServers
      then (builtins.fromJSON (builtins.readFile (componentPath manifest.mcpServers))).mcpServers
      else {};
    resolveServer = serverName: server:
      if server ? url
      then builtins.removeAttrs server ["type"]
      else let
        command = resolveCommand server.command;
        args = map replaceRoot (server.args or []);
        cwd = runtimePath (server.cwd or ".");
        # Home Manager's OpenCode integration doesn't carry cwd through. Keep
        # it in the launcher rather than relying on OpenCode's process cwd.
        launcher = pkgs.writeShellScript "opencode-mcp-${name}-${serverName}" ''
          cd ${lib.escapeShellArg cwd} || exit 1
          exec ${lib.escapeShellArgs ([command] ++ args)} "$@"
        '';
      in
        builtins.removeAttrs server ["type" "cwd" "command" "args" "env"]
        // {
          command = toString launcher;
          args = [];
          env = lib.mapAttrs (_: replaceRoot) (server.env or {});
        };
  in {
    inherit skills;
    mcpServers = lib.mapAttrs resolveServer rawServers;
    hooks = lib.optional (manifest ? hooks) {
      inherit name root;
      file = componentPath manifest.hooks;
    };
  };
  loaded = map loadPlugin plugins;
in {
  skills = mergeUnique "skill" (map (plugin: plugin.skills) loaded);
  mcpServers = mergeUnique "MCP server" (map (plugin: plugin.mcpServers) loaded);
  hooks = lib.concatMap (plugin: plugin.hooks) loaded;
}
