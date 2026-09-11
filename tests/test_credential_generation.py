"""Exercise credential serialization and effective path resolution at the CLI."""

import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/generate-credential-files.sh"


class CredentialDestinationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.root / "flake.nix").write_text("{}")
        self.calls = self.root / "nix-calls"
        self.env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("NIXSTEAD_", "NIXCONFIG_", "SOPS_"))
        }
        self.env.update(
            PATH=f"{self.bin}:{self.env['PATH']}",
            NIXSTEAD_REPOSITORY_ROOT=str(self.root),
            NIXSTEAD_LIB=str(ROOT / "scripts/lib/nixstead.sh"),
            NIXSTEAD_HOST="fixture",
            LOOKUP="",
            PAPERLESS_USER=pwd.getpwuid(os.geteuid()).pw_name,
            CALLS=str(self.calls),
        )
        self.stub(
            "nix",
            'printf "%s\\n" "$*" >> "$CALLS"\n'
            'if [[ "$*" == *services.paperless.user* ]]; then\n'
            '  printf "%s" "$PAPERLESS_USER"\n'
            'else\n  printf "%s" "$LOOKUP"\nfi\n',
        )
        if not shutil.which("sops"):
            self.stub("sops", "exit 91\n")

    def stub(self, name, body):
        command = self.bin / name
        command.write_text(f"#!{shutil.which('bash')}\nset -euo pipefail\n{body}")
        command.chmod(0o755)

    def run_generator(self, *args, values="fixture-key\n"):
        return subprocess.run(
            ["bash", str(SCRIPT), *args],
            input=values,
            env=self.env,
            cwd=self.root,
            text=True,
            capture_output=True,
            timeout=60,
        )

    def test_native_paths_and_explicit_kavita_key_override(self):
        for target, lookup, destination, option in (
            (
                "paperless-secret",
                self.root / "paperless",
                self.root / "paperless/nixos-paperless-secret-key",
                "services.paperless.dataDir",
            ),
            (
                "kavita-token",
                self.root / "custom/kavita-signing-key",
                self.root / "custom/kavita-signing-key",
                "nixstead.services.media.kavita.tokenKeyFile",
            ),
            (
                "nextcloud-admin",
                self.root / "custom/cloud-pass",
                self.root / "custom/cloud-pass",
                "services.nextcloud.config.adminpassFile",
            ),
        ):
            with self.subTest(target=target):
                self.env["LOOKUP"] = str(lookup)
                result = self.run_generator(target)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(destination.read_text(), "fixture-key\n")
                self.assertIn(option, self.calls.read_text())
                self.assertEqual(destination.stat().st_mode & 0o777, 0o600)
                if target == "paperless-secret":
                    self.assertIn("services.paperless.user", self.calls.read_text())
                    self.assertEqual(destination.stat().st_uid, os.geteuid())

    def test_invalid_paperless_preseeds_are_refused(self):
        self.env["LOOKUP"] = str(self.root / "paperless")
        self.env["PAPERLESS_USER"] = "nixstead-missing-account-fixture"
        result = self.run_generator("paperless-secret")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "paperless").exists())
        self.env["PAPERLESS_USER"] = pwd.getpwuid(os.geteuid()).pw_name
        result = self.run_generator("paperless-secret", values="literal ${value}\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("only letters", result.stderr)
        self.assertFalse((self.root / "paperless").exists())

    def test_empty_effective_path_is_rejected_before_prompting(self):
        for target in ("paperless-secret", "kavita-token", "nextcloud-admin"):
            result = self.run_generator(target)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("Generating", result.stdout)

    def test_paperless_active_key_prevents_ignored_legacy_writes(self):
        self.env["LOOKUP"] = str(self.root)
        active = self.root / "nixos-paperless-secret-key.env"
        active.write_text("PAPERLESS_SECRET_KEY=existing-key\n")
        result = self.run_generator("--force", "paperless-secret")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already has an active key", result.stderr)
        self.assertFalse((self.root / "nixos-paperless-secret-key").exists())
        self.assertEqual(active.read_text(), "PAPERLESS_SECRET_KEY=existing-key\n")


@unittest.skipUnless(
    shutil.which("sops") and shutil.which("age-keygen"), "requires SOPS and age"
)
class EncryptedGenerationTests(CredentialDestinationTests):
    def setUp(self):
        super().setUp()
        identity = self.root / "age-key.txt"
        subprocess.run(
            ["age-keygen", "-o", str(identity)], capture_output=True, check=True
        )
        recipient = subprocess.run(
            ["age-keygen", "-y", str(identity)],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        (self.root / ".sops.yaml").write_text(
            f"creation_rules:\n  - path_regex: secrets/fixture\\.yaml$\n    age: {recipient}\n"
        )
        self.env["SOPS_AGE_KEY_FILE"] = str(identity)
        self.encrypted = self.root / "secrets/fixture.yaml"

    def decrypt(self):
        result = subprocess.run(
            ["sops", "decrypt", "--output-type", "json", str(self.encrypted)],
            env=self.env,
            capture_output=True,
            text=True,
            check=True,
        )
        return json.loads(result.stdout)

    def test_literal_values_roundtrip_without_entering_nix(self):
        self.env["NIXSTEAD_SECRETS_DIR"] = "secrets"
        password = '  literal ${value} $(false) `false` "quote" \\ café  '
        result = self.run_generator(
            "cifs", values=f"fixture-user\n{password}\nWORKGROUP\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.decrypt()["cifs"],
            {"username": "fixture-user", "password": password, "domain": "WORKGROUP"},
        )
        self.assertFalse(
            self.calls.exists(), "credential values must not enter Nix evaluation"
        )
        self.assertNotIn(password, self.encrypted.read_text())

    def test_nested_credential_branches_keep_their_schema(self):
        values = [
            "pg-user",
            "pg-pass",
            "mongo-pass",
            "redis-user",
            "redis-pass",
            "rabbit-user",
            "rabbit-pass",
            "grafana-user",
            "grafana-pass",
            "grafana-key",
            "pgadmin-pass",
        ]
        result = self.run_generator("devdb", values="\n".join(values) + "\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        data = self.decrypt()["devdb"]
        self.assertEqual(
            data["postgresql"], {"rootUser": "pg-user", "rootPassword": "pg-pass"}
        )
        self.assertEqual(
            data["grafana"],
            {
                "adminUser": "grafana-user",
                "adminPassword": "grafana-pass",
                "secretKey": "grafana-key",
            },
        )
        self.assertEqual(data["pgadmin"], {"initialPassword": "pgadmin-pass"})
        self.assertFalse(self.calls.exists())

    def test_homepage_update_preserves_managed_and_unowned_keys(self):
        result = self.run_generator("--bootstrap", "homepage", values="")
        self.assertEqual(result.returncode, 0, result.stderr)
        for key in ("sonarrApiKey", "futureManagedKey", "customWidgetKey"):
            subprocess.run(
                [
                    "sops",
                    "set",
                    "--value-stdin",
                    str(self.encrypted),
                    f'["homepage"]["{key}"]',
                ],
                input='"retained"',
                env=self.env,
                text=True,
                capture_output=True,
                check=True,
            )
        result = self.run_generator("--force", "--bootstrap", "homepage", values="")
        self.assertEqual(result.returncode, 0, result.stderr)
        data = self.decrypt()["homepage"]
        for key in ("sonarrApiKey", "futureManagedKey", "customWidgetKey"):
            self.assertEqual(data[key], "retained")
