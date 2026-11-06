#!/usr/bin/env python3
"""Exercise real recipes and orchestration with external tools replaced by argv recorders."""

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
if name == os.environ.get('FAIL_COMMAND'):
    sys.exit(17)
if name == 'nix' and sys.argv[1] == 'eval':
    print(os.environ.get('STRICT', 'false'))
if name == 'nix' and sys.argv[1] == 'run':
    sys.exit(int(os.environ.get('DEPLOY_EXIT', '0')))
if name == 'tofu' and sys.argv[2] == 'state' and os.environ.get('UNSPLIT') == 'true':
    print('cloudflare_zero_trust_access_policy.allow_admins')
if name == 'tofu' and sys.argv[2] == 'output':
    print(json.dumps({'policies': {'allow_machine': 'machine-id'},
                      'allowed_idps': ['idp-id'], 'session_duration': '24h'}))
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
            ROOT / "scripts/cloudflare-tofu.sh",
        ]:
            destination = self.root / source.relative_to(ROOT)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(source, destination)
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
        self.services = self.root / "opentofu/cloudflare"
        self.foundation = self.services / "foundation"
        for directory in [self.services, self.foundation]:
            marker = directory / ".terraform/terraform.tfstate"
            marker.parent.mkdir(parents=True)
            marker.write_text("{}")
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

    def tofu_commands(self):
        return [
            command
            for command in self.commands
            if command[0] == "tofu" and command[2] != "state"
        ]

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

    def test_init_selects_independent_backends_and_passes_arguments(self):
        for flags, directory in [
            ([], self.services),
            (["--foundation"], self.foundation),
        ]:
            with self.subTest(flags=flags):
                self.assert_success(self.run_just("tofu::init", *flags, "-upgrade"))
                command = self.tofu_commands()[-1]
                self.assertEqual(command[:3], ["tofu", f"-chdir={directory}", "init"])
                self.assertEqual(command[-1], "-upgrade")
                self.assertEqual(
                    any(arg.startswith("-backend-config=key=") for arg in command),
                    bool(flags),
                )

    def test_services_apply_reads_foundation_references_without_refreshing_it(self):
        self.assert_success(
            self.run_just(
                "tofu::apply",
                "-auto-approve",
                "--sync",
                "-var=label=two words; $(not-a-command)",
            )
        )
        self.assertEqual(
            [cmd[0] for cmd in self.commands[:3]],
            [
                "export-web-services-policy.sh",
                "check-web-services-policy.sh",
                "render-opentofu-cloudflare-runtime.sh",
            ],
        )
        self.assertEqual(
            self.tofu_commands(),
            [
                [
                    "tofu",
                    f"-chdir={self.foundation}",
                    "output",
                    "-json",
                    "service_access",
                ],
                [
                    "tofu",
                    f"-chdir={self.services}",
                    "apply",
                    "-auto-approve",
                    "-var=label=two words; $(not-a-command)",
                ],
            ],
        )
        refs = json.loads((self.services / "foundation.auto.tfvars.json").read_text())
        self.assertEqual(refs["foundation_access"]["allowed_idps"], ["idp-id"])

    def test_foundation_apply_does_not_apply_services(self):
        self.assert_success(
            self.run_just("tofu::apply", "--foundation", "-parallelism=3")
        )
        self.assertEqual(
            self.tofu_commands(),
            [["tofu", f"-chdir={self.foundation}", "apply", "-parallelism=3"]],
        )

    def test_apply_initializes_only_when_needed(self):
        (self.services / ".terraform/terraform.tfstate").unlink()
        self.assert_success(self.run_just("tofu::apply"))
        commands = self.tofu_commands()
        self.assertEqual(commands[0][2], "init")
        self.assertFalse(any("-reconfigure" in command for command in commands))
        self.assertEqual(sum(command[2] == "init" for command in commands), 1)

    def test_saved_plan_and_separator_are_forwarded(self):
        self.assert_success(self.run_just("tofu::apply", "--", "--foundation"))
        self.assertEqual(
            self.tofu_commands()[-1],
            ["tofu", f"-chdir={self.services}", "apply", "--", "--foundation"],
        )

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
                    any(command[2] == "apply" for command in self.tofu_commands())
                )

    def test_unowned_state_resources_block_both_applies(self):
        for flags in [[], ["--foundation"]]:
            with self.subTest(flags=flags):
                self.log.unlink(missing_ok=True)
                result = self.run_just("tofu::apply", *flags, UNSPLIT="true")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Split the combined Cloudflare state", result.stderr)
                self.assertFalse(
                    any(command[2] == "apply" for command in self.tofu_commands())
                )

    def test_init_failure_prevents_apply(self):
        (self.services / ".terraform/terraform.tfstate").unlink()
        result = self.run_just("tofu::apply", FAIL_COMMAND="tofu")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(command[2] == "apply" for command in self.tofu_commands()))

    def test_runtime_credentials_are_scoped_to_their_root(self):
        renderer = self.root / "scripts/render-opentofu-cloudflare-runtime.sh"
        shutil.copy(ROOT / "scripts/render-opentofu-cloudflare-runtime.sh", renderer)
        for name in ["cloudflare", "oidc"]:
            path = self.root / f"secrets/opentofu/{name}.yaml"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        sops = self.root / "bin/sops"
        sops.write_text("""#!/usr/bin/env python3
import json, sys
if sys.argv[-1].endswith('/oidc.yaml'):
    print(json.dumps({'cloudflare-access': {'client_secret': 'fixture-idp-secret'}}))
else:
    keys = ['cloudflare_api_token', 'cloudflare_account_id', 'cloudflare_zone_id',
            'edge_record_target', 'origin_record_content', 'admin_email']
    print(json.dumps({'cloudflare': {key: 'fixture-' + key for key in keys}}))
""")
        sops.chmod(0o755)
        result = subprocess.run(
            [str(renderer)], cwd=self.root, env=self.env, text=True, capture_output=True
        )
        self.assert_success(result)
        service_vars = self.services / "secrets.auto.tfvars"
        foundation_vars = self.foundation / "secrets.auto.tfvars"
        self.assertIn("edge_record_target =", service_vars.read_text())
        self.assertNotIn("idp_client_secret =", service_vars.read_text())
        self.assertNotIn("admin_email =", service_vars.read_text())
        self.assertIn("idp_client_secret =", foundation_vars.read_text())
        self.assertNotIn("edge_record_target =", foundation_vars.read_text())
        for path in [service_vars, foundation_vars]:
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
