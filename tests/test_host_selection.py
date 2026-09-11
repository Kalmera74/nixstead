"""Host selection must fail before a helper reads or changes another host's state."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class HostSelectionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.calls = self.directory / "calls"
        self.env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("NIXSTEAD_", "NIXCONFIG_")) and key != "HOST_NAME"
        }
        self.env.update(
            PATH=str(self.bin) + os.pathsep + self.env["PATH"],
            NIXSTEAD_REPOSITORY_ROOT=str(ROOT),
            NIXSTEAD_SECRETS_DIR=str(self.directory / "secrets"),
            HOST_TEST_CALLS=str(self.calls),
        )
        for name in ("nix", "sops", "jq"):
            stub = self.bin / name
            stub.write_text(
                f"#!{shutil.which('bash')}\n"
                'printf "%s\\n" "$@" >> "$HOST_TEST_CALLS"\n'
                "exit 91\n"
            )
            stub.chmod(0o755)

    def run_script(self, name, args=(), **kwargs):
        return subprocess.run(
            ["bash", str(ROOT / "scripts" / name), *args],
            env=self.env,
            text=True,
            capture_output=True,
            timeout=10,
            **kwargs,
        )

    def test_missing_host_fails_before_external_commands_or_secret_writes(self):
        for name, args in (
            ("healthcheck.sh", []),
            ("dev-healthcheck.sh", []),
            ("check-secret-store-leaks.sh", []),
            ("check-homepage-secrets.sh", []),
            ("configure-homepage-integrations.sh", []),
            ("service-credentials.sh", ["list"]),
            ("generate-credential-files.sh", ["cifs"]),
            ("generate-credential-files.sh", ["paperless-secret"]),
            ("generate-credential-files.sh", ["all", "--bootstrap"]),
        ):
            with self.subTest(script=name, args=args):
                result = self.run_script(name, args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("select a NixOS configuration", result.stderr)
                self.assertFalse(self.calls.exists())
                self.assertFalse((self.directory / "secrets").exists())

    def test_help_does_not_require_a_host(self):
        for path in (ROOT / "scripts").glob("*.sh"):
            if 'HOST_NAME="${' not in path.read_text():
                continue
            with self.subTest(script=path.name):
                result = self.run_script(path.name, ["--help"])
                self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.calls.exists())

    def test_host_argument_overrides_environment(self):
        self.env["NIXSTEAD_HOST"] = "environment-host"
        for args, expected in (
            (["list"], "environment-host"),
            (["--host", "selected-host", "list"], "selected-host"),
        ):
            with self.subTest(args=args):
                self.calls.unlink(missing_ok=True)
                result = self.run_script("service-credentials.sh", args)
                self.assertTrue(self.calls.exists(), result.stderr)
                self.assertIn(
                    f'nixosConfigurations."{expected}".config.nixstead.serviceRegistry',
                    self.calls.read_text(),
                )

    def test_invalid_host_rejected_before_lookup(self):
        result = self.run_script(
            "service-credentials.sh", ["--host", "../another-host", "list"]
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid NixOS configuration name", result.stderr)
        self.assertFalse(self.calls.exists())

    def test_failed_path_lookup_stops_credential_generation(self):
        self.env["NIXSTEAD_HOST"] = "selected-host"
        for target in ("paperless-secret", "kavita-token"):
            with self.subTest(target=target):
                result = self.run_script(
                    "generate-credential-files.sh", [target], input=""
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    "Could not resolve the default output path", result.stderr
                )
                self.assertNotIn("Generating", result.stdout)

    def test_explicit_secret_destination_does_not_require_host(self):
        destination = self.directory / "nextcloud-password"
        result = self.run_script(
            "generate-credential-files.sh",
            ["nextcloud-admin", str(destination)],
            input="local-test-password\n",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(destination.read_text(), "local-test-password\n")
        self.assertEqual(destination.stat().st_mode & 0o777, 0o600)
        self.assertFalse(self.calls.exists())

    def test_legacy_secrets_directory_override_is_preserved(self):
        self.env.pop("NIXSTEAD_SECRETS_DIR")
        self.env["NIXCONFIG_SECRETS_DIR"] = str(self.directory / "legacy-secrets")
        self.env["NIXSTEAD_HOST"] = "selected-host"
        result = self.run_script("check-homepage-secrets.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("legacy-secrets/selected-host.yaml", result.stdout)
        self.assertFalse(self.calls.exists())
