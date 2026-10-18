#!/usr/bin/env python3
"""Inspect or remove unmounted former roots after a healthy boot."""
import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


PROC_ROOT = Path('/proc')

# Python and this code are loaded before setns. Entering a mount namespace
# resets the helper's root to the namespace root, rather than a task's chroot.
# An inherited host proc handle works even when that root has no /proc or /nix.
NAMESPACE_MOUNTINFO_READER = '''
import os, sys
os.setns(int(sys.argv[1]), os.CLONE_NEWNS)
descriptor = os.open('self/mountinfo', os.O_RDONLY, dir_fd=int(sys.argv[2]))
with os.fdopen(descriptor) as stream:
    sys.stdout.write(stream.read())
'''


def namespace_mountinfo(descriptor, proc_descriptor):
    table = output(sys.executable, '-c', NAMESPACE_MOUNTINFO_READER,
                   str(descriptor), str(proc_descriptor),
                   pass_fds=(descriptor, proc_descriptor))
    require(table.strip(), 'Empty namespace mount inventory')
    return table


def output(*args, pass_fds=()):
    return subprocess.check_output(args, text=True, pass_fds=pass_fds).strip()


def run(*args):
    print('+ ' + ' '.join(args), flush=True)
    subprocess.run(args, check=True)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def write_report(path, report):
    if not path:
        return
    # Publish a complete, durable replacement without truncating prior progress.
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent,
                                         prefix='.' + path.name + '.', suffix='.tmp',
                                         delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(report, stream, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        os.fsync(directory)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        os.close(directory)


def parse_inventory(text):
    records = {}
    for line in text.splitlines():
        match = re.fullmatch(r'ID (\d+) .*? top level (\d+) (.*?)path (.+)', line)
        require(match is not None, 'Unexpected Btrfs inventory format')
        identifier, parent, fields, path = match.groups()
        uuids = {}
        for key in ['uuid', 'parent_uuid']:
            value = re.search(r'(?:^| )' + key + r' (\S+)(?: |$)', fields)
            require(value is not None, 'Missing ' + key + ' in inventory')
            uuids[key] = value[1]
        identifier = int(identifier)
        require(identifier not in records, 'Duplicate subvolume ID')
        records[identifier] = dict(id=identifier, parent_id=int(parent),
                                   path=path.removeprefix('<FS_TREE>/'), **uuids)
    return records


def load_layout(path):
    layout = json.loads(path.read_text())
    mounts = layout['mounts']
    require(isinstance(mounts, dict) and '/' in mounts, 'Layout must include the root mount')
    names = [*mounts.values(), layout['blankSubvolume'], layout['oldRootsDirectory']]
    require(all(isinstance(name, str) and re.fullmatch(r'@?[a-zA-Z0-9_-]+', name)
                for name in names), 'Invalid top-level subvolume or directory name')
    require(len(set(names)) == len(names), 'Layout names must be distinct')
    require(all(isinstance(mount, str) and mount.startswith('/') and
                str(Path(mount)) == mount and '..' not in Path(mount).parts
                for mount in mounts), 'Invalid mount path in layout')
    return layout


def plan_deletions(records, entry_names, blank_uuid, protected, mounted, old_directory):
    """Validate the entire target set before allowing any deletion."""
    roots = {}
    for name in entry_names:
        require(re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', name),
                'Unexpected entry in ' + old_directory + ': ' + name)
        path = old_directory + '/' + name
        matches = [item for item in records.values() if item['path'] == path]
        require(len(matches) == 1, 'Old-root entry is not a unique subvolume: ' + path)
        item = matches[0]
        require(item['parent_id'] == 5, 'Old root has unexpected containing subvolume')
        require(item['parent_uuid'] == blank_uuid,
                'Old root is not a snapshot of the blank template: ' + path)
        roots[item['id']] = item
    selected = {}
    depths = {}
    for identifier, item in records.items():
        if not item['path'].startswith(old_directory + '/'):
            continue
        enclosing = [root for root in roots.values()
                     if item['path'] == root['path'] or item['path'].startswith(root['path'] + '/')]
        require(len(enclosing) == 1, 'Unreviewed subvolume below ' + old_directory + ': ' + item['path'])
        root = enclosing[0]
        parent = identifier
        visited = set()
        while parent != root['id']:
            require(parent not in visited and parent in records, 'Invalid subvolume ancestry')
            visited.add(parent)
            parent = records[parent]['parent_id']
        require(identifier not in protected and identifier not in mounted,
                'Refusing to delete protected or mounted subvolume: ' + item['path'])
        selected[identifier] = item
        depths[identifier] = len(visited)
    # A child outside the expected pathname would make the inventory inconsistent.
    for identifier, item in records.items():
        if item['parent_id'] in selected:
            require(identifier in selected, 'Descendant outside the validated old-root tree')
    return sorted(selected.values(), key=lambda item: (-depths[item['id']], item['id']))


def mounted_subvolumes(expected_uuid):
    """Inspect pinned namespaces and task views without relying on sandbox executables."""
    with contextlib.ExitStack() as stack:
        proc_descriptor = os.open(PROC_ROOT, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        stack.callback(os.close, proc_descriptor)
        namespaces = {}
        tables = set()
        for process in PROC_ROOT.iterdir():
            if not process.name.isdecimal():
                continue
            try:
                tasks = list((process / 'task').iterdir())
            except (FileNotFoundError, ProcessLookupError):
                # The process exited before its tasks could be enumerated.
                continue
            for task in tasks:
                try:
                    descriptor = os.open(task / 'ns/mnt', os.O_RDONLY | os.O_CLOEXEC)
                except (FileNotFoundError, ProcessLookupError):
                    continue
                try:
                    identity = os.fstat(descriptor)
                    table_descriptor = os.open(task / 'mountinfo', os.O_RDONLY | os.O_CLOEXEC)
                except (FileNotFoundError, ProcessLookupError):
                    os.close(descriptor)
                    continue
                except OSError:
                    os.close(descriptor)
                    raise
                # The kernel pins the namespace and task root when mountinfo is
                # opened. Capture it now, so task exit or setns cannot invalidate
                # the later probe. Tasks sharing a namespace can have different
                # chroot views; deduplicate tables, never just namespace IDs.
                try:
                    with os.fdopen(table_descriptor) as stream:
                        table = stream.read()
                    if not table.strip():
                        # An empty table can hide a live root on a detached
                        # mount. Namespace inventory cannot recover that mount;
                        # only exited tasks and kernel threads without a root
                        # can safely contribute no task view.
                        try:
                            os.stat(task / 'root')
                        except (FileNotFoundError, ProcessLookupError):
                            pass
                        else:
                            raise ValueError('Task root has an empty mount inventory: ' + str(task))
                    try:
                        current_namespace = os.stat(task / 'ns/mnt')
                    except (FileNotFoundError, ProcessLookupError):
                        # The captured table and namespace handle survive exit.
                        pass
                    else:
                        require((current_namespace.st_dev, current_namespace.st_ino)
                                == (identity.st_dev, identity.st_ino),
                                'Task changed mount namespace during inspection: ' + str(task))
                except BaseException:
                    os.close(descriptor)
                    raise
                # Retain a namespace handle until the entire inventory is checked.
                key = (identity.st_dev, identity.st_ino)
                if key in namespaces:
                    os.close(descriptor)
                else:
                    stack.callback(os.close, descriptor)
                    namespaces[key] = descriptor
                # Preserve distinct chroot views as well as namespace views.
                # Empty views with live roots have already been refused above.
                if table.strip():
                    tables.add(table)
        require(namespaces, 'No process mount namespaces could be inspected')
        for descriptor in namespaces.values():
            tables.add(namespace_mountinfo(descriptor, proc_descriptor))
        ids = set()
        for table in tables:
            # Kernel-thread and sandbox namespaces need not contain findmnt or
            # its Nix closure. Parse their captured mountinfo in the host instead,
            # where filesystem UUIDs can be resolved against the host devices.
            with tempfile.TemporaryFile(mode='w+') as snapshot:
                snapshot.write(table)
                snapshot.flush()
                snapshot.seek(0)
                descriptor = snapshot.fileno()
                mounts = json.loads(output('findmnt', '--kernel', '--tab-file',
                                           '/proc/self/fd/' + str(descriptor), '--json', '--list',
                                           '-o', 'FSTYPE,UUID,OPTIONS', pass_fds=(descriptor,)))
            require(isinstance(mounts.get('filesystems'), list), 'Missing namespace mount inventory')
            for mount in mounts['filesystems']:
                if mount['fstype'] != 'btrfs':
                    continue
                require(mount['uuid'], 'Cannot identify a mounted Btrfs filesystem')
                if mount['uuid'] != expected_uuid:
                    continue
                match = re.search(r'(?:^|,)subvolid=(\d+)(?:,|$)', mount['options'])
                require(match is not None, 'Mounted Btrfs subvolume ID is missing')
                ids.add(int(match[1]))
        return ids


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--uuid', required=True)
    parser.add_argument('--layout', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args(argv)
    require(os.geteuid() == 0, 'Run locally with sudo')
    require(re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', args.uuid),
            'Invalid filesystem UUID')
    layout = load_layout(args.layout)
    root_name = layout['mounts']['/']
    blank_name = layout['blankSubvolume']
    old_directory = layout['oldRootsDirectory']
    os.environ['LC_ALL'] = 'C'
    with open('/run/impermanence-old-root-cleanup.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        require(subprocess.run(['systemctl', 'is-active', '--quiet', 'multi-user.target']).returncode == 0,
                'System has not reached multi-user.target')
        require(not output('systemctl', '--failed', '--no-legend', '--plain', '--no-pager'),
                'Failed system units must be inspected before root cleanup')
        require(output('findmnt', '-nro', 'FSTYPE,UUID,FSROOT', '--mountpoint', '/').split() ==
                ['btrfs', args.uuid, '/' + root_name], 'Unexpected mounted root')
        run('btrfs', 'device', 'stats', '--check', '/')
        protected_names = [*layout['mounts'].values(), blank_name]
        with tempfile.TemporaryDirectory(prefix='impermanence-old-root-cleanup-', dir='/run') as directory:
            top = Path(directory)
            run('mount', '-t', 'btrfs', '-o', 'subvolid=5' + ('' if args.apply else ',ro'),
                '/dev/disk/by-uuid/' + args.uuid, directory)
            try:
                records = parse_inventory(output('btrfs', 'subvolume', 'list', '-u', '-q', directory))
                protected = set()
                for name in protected_names:
                    matches = [item for item in records.values() if item['path'] == name]
                    require(len(matches) == 1, 'Missing protected subvolume: ' + name)
                    protected.add(matches[0]['id'])
                root = next(item for item in records.values() if item['path'] == root_name)
                blank = next(item for item in records.values() if item['path'] == blank_name)
                require(root['parent_uuid'] == blank['uuid'], 'Current root is not from the blank template')
                require(output('btrfs', 'property', 'get', '-t', 'subvol', str(top / blank_name), 'ro') == 'ro=true',
                        'Blank template is not read-only')
                for path, name in layout['mounts'].items():
                    expected = next(item for item in records.values() if item['path'] == name)
                    mounted = output('findmnt', '-nro', 'UUID,FSROOT', '--mountpoint', path).split()
                    require(mounted == [args.uuid, '/' + name], 'Persistent mount changed: ' + path)
                    opts = output('findmnt', '-nro', 'OPTIONS', '--mountpoint', path)
                    require(('subvolid=' + str(expected['id'])) in opts.split(','), 'Mount identity differs: ' + path)
                old = top / old_directory
                require(not old.is_symlink(), old_directory + ' must not be a symlink')
                require(not any(item['path'] == old_directory for item in records.values()),
                        old_directory + ' must be an ordinary directory')
                entries = list(old.iterdir()) if old.exists() else []
                require(all(entry.is_dir() and not entry.is_symlink() for entry in entries),
                        'Unexpected non-directory or symlink in @old-roots')
                plan = plan_deletions(records, [entry.name for entry in entries], blank['uuid'], protected,
                                      mounted_subvolumes(args.uuid), old_directory)
                report = {'filesystem_uuid': args.uuid, 'mode': 'apply' if args.apply else 'inspect',
                          'protected_ids': sorted(protected), 'targets': plan, 'deleted_ids': [],
                          'complete': not args.apply}
                print(json.dumps(report, indent=2), flush=True)
                write_report(args.report, report)
                if args.apply:
                    for item in plan:
                        require(item['id'] not in mounted_subvolumes(args.uuid), 'Target became mounted')
                        # Delete by ID at the top-level mount, never by a followed pathname.
                        run('btrfs', 'subvolume', 'delete', '--commit-after', '--subvolid', str(item['id']), directory)
                        report['deleted_ids'].append(item['id'])
                        write_report(args.report, report)
                    remaining = parse_inventory(output('btrfs', 'subvolume', 'list', '-u', '-q', directory))
                    require(not any(item['path'].startswith(old_directory + '/') for item in remaining.values()),
                            'Some old-root subvolumes remain')
                    require(protected <= set(remaining), 'Protected subvolume missing after cleanup')
                    report['complete'] = True
                    write_report(args.report, report)
                print('Old roots removed.' if args.apply else 'Inspection complete; no roots deleted.')
            finally:
                run('umount', directory)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, subprocess.CalledProcessError, OSError) as error:
        raise SystemExit('STOP: ' + str(error))
