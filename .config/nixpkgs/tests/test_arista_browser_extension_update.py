"""Exercise the Arista extension updater without Gerrit, AMO, or Nix writes."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "packages/arista-browser-extension/update.sh"
)
CURRENT_REV = "a" * 40
LATEST_REV = "b" * 40
CURRENT_HASH = "sha256-current-signed-xpi"
NEW_HASH = "sha256-new-signed-xpi"


FAKE_COMMAND = r'''
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["TEST_LOG"], "a") as log:
    log.write(json.dumps({"command": name, "args": args}) + "\n")

if name == "git":
    print(os.environ["TEST_REMOTE_REV"] + "\trefs/heads/main")
elif name == "nix":
    if args[0] == "shell":
        command = args[args.index("--command") + 1:]
        sys.exit(subprocess.run(command, env=os.environ).returncode)
    elif args[:2] == ["store", "prefetch-file"]:
        print(json.dumps({
            "hash": "sha256-new-source",
            "storePath": os.environ["TEST_SOURCE"],
        }))
    elif args[:2] == ["hash", "file"]:
        print(os.environ["TEST_SIGNED_HASH"])
    elif args[0] == "build" and "--print-out-paths" in args:
        if os.environ.get("TEST_UNSIGNED_BUILD_FAIL") == "1":
            sys.exit(41)
        print(os.environ["TEST_UNSIGNED"])
    elif args[0] == "build" and os.environ.get("TEST_FINAL_BUILD_FAIL") == "1":
        sys.exit(42)
elif name == "nix-store":
    print("/nix/store/fake-arista-browser-extension.xpi")
elif name == "prefetch-npm-deps":
    print("sha256-new-npm-deps")
elif name == "node":
    amo_result = os.environ.get("TEST_AMO_RESULT", "missing")
    if amo_result == "success":
        Path(args[3]).write_bytes(b"amo-signed-xpi")
    elif amo_result == "missing":
        # Only a definite AMO miss permits a new signing submission.
        sys.exit(44)
    else:
        sys.exit(2)
elif name == "web-ext":
    artifacts = Path(args[args.index("--artifacts-dir") + 1])
    artifacts.mkdir(parents=True, exist_ok=True)
    (artifacts / "signed.xpi").write_bytes(b"signed-xpi")
elif name == "unzip":
    if "-qq" in args:
        destination = Path(args[args.index("-d") + 1])
        shutil.copytree(
            Path(os.environ["TEST_UNSIGNED"]) / "unpacked",
            destination,
            dirs_exist_ok=True,
        )
else:
    raise SystemExit("unexpected fake command: " + name)
'''


class AristaUpdaterTests(unittest.TestCase):
    def setUp(self):
        if shutil.which("jq") is None:
            self.skipTest("jq is required by the updater")

        self.temp = tempfile.TemporaryDirectory(prefix="arista-updater-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.flake = self.root / "flake"
        self.package = self.flake / "packages/arista-browser-extension"
        self.package.mkdir(parents=True)
        self.metadata = self.package / "metadata.json"
        self.original_metadata = {
            "addonId": "arista-browser-extension@test.invalid",
            "displayName": "Arista Browser Extension (Test)",
            "npmDepsHash": "sha256-current-npm-deps",
            "rev": CURRENT_REV,
            "signedXpiHash": CURRENT_HASH,
            "sourceHash": "sha256-current-source",
            "upstreamVersion": "0.0.63",
        }
        self.metadata.write_text(json.dumps(self.original_metadata, indent=2) + "\n")

        self.source = self.root / "source"
        (self.source / "src").mkdir(parents=True)
        (self.source / "src/manifest.ts").write_text('  version: "0.0.64",\n')
        (self.source / "package-lock.json").write_text("{}\n")

        self.unsigned = self.root / "unsigned"
        (self.unsigned / "unpacked").mkdir(parents=True)
        (self.unsigned / "unpacked/manifest.json").write_text(
            '{"version":"0.0.64"}\n'
        )
        (self.unsigned / "source.zip").write_bytes(b"source")

        amo = self.home / ".config/amo"
        amo.mkdir(parents=True)
        (amo / "api-key").write_text("key\n")
        (amo / "api-secret").write_text("secret\n")

        self.bin = self.root / "bin"
        self.bin.mkdir()
        for command in (
            "git",
            "nix",
            "nix-store",
            "node",
            "prefetch-npm-deps",
            "unzip",
            "web-ext",
        ):
            path = self.bin / command
            path.write_text("#!" + sys.executable + "\n" + FAKE_COMMAND)
            path.chmod(0o755)

        self.log = self.root / "commands.jsonl"
        self.env = os.environ.copy()
        self.env.update(
            {
                "ARISTA_EXTENSION_FLAKE_DIR": str(self.flake),
                "HOME": str(self.home),
                "PATH": str(self.bin) + os.pathsep + self.env["PATH"],
                "TEST_LOG": str(self.log),
                "TEST_REMOTE_REV": CURRENT_REV,
                "TEST_SIGNED_HASH": NEW_HASH,
                "TEST_SOURCE": str(self.source),
                "TEST_UNSIGNED": str(self.unsigned),
            }
        )

    def run_updater(self, *args, success=True, script=SCRIPT):
        self.log.write_text("")
        result = subprocess.run(
            ["/bin/bash", str(script), *args],
            env=self.env,
            cwd=self.home,
            capture_output=True,
            text=True,
            timeout=15,
        )
        output = result.stdout + result.stderr
        if success:
            self.assertEqual(result.returncode, 0, output)
        else:
            self.assertNotEqual(result.returncode, 0, output)
        self.events = [
            json.loads(line) for line in self.log.read_text().splitlines()
        ]
        return output

    def test_check_reports_current_without_writes_or_credentials(self):
        shutil.rmtree(self.home / ".config/amo")
        output = self.run_updater("--check")

        self.assertIn("is current", output)
        self.assertEqual([event["command"] for event in self.events], ["git"])
        self.assertEqual(json.loads(self.metadata.read_text()), self.original_metadata)

    def test_check_finds_flake_relative_to_script_from_another_directory(self):
        script = self.package / "update.sh"
        shutil.copyfile(SCRIPT, script)
        self.env.pop("ARISTA_EXTENSION_FLAKE_DIR")

        output = self.run_updater("--check", script=script)

        self.assertIn("is current", output)
        self.assertEqual([event["command"] for event in self.events], ["git"])
        self.assertEqual(json.loads(self.metadata.read_text()), self.original_metadata)

    def test_check_reports_new_revision_without_prefetching_or_signing(self):
        self.env["TEST_REMOTE_REV"] = LATEST_REV
        output = self.run_updater("--check")

        self.assertIn("selected Arista Browser Extension revision differs", output)
        self.assertIn(LATEST_REV, output)
        self.assertEqual([event["command"] for event in self.events], ["git"])
        self.assertEqual(json.loads(self.metadata.read_text()), self.original_metadata)

    def test_current_revision_reuses_retained_artifact(self):
        artifact = (
            self.home
            / ".local/share/arista-browser-extension"
            / "arista-browser-extension-0.0.63.xpi"
        )
        artifact.parent.mkdir(parents=True)
        artifact.write_bytes(b"current-xpi")
        self.env["TEST_SIGNED_HASH"] = CURRENT_HASH

        output = self.run_updater()

        self.assertIn("already current", output)
        commands = [event["command"] for event in self.events]
        self.assertEqual(commands, ["git", "unzip", "nix", "nix-store"])
        self.assertEqual(json.loads(self.metadata.read_text()), self.original_metadata)

    def test_current_revision_recovers_missing_artifact_from_amo(self):
        self.env["TEST_AMO_RESULT"] = "success"
        self.env["TEST_SIGNED_HASH"] = CURRENT_HASH

        output = self.run_updater()

        self.assertIn("Recovered Arista Browser Extension 0.0.63 from AMO", output)
        commands = [event["command"] for event in self.events]
        self.assertIn("node", commands)
        self.assertNotIn("web-ext", commands)
        artifact = (
            self.home
            / ".local/share/arista-browser-extension"
            / "arista-browser-extension-0.0.63.xpi"
        )
        self.assertTrue(artifact.is_file())
        self.assertEqual(json.loads(self.metadata.read_text()), self.original_metadata)

    def test_update_records_hash_and_validates_package_outputs(self):
        self.env["TEST_REMOTE_REV"] = LATEST_REV
        output = self.run_updater()

        self.assertIn("Updated Arista Browser Extension to 0.0.64", output)
        updated = json.loads(self.metadata.read_text())
        self.assertEqual(updated["rev"], LATEST_REV)
        self.assertEqual(updated["upstreamVersion"], "0.0.64")
        self.assertEqual(updated["sourceHash"], "sha256-new-source")
        self.assertEqual(updated["npmDepsHash"], "sha256-new-npm-deps")
        self.assertEqual(updated["signedXpiHash"], NEW_HASH)

        final_build = [
            event
            for event in self.events
            if event["command"] == "nix"
            and event["args"][0] == "build"
            and "--print-out-paths" not in event["args"]
        ]
        self.assertEqual(len(final_build), 1)
        self.assertIn(
            "path:" + str(self.flake) + "#arista-browser-extension-signed",
            final_build[0]["args"],
        )
        self.assertFalse(
            any("darwinConfigurations" in arg for arg in final_build[0]["args"])
        )

        tools = [
            event["args"] for event in self.events
            if event["command"] == "nix" and event["args"][0] == "shell"
        ]
        self.assertEqual([args[3] for args in tools], [
            "nixpkgs#prefetch-npm-deps", "nixpkgs#nodejs_22", "nixpkgs#web-ext",
        ])
        self.assertTrue(all(
            args[1:3] == ["--inputs-from", "path:" + str(self.flake)]
            for args in tools
        ))
        unsigned_build = next(
            i for i, event in enumerate(self.events)
            if event["command"] == "nix"
            and event["args"][0] == "build"
            and "--print-out-paths" in event["args"]
        )
        signing = next(
            i for i, event in enumerate(self.events)
            if event["command"] == "web-ext"
        )
        self.assertLess(unsigned_build, signing)

    def test_revision_without_newer_version_does_not_load_build_tools(self):
        self.env["TEST_REMOTE_REV"] = LATEST_REV
        (self.source / "src/manifest.ts").write_text('  version: "0.0.63",\n')

        output = self.run_updater(success=False)

        self.assertIn("does not advance signed version", output)
        self.assertFalse(any(
            event["command"] == "nix"
            and event["args"][0] in ("shell", "build")
            for event in self.events
        ))
        self.assertEqual(json.loads(self.metadata.read_text()), self.original_metadata)

    def test_unsigned_build_failure_restores_metadata_without_signing(self):
        self.env["TEST_REMOTE_REV"] = LATEST_REV
        self.env["TEST_UNSIGNED_BUILD_FAIL"] = "1"

        self.run_updater(success=False)

        self.assertEqual(json.loads(self.metadata.read_text()), self.original_metadata)
        self.assertNotIn("web-ext", [event["command"] for event in self.events])
        self.assertNotIn("node", [event["command"] for event in self.events])

    def test_final_validation_failure_restores_metadata(self):
        self.env["TEST_REMOTE_REV"] = LATEST_REV
        self.env["TEST_FINAL_BUILD_FAIL"] = "1"

        output = self.run_updater(success=False)

        self.assertIn("Targeted validation failed", output)
        self.assertEqual(json.loads(self.metadata.read_text()), self.original_metadata)

    def test_transient_amo_failure_does_not_attempt_signing(self):
        self.env["TEST_REMOTE_REV"] = LATEST_REV
        self.env["TEST_AMO_RESULT"] = "error"

        self.run_updater(success=False)

        commands = [event["command"] for event in self.events]
        self.assertIn("node", commands)
        self.assertNotIn("web-ext", commands)
        self.assertEqual(json.loads(self.metadata.read_text()), self.original_metadata)


if __name__ == "__main__":
    unittest.main()
