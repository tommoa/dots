{
  config,
  pkgs,
  ...
}: let
  btrfsDevice = "/dev/disk/by-uuid/2ae3c985-a150-47fc-8953-817bbf6cf0e0";
  peterHostKey = "/persist/etc/agenix/identity";
in {
  # Keep the original Btrfs top level untouched as the recovery root.
  fileSystems."/".options = ["subvol=@root"];
  fileSystems."/nix".neededForBoot = true;

  fileSystems."/persist" = {
    device = btrfsDevice;
    fsType = "btrfs";
    options = ["subvol=@persist"];
    neededForBoot = true;
  };

  # Provision this key on @persist before boot: host-key generation happens
  # too late for initrd agenix. Declaring it here does not enable sshd.
  # System agenix can then decrypt without reading the user's key from /home.
  services.openssh.hostKeys = [
    {
      type = "ed25519";
      path = peterHostKey;
    }
  ];
  age.identityPaths = [peterHostKey];

  # Recreate / only after systemd has attempted hibernation resume and before
  # sysroot.mount. The old top-level root remains available for recovery.
  boot.resumeDevice = "/dev/disk/by-uuid/ed45594d-13b2-49c6-a9ad-e7346069794c";
  boot.initrd.systemd.services.recreate-root = {
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
      mount -t btrfs -o subvolid=5 ${btrfsDevice} "$top"
      trap 'umount "$top"' EXIT

      blank="$top/@root-blank"
      root="$top/@root"
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

      # Prepare the new root before moving the previous one. Old roots are
      # kept during the trial so a failed boot can be diagnosed or recovered.
      boot_id="$(cat /proc/sys/kernel/random/boot_id)"
      next="$top/@root-next-$boot_id"
      old="$top/@old-roots/$boot_id"
      btrfs subvolume snapshot "$blank" "$next"
      if btrfs subvolume show "$root" >/dev/null 2>&1; then
        mkdir -p "$top/@old-roots"
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

  # System agenix decrypts the login hash before NixOS creates users. Only
  # the encrypted file enters the store; the decrypted hash lives in /run.
  age.secrets.peter-login-hash.file = ../../../secrets/misc/peter-login-hash.age;
  users.mutableUsers = false;
  users.users.tommoa.hashedPasswordFile = config.age.secrets.peter-login-hash.path;

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
      "/var/lib/cups"
      "/var/lib/NetworkManager"
      "/var/lib/nixos"
      "/var/log"
    ];

    files = [
      "/etc/machine-id"
      "/var/lib/systemd/random-seed"
    ];
  };
}
