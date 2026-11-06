#!/usr/bin/env python3
"""Exercise real just recipes with external tools replaced by argv recorders."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RECORDER = """#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
with open(os.environ['COMMAND_LOG'], 'a') as log:
    log.write(json.dumps([name, *sys.argv[1:]]) + '\\n')
if name == 'nix' and sys.argv[1] == 'eval':
    print(os.environ.get('STRICT', 'false'))
if name == 'nix' and sys.argv[1] == 'run':
    sys.exit(int(os.environ.get('DEPLOY_EXIT', '0')))
if name == os.environ.get('FAIL_COMMAND'):
    sys.exit(17)
"""


class CommandSurface(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for source in [
            ROOT / "justfile",
            *ROOT.glob(".just/*.just"),
            ROOT / "opentofu/justfile",
            ROOT / "secrets/justfile",
        ]:
            destination = self.root / source.relative_to(ROOT)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
        for path in [
            "bin/nix",
            "bin/ssh",
            "bin/tofu",
            "scripts/export-web-services-policy.sh",
            "tests/check-web-services-policy.sh",
            "scripts/render-opentofu-cloudflare-runtime.sh",
        ]:
            destination = self.root / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(RECORDER)
            destination.chmod(0o755)
        self.log = self.root / "commands.jsonl"
        self.env = {
            **os.environ,
            "PATH": f"{self.root / 'bin'}:{os.environ['PATH']}",
            "COMMAND_LOG": str(self.log),
            "STRICT": "false",
            "DEPLOY_EXIT": "0",
            "FAIL_COMMAND": "",
        }

    def run_just(self, *args, **env):
        result = subprocess.run(
            ["just", *args],
            cwd=self.root,
            env={**self.env, **env},
            text=True,
            capture_output=True,
        )
        self.commands = [json.loads(line) for line in self.log.read_text().splitlines()]
        return result

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_deploy_native_flags_and_nix_argument_boundaries(self):
        self.assert_success(
            self.run_just(
                "deploy",
                "home-forge",
                "--debug-logs",
                "--auto-rollback",
                "false",
                "--",
                "--option",
                "builders",
                "remote builder; $(not-a-command)",
            )
        )
        self.assertEqual(
            self.commands[1],
            [
                "nix",
                "run",
                ".#deploy-rs",
                "--",
                "--skip-checks",
                "--debug-logs",
                "--auto-rollback",
                "false",
                ".#home-forge",
                "--",
                "--option",
                "builders",
                "remote builder; $(not-a-command)",
            ],
        )

    def test_strict_deploy_preserves_build_restrictions_and_exit_status(self):
        result = self.run_just(
            "deploy", "oci-melb-1", "--", "-v", STRICT="true", DEPLOY_EXIT="23"
        )
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(
            self.commands[1][-8:],
            ["--", "-v", "--option", "max-jobs", "0", "--option", "builders", ""],
        )
        self.assertIn("warning", self.commands[2])

    def test_default_deploy_does_not_disable_rollback(self):
        self.assert_success(self.run_just("deploy"))
        self.assertEqual(
            self.commands[1],
            ["nix", "run", ".#deploy-rs", "--", "--skip-checks", ".#la-admin-1"],
        )

    def test_host_passthrough(self):
        self.assert_success(self.run_just("host", "home-forge", "--dry-activate"))
        self.assertEqual(
            self.commands[0],
            [
                "nix",
                "run",
                ".#deploy-rs",
                "--",
                "--skip-checks",
                ".#home-forge",
                "--dry-activate",
            ],
        )

    def test_tofu_init_and_plan_passthrough(self):
        for command in ["init", "plan"]:
            with self.subTest(command=command):
                self.assert_success(
                    self.run_just(f"tofu::{command}", "-lock-timeout=30s")
                )
                self.assertEqual(self.commands[-1][-1], "-lock-timeout=30s")
                self.assertEqual(self.commands[-1][2], command)

    def test_tofu_apply_sync_and_argument_boundaries(self):
        self.assert_success(
            self.run_just(
                "tofu::apply",
                "-auto-approve",
                "--sync",
                "-var=label=two words; $(not-a-command)",
            )
        )
        self.assertEqual(
            [cmd[0] for cmd in self.commands],
            [
                "export-web-services-policy.sh",
                "check-web-services-policy.sh",
                "render-opentofu-cloudflare-runtime.sh",
                "tofu",
                "tofu",
            ],
        )
        self.assertEqual(
            self.commands[-1],
            [
                "tofu",
                "-chdir=opentofu/cloudflare",
                "apply",
                "-auto-approve",
                "-var=label=two words; $(not-a-command)",
            ],
        )

    def test_tofu_apply_without_sync(self):
        self.assert_success(self.run_just("tofu::apply", "saved plan"))
        self.assertEqual(
            [cmd[0] for cmd in self.commands],
            ["render-opentofu-cloudflare-runtime.sh", "tofu", "tofu"],
        )
        self.assertEqual(self.commands[-1][-1], "saved plan")

    def test_failed_preparation_prevents_apply(self):
        for failed in [
            "check-web-services-policy.sh",
            "render-opentofu-cloudflare-runtime.sh",
            "tofu",
        ]:
            with self.subTest(failed=failed):
                self.log.unlink(missing_ok=True)
                result = self.run_just("tofu::apply", "--sync", FAIL_COMMAND=failed)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(
                    any(
                        cmd[:3] == ["tofu", "-chdir=opentofu/cloudflare", "apply"]
                        for cmd in self.commands
                    )
                )


if __name__ == "__main__":
    unittest.main()
