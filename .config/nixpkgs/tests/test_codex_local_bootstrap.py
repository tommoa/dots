"""Check local Codex bootstrap preserves edits and isolates credentials."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(os.environ.get(
    "CODEX_LOCAL_BOOTSTRAP",
    Path(__file__).resolve().parents[1] / "modules/home-manager/profiles/development/ai-tools/codex-local-bootstrap.sh",
))


class CodexLocalStateTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / "shared-home"
        self.shared = self.home / ".codex"
        self.shared.mkdir(parents=True)
        self.local = self.root / "container-one/.codex"
        self.generation = self.root / "generation-one.toml"
        self.generation.write_text('model = "managed"\n')
        (self.shared / "server-config.toml").symlink_to(self.generation)
        (self.shared / "AGENTS.md").write_text("managed input")
        (self.shared / "skills").mkdir()
        self.wrapper = self.root / "codex-wrapper"
        self.wrapper.write_text("wrapper")
        self.env = dict(os.environ, HOME=str(self.home), CODEX_HOME=str(self.local),
                        CODEX_SQLITE_HOME=str(self.local / "sqlite"))

    def bootstrap(self):
        return subprocess.run(
            ["bash", str(SCRIPT), str(self.wrapper)],
            env=self.env, check=True, capture_output=True, text=True,
        )

    def test_shared_credentials_and_databases_are_not_imported_or_overwrite_local_state(self):
        for name in ("auth.json", "state.sqlite"):
            (self.shared / name).write_text("shared state")
        self.bootstrap()
        for name in ("auth.json", "state.sqlite"):
            self.assertFalse((self.local / name).exists())
            (self.local / name).write_text("host-local state")
        self.bootstrap()
        for name in ("auth.json", "state.sqlite"):
            self.assertEqual((self.local / name).read_text(), "host-local state")

    def test_runtime_edits_survive_until_generation_changes(self):
        self.bootstrap()
        config = self.local / "config.toml"
        self.assertEqual(config.read_text(), self.generation.read_text())
        self.assertFalse(config.is_symlink())
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)
        config.write_text('model = "runtime-edit"\n')
        self.bootstrap()
        self.assertIn("runtime-edit", config.read_text())
        new = self.root / "generation-two.toml"
        new.write_text('model = "new-managed"\n')
        (self.shared / "server-config.toml").unlink()
        (self.shared / "server-config.toml").symlink_to(new)
        self.bootstrap()
        self.assertEqual(config.read_text(), new.read_text())

if __name__ == "__main__":
    unittest.main()
