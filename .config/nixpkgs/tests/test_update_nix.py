"""Exercise update-nix under sh and Dash with isolated, non-activating commands.

Run with: python3 -m unittest discover -s tests -p 'test_update_nix.py'
Only jq and the shell are real; Nix, host detection, and all updaters are mocked.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "update-nix"
INPUTS = [
    "nixpkgs", "nixpkgs-darwin", "nix-darwin", "home-manager",
    "zen-browser", "codex-desktop-linux", "llm-agents", "fresh-input",
]
PSEUDOS = {
    "obsidian-headless": "packages/obsidian-headless/update.sh",
    "model-benchmarks": (
        "modules/home-manager/profiles/development/ai-skills/model-selection/update.sh"
    ),
}

# The fake metadata deliberately uses a non-default root node and a fresh input
# absent from the on-disk lock. This catches accidental stale-lock discovery.
FAKE_COMMAND = r'''
import json
import os
from pathlib import Path
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
if name in ("uname", "whoami", "hostname", "ps"):
    values = {
        "uname": os.environ["TEST_SYSTEM"],
        "whoami": os.environ["TEST_USER"],
        "hostname": "arbitrary-host-492",
        "ps": os.environ.get("TEST_PARENT", "zsh"),
    }
    print(values[name])
    sys.exit(0)

if name == "nix":
    stage = args[1] if args[0] == "flake" else args[0]
elif name == "update.sh":
    stage = "obsidian-headless" if "obsidian-headless" in sys.argv[0] else "model-benchmarks"
else:
    stage = "activate"
with open(os.environ["TEST_LOG"], "a") as log:
    log.write(json.dumps({"stage": stage, "command": name, "args": args}) + "\n")
if stage == os.environ.get("TEST_FAIL"):
    print("simulated " + stage + " failure", file=sys.stderr)
    sys.exit(42)

if stage == "metadata":
    inputs = json.loads(os.environ["TEST_INPUTS"])
    print(json.dumps({"locks": {"root": "flake-root", "nodes": {
        "flake-root": {"inputs": {key: key for key in inputs}},
    }}}))
elif stage == "eval":
    print(os.environ["TEST_CONFIGS"])
elif stage == "lock":
    lock = Path(os.environ["HOME"]) / ".config/nixpkgs/flake.lock"
    lock.write_text('{"updated_by_mock": true}\n')
'''


class UpdateNixScenarios:
    """Behavioral cases shared by the supported shell executables."""

    def setUp(self):
        jq = shutil.which("jq")
        if jq is None:
            self.skipTest("jq is required by update-nix")
        self.temp = tempfile.TemporaryDirectory(prefix="update-nix-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home with spaces"
        self.flake = self.home / ".config/nixpkgs"
        self.flake.mkdir(parents=True)
        (self.flake / "flake.nix").write_text("{}\n")
        self.lock = self.flake / "flake.lock"
        self.original_lock = '{"nodes":{"root":{"inputs":{"stale-input":"stale"}}}}\n'
        self.lock.write_text(self.original_lock)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "commands.jsonl"
        self.env = os.environ.copy()
        for key in ("SSH_CLIENT", "SSH_TTY", "NIX_FLAGS"):
            self.env.pop(key, None)
        self.env.update({
            "HOME": str(self.home),
            "PATH": str(self.bin),
            "TEST_LOG": str(self.log),
            "TEST_SYSTEM": "Linux",
            "TEST_USER": "toma",
            "TEST_INPUTS": json.dumps(INPUTS),
            "TEST_CONFIGS": json.dumps([
                "arbitrary-host-492", "toma@server", "toma@work", "tommoa@personal",
                "custom@server", 'config with "quotes"',
            ]),
        })
        for name in ("nix", "uname", "whoami", "hostname", "ps", "sudo", "home-manager"):
            self.make_command(self.bin / name)
        (self.bin / "jq").symlink_to(jq)
        (self.bin / "cat").symlink_to(shutil.which("cat"))
        (self.bin / "tr").symlink_to(shutil.which("tr"))
        for relative in PSEUDOS.values():
            self.make_command(self.flake / relative)

    def make_command(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!" + sys.executable + "\n" + FAKE_COMMAND)
        path.chmod(0o755)

    def run_script(self, *args, success=True):
        self.log.write_text("")
        self.result = subprocess.run(
            [self.shell, str(SCRIPT), *args], env=self.env,
            capture_output=True, text=True, timeout=15,
        )
        self.events = [json.loads(line) for line in self.log.read_text().splitlines()]
        output = self.result.stdout + self.result.stderr
        if success:
            self.assertEqual(self.result.returncode, 0, output)
        else:
            self.assertNotEqual(self.result.returncode, 0, output)
        return output

    def stages(self):
        return [event["stage"] for event in self.events]

    def selected_inputs(self):
        updates = [event for event in self.events if event["stage"] == "update"]
        self.assertLessEqual(len(updates), 1)
        if not updates:
            return set()
        return set(updates[0]["args"]) & set(INPUTS)

    def assert_no_updates(self):
        self.assertFalse(set(self.stages()) & {"lock", "update", "activate", *PSEUDOS})
        self.assertEqual(self.lock.read_text(), self.original_lock)

    def test_system_default_includes_integrated_home_only_once(self):
        for platform, rebuild in (("Darwin", "darwin-rebuild"), ("Linux", "nixos-rebuild")):
            with self.subTest(platform=platform):
                self.env["TEST_SYSTEM"] = platform
                self.make_command(self.bin / rebuild)
                self.run_script()
                activations = [e for e in self.events if e["stage"] == "activate"]
                self.assertEqual(len(activations), 1)
                self.assertEqual(activations[0]["command"], "sudo")
                self.assertEqual(activations[0]["args"][0], rebuild)
                self.assertIn(str(self.flake) + "#arbitrary-host-492", activations[0]["args"])
                excluded = {"codex-desktop-linux"} if platform == "Darwin" else {"nix-darwin", "nixpkgs-darwin"}
                self.assertEqual(self.selected_inputs(), set(INPUTS) - excluded)
                self.assertFalse(set(self.stages()) & set(PSEUDOS))
                (self.bin / rebuild).unlink()

    def test_ssh_server_detection_does_not_depend_on_hostname(self):
        for signal in ("SSH_CLIENT", "SSH_TTY", "TEST_PARENT"):
            with self.subTest(signal=signal):
                self.env[signal] = "sshd" if signal == "TEST_PARENT" else "present"
                self.run_script()
                self.assertIn(str(self.flake) + "#toma@server", self.events[-1]["args"])
                self.assertEqual(self.selected_inputs(), set(INPUTS) - {
                    "nixpkgs-darwin", "nix-darwin", "zen-browser", "codex-desktop-linux",
                })
                self.env.pop(signal)

    def test_local_user_defaults(self):
        for user, config in (("toma", "toma@work"), ("tommoa", "tommoa@personal")):
            with self.subTest(user=user):
                self.env["TEST_USER"] = user
                self.run_script("--none")
                self.assertIn(str(self.flake) + "#" + config, self.events[-1]["args"])

    def test_system_without_home_manager_cli(self):
        (self.bin / "home-manager").unlink()
        self.make_command(self.bin / "nixos-rebuild")
        self.run_script("--none")
        self.assertEqual(self.events[-1]["args"][0], "nixos-rebuild")

    def test_server_substring_filter_is_preserved(self):
        self.env["TEST_CONFIGS"] = json.dumps(["toma@server-special"])
        self.run_script("home", "toma@server-special")
        self.assertNotIn("zen-browser", self.selected_inputs())
        self.assertNotIn("codex-desktop-linux", self.selected_inputs())

    def test_explicit_home_and_config_override(self):
        self.make_command(self.bin / "nixos-rebuild")
        self.run_script("home", "custom@server")
        self.assertEqual(self.events[-1]["command"], "home-manager")
        self.assertIn(str(self.flake) + "#custom@server", self.events[-1]["args"])
        self.assertNotIn("zen-browser", self.selected_inputs())

    def test_quoted_config_name_is_passed_intact(self):
        self.run_script("home", 'config with "quotes"', "--none")
        self.assertIn(str(self.flake) + '#config with "quotes"', self.events[-1]["args"])

    def test_explicit_include_overrides_server_and_platform_defaults(self):
        self.env["SSH_TTY"] = "present"
        self.run_script("--zen-browser", "--nix-darwin")
        self.assertIn("zen-browser", self.selected_inputs())
        self.assertIn("nix-darwin", self.selected_inputs())

    def test_exclusion_wins_regardless_of_order_or_repetition(self):
        for flags in (
            ("--no-nixpkgs", "--nixpkgs"),
            ("--nixpkgs", "--no-nixpkgs"),
            ("--no-nixpkgs", "--nixpkgs", "--no-nixpkgs", "--nixpkgs"),
        ):
            with self.subTest(flags=flags):
                output = self.run_script(*flags)
                self.assertNotIn("nixpkgs", self.selected_inputs())
                self.assertIn("WARNING", output)

    def test_none_wins_over_all_but_explicit_include_still_works(self):
        for flags in (("--all", "--none"), ("--none", "--all")):
            with self.subTest(flags=flags):
                output = self.run_script(*flags, "--fresh-input")
                self.assertEqual(self.selected_inputs(), {"fresh-input"})
                self.assertFalse(set(self.stages()) & set(PSEUDOS))
                self.assertIn("WARNING", output)

    def test_all_bypasses_filters_and_runs_pseudos_before_activation(self):
        self.env["SSH_TTY"] = "present"
        self.run_script("--all", "--no-nixpkgs")
        self.assertEqual(self.selected_inputs(), set(INPUTS) - {"nixpkgs"})
        stages = self.stages()
        for pseudo in PSEUDOS:
            self.assertEqual(stages.count(pseudo), 1)
            self.assertLess(stages.index("update"), stages.index(pseudo))
            self.assertLess(stages.index(pseudo), stages.index("activate"))

    def test_none_reconciles_lock_but_does_not_refresh_inputs(self):
        self.run_script("--none")
        self.assertIn("lock", self.stages())
        self.assertNotIn("update", self.stages())
        self.assertFalse(set(self.stages()) & set(PSEUDOS))
        self.assertEqual(self.stages()[-1], "activate")

    def test_pseudo_only_refresh(self):
        for pseudo in PSEUDOS:
            with self.subTest(pseudo=pseudo):
                self.run_script("--none", "--" + pseudo)
                self.assertNotIn("update", self.stages())
                self.assertEqual(set(self.stages()) & set(PSEUDOS), {pseudo})
                self.assertLess(self.stages().index(pseudo), self.stages().index("activate"))

    def test_explicit_pseudo_exclusion_wins_over_all_and_include(self):
        self.run_script("--all", "--no-model-benchmarks", "--model-benchmarks")
        self.assertNotIn("model-benchmarks", self.stages())
        self.assertIn("obsidian-headless", self.stages())

    def test_custom_nix_flags_are_forwarded(self):
        self.env["NIX_FLAGS"] = "--option sandbox false"
        self.run_script("--none")
        for event in self.events:
            if event["command"] in ("nix", "home-manager"):
                args = event["args"]
                self.assertIn("--option", args)
                offset = args.index("--option")
                self.assertEqual(args[offset:offset + 3], ["--option", "sandbox", "false"])

    def test_preflight_discovers_fresh_input_without_writing_lock(self):
        self.run_script("--none", "--fresh-input")
        self.assertEqual(self.selected_inputs(), {"fresh-input"})
        for event in self.events:
            if event["stage"] in ("metadata", "eval"):
                self.assertIn("--no-write-lock-file", event["args"])
                self.assertLess(self.stages().index(event["stage"]), self.stages().index("lock"))

    def test_bad_arguments_and_unknown_resources_fail_before_updates(self):
        for args in (("both",), ("invalid",), ("home", "toma@work", "extra"),
                     ("--",), ("--no-",),
                     ("--missing-input",), ("--no-missing-input",),
                     ("home", "missing-config"), ("system",)):
            with self.subTest(args=args):
                self.run_script(*args, success=False)
                self.assert_no_updates()

    def test_no_available_target_fails_before_updates(self):
        (self.bin / "home-manager").unlink()
        self.run_script(success=False)
        self.assert_no_updates()

    def test_missing_selected_updater_fails_before_updates(self):
        (self.flake / PSEUDOS["model-benchmarks"]).unlink()
        self.run_script("--all", success=False)
        self.assert_no_updates()

    def test_preflight_failures_do_not_mutate_lock(self):
        for stage in ("metadata", "eval"):
            with self.subTest(stage=stage):
                self.env["TEST_FAIL"] = stage
                self.run_script(success=False)
                self.assert_no_updates()

    def test_update_failures_stop_later_actions(self):
        for stage in ("lock", "update", "obsidian-headless", "model-benchmarks"):
            with self.subTest(stage=stage):
                self.env["TEST_FAIL"] = stage
                self.run_script("--all", success=False)
                self.assertEqual(self.stages()[-1], stage)
                self.assertNotIn("activate", self.stages())

    def test_activation_failure_propagates(self):
        self.env["TEST_FAIL"] = "activate"
        output = self.run_script("--none", success=False)
        self.assertNotIn("SUCCESS", output)

    def test_help_needs_no_available_commands(self):
        for name in ("nix", "home-manager", "uname", "whoami", "hostname", "jq"):
            (self.bin / name).unlink()
        output = self.run_script("--help")
        self.assertIn("Usage:", output)
        self.assertEqual(self.events, [])


class ShTests(UpdateNixScenarios, unittest.TestCase):
    shell = "/bin/sh"


@unittest.skipUnless(shutil.which("dash"), "Dash is not installed")
class DashTests(UpdateNixScenarios, unittest.TestCase):
    shell = shutil.which("dash")


if __name__ == "__main__":
    unittest.main()
