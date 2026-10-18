# Onboarding a NixOS system with impermanence

The shared `modules/nixos/profiles/impermanence.nix` provides the storage layout,
root reset, persistent system state, agenix identity path and root cleanup.
This procedure covers a fresh installation on an already partitioned disk with
Btrfs for the system and a separate EFI filesystem. Run the filesystem and
installation commands as root from a NixOS installer.

## Configure the host

Create `hosts/<host>.nix` and `modules/nixos/hardware/<host>.nix`, using the
current host definitions as structural examples. The hardware module supplies
the Btrfs root device as `/dev/disk/by-uuid/<UUID>`, `fsType = "btrfs"`, the EFI
mount, swap/resume configuration and hardware settings. The shared profile
supplies the root mount options and the persistent subvolume mounts below;
remove duplicate declarations for those mounts from generated hardware config.

Import the hardware module, the NixOS base profile and the impermanence profile
in the host definition. Enable a systemd initrd and start with cleanup disabled:

```nix
boot.initrd.systemd.enable = true;
my.impermanence = {
  enable = true;
  resetRoot = true;
  cleanup.enable = false;
};
```

Define the hostname, user and declarative login credentials. Register the host
in `flake.nix` through `mkNixosConfig`, selecting a suitable Home Manager
configuration. That helper supplies `inputs`, `username`, agenix and Home
Manager. Its username and home directory must match the host's user definition.
Add new configuration and encrypted-secret files to Git so the flake includes
them.

## Prepare storage

The following subvolumes must share the Btrfs root filesystem:

| Mount | Subvolume | Behavior |
| --- | --- | --- |
| `/` | `@root` | Recreated from the blank template at normal boot |
| `/home` | `home` | Persistent user data |
| `/nix` | `nix` | Persistent store; mounted in the initrd |
| `/persist` | `@persist` | Persistent system state; mounted in the initrd |
| `/home/<user>/.local/share/Steam/steamapps` | `steamapps` | Persistent games |

`@root-blank` is an empty, read-only subvolume. Create `@root` as its writable
snapshot so even the first installed root has the ancestry required by cleanup.
`@old-roots` is an ordinary directory, not a subvolume; root reset places
retained roots there.

Replace the device and host placeholders. Use these creation commands only on
a fresh filesystem with none of the named subvolumes or directories present:

```sh
set -eu
host=newhost
username=tommoa
btrfs_device=/dev/disk/by-uuid/BTRFS_UUID
boot_device=/dev/disk/by-uuid/EFI_UUID
top=/run/impermanence-setup

mkdir -p "$top"
mount -t btrfs -o subvolid=5 "$btrfs_device" "$top"
btrfs subvolume create "$top/@root-blank"
btrfs property set -t subvol "$top/@root-blank" ro true
btrfs subvolume snapshot "$top/@root-blank" "$top/@root"
for name in home nix @persist steamapps; do
  btrfs subvolume create "$top/$name"
done
mkdir "$top/@old-roots"
umount "$top"
rmdir "$top"

mkdir -p /mnt
mount -t btrfs -o subvol=@root "$btrfs_device" /mnt
mkdir -p /mnt/home /mnt/nix /mnt/persist /mnt/boot
mount -t btrfs -o subvol=home "$btrfs_device" /mnt/home
mount -t btrfs -o subvol=nix "$btrfs_device" /mnt/nix
mount -t btrfs -o subvol=@persist "$btrfs_device" /mnt/persist
mount "$boot_device" /mnt/boot
mkdir -p "/mnt/home/$username/.local/share/Steam/steamapps"
mount -t btrfs -o subvol=steamapps "$btrfs_device" \
  "/mnt/home/$username/.local/share/Steam/steamapps"
```

Keep the blank template empty. Populate the prepared dotfiles checkout with
`/mnt/home/<user>` as its Git worktree root, keeping `.git` in that persistent
home. Preserve the Steam mount and existing provisioned files when transferring
the checkout. The flake is in `.config/nixpkgs` inside the worktree; use paths
relative to that flake directory for the configuration and secret files above.
This also gives `update-nix` its expected `~/.config/nixpkgs` path after boot.
Ensure the user's home, Steam subvolume and parent directories belong to the
configured UID/GID.
Any additional application state that must survive reboot belongs in a
persistent filesystem or in `environment.persistence."/persist"` declarations.
The shared profile already declares the common system-state paths, including
logs, network/Bluetooth state, machine identity, maintenance history and
`/var/lib/logrotate/status`.

## Provision secret identities

System-secret decryption uses a dedicated, unencrypted private identity at
`/persist/etc/agenix/identity`. Generate it directly in the mounted persistent
filesystem, with root ownership and private permissions:

```sh
install -d -m 0700 /mnt/persist/etc/agenix
ssh-keygen -t ed25519 -N '' -C "$host-agenix" \
  -f /mnt/persist/etc/agenix/identity
chmod 0600 /mnt/persist/etc/agenix/identity
```

On a machine with an authorized editing identity, add the new public key to
`secrets/secrets.nix` as a recipient for the system secrets this host uses, then
run `agenix -r` from the `secrets` directory. Include the updated encrypted files
in the installation checkout. The private host identity stays on the target
system; it is not a repository file.

Home Manager decrypts user secrets with `/home/<user>/.ssh/id_ed25519`.
Provision that authorized user identity separately in the persistent home,
with user ownership, mode `0700` on `.ssh` and `0600` on the private key. The
host identity does not replace the user identity.

## Install and verify

Build and install the configured host from its persistent checkout:

```sh
checkout_root="/mnt/home/$username"
flake_dir="$checkout_root/.config/nixpkgs"
test -f "$flake_dir/flake.nix"
nix --extra-experimental-features 'nix-command flakes' build \
  --no-link --no-write-lock-file \
  "$flake_dir#nixosConfigurations.$host.config.system.build.toplevel"
nixos-install --root /mnt --flake "$flake_dir#$host" --no-root-password
```

Boot normally. Check that each mount matches the table, that system and user
secrets decrypt, and that login and the configured applications work:

```sh
systemctl --failed
sudo journalctl -b -u recreate-root.service --no-pager
sudo btrfs device stats --check /
findmnt --mountpoint /
findmnt --mountpoint /home
findmnt --mountpoint /nix
findmnt --mountpoint /persist
```

Also inspect the Steam mount and persistent state directories. Verify after
another normal reboot that root contents reset, persistent state survives and
root recreation runs once per boot. If hibernation is configured, test resume;
root reset runs after the initrd's resume attempt.

Inspect retained roots with the installed cleanup command:

```sh
sudo impermanence-clean-old-roots --report /persist/old-root-inspection.json
```

Inspection checks mount identities, the read-only template, snapshot ancestry,
mounted/protected subvolumes, failed units and Btrfs error counters. Resolve any
rejection before proceeding. Once the checks and functional tests pass, set
`my.impermanence.cleanup.enable = true` in the host definition and switch using
the checkout path on the installed system:

```sh
host=newhost
username=tommoa
checkout_root="/home/$username"
flake_dir="$checkout_root/.config/nixpkgs"
sudo nixos-rebuild switch --no-reexec --flake "$flake_dir#$host"
```

Cleanup runs five minutes after timer activation and daily afterward. After
its first run, verify that the timer is active and the service completed:

```sh
systemctl status impermanence-clean-old-roots.timer
sudo journalctl -b -u impermanence-clean-old-roots.service --no-pager
```

The cleanup tool is also available manually; deletion requires `--apply`.
Keep a known-working NixOS generation and separate backups of persistent data.
Root snapshots are temporary boot state, not application-data backups.

## Recovery

Disable cleanup to retain old roots, and disable root reset when inspecting an
existing root across boots. Before mounting a retained root, stop the timer and
hold the cleanup lock for the entire recovery session:

```sh
sudo systemctl stop impermanence-clean-old-roots.timer
sudo flock --shared /run/impermanence-old-root-cleanup.lock bash
# Mount, inspect and unmount recovery roots inside this shell, then exit.
```

The shared lock waits for any running cleanup to finish and prevents new cleanup
invocations from proceeding. Mount checks are observations; holding the lock
prevents a cooperating recovery session from mounting a root between the final
check and deletion. Keep the shell open until every recovery mount is removed.
Restart the timer only after leaving the shell, if cleanup should resume:

```sh
sudo systemctl start impermanence-clean-old-roots.timer
```

Run cleanup on the host with its full `/proc` visible. It refuses an empty task
mount inventory when that task still has a filesystem root, because a detached
mount can retain a live chroot without appearing in any namespace inventory.
Resolve the chroot or sandbox before retrying; do not bypass the refusal.
A previous NixOS generation restores configuration, not deleted roots or
persistent application data. Keep the persistent subvolumes and blank template
intact and recover application data from separate backups.
