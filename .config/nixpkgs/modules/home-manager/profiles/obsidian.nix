{
  config,
  lib,
  pkgs,
  ...
}: let
  vaultPath =
    if pkgs.stdenv.isDarwin
    then "${config.home.homeDirectory}/Documents/Personal"
    else "${config.home.homeDirectory}/docs/Personal";
  stateDir = "${config.home.homeDirectory}/.local/state/obsidian-headless-sync";
  ob = "${pkgs.obsidian-headless}/bin/ob";
  syncFileTypes = [
    "image"
    "audio"
    "video"
    "pdf"
    "unsupported"
  ];
  syncExcludedFolders = [
    "Extras/site/target"
    "Extras/site/result"
    "Outputs/site/result"
    "Outputs/site/target"
  ];
  syncConfigs = [
    "core-plugin"
    "core-plugin-data"
  ];

  vaultSync = pkgs.writeShellScriptBin "vault-sync" ''
    exec ${ob} sync --path "${vaultPath}" "$@"
  '';

  vaultSyncStatus = pkgs.writeShellScriptBin "vault-sync-status" ''
    exec ${ob} sync-status --path "${vaultPath}" "$@"
  '';

  vaultSyncContinuous = pkgs.writeShellScript "vault-sync-continuous" ''
    set -eu

    mkdir -p "${stateDir}"

    if [ ! -d "${vaultPath}" ]; then
      echo "Vault path does not exist: ${vaultPath}" >&2
      exit 1
    fi

    if ! ${ob} sync-status --path "${vaultPath}" >/dev/null 2>&1; then
      echo "Obsidian Headless Sync is not configured for ${vaultPath}." >&2
      echo "Run: ob login" >&2
      echo "Then: ob sync-setup --vault Personal --path ${vaultPath}" >&2
      exit 1
    fi

    ${ob} sync-config \
      --path "${vaultPath}" \
      --mode bidirectional \
      --conflict-strategy merge \
      --file-types "${lib.concatStringsSep "," syncFileTypes}" \
      --configs "${lib.concatStringsSep "," syncConfigs}" \
      --excluded-folders "${lib.concatStringsSep "," syncExcludedFolders}" \
      --config-dir ".obsidian" \
      >/dev/null

    exec ${ob} sync --path "${vaultPath}" --continuous
  '';
in {
  home.packages =
    [
      pkgs.imagemagick
      pkgs.obsidian-headless
      vaultSync
      vaultSyncStatus
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      pkgs.pngpaste
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      pkgs.wl-clipboard
    ];

  home.file.".local/state/obsidian-headless-sync/.keep".text = "";

  launchd.agents.obsidian-headless-sync = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = ["${vaultSyncContinuous}"];
      RunAtLoad = true;
      KeepAlive = {
        Crashed = true;
      };
      StartInterval = 300;
      StandardOutPath = "${stateDir}/stdout.log";
      StandardErrorPath = "${stateDir}/stderr.log";
    };
  };

  systemd.user.services.obsidian-headless-sync = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "Obsidian Headless Sync";
      After = ["network-online.target"];
    };

    Service = {
      ExecStart = "${vaultSyncContinuous}";
      Restart = "on-failure";
      RestartSec = "5m";
      StandardOutput = "append:${stateDir}/stdout.log";
      StandardError = "append:${stateDir}/stderr.log";
    };

    Install.WantedBy = ["default.target"];
  };
}
