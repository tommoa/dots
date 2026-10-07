{
  config,
  lib,
  pkgs,
  inputs,
  username,
  ...
}: let
  cfg = config.my.impermanence;
  btrfsDevice = config.fileSystems."/".device;
  rootSubvolume = "@root";
  blankSubvolume = "@root-blank";
  oldRootsDirectory = "@old-roots";
  mounts = {
    "/" = rootSubvolume;
    "/home" = "home";
    "/nix" = "nix";
    "/persist" = "@persist";
    "/home/${username}/.local/share/Steam/steamapps" = "steamapps";
  };
  cleanupLayout = pkgs.writeText "impermanence-layout.json" (builtins.toJSON {
    inherit mounts blankSubvolume oldRootsDirectory;
  });
  cleanup = pkgs.writeShellApplication {
    name = "impermanence-clean-old-roots";
    runtimeInputs = [pkgs.btrfs-progs pkgs.util-linux pkgs.systemd];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../scripts/impermanence-clean-old-roots.py} \
        --uuid ${lib.escapeShellArg (lib.removePrefix "/dev/disk/by-uuid/" btrfsDevice)} \
        --layout ${cleanupLayout} "$@"
    '';
  };
in {
  imports = [inputs.impermanence.nixosModules.impermanence];

  options.my.impermanence = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the persistent mounts and Btrfs root layout.";
    };
    resetRoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Recreate the root from @root-blank in the initrd. Disable during layout trials or recovery.";
    };
    cleanup.enable = lib.mkEnableOption "validated old-root cleanup after a healthy boot (only while root reset is enabled)";
  };

  config = lib.mkIf cfg.enable {
    # The host supplies the root device; all persistent subvolumes share it.
    fileSystems =
      (lib.mapAttrs (mount: subvolume: {
        device = btrfsDevice;
        fsType = "btrfs";
        options = ["subvol=${subvolume}"];
        # System-secret decryption uses /persist; Home Manager waits for /home.
        neededForBoot = builtins.elem mount ["/nix" "/persist"];
      }) (builtins.removeAttrs mounts ["/"]))
      // {
        "/".options = ["subvol=${rootSubvolume}"];
      };

    assertions = [
      {
        assertion = config.fileSystems."/".fsType == "btrfs";
        message = "The impermanence profile requires a Btrfs root filesystem.";
      }
      {
        assertion = config.boot.initrd.systemd.enable;
        message = "The impermanence profile requires a systemd initrd.";
      }
      {
        assertion =
          config.fileSystems."/nix".fsType
          == "btrfs"
          && config.fileSystems."/nix".device == btrfsDevice
          && builtins.elem "subvol=nix" config.fileSystems."/nix".options;
        message = "The impermanence profile requires a separate persistent nix subvolume on the root device.";
      }
      {
        assertion = builtins.match "/dev/disk/by-uuid/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}" btrfsDevice != null;
        message = "The impermanence cleanup tool requires a Btrfs root device addressed by filesystem UUID.";
      }
    ];

    # Recreate / only after systemd has attempted hibernation resume and before
    # sysroot.mount. Former roots remain until validated post-boot cleanup.
    boot.initrd.systemd.services.recreate-root = lib.mkIf cfg.resetRoot {
      description = "Restore a blank Btrfs root";
      requiredBy = ["sysroot.mount"];
      after = ["systemd-hibernate-resume.service" "initrd-root-device.target"];
      before = ["sysroot.mount"];
      unitConfig.DefaultDependencies = false;
      path = [pkgs.btrfs-progs pkgs.coreutils pkgs.util-linux];
      serviceConfig = {
        Type = "oneshot";
        # initrd-parse-etc reloads systemd and can request sysroot.mount again.
        # Keep this prerequisite active so the root is recreated only once.
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        # Never rename the root after systemd has mounted it at /sysroot.
        if mountpoint -q /sysroot; then
          echo 'Root already mounted; skipping recreation' >&2
          exit 0
        fi

        top=/run/btrfs-top
        mkdir -p "$top"
        mount -t btrfs -o subvolid=5 ${lib.escapeShellArg btrfsDevice} "$top"
        trap 'umount "$top"' EXIT

        blank="$top/${blankSubvolume}"
        root="$top/${rootSubvolume}"
        if [ -e "$root" ] && ! btrfs subvolume show "$root" >/dev/null 2>&1; then
          echo 'Root path exists but is not a Btrfs subvolume' >&2
          exit 1
        fi
        if ! btrfs subvolume show "$blank" >/dev/null 2>&1; then
          if btrfs subvolume show "$root" >/dev/null 2>&1; then
            echo 'Blank root snapshot missing; preserving the existing root' >&2
            exit 0
          fi
          echo 'Neither a blank root snapshot nor a bootable root exists' >&2
          exit 1
        fi

        # Prepare the new root before moving the previous one. Keep the old
        # root until a healthy boot so a failed boot can be inspected.
        boot_id="$(cat /proc/sys/kernel/random/boot_id)"
        next="$top/@root-next-$boot_id"
        old="$top/${oldRootsDirectory}/$boot_id"
        btrfs subvolume snapshot "$blank" "$next"
        if btrfs subvolume show "$root" >/dev/null 2>&1; then
          mkdir -p "$top/${oldRootsDirectory}"
          mv "$root" "$old"
        fi
        if ! mv "$next" "$root"; then
          if [ -e "$old" ]; then
            mv "$old" "$root"
          fi
          exit 1
        fi
      '';
    };

    # Inspection remains available even when automatic deletion is disabled.
    environment.systemPackages = [cleanup];
    systemd.services.impermanence-clean-old-roots = lib.mkIf (cfg.cleanup.enable && cfg.resetRoot) {
      description = "Remove former ephemeral roots after a healthy boot";
      after = ["local-fs.target" "multi-user.target"];
      unitConfig.RequiresMountsFor = builtins.attrNames mounts;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${cleanup}/bin/impermanence-clean-old-roots --apply";
        PrivateTmp = true;
        ProtectHome = "read-only";
        TimeoutStartSec = "30min";
      };
    };
    systemd.timers.impermanence-clean-old-roots = lib.mkIf (cfg.cleanup.enable && cfg.resetRoot) {
      description = "Clean former ephemeral roots after boot";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnActiveSec = "5min";
        OnUnitActiveSec = "1d";
      };
    };

    age.identityPaths = ["/persist/etc/agenix/identity"];

    # Logrotate atomically replaces its state; persist the enclosing directory.
    services.logrotate.extraArgs = ["--state" "/var/lib/logrotate/status"];
    systemd.services.logrotate.unitConfig.RequiresMountsFor = ["/var/lib/logrotate"];

    environment.persistence."/persist" = {
      hideMounts = true;

      directories = [
        {
          directory = "/etc/NetworkManager/system-connections";
          mode = "0700";
        }
        "/var/lib/AccountsService"
        {
          directory = "/var/lib/bluetooth";
          mode = "0700";
        }
        "/var/lib/btrfs"
        "/var/lib/cups"
        "/var/lib/logrotate"
        "/var/lib/NetworkManager"
        "/var/lib/nixos"
        "/var/lib/systemd/rfkill"
        "/var/lib/systemd/timers"
        {
          directory = "/var/lib/systemd/timesync";
          user = "systemd-timesync";
          group = "systemd-timesync";
        }
        "/var/log"
        # nixos-rebuild runs as root, so keep root's flake trust approvals
        # across the ephemeral root reset.
        {
          directory = "/root/.local/share/nix";
          mode = "0700";
        }
      ];

      files = [
        "/etc/machine-id"
        "/var/lib/systemd/random-seed"
      ];
    };
  };
}
