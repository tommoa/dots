# Impermanence on James and Peter

The shared `modules/nixos/profiles/impermanence.nix` owns the Btrfs subvolume
layout, root reset, system-state persistence, agenix identity path, logrotate
state and old-root cleanup. Each hardware file supplies its root filesystem
UUID, EFI filesystem, swap and hardware settings.

| Mount | Subvolume | Behavior |
| --- | --- | --- |
| `/` | `@root` | Recreated from read-only `@root-blank` at normal boot |
| `/home` | `home` | Persistent; mounted during normal system startup |
| `/nix` | `nix` | Persistent; mounted in the initrd |
| `/persist` | `@persist` | Persistent; mounted in the initrd |
| `/home/<user>/.local/share/Steam/steamapps` | `steamapps` | Persistent; outside home snapshots |

James additionally mounts its external ext4 Steam SSD at
`/home/tommoa/steamapps`. Peter keeps its existing swap resume device. Root reset
runs after the hibernation-resume attempt, before mounting `/sysroot`, and at
most once per boot. Successful resume restores the running session.

Persistent system state includes NetworkManager connections/state, Bluetooth,
CUPS, AccountsService, NixOS state, logs, root's Nix trust settings, machine ID,
random seed, Btrfs scrub history, logrotate state, radio settings, timer history
and clock synchronization. Logrotate uses `/var/lib/logrotate/status`; its
directory is persisted because logrotate replaces the state atomically.

Each host retains its own existing identity at `/persist/etc/agenix/identity`.
The shared profile sets `age.identityPaths` explicitly; an SSH host-key
declaration is unnecessary while the SSH server is disabled. No keys or
encrypted secret recipients need changing for this consolidation.

An older setup needed `/home` early because system-secret decryption used the
`toma` SSH key there. The explicit identity under `/persist` removes that
dependency. Home Manager still uses the user's SSH key, but its service waits
for the home mount with `RequiresMountsFor`.

## Old-root cleanup

`my.impermanence.cleanup.enable` defaults to false. James explicitly enables
it. Peter leaves it disabled until the local rollout below is verified.
`resetRoot = false` also disables the automatic cleanup service and timer.

The installed `impermanence-clean-old-roots` command uses the same generated
layout as the filesystem declarations. It defaults to inspection:

```sh
sudo impermanence-clean-old-roots --report /persist/old-root-inspection.json
```

Deletion requires `--apply`. The service performs it five minutes after timer
activation and daily afterward. It requires a healthy boot, zero Btrfs device
error counters, the expected mount identities, a read-only blank template and
old roots descended from that template. It rejects unexpected entries,
symlinks, invalid ancestry and mounted/protected subvolumes. Mount checks scan
each distinct mount namespace used by live processes and threads, including
private service namespaces, before planning and before each deletion. Cleanup
stops if a namespace cannot be inspected or a mounted Btrfs filesystem cannot
be identified. Run the command on the host, with its full `/proc` visible.
Nested subvolumes are deleted before their parents. Reports requested with
`--report` record partial progress and whether cleanup completed. Updates are
synced and atomically replaced so an interrupted write preserves the previous
valid JSON record. That record can lag the last deletion; inspect again
before retrying so the new plan reflects the remaining subvolumes.

```sh
systemctl --failed
systemctl status impermanence-clean-old-roots.timer
journalctl -u impermanence-clean-old-roots.service
sudo btrfs device stats --check /
```

The old `james-clean-old-roots` units are retired when switching James. Verify
that the old timer is inactive and only the new timer is scheduled. Legacy
roots on Peter may fail ancestry checks; inspect those as a separate migration
task. Routine cleanup deliberately has no original-root bypass.

## First rollout on Peter

Perform these steps locally on Peter; it has no SSH server. Transfer the changes
to the laptop and build its system before changing any state:

```sh
cd /home/tommoa/.config/nixpkgs
nix build --no-link .#nixosConfigurations.peter.config.system.build.toplevel
```

Keep `cleanup.enable = false`. Verify recovery access and a current backup of
important persistent data. Before switching, inspect the current layout and
maintenance state:

```sh
findmnt -rn -o TARGET,UUID,FSROOT,FSTYPE
systemctl --failed
sudo btrfs device stats --check /
sudo btrfs subvolume list -u -q /
systemctl cat logrotate.service
# Run the logrotate executable shown in that unit with --version.
```

Check that the filesystem UUID is
`2ae3c985-a150-47fc-8953-817bbf6cf0e0`, the persistent mounts use the subvolumes
above, and `@root-blank` is read-only. To inspect the blank template, mount the
filesystem top level read-only, use `btrfs property get -t subvol` on its
`@root-blank`, then unmount it. Check the identity's ownership and permissions
without printing its contents.

The old logrotate unit has no explicit state argument. Its executable's
`--version` output prints the default state path (`/var/lib/logrotate.status`
in the pinned package). It may not be on the interactive shell's PATH, so use
the absolute executable path from the unit. If the live unit supplies an
override, use that override instead. Record this path for the seeding step.

### Seed maintenance state before activation

Run the following in an interactive root Bash shell (`sudo bash`). Set
`old_logrotate_state` to the verified live state path. The procedure refuses
nonempty persistence destinations that are not already the same directory;
reconcile those manually before continuing. It leaves the ephemeral source
directories intact and makes a persistent backup before copying.

```bash
set -euo pipefail
old_logrotate_state=/var/lib/logrotate.status  # Confirm against the live unit/version.
state_dirs=(
  /var/lib/btrfs
  /var/lib/logrotate
  /var/lib/systemd/rfkill
  /var/lib/systemd/timers
  /var/lib/systemd/timesync
)
test "$(findmnt -nro UUID --mountpoint /persist)" = 2ae3c985-a150-47fc-8953-817bbf6cf0e0
for source_dir in "${state_dirs[@]}"; do
  destination="/persist$source_dir"
  if [[ -L "$source_dir" || -L "$destination" ]]; then
    echo "Inspect unexpected symlink: $source_dir or $destination" >&2
    exit 1
  fi
  if [[ -e "$destination" ]]; then
    test -d "$destination"
    if [[ ! "$source_dir" -ef "$destination" ]] &&
       [[ -n "$(find "$destination" -mindepth 1 -print -quit)" ]]; then
      echo "Reconcile existing persistent state before continuing: $destination" >&2
      exit 1
    fi
  fi
done
backup="/persist/impermanence-seeding-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -m 0700 "$backup"

# Stop triggers before inspecting writers, including services they just started.
mapfile -t active_timers < <(systemctl list-units --type=timer --state=active,activating,deactivating --no-legend --plain | awk '{print $1}')
printf '%s\n' "${active_timers[@]}" > "$backup/active-timers"
if (( ${#active_timers[@]} )); then systemctl stop "${active_timers[@]}"; fi
rfkill_socket_active=false
if systemctl is-active --quiet systemd-rfkill.socket; then
  rfkill_socket_active=true
  systemctl stop systemd-rfkill.socket
fi
printf '%s\n' "$rfkill_socket_active" > "$backup/rfkill-socket-active"
mapfile -t active_writers < <(systemctl list-units --type=service --state=active,activating,deactivating --no-legend --plain |
  awk '$1 ~ /^(btrfs-scrub[^ ]*|systemd-timesyncd|systemd-rfkill)\.service$/ {print $1}')
printf '%s\n' "${active_writers[@]}" > "$backup/active-writers"
if (( ${#active_writers[@]} )); then systemctl stop "${active_writers[@]}"; fi

# Logrotate is activating while its oneshot runs. Let it finish rather than
# interrupting a rotation; do not restart the completed oneshot after migration.
while :; do
  logrotate_state=$(systemctl show --property=ActiveState --value logrotate.service)
  case "$logrotate_state" in
    inactive) break ;;
    active|activating|deactivating) sleep 1 ;;
    *)
      echo "Inspect logrotate before seeding state: $logrotate_state" >&2
      exit 1
      ;;
  esac
done

for source_dir in "${state_dirs[@]}"; do
  destination="/persist$source_dir"
  if [[ -d "$source_dir" ]]; then
    cp -a --parents -- "$source_dir" "$backup"
    if [[ ! "$source_dir" -ef "$destination" ]]; then
      mkdir -p -- "$destination"
      cp -a -- "$source_dir/." "$destination/"
    fi
  fi
done
if [[ -f "$old_logrotate_state" ]]; then
  cp -a --parents -- "$old_logrotate_state" "$backup"
  mkdir -p /persist/var/lib/logrotate
  if [[ -e /persist/var/lib/logrotate/status ]]; then
    cmp -- "$old_logrotate_state" /persist/var/lib/logrotate/status
  else
    cp -a -- "$old_logrotate_state" /persist/var/lib/logrotate/status
  fi
fi
```

The copy waits for any in-flight logrotate operation to finish and refuses to
continue if the service has failed. Avoid manually starting state writers until
seeding is complete.

If any step fails, keep the backup, inspect the error, and restart the recorded
writers and timers before leaving the machine. Do not rerun the whole copy over
a nonempty destination. If the source logrotate state was already copied as
`/var/lib/logrotate/status`, compare it to the persisted copy and skip the final
copy after verifying they match. The final copy above already handles an
identical existing state file.

### Switch and verify

In the same root shell, switch and verify all five persistence bind mounts
before restarting writers. If switching fails, inspect the mounts and restore
the recorded services; do not reboot with an unverified migration.

```bash
nixos-rebuild switch --flake /home/tommoa/.config/nixpkgs#peter
for source_dir in "${state_dirs[@]}"; do
  findmnt --mountpoint "$source_dir"
  test "$source_dir" -ef "/persist$source_dir"
done
if (( ${#active_writers[@]} )); then systemctl start "${active_writers[@]}"; fi
if "$rfkill_socket_active"; then systemctl start systemd-rfkill.socket; fi
if (( ${#active_timers[@]} )); then systemctl start "${active_timers[@]}"; fi
systemctl --failed
impermanence-clean-old-roots --report /persist/old-root-inspection.json
```

Keep the backup and a known-working boot generation. Reboot normally and verify
the reset service ran once, mounts and selected maintenance state survived,
login and secret decryption work, Wi-Fi/Bluetooth and Steam work, and logrotate
uses `/var/lib/logrotate/status`. Then test hibernation/resume separately.

If cleanup inspection fails only on legacy ancestry, leave cleanup disabled
while those roots are reviewed. After all checks pass, set
`my.impermanence.cleanup.enable = true` in `hosts/peter.nix`, rebuild and switch,
then stop the timer while reviewing and performing the first controlled run:

```sh
sudo systemctl stop impermanence-clean-old-roots.timer
sudo impermanence-clean-old-roots --report /persist/old-root-inspection.json
# After reviewing the targets:
sudo impermanence-clean-old-roots --apply --report /persist/old-root-cleanup.json
sudo systemctl start impermanence-clean-old-roots.timer
```

Finally verify its automatic run after a normal boot. Leave the timer stopped
and the configuration disabled if inspection rejects any target.

## Recovery

Disable cleanup to preserve old roots; disable root reset as well when an
existing root needs inspection. Before mounting a recovery root, stop the
cleanup timer and hold the cleanup lock for the entire recovery session:

```sh
sudo systemctl stop impermanence-clean-old-roots.timer
sudo flock --shared /run/impermanence-old-root-cleanup.lock bash
# Mount, inspect and unmount recovery roots inside this shell, then exit.
```

Cleanup invocations refuse to run while the shared lock is held. Mount checks
are observations, so the lock also prevents a cooperating recovery session
from mounting a root between the final check and deletion. Keep the shell open
until every recovery mount is removed; restart the timer only afterward, if
cleanup should resume. Leave cleanup disabled when retaining roots beyond the
session.

A previous NixOS generation restores
configuration, not deleted roots or persistent application data. Recover that
data from the backup. Keep `home`, `nix`, `@persist`, `steamapps` and the blank
template intact. James's existing RAM maintenance entry remains available;
its historical migration helpers should not be rerun for this consolidation.
