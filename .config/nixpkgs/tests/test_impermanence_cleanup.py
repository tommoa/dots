"""Test deletion safeguards; real mounts stay inside disposable user namespaces."""
import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import shutil
import stat
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import mock_open, patch


SCRIPT = Path(__file__).resolve().parents[1] / 'modules/nixos/scripts/impermanence-clean-old-roots.py'
spec = importlib.util.spec_from_file_location('cleanup', SCRIPT)
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)
UUID = '2ae3c985-a150-47fc-8953-817bbf6cf0e0'
BOOT = 'bb7f7fe8-6668-4690-9e24-966803ab2ee9'
OLD = '@old-roots'
LAYOUT = {
    'mounts': {
        '/': '@root', '/home': 'home', '/nix': 'nix', '/persist': '@persist',
        '/home/test-user/.local/share/Steam/steamapps': 'steamapps',
    },
    'blankSubvolume': '@root-blank',
    'oldRootsDirectory': OLD,
}


def record(identifier, path, parent=5, parent_uuid='blank'):
    return dict(id=identifier, path=path, parent_id=parent,
                uuid='blank' if path == '@root-blank' else str(identifier),
                parent_uuid=parent_uuid)


def namespace(proc, process, thread, shared=None):
    path = proc / str(process) / 'task' / str(thread) / 'ns/mnt'
    path.parent.mkdir(parents=True, exist_ok=True)
    if shared is None:
        path.write_text(f'namespace-{process}-{thread}\n')
    else:
        path.hardlink_to(shared)
    (path.parent.parent / 'mountinfo').write_text(path.read_text())
    (path.parent.parent / 'root').symlink_to('/')
    return path


def mount(identifier, uuid=UUID):
    return dict(fstype='btrfs', uuid=uuid, options=f'rw,subvolid={identifier}')


class MountNamespaceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.proc = Path(self.temporary.name)
        host = namespace(self.proc, 100, 100)
        namespace(self.proc, 200, 200, shared=host)
        recovery = namespace(self.proc, 200, 201)
        self.recovery = recovery
        self.mounts = {host.read_text(): [mount(256)], recovery.read_text(): [mount(301)]}
        self.descriptors = []

    def output(self, *args, pass_fds=()):
        if args[:3] == (sys.executable, '-c', cleanup.NAMESPACE_MOUNTINFO_READER):
            self.assertEqual(args[3:], tuple(map(str, pass_fds)))
            return os.pread(pass_fds[0], 65536, 0).decode()
        self.assertEqual(args, ('findmnt', '--kernel', '--tab-file', '/proc/self/fd/' + str(pass_fds[0]),
                                '--json', '--list', '-o', 'FSTYPE,UUID,OPTIONS'))
        descriptor, = pass_fds
        self.descriptors.append(descriptor)
        table = os.pread(descriptor, 65536, 0).decode()
        return json.dumps({'filesystems': self.mounts[table]})

    def inspect(self):
        with patch.object(cleanup, 'PROC_ROOT', self.proc), \
             patch.object(cleanup, 'output', side_effect=self.output):
            return cleanup.mounted_subvolumes(UUID)

    def test_private_thread_mount_is_found_and_shared_namespaces_are_deduplicated(self):
        self.assertEqual(self.inspect(), {256, 301})
        self.assertEqual(len(self.descriptors), 2)
        for descriptor in self.descriptors:
            with self.assertRaises(OSError):
                os.fstat(descriptor)

    def test_non_btrfs_and_other_filesystem_mounts_do_not_protect_targets(self):
        self.mounts = {key: [dict(fstype='tmpfs', uuid=None, options='rw'),
                             mount(301, uuid='another-filesystem')] for key in self.mounts}
        self.assertEqual(self.inspect(), set())

    @unittest.skipUnless(shutil.which('unshare') and shutil.which('mount') and hasattr(os, 'setns'),
                         'Linux namespace tools and Python setns are required')
    def test_real_namespace_with_no_proc_or_executables_is_fully_read(self):
        probe = subprocess.run(['unshare', '--user', '--map-root-user', '--mount', 'true'],
                               capture_output=True, text=True)
        if probe.returncode:
            self.skipTest('Unprivileged user/mount namespaces are unavailable: ' + probe.stderr.strip())
        root = Path(self.temporary.name) / 'isolated-root'
        root.mkdir()
        # The driver keeps the host root. Its child pivots into an empty tmpfs
        # and detaches the old root, leaving no /proc, /nix or executables.
        # All mounts occur inside disposable user/mount namespaces.
        code = '''
import ctypes, importlib.util, os, signal, subprocess, sys, traceback
from pathlib import Path
spec = importlib.util.spec_from_file_location('cleanup', sys.argv[1])
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)
libc = ctypes.CDLL(None, use_errno=True)
reader, writer = os.pipe()
child = os.fork()
if child == 0:
    os.close(reader)
    try:
        os.unshare(os.CLONE_NEWNS)
        subprocess.run(['mount', '--make-rprivate', '/'], check=True)
        subprocess.run(['mount', '-t', 'tmpfs', 'tmpfs', sys.argv[2]], check=True)
        os.chdir(sys.argv[2])
        os.mkdir('old-root')
        if libc.pivot_root(b'.', b'old-root') != 0:
            raise OSError(ctypes.get_errno(), 'pivot_root failed')
        os.chdir('/')
        if libc.umount2(b'/old-root', 2) != 0:
            raise OSError(ctypes.get_errno(), 'detach old root failed')
        os.rmdir('/old-root')
        assert not os.path.exists('/proc') and not os.path.exists('/nix')
        os.write(writer, b'R')
        signal.pause()
    except BaseException:
        traceback.print_exc()
    finally:
        os._exit(1)
os.close(writer)
try:
    assert os.read(reader, 1) == b'R', 'isolated child failed'
    namespace = os.open(f'/proc/{child}/ns/mnt', os.O_RDONLY)
    proc = os.open('/proc', os.O_RDONLY | os.O_DIRECTORY)
    try:
        table = cleanup.namespace_mountinfo(namespace, proc)
        assert len(table.splitlines()) == 1, table
        assert ' / / ' in table and ' - tmpfs ' in table, table
        print('ISOLATED_PROBE_OK')
    finally:
        os.close(namespace)
        os.close(proc)
finally:
    os.close(reader)
    os.kill(child, signal.SIGKILL)
    os.waitpid(child, 0)
'''
        result = subprocess.run(['unshare', '--user', '--map-root-user', '--mount',
                                 sys.executable, '-c', code, str(SCRIPT), str(root)],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('ISOLATED_PROBE_OK', result.stdout)

    @unittest.skipUnless(shutil.which('findmnt'), 'findmnt is required for the kernel-table regression')
    def test_kernel_thread_namespace_without_executables_is_parsed_on_host(self):
        proc = Path(self.temporary.name) / 'kernel-proc'
        task_namespace = namespace(proc, 65, 65)
        table = '1 0 0:1 / / rw - devtmpfs devtmpfs rw\n'
        (task_namespace.parent.parent / 'mountinfo').write_text(table)
        with patch.object(cleanup, 'PROC_ROOT', proc), \
             patch.object(cleanup, 'namespace_mountinfo', return_value=table):
            self.assertEqual(cleanup.mounted_subvolumes(UUID), set())

    def test_different_task_root_views_of_same_namespace_are_all_inspected(self):
        task_namespace = self.proc / '200/task/200/ns/mnt'
        (task_namespace.parent.parent / 'mountinfo').write_text('different-root-view\n')
        self.mounts['different-root-view\n'] = [mount(302)]
        self.assertEqual(self.inspect(), {256, 301, 302})

    def test_unreadable_task_mountinfo_refuses(self):
        table = self.recovery.parent.parent / 'mountinfo'
        real_open = os.open
        def denied(path, *args, **kwargs):
            if path == table:
                raise PermissionError('mountinfo inaccessible')
            return real_open(path, *args, **kwargs)
        with patch.object(cleanup.os, 'open', side_effect=denied), self.assertRaises(PermissionError):
            self.inspect()

    def test_empty_chroot_view_refuses_even_when_namespace_inventory_is_available(self):
        task = self.proc / '200/task/200'
        (task / 'mountinfo').write_text('')
        with self.assertRaisesRegex(ValueError, 'Task root has an empty mount inventory'):
            self.inspect()

    def test_namespace_with_only_empty_chroot_views_refuses(self):
        task = self.recovery.parent.parent
        (task / 'mountinfo').write_text('')
        with self.assertRaisesRegex(ValueError, 'Task root has an empty mount inventory'):
            self.inspect()

    def test_empty_kernel_thread_view_is_covered_by_namespace_probe(self):
        task = self.recovery.parent.parent
        (task / 'root').unlink()
        (task / 'mountinfo').write_text('')
        self.assertEqual(self.inspect(), {256, 301})

    def test_unreadable_root_of_empty_task_view_refuses(self):
        task = self.recovery.parent.parent
        (task / 'mountinfo').write_text('')
        real_stat = os.stat
        def denied(path, *args, **kwargs):
            if path == task / 'root':
                raise PermissionError('task root inaccessible')
            return real_stat(path, *args, **kwargs)
        with patch.object(cleanup.os, 'stat', side_effect=denied), self.assertRaises(PermissionError):
            self.inspect()

    @unittest.skipUnless(shutil.which('unshare') and shutil.which('mount') and
                         shutil.which('findmnt') and hasattr(os, 'setns'),
                         'Linux namespace tools and Python setns are required')
    def test_real_detached_chroot_refuses_even_when_namespace_contains_only_tmpfs(self):
        probe = subprocess.run(['unshare', '--user', '--map-root-user', '--mount', 'true'],
                               capture_output=True, text=True)
        if probe.returncode:
            self.skipTest('Unprivileged user/mount namespaces are unavailable: ' + probe.stderr.strip())
        root = Path(self.temporary.name) / 'detached-root'
        root.mkdir()
        # A grandchild retains its chroot on the original filesystem while the
        # child pivots into tmpfs and detaches that filesystem. The real task
        # table is empty, though the namespace probe successfully sees tmpfs.
        code = '''
import ctypes, importlib.util, os, signal, subprocess, sys, traceback
from pathlib import Path
from unittest.mock import patch
spec = importlib.util.spec_from_file_location('cleanup', sys.argv[1])
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)
root = Path(sys.argv[2])
original_device = root.stat().st_dev
libc = ctypes.CDLL(None, use_errno=True)
reader, writer = os.pipe()
child = os.fork()
if child == 0:
    os.close(reader)
    held = None
    try:
        os.unshare(os.CLONE_NEWNS)
        subprocess.run(['mount', '--make-rprivate', '/'], check=True)
        ready_reader, ready_writer = os.pipe()
        held = os.fork()
        if held == 0:
            os.close(ready_reader)
            try:
                os.chroot(root)
                os.chdir('/')
                os.write(ready_writer, b'R')
                signal.pause()
            finally:
                os._exit(0)
        os.close(ready_writer)
        assert os.read(ready_reader, 1) == b'R', 'chroot child failed'
        os.close(ready_reader)
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
        subprocess.run(['mount', '-t', 'tmpfs', 'tmpfs', str(root)], check=True)
        os.chdir(root)
        os.mkdir('old-root')
        if libc.pivot_root(b'.', b'old-root') != 0:
            raise OSError(ctypes.get_errno(), 'pivot_root failed')
        os.chdir('/')
        if libc.umount2(b'/old-root', 2) != 0:
            raise OSError(ctypes.get_errno(), 'detach old root failed')
        os.write(writer, (str(held) + '\\n').encode())
        signal.pause()
    except SystemExit:
        pass
    except BaseException:
        traceback.print_exc()
    finally:
        if held:
            os.kill(held, signal.SIGKILL)
            os.waitpid(held, 0)
        os._exit(0)
os.close(writer)
try:
    with os.fdopen(reader) as stream:
        held = int(stream.readline())
    assert Path(f'/proc/{held}/mountinfo').read_text() == ''
    assert os.stat(f'/proc/{held}/root').st_dev == original_device
    namespace = os.open(f'/proc/{child}/ns/mnt', os.O_RDONLY)
    proc = os.open('/proc', os.O_RDONLY | os.O_DIRECTORY)
    try:
        table = cleanup.namespace_mountinfo(namespace, proc)
        assert len(table.splitlines()) == 1 and ' - tmpfs ' in table, table
    finally:
        os.close(namespace)
        os.close(proc)
    # Enumerate only the real chroot task. The fake proc directory cannot
    # resolve self/mountinfo after setns, so reuse the real probe above.
    view = root.parent / 'detached-proc'
    (view / str(held)).mkdir(parents=True)
    (view / str(held) / 'task').symlink_to(f'/proc/{held}/task')
    with patch.object(cleanup, 'PROC_ROOT', view), \\
         patch.object(cleanup, 'namespace_mountinfo', return_value=table):
        try:
            cleanup.mounted_subvolumes('unused-filesystem-uuid')
        except ValueError as error:
            assert 'Task root has an empty mount inventory' in str(error), error
        else:
            raise AssertionError('Detached live chroot was not refused')
    print('DETACHED_CHROOT_REFUSED')
finally:
    os.kill(child, signal.SIGTERM)
    os.waitpid(child, 0)
'''
        result = subprocess.run(['unshare', '--user', '--map-root-user', '--mount',
                                 sys.executable, '-c', code, str(SCRIPT), str(root)],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('DETACHED_CHROOT_REFUSED', result.stdout)

    def test_empty_full_namespace_inventory_refuses(self):
        original_output = self.output
        def empty(*args, **kwargs):
            if args[:3] == (sys.executable, '-c', cleanup.NAMESPACE_MOUNTINFO_READER):
                return ''
            return original_output(*args, **kwargs)
        with patch.object(cleanup, 'PROC_ROOT', self.proc), \
             patch.object(cleanup, 'output', side_effect=empty), \
             self.assertRaisesRegex(ValueError, 'Empty namespace mount inventory'):
            cleanup.mounted_subvolumes(UUID)

    def test_unidentified_btrfs_or_missing_subvolume_id_refuses(self):
        for entry in [mount(301, uuid=None), dict(fstype='btrfs', uuid=UUID, options='rw')]:
            self.mounts = {key: [entry] for key in self.mounts}
            with self.assertRaises(ValueError):
                self.inspect()

    def test_unreadable_namespace_refuses(self):
        real_open = os.open
        def denied(path, *args, **kwargs):
            if str(path).endswith('/201/ns/mnt'):
                raise PermissionError('namespace inaccessible')
            return real_open(path, *args, **kwargs)
        with patch.object(cleanup.os, 'open', side_effect=denied):
            with self.assertRaises(PermissionError):
                self.inspect()

    def test_exited_process_and_thread_are_skipped(self):
        (self.proc / '300').mkdir()
        (self.proc / '200/task/202').mkdir()
        self.assertEqual(self.inspect(), {256, 301})

    def test_pinned_namespace_remains_inspectable_after_representative_exit(self):
        original_output = self.output
        def output(*args, **kwargs):
            self.recovery.unlink(missing_ok=True)
            (self.recovery.parent.parent / 'mountinfo').unlink(missing_ok=True)
            return original_output(*args, **kwargs)
        with patch.object(cleanup, 'PROC_ROOT', self.proc), \
             patch.object(cleanup, 'output', side_effect=output):
            self.assertEqual(cleanup.mounted_subvolumes(UUID), {256, 301})

    def test_failed_namespace_inventory_refuses_and_releases_descriptors(self):
        def failure(*args, pass_fds=()):
            self.descriptors.extend(pass_fds)
            raise subprocess.CalledProcessError(1, args)
        with patch.object(cleanup, 'PROC_ROOT', self.proc), \
             patch.object(cleanup, 'output', side_effect=failure):
            with self.assertRaises(subprocess.CalledProcessError):
                cleanup.mounted_subvolumes(UUID)
        for descriptor in self.descriptors:
            with self.assertRaises(OSError):
                os.fstat(descriptor)


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / 'report.json'
        self.before = dict(deleted_ids=[301], complete=False)
        self.after = dict(deleted_ids=[301, 300], complete=True)
        cleanup.write_report(self.path, self.before)

    def test_success_publishes_complete_report_and_syncs_file_then_directory(self):
        synced = []
        real_fsync = os.fsync
        def fsync(descriptor):
            synced.append(os.fstat(descriptor).st_mode)
            return real_fsync(descriptor)
        with patch.object(cleanup.os, 'fsync', side_effect=fsync):
            cleanup.write_report(self.path, self.after)
        self.assertTrue(stat.S_ISREG(synced[0]))
        self.assertTrue(stat.S_ISDIR(synced[1]))
        self.assertEqual(json.loads(self.path.read_text()), self.after)
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])

    def test_partial_write_preserves_previous_report_and_removes_temporary(self):
        def interrupted_dump(report, stream, **kwargs):
            stream.write('{"deleted_ids":')
            stream.flush()
            raise OSError('interrupted write')
        with patch.object(cleanup.json, 'dump', side_effect=interrupted_dump):
            with self.assertRaisesRegex(OSError, 'interrupted write'):
                cleanup.write_report(self.path, self.after)
        self.assertEqual(json.loads(self.path.read_text()), self.before)
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])

    def test_file_sync_or_replace_failure_preserves_previous_report(self):
        for operation in ['fsync', 'replace']:
            with self.subTest(operation=operation):
                with patch.object(cleanup.os, operation, side_effect=OSError('publication failed')):
                    with self.assertRaises(OSError):
                        cleanup.write_report(self.path, self.after)
                self.assertEqual(json.loads(self.path.read_text()), self.before)
                self.assertEqual(list(self.path.parent.iterdir()), [self.path])

    def test_killed_writer_preserves_previous_report(self):
        code = '''
import importlib.util, signal, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('cleanup', sys.argv[1])
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)
def interrupted_dump(report, stream, **kwargs):
    stream.write('{"deleted_ids":')
    stream.flush()
    print('writing', flush=True)
    signal.pause()
cleanup.json.dump = interrupted_dump
cleanup.write_report(Path(sys.argv[2]), {'deleted_ids': [301, 300], 'complete': True})
'''
        with subprocess.Popen([sys.executable, '-B', '-c', code, str(SCRIPT), str(self.path)],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as process:
            try:
                self.assertEqual(process.stdout.readline().strip(), 'writing')
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate(timeout=5)
            self.assertEqual(process.returncode, -signal.SIGKILL)
        self.assertEqual(json.loads(self.path.read_text()), self.before)


class PlannerTests(unittest.TestCase):
    def setUp(self):
        self.records = {
            300: record(300, OLD + '/' + BOOT),
            301: record(301, OLD + '/' + BOOT + '/var/lib/machines', parent=300),
        }

    def plan(self, **kwargs):
        args = dict(records=self.records, entry_names=[BOOT], blank_uuid='blank',
                    protected={256}, mounted={256}, old_directory=OLD)
        args.update(kwargs)
        return cleanup.plan_deletions(**args)

    def test_children_are_deleted_before_parents(self):
        self.assertEqual([item['id'] for item in self.plan()], [301, 300])

    def test_mounted_or_protected_parent_and_child_reject_entire_plan(self):
        for identifier in [300, 301]:
            for field in ['mounted', 'protected']:
                with self.subTest(identifier=identifier, field=field):
                    with self.assertRaisesRegex(ValueError, 'protected or mounted'):
                        self.plan(**{field: {identifier}})

    def test_original_or_unknown_snapshot_ancestry_is_rejected(self):
        for parent_uuid in ['-', 'different-blank']:
            self.records[300]['parent_uuid'] = parent_uuid
            with self.assertRaisesRegex(ValueError, 'not a snapshot'):
                self.plan()

    def test_unknown_entry_and_missing_subvolume_are_rejected(self):
        for entries in [[BOOT, 'unexpected'], [BOOT, '90c224d5-00a7-4bfc-868b-00cdcea4d416']]:
            with self.assertRaises(ValueError):
                self.plan(entry_names=entries)

    def test_unlisted_old_root_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Unreviewed'):
            self.plan(entry_names=[])

    def test_invalid_nested_ancestry_is_rejected(self):
        for parent in [256, 301]:
            self.records[301]['parent_id'] = parent
            with self.assertRaisesRegex(ValueError, 'Invalid subvolume ancestry'):
                self.plan()

    def test_descendant_outside_validated_tree_is_rejected(self):
        self.records[301]['path'] = 'nix'
        with self.assertRaisesRegex(ValueError, 'Descendant outside'):
            self.plan()

    def test_retry_after_partial_deletion_and_empty_plan(self):
        del self.records[301]
        self.assertEqual([item['id'] for item in self.plan()], [300])
        self.assertEqual(self.plan(records={}, entry_names=[]), [])

    def test_inventory_parser_rejects_duplicates_and_unknown_output(self):
        line = 'ID 301 gen 400 top level 300 parent_uuid - uuid 1234 path <FS_TREE>/' + OLD + '/' + BOOT
        self.assertEqual(cleanup.parse_inventory(line)[301]['path'], OLD + '/' + BOOT)
        for text in [line + '\n' + line, 'unknown output']:
            with self.assertRaises(ValueError):
                cleanup.parse_inventory(text)


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.top = Path(self.temporary.name) / 'top'
        (self.top / OLD / BOOT).mkdir(parents=True)
        self.layout = Path(self.temporary.name) / 'layout.json'
        self.layout.write_text(json.dumps(LAYOUT))
        self.report = Path(self.temporary.name) / 'report.json'
        self.records = {i: record(i, name) for i, name in enumerate(
            [*LAYOUT['mounts'].values(), LAYOUT['blankSubvolume']], start=256)}
        self.records.update({300: record(300, OLD + '/' + BOOT),
                             301: record(301, OLD + '/' + BOOT + '/nested', parent=300)})
        self.commands = []
        self.failed_units = ''
        self.target_active = True
        self.fail_command = None
        self.blank_readonly = True
        self.mounted = set(range(256, 261))
        self.mount_checks = 0
        self.mount_after_planning = False
        self.wrong_mount = False
        self.proc = Path(self.temporary.name) / 'proc'
        host = namespace(self.proc, 100, 100)
        recovery = namespace(self.proc, 200, 200)
        self.host_namespace = host.read_text()
        self.recovery_namespace = recovery.read_text()
        self.foreign_mounted = set()
        self.namespace_checks = 0
        self.namespace_failure = False

    def output(self, *args, pass_fds=()):
        if args[:3] == (sys.executable, '-c', cleanup.NAMESPACE_MOUNTINFO_READER):
            return os.pread(pass_fds[0], 65536, 0).decode()
        if args[:3] == ('findmnt', '--kernel', '--tab-file'):
            if self.namespace_failure:
                raise subprocess.CalledProcessError(1, args)
            identity = os.pread(pass_fds[0], 65536, 0).decode()
            if identity == self.recovery_namespace:
                self.namespace_checks += 1
                if self.mount_after_planning and self.namespace_checks == 2:
                    self.foreign_mounted.add(301)
                ids = self.foreign_mounted
            else:
                self.assertEqual(identity, self.host_namespace)
                ids = self.mounted
            return json.dumps({'filesystems': [mount(i) for i in ids]})
        if args[0] == 'systemctl':
            return self.failed_units
        if args[:3] == ('btrfs', 'subvolume', 'list'):
            return '\n'.join(f"ID {r['id']} gen 1 top level {r['parent_id']} parent_uuid {r['parent_uuid']} uuid {r['uuid']} path {r['path']}"
                             for r in self.records.values())
        if args[:3] == ('btrfs', 'property', 'get'):
            return 'ro=true' if self.blank_readonly else 'ro=false'
        if args[0] == 'findmnt':
            path = args[-1]
            name = LAYOUT['mounts'][path]
            if args[2] == 'FSTYPE,UUID,FSROOT':
                return f'btrfs {UUID} /{name}'
            if args[2] == 'UUID,FSROOT':
                return f'{UUID} /unexpected' if self.wrong_mount else f'{UUID} /{name}'
            identifier = next(r['id'] for r in self.records.values() if r['path'] == name)
            return f'rw,subvolid={identifier},subvol=/{name}'
        self.fail('Unexpected command: ' + str(args))

    def run_command(self, *args):
        self.commands.append(args)
        if self.fail_command and self.fail_command(args):
            raise subprocess.CalledProcessError(1, args)
        if args[:3] == ('btrfs', 'subvolume', 'delete'):
            del self.records[int(args[-2])]

    def mounted_subvolumes(self, _):
        self.mount_checks += 1
        if self.mount_after_planning and self.mount_checks == 2:
            self.mounted.add(301)
        return self.mounted

    def invoke(self, apply=False, use_namespace_probe=False):
        args = ['--uuid', UUID, '--layout', str(self.layout), '--report', str(self.report)]
        if apply:
            args.append('--apply')
        with contextlib.ExitStack() as stack:
            stack.enter_context(patch.object(cleanup.os, 'geteuid', return_value=0))
            stack.enter_context(patch.object(cleanup, 'open', mock_open(), create=True))
            stack.enter_context(patch.object(cleanup.fcntl, 'flock'))
            stack.enter_context(patch.object(cleanup.tempfile, 'TemporaryDirectory',
                                             return_value=contextlib.nullcontext(str(self.top))))
            stack.enter_context(patch.object(cleanup.subprocess, 'run', return_value=SimpleNamespace(
                returncode=0 if self.target_active else 1)))
            stack.enter_context(patch.object(cleanup, 'output', side_effect=self.output))
            stack.enter_context(patch.object(cleanup, 'run', side_effect=self.run_command))
            if use_namespace_probe:
                stack.enter_context(patch.object(cleanup, 'PROC_ROOT', self.proc))
            else:
                stack.enter_context(patch.object(cleanup, 'mounted_subvolumes', side_effect=self.mounted_subvolumes))
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            cleanup.main(args)

    def deletions(self):
        return [args for args in self.commands if args[:3] == ('btrfs', 'subvolume', 'delete')]

    def test_inspection_mounts_readonly_and_never_deletes(self):
        self.invoke()
        self.assertEqual(self.deletions(), [])
        self.assertIn(('mount', '-t', 'btrfs', '-o', 'subvolid=5,ro',
                       '/dev/disk/by-uuid/' + UUID, str(self.top)), self.commands)
        self.assertEqual(self.commands[-1], ('umount', str(self.top)))
        self.assertEqual(json.loads(self.report.read_text())['mode'], 'inspect')

    def test_apply_deletes_by_id_and_preserves_protected_subvolumes(self):
        self.invoke(apply=True)
        self.assertEqual([int(args[-2]) for args in self.deletions()], [301, 300])
        self.assertEqual(set(self.records), set(range(256, 262)))
        self.assertTrue(json.loads(self.report.read_text())['complete'])

    def test_failed_units_or_unreached_target_refuse_before_mounting(self):
        for field, value in [('failed_units', 'failed.service'), ('target_active', False)]:
            setattr(self, field, value)
            with self.assertRaises(ValueError):
                self.invoke(apply=True)
            self.assertEqual(self.commands, [])
            setattr(self, field, '' if field == 'failed_units' else True)

    def test_device_errors_refuse_before_mounting(self):
        self.fail_command = lambda args: args[:3] == ('btrfs', 'device', 'stats')
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke(apply=True)
        self.assertEqual(len(self.commands), 1)
        self.assertEqual(self.deletions(), [])

    def test_invalid_template_refuses_and_unmounts(self):
        self.blank_readonly = False
        with self.assertRaisesRegex(ValueError, 'not read-only'):
            self.invoke(apply=True)
        self.assertEqual(self.deletions(), [])
        self.assertEqual(self.commands[-1], ('umount', str(self.top)))

    def test_missing_protected_subvolume_or_changed_mount_refuses_and_unmounts(self):
        for failure in ['missing', 'mount']:
            with self.subTest(failure=failure):
                saved = self.records.pop(258) if failure == 'missing' else None
                self.wrong_mount = failure == 'mount'
                with self.assertRaises(ValueError):
                    self.invoke(apply=True)
                self.assertEqual(self.deletions(), [])
                self.assertEqual(self.commands[-1], ('umount', str(self.top)))
                if saved:
                    self.records[258] = saved

    def test_unexpected_file_or_symlink_in_old_roots_refuses(self):
        unexpected = self.top / OLD / 'unexpected'
        for kind in ['file', 'symlink']:
            with self.subTest(kind=kind):
                if kind == 'file':
                    unexpected.write_text('keep me')
                else:
                    unexpected.symlink_to(self.top / OLD / BOOT, target_is_directory=True)
                with self.assertRaisesRegex(ValueError, 'non-directory or symlink'):
                    self.invoke(apply=True)
                self.assertEqual(self.deletions(), [])
                unexpected.unlink()

    def test_partial_failure_records_progress_unmounts_and_can_retry(self):
        self.fail_command = lambda args: args[:3] == ('btrfs', 'subvolume', 'delete') and args[-2] == '300'
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke(apply=True)
        report = json.loads(self.report.read_text())
        self.assertEqual(report['deleted_ids'], [301])
        self.assertFalse(report['complete'])
        self.assertEqual(self.commands[-1], ('umount', str(self.top)))
        self.fail_command = None
        self.invoke(apply=True)
        self.assertEqual(json.loads(self.report.read_text())['deleted_ids'], [300])

    def test_target_mounted_after_planning_is_not_deleted(self):
        self.mount_after_planning = True
        with self.assertRaisesRegex(ValueError, 'Target became mounted'):
            self.invoke(apply=True)
        self.assertEqual(self.deletions(), [])

    def test_private_namespace_mount_rejects_entire_plan(self):
        for identifier in [300, 301]:
            with self.subTest(identifier=identifier):
                self.foreign_mounted = {identifier}
                with self.assertRaisesRegex(ValueError, 'protected or mounted'):
                    self.invoke(apply=True, use_namespace_probe=True)
                self.assertEqual(self.deletions(), [])
                self.assertEqual(self.commands[-1], ('umount', str(self.top)))

    def test_target_mounted_privately_after_planning_is_not_deleted(self):
        self.mount_after_planning = True
        with self.assertRaisesRegex(ValueError, 'Target became mounted'):
            self.invoke(apply=True, use_namespace_probe=True)
        self.assertEqual(self.deletions(), [])

    def test_namespace_inspection_failure_prevents_deletion_and_unmounts(self):
        self.namespace_failure = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke(apply=True, use_namespace_probe=True)
        self.assertEqual(self.deletions(), [])
        self.assertEqual(self.commands[-1], ('umount', str(self.top)))

    def test_report_failure_stops_deletion_and_retry_reconciles_inventory(self):
        real_report = cleanup.write_report
        calls = 0
        def report(path, state):
            nonlocal calls
            calls += 1
            if calls == 2:
                def interrupted_dump(report, stream, **kwargs):
                    stream.write('{')
                    raise OSError('interrupted progress write')
                with patch.object(cleanup.json, 'dump', side_effect=interrupted_dump):
                    real_report(path, state)
            else:
                real_report(path, state)
        with patch.object(cleanup, 'write_report', side_effect=report):
            with self.assertRaisesRegex(OSError, 'interrupted progress write'):
                self.invoke(apply=True)
        state = json.loads(self.report.read_text())
        self.assertFalse(state['complete'])
        self.assertEqual(state['deleted_ids'], [])
        self.assertNotIn(301, self.records)
        self.assertIn(300, self.records)
        self.assertEqual(self.commands[-1], ('umount', str(self.top)))
        self.invoke(apply=True)
        self.assertTrue(json.loads(self.report.read_text())['complete'])

    def test_layout_rejects_unsafe_paths_and_duplicate_names(self):
        for mount, name in [('/home/../nix', 'other'), ('/home/test-user', '../escape'),
                            ('/home/test-user', '@root-blank')]:
            invalid = copy.deepcopy(LAYOUT)
            invalid['mounts'][mount] = name
            self.layout.write_text(json.dumps(invalid))
            with self.assertRaises(ValueError):
                self.invoke(apply=True)
            self.assertEqual(self.commands, [])


if __name__ == '__main__':
    unittest.main()
