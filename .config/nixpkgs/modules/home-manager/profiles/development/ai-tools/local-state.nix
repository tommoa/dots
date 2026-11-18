{
  config,
  lib,
  pkgs,
  ...
}: let
  root = config.my.aiTools.localStateRoot;
  enabled = root != null;
  home = config.home.homeDirectory;
  paths = config.my.aiTools.localStatePaths;
in {
  options.my.aiTools = {
    localStateRoot = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Opt in to container-local AI runtime state on remote Linux servers with
        an NFS home. Set to a host-local volume such as /user; null leaves
        desktop and ordinary server storage unchanged. Enable explicitly in
        the NFS server profile, not by detecting SSH sessions at runtime.
      '';
    };
    localStatePaths = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      internal = true;
      description = "App-specific shared-home symlinks contributed by enabled AI tools.";
    };
  };

  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = pkgs.stdenv.isLinux && lib.hasPrefix "/" root && !lib.hasPrefix "${home}/" root && root != home;
        message = "my.aiTools.localStateRoot must be an absolute Linux path outside the shared home directory.";
      }
    ];

    home.file = lib.mapAttrs' (source: target:
      lib.nameValuePair (lib.removePrefix "${home}/" source) {
        source = config.lib.file.mkOutOfStoreSymlink target;
      })
    paths;

    home.activation.aiToolsLocalState = lib.hm.dag.entryBetween ["linkGeneration"] ["writeBoundary"] (lib.optionalString (paths != {}) ''
      run ${pkgs.coreutils}/bin/mkdir -p -m 700 -- ${lib.escapeShellArgs (lib.unique (builtins.attrValues paths))}
    '');
  };
}
