"""Check T3 settings updates preserve existing preferences and files."""

import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(os.environ.get(
    "T3CODE_SETTINGS",
    Path(__file__).resolve().parents[1] / "modules/home-manager/profiles/development/ai-tools/t3code-settings.py",
))
spec = importlib.util.spec_from_file_location("t3_settings", SCRIPT)
t3_settings = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t3_settings)


class T3LocalSettingsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.baseline = self.root / "generation-one.json"
        self.defaults = {
            "userSettings": {
                "defaultTheme": "one-dark",
                "defaultModelSelection": {"instanceId": "codex", "model": "work-model"},
                "providerInstances": {"codex": {"config": {"binaryPath": "/nix/store/wrapped-codex"}}},
            },
            "clientSettings": {"fontSizeInterface": 16},
            "modelSettings": {
                "defaultModelSelection": {
                    "instanceId": "codex", "model": "work-model",
                    "options": [{"id": "reasoningEffort", "value": "high"}],
                },
            },
            "theme": {"name": "One Dark", "appearance": "dark"},
        }
        self.baseline.write_text(json.dumps(self.defaults))
        self.shared_settings = self.root / "managed-settings.json"
        self.shared_settings.symlink_to(self.baseline)
        self.directory = self.root / ".t3/userdata"

    def test_activation_is_idempotent_and_does_not_reset_runtime_edits(self):
        t3_settings.bootstrap(self.directory, self.shared_settings)
        settings = self.directory / "settings.json"
        edited = json.loads(settings.read_text())
        edited["defaultTheme"] = "user-theme"
        settings.write_text(json.dumps(edited))
        t3_settings.bootstrap(self.directory, self.shared_settings)
        self.assertEqual(json.loads(settings.read_text())["defaultTheme"], "user-theme")

    def test_new_generation_merges_defaults_and_keeps_unmanaged_model_options(self):
        t3_settings.bootstrap(self.directory, self.shared_settings)
        settings_path = self.directory / "settings.json"
        settings = json.loads(settings_path.read_text())
        settings["unmanaged"] = True
        settings["defaultTheme"] = "user-theme"
        settings["defaultModelSelection"]["options"].append({"id": "serviceTier", "value": "fast"})
        settings_path.write_text(json.dumps(settings))
        client_path = self.directory / "client-settings.json"
        client_path.write_text(json.dumps({"fontSizeInterface": 12, "sidebarWidth": 300}))
        new_baseline = self.root / "generation-two.json"
        self.defaults["clientSettings"]["fontSizeInterface"] = 18
        new_baseline.write_text(json.dumps(self.defaults))
        self.shared_settings.unlink()
        self.shared_settings.symlink_to(new_baseline)
        t3_settings.bootstrap(self.directory, self.shared_settings)
        settings = json.loads(settings_path.read_text())
        self.assertTrue(settings["unmanaged"])
        self.assertEqual(settings["defaultTheme"], "one-dark")
        self.assertIn({"id": "serviceTier", "value": "fast"}, settings["defaultModelSelection"]["options"])
        self.assertEqual(json.loads(client_path.read_text()), {"fontSizeInterface": 18, "sidebarWidth": 300})

    def test_switching_provider_discards_the_previous_providers_options(self):
        self.directory.mkdir(parents=True)
        (self.directory / "settings.json").write_text(json.dumps({
            "defaultModelSelection": {
                "instanceId": "opencode", "model": "old-model",
                "options": [{"id": "opencode-only", "value": True}],
            },
        }))
        t3_settings.bootstrap(self.directory, self.shared_settings)
        selection = json.loads((self.directory / "settings.json").read_text())["defaultModelSelection"]
        self.assertEqual(selection, self.defaults["modelSettings"]["defaultModelSelection"])

    def test_malformed_client_settings_leave_all_settings_and_marker_unchanged(self):
        self.directory.mkdir(parents=True)
        (self.directory / "settings.json").write_text('{"custom": true}')
        (self.directory / "client-settings.json").write_text("invalid json")
        with self.assertRaises(ValueError):
            t3_settings.bootstrap(self.directory, self.shared_settings)
        self.assertEqual((self.directory / "settings.json").read_text(), '{"custom": true}')
        self.assertFalse((self.directory / ".managed-settings-source").exists())

if __name__ == "__main__":
    unittest.main()
