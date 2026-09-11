"""Credential lifecycle checks, including actual age-encrypted SOPS updates."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "modules/services/arr"))
import credential_store as store
import credential_enrollment as enrollment
import credentials
import reconcile
import runtime_environment

KEY = "a" * 32
OTHER = "b" * 32
ENTRY = {
    "enabled": True,
    "settings": {"port": 8989},
    "api": {
        "sopsSecret": "sonarr/apiKey",
        "previousSecrets": ["homepage/sonarrApiKey", "swaparr/sonarrApiKey"],
        "format": "xml",
        "stateFile": "/unused/config.xml",
    },
}


class EnrollmentTests(unittest.TestCase):
    def test_automatic_enrollment_reuses_state_and_generates_only_missing_values(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "config.xml"
            state.write_text("<Config><ApiKey>" + KEY + "</ApiKey></Config>")
            entry = dict(ENTRY, api=dict(ENTRY["api"], stateFile=str(state)))
            registry = {"sonarr": entry, "qbittorrent": {}}
            first = store.automatic_enrollment({}, registry)
            self.assertEqual(first["sonarr"]["apiKey"], KEY)
            self.assertEqual(first["qbittorrent"]["username"], "arr")
            self.assertGreaterEqual(len(first["qbittorrent"]["password"]), 32)
            state.write_text("<Config><ApiKey>" + OTHER + "</ApiKey></Config>")
            self.assertEqual(store.automatic_enrollment(first, registry), first)
            state.unlink()
            generated = store.automatic_enrollment({}, registry)
            self.assertTrue(credentials.valid_key(generated["sonarr"]["apiKey"]))
            state.write_text("broken XML")
            with self.assertRaises(store.StoreError):
                store.automatic_enrollment({}, registry)

    def test_existing_sops_is_authoritative_without_reading_application(self):
        original = {"sonarr": {"apiKey": KEY}, "unrelated": {"value": "retained"}}
        with patch.object(store, "application_key", side_effect=AssertionError):
            result = store.enroll(
                original, "sonarr", ENTRY, application=lambda _: self.fail()
            )
        self.assertEqual(result, original)

    def test_malformed_branch_is_never_treated_as_a_missing_key(self):
        with self.assertRaises(store.StoreError):
            store.enroll(
                {"sonarr": "malformed"},
                "sonarr",
                ENTRY,
                application=lambda _: self.fail(),
            )
        self.assertEqual(
            store.inspect_status({"sonarr": "malformed"}, "sonarr", ENTRY),
            "invalid SOPS credential",
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "document"
            path.write_text(json.dumps({"sonarr": "malformed"}))
            with self.assertRaises(ValueError):
                credentials.deployed_values(
                    {
                        "document": str(path),
                        "service": "sonarr",
                        "keys": {"api-key": {"path": "sonarr/apiKey"}},
                    }
                )

    def test_missing_imports_existing_application_key_and_preserves_unowned(self):
        original = {"homepage": {"sonarrApiKey": "replace-me", "custom": "keep"}}
        result = store.enroll(original, "sonarr", ENTRY, application=lambda _: KEY)
        self.assertEqual(result["sonarr"]["apiKey"], KEY)
        self.assertEqual(result["homepage"], {"custom": "keep"})
        self.assertIn("sonarrApiKey", original["homepage"])

    def test_conflict_requires_selection_and_identical_duplicates_consolidate(self):
        original = {
            "homepage": {"sonarrApiKey": KEY},
            "swaparr": {"sonarrApiKey": OTHER},
        }
        with self.assertRaisesRegex(
            store.StoreError, "Conflicting SOPS sources"
        ) as raised:
            store.enroll(original, "sonarr", ENTRY)
        self.assertNotIn(KEY, str(raised.exception))
        self.assertNotIn(OTHER, str(raised.exception))
        result = store.enroll(original, "sonarr", ENTRY, "swaparr/sonarrApiKey")
        self.assertEqual(result["sonarr"]["apiKey"], OTHER)
        self.assertEqual(result["homepage"], {})
        self.assertEqual(result["swaparr"], {})
        original["swaparr"]["sonarrApiKey"] = KEY
        self.assertEqual(
            store.enroll(original, "sonarr", ENTRY)["sonarr"]["apiKey"], KEY
        )

    def test_explicit_adoption_and_restore_revision(self):
        original = {"sonarr": {"apiKey": KEY}}
        adopted = store.enroll(
            original, "sonarr", ENTRY, "application", application=lambda _: OTHER
        )
        self.assertEqual(adopted["sonarr"]["apiKey"], OTHER)
        restored = store.enroll(original, "sonarr", ENTRY, restore=True)
        self.assertEqual(restored["sonarr"]["apiKey"], KEY)
        self.assertTrue(restored["sonarr"]["credentialRevision"])

    def test_qbittorrent_preserves_password_and_discards_derived_hash(self):
        original = {
            "qbittorrent": {
                "username": "user",
                "password": ' password $`"\\ ',
                "passwordHash": "old-derived",
            },
            "homepage": {
                "qbittorrentUsername": "user",
                "qbittorrentPassword": ' password $`"\\ ',
            },
        }
        result = store.enroll(original, "qbittorrent", {})
        self.assertEqual(
            result["qbittorrent"]["password"], original["qbittorrent"]["password"]
        )
        self.assertNotIn("passwordHash", result["qbittorrent"])
        self.assertEqual(result["homepage"], {})
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "password").write_text(result["qbittorrent"]["password"] + "\n")
            with patch.dict(os.environ, CREDENTIALS_DIRECTORY=str(root)):
                runtime_environment.render(
                    {"QBITTORRENT_PASSWORD": "password"}, root / "environment"
                )
            self.assertEqual(
                json.loads((root / "environment").read_text().split("=", 1)[1]),
                result["qbittorrent"]["password"],
            )
        with self.assertRaises(store.StoreError):
            store.enroll(
                {"qbittorrent": {"username": "user", "passwordHash": "not-reversible"}},
                "qbittorrent",
                {},
            )

    def test_qbittorrent_username_and_password_conflicts_are_selected_independently(
        self,
    ):
        original = {
            "qbittorrent": {"username": "one", "password": "first"},
            "homepage": {"qbittorrentUsername": "two", "qbittorrentPassword": "second"},
        }
        result = store.enroll(
            original,
            "qbittorrent",
            {},
            ["homepage/qbittorrentUsername", "qbittorrent/password"],
        )
        self.assertEqual(
            result["qbittorrent"], {"username": "two", "password": "first"}
        )
        with self.assertRaises(store.StoreError):
            store.enroll(original, "qbittorrent", {}, rotate=True)
        with self.assertRaises(store.StoreError):
            store.enroll(
                {}, "sonarr", ENTRY, restore=True, application=lambda _: self.fail()
            )

    def test_bootstrap_never_publishes_an_unsaved_application_key(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            document = root / "deployed.yaml"
            document.write_text("{}")
            config = {
                "document": str(document),
                "service": "sonarr",
                "keys": {"api-key": {"path": "sonarr/apiKey"}},
                "outputs": [
                    {"path": str(root / "api-key"), "key": "api-key"},
                    {
                        "path": str(root / "native.env"),
                        "environment": {"SONARR__AUTH__APIKEY": "api-key"},
                        "optional": True,
                    },
                    {
                        "path": str(root / "swaparr.env"),
                        "key": "api-key",
                        "prefix": "APIKEY=",
                    },
                ],
                "consumers": ["sonarr.service"],
            }
            with patch.object(credentials.subprocess, "run"):
                credentials.publish(config)
            self.assertEqual((root / "api-key").read_text(), "\n")
            self.assertEqual((root / "native.env").read_text(), "")
            document.write_text(json.dumps({"sonarr": {"apiKey": KEY}}))
            with patch.object(credentials.subprocess, "run") as restart:
                credentials.publish(config)
                credentials.publish(config)
                self.assertEqual(restart.call_count, 1)
            self.assertEqual((root / "api-key").stat().st_mode & 0o777, 0o400)
            self.assertIn(KEY, (root / "native.env").read_text())
            self.assertEqual((root / "swaparr.env").read_text(), "APIKEY=" + KEY + "\n")

    def test_status_distinguishes_pending_unknown_and_application_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            document = {"sonarr": {"apiKey": KEY}}
            self.assertEqual(
                store.inspect_status({}, "sonarr", ENTRY, root),
                "awaiting credential setup",
            )
            self.assertEqual(
                store.inspect_status(document, "sonarr", ENTRY, root), "not yet checked"
            )
            (root / "sonarr").mkdir()
            (root / "sonarr/api-key").write_text(OTHER)
            self.assertEqual(
                store.inspect_status(document, "sonarr", ENTRY, root),
                "pending deployment",
            )
            (root / "sonarr/api-key").write_text(KEY)
            with patch.object(
                credentials, "verify_application", return_value="application drift"
            ):
                self.assertEqual(
                    store.inspect_status(document, "sonarr", ENTRY, root),
                    "application drift",
                )
            self.assertEqual(
                store.inspect_status(
                    {"sonarr": {"apiKey": KEY}, "homepage": {"sonarrApiKey": OTHER}},
                    "sonarr",
                    ENTRY,
                    root,
                ),
                "conflicting SOPS sources",
            )
            self.assertEqual(
                store.inspect_status(
                    {"sonarr": {"apiKey": 123}}, "sonarr", ENTRY, root
                ),
                "invalid SOPS credential",
            )
            document["sonarr"]["credentialRevision"] = "restore-request"
            self.assertEqual(
                store.inspect_status(document, "sonarr", ENTRY, root),
                "pending deployment",
            )

    def test_runtime_show_does_not_decrypt_source(self):
        with tempfile.TemporaryDirectory() as directory:
            registry = Path(directory) / "registry.json"
            registry.write_text(json.dumps({"sonarr": ENTRY}))
            with (
                patch.object(
                    sys,
                    "argv",
                    [
                        "credentials",
                        "--registry",
                        str(registry),
                        "--file",
                        str(Path(directory) / "missing.yaml"),
                        "show",
                        "sonarr",
                        "--runtime",
                    ],
                ),
                patch.object(
                    store, "decrypt", side_effect=AssertionError("must not decrypt")
                ),
                patch.object(store, "read_private", return_value=KEY),
                patch("builtins.print") as output,
            ):
                store.main()
                self.assertIn("deployed runtime", output.call_args.args[0])

    def test_explicit_rotation_changes_only_selected_canonical_values(self):
        original = {"sonarr": {"apiKey": KEY}, "other": {"secret": OTHER}}
        result = store.enroll(original, "sonarr", ENTRY, rotate=True)
        self.assertNotEqual(result["sonarr"]["apiKey"], KEY)
        self.assertTrue(credentials.valid_key(result["sonarr"]["apiKey"]))
        self.assertEqual(result["other"], original["other"])
        self.assertTrue(result["sonarr"]["credentialRevision"])

    def test_relationships_are_isolated_and_missing_credentials_fail_before_api_calls(
        self,
    ):
        config = {
            "applications": [{"application": "sonarr"}, {"application": "radarr"}],
            "seerr": {
                "endpoint": "http://localhost:5055",
                "jellyfin": None,
                "destinations": [{"application": "sonarr"}, {"application": "radarr"}],
            },
        }
        jobs = list(reconcile.relationship_configs(config))
        self.assertEqual(len(jobs), 4)
        jobs[0][1]["applications"][0]["application"] = "changed"
        self.assertEqual(config["applications"][0]["application"], "sonarr")
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(
                reconcile.ReconcileError, "Awaiting credential setup"
            ):
                reconcile.read_credential(Path(directory), "sonarr")

    def test_interrupted_delivery_retries_consumer_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            document = root / "document"
            document.write_text(json.dumps({"sonarr": {"apiKey": KEY}}))
            config = {
                "document": str(document),
                "service": "sonarr",
                "keys": {"api-key": {"path": "sonarr/apiKey"}},
                "outputs": [{"path": str(root / "api-key"), "key": "api-key"}],
                "consumers": ["sonarr.service"],
            }
            with patch.object(credentials.subprocess, "run", side_effect=OSError):
                with self.assertRaises(OSError):
                    credentials.publish(config)
            self.assertTrue((root / "delivery-pending").exists())
            with patch.object(credentials.subprocess, "run") as restart:
                credentials.publish(config)
                self.assertEqual(restart.call_count, 1)
            self.assertFalse((root / "delivery-pending").exists())

    def test_failed_relationship_does_not_suppress_healthy_relationship(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "desired.json"
            config.write_text(
                json.dumps(
                    {
                        "applications": [
                            {"application": "sonarr"},
                            {"application": "radarr"},
                        ],
                        "dryRun": False,
                        "metricsFile": str(root / "metrics"),
                    }
                )
            )
            calls = []

            def run(selected, state):
                app = selected["applications"][0]["application"]
                calls.append(app)
                if app == "sonarr":
                    raise reconcile.ReconcileError(
                        "Application credential drift; explicit repair required"
                    )
                return []

            with (
                patch.object(
                    sys, "argv", ["reconcile", str(config), "--state-dir", str(root)]
                ),
                patch.object(reconcile, "run_configuration", side_effect=run),
            ):
                with self.assertRaises(SystemExit) as result:
                    reconcile.main()
            self.assertEqual(result.exception.code, 1)
            self.assertEqual(calls, ["sonarr", "radarr"])
            status = json.loads((root / "status.json").read_text())
            self.assertFalse(status["relationships"]["applications:sonarr"]["success"])
            self.assertTrue(status["relationships"]["applications:radarr"]["success"])
            self.assertNotIn(KEY, (root / "status.json").read_text())


@unittest.skipUnless(
    shutil.which("sops") and shutil.which("age-keygen"), "requires SOPS and age"
)
class SopsTransactionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.key_file = self.root / "identity"
        subprocess.run(
            ["age-keygen", "-o", str(self.key_file)], capture_output=True, check=True
        )
        public = subprocess.run(
            ["age-keygen", "-y", str(self.key_file)],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        self.environment = patch.dict(
            os.environ, {"SOPS_AGE_KEY_FILE": str(self.key_file)}
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.original = {
            "homepage": {"sonarrApiKey": KEY, "unrelated": "retained"},
            "other": {"secret": "unchanged"},
        }
        encrypted = subprocess.run(
            [
                "sops",
                "encrypt",
                "--age",
                public,
                "--input-type",
                "json",
                "--output-type",
                "yaml",
                "/dev/stdin",
            ],
            input=json.dumps(self.original),
            capture_output=True,
            text=True,
            check=True,
            cwd=self.root,
        ).stdout
        self.path = self.root / "host.yaml"
        self.path.write_text(encrypted)
        self.before = self.path.read_bytes()

    def automatic_config(self):
        runtime = self.root / "runtime"
        return {
            "sourceFile": str(self.path),
            "runtimeDirectory": str(runtime),
            "documentFile": str(runtime / "document.json"),
            "ageKeyFile": str(self.key_file),
            "sshKeyPaths": [],
            "registry": {"sonarr": ENTRY, "qbittorrent": {}},
        }

    def test_automatic_save_precedes_delivery_and_is_repeatable(self):
        config = self.automatic_config()
        with patch.object(enrollment.subprocess, "run", wraps=subprocess.run) as calls:
            enrollment.run(config)
            self.assertFalse(
                any(call.args[0][0] == "systemctl" for call in calls.call_args_list)
            )
        encrypted = self.path.read_bytes()
        saved = store.decrypt(self.path)
        delivered = json.loads(Path(config["documentFile"]).read_text())
        self.assertEqual(delivered["sonarr"], saved["sonarr"])
        self.assertEqual(delivered["qbittorrent"], saved["qbittorrent"])
        self.assertNotIn("other", delivered)
        self.assertNotIn(KEY.encode(), encrypted)
        self.assertFalse((self.root / "runtime/identity").exists())
        self.assertEqual(Path(config["documentFile"]).stat().st_mode & 0o777, 0o400)
        enrollment.run(config)
        self.assertEqual(self.path.read_bytes(), encrypted)

    def test_failed_encryption_never_delivers_generated_values(self):
        config = self.automatic_config()
        with patch.object(
            enrollment,
            "save_encrypted",
            side_effect=store.StoreError("fixture write failure"),
        ):
            with self.assertRaises(store.StoreError):
                enrollment.run(config)
        self.assertEqual(self.path.read_bytes(), self.before)
        self.assertFalse(Path(config["documentFile"]).exists())
        self.assertFalse((self.root / "runtime/identity").exists())
        status = json.loads((self.root / "runtime/status.json").read_text())
        self.assertFalse(status["success"])
        self.assertNotIn(KEY, json.dumps(status))

    def test_delivery_interruption_reuses_saved_key_on_recovery(self):
        config = self.automatic_config()
        write = enrollment.atomic_write

        def interrupt(path, *args, **kwargs):
            if str(path) == config["documentFile"]:
                raise OSError("interrupted delivery")
            return write(path, *args, **kwargs)

        with patch.object(enrollment, "atomic_write", side_effect=interrupt):
            with self.assertRaises(store.StoreError):
                enrollment.run(config)
        encrypted = self.path.read_bytes()
        enrollment.run(config)
        self.assertEqual(self.path.read_bytes(), encrypted)
        self.assertEqual(
            json.loads(Path(config["documentFile"]).read_text())["qbittorrent"],
            store.decrypt(self.path)["qbittorrent"],
        )

    def test_automatic_conflicts_preserve_source_and_runtime(self):
        config = self.automatic_config()
        original = store.decrypt(self.path)
        conflict = dict(original, sonarr={"apiKey": OTHER})
        store.save_encrypted(self.path, self.before, original, conflict)
        before = self.path.read_bytes()
        with self.assertRaisesRegex(store.StoreError, "Conflicting SOPS sources"):
            enrollment.run(config)
        self.assertEqual(self.path.read_bytes(), before)
        self.assertFalse(Path(config["documentFile"]).exists())

    def test_actual_sops_consolidation_and_second_run_no_ciphertext_changes(self):
        updated = store.enroll(self.original, "sonarr", ENTRY)
        self.assertTrue(
            store.save_encrypted(self.path, self.before, self.original, updated)
        )
        self.assertEqual(store.decrypt(self.path), updated)
        self.assertNotIn(KEY, self.path.read_text())
        encrypted = self.path.read_bytes()
        self.assertFalse(
            store.save_encrypted(
                self.path, encrypted, updated, store.enroll(updated, "sonarr", ENTRY)
            )
        )
        self.assertEqual(self.path.read_bytes(), encrypted)

    def test_interrupted_update_preserves_original_ciphertext(self):
        updated = store.enroll(self.original, "sonarr", ENTRY)
        with patch.object(
            store, "sops_run", side_effect=store.StoreError("interrupted")
        ):
            with self.assertRaises(store.StoreError):
                store.save_encrypted(self.path, self.before, self.original, updated)
        self.assertEqual(self.path.read_bytes(), self.before)
        self.assertEqual(list(self.root.glob(".nixstead-credentials-*")), [])

    def test_concurrent_source_edit_is_not_overwritten(self):
        changed = self.before + b"\n"
        self.path.write_bytes(changed)
        with self.assertRaisesRegex(store.StoreError, "changed during synchronization"):
            store.save_encrypted(
                self.path,
                self.before,
                self.original,
                store.enroll(self.original, "sonarr", ENTRY),
            )
        self.assertEqual(self.path.read_bytes(), changed)

    def test_decryption_failure_is_not_treated_as_missing(self):
        self.path.write_text("not an encrypted document")
        with self.assertRaises(store.StoreError):
            store.decrypt(self.path)

    def test_cli_sync_dry_run_and_show_are_separate(self):
        registry = self.root / "registry.json"
        registry.write_text(json.dumps({"sonarr": ENTRY}))
        command = [
            sys.executable,
            str(Path(store.__file__)),
            "--registry",
            str(registry),
            "--file",
            str(self.path),
        ]
        result = subprocess.run(
            [*command, "sync", "--dry-run"], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(KEY, result.stdout + result.stderr)
        self.assertEqual(self.path.read_bytes(), self.before)
        result = subprocess.run([*command, "sync"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(KEY, result.stdout + result.stderr)
        result = subprocess.run(
            [*command, "show", "sonarr"], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(KEY, result.stdout)
        self.assertIn("canonical SOPS", result.stdout)

    @unittest.skipUnless(
        shutil.which("jq") and shutil.which("bash"), "requires shell helper tools"
    )
    def test_shell_wrapper_managed_commands_and_qbittorrent_only_list(self):
        custom_source = self.root / "custom-source.yaml"
        self.path.rename(custom_source)
        self.path = custom_source
        repository = self.root / "repository"
        repository.mkdir()
        (repository / "flake.nix").write_text(
            "{ outputs = { self }: { nixosConfigurations.host.config.nixstead.serviceRegistry = builtins.fromJSON (builtins.readFile ./registry.json); }; }"
        )
        registry = repository / "registry.json"
        registry.write_text(
            json.dumps({"sonarr": dict(ENTRY, credentialSopsFile=str(self.path))})
        )
        binary = self.root / "bin"
        binary.mkdir()
        nix = binary / "nix"
        nix.write_text(
            "#!"
            + shutil.which("bash")
            + '\nset -euo pipefail\ncat "$FIXTURE_REGISTRY"\n'
        )
        nix.chmod(0o700)
        temporary = self.root / "temporary"
        temporary.mkdir()
        wrapper = os.environ.get(
            "NIXSTEAD_TEST_CREDENTIAL_WRAPPER",
            str(Path(__file__).parents[1] / "scripts/service-credentials.sh"),
        )
        command = [
            shutil.which("bash"),
            wrapper,
            "--repo-root",
            str(repository),
            "--host",
            "host",
            "--secrets-dir",
            str(self.root),
        ]
        environment = dict(
            os.environ,
            PATH=str(binary) + os.pathsep + os.environ["PATH"],
            FIXTURE_REGISTRY=str(registry),
            TMPDIR=str(temporary),
            NIXSTEAD_CREDENTIAL_STORE=str(Path(store.__file__)),
        )

        def run(*arguments):
            result = subprocess.run(
                [*command, *arguments], capture_output=True, text=True, env=environment
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                list(temporary.iterdir()), [], "wrapper leaked its temporary registry"
            )
            return result.stdout

        self.assertNotIn(KEY, run("sync", "--dry-run"))
        self.assertEqual(self.path.read_bytes(), self.before)
        self.assertNotIn(KEY, run("sync"))
        self.assertIn("sonarr: SOPS sonarr/apiKey", run("list"))
        self.assertNotIn(KEY, run("list"))
        self.assertIn(KEY, run("show", "sonarr"))

        registry.write_text(
            json.dumps(
                {
                    "qbittorrent": {
                        "enabled": True,
                        "settings": {"port": 8080},
                        "credentialSopsFile": str(self.path),
                    }
                }
            )
        )
        original = store.decrypt(self.path)
        updated = dict(
            original,
            qbittorrent={"username": "fixture", "password": "canonical-password"},
            homepage={
                "qbittorrentUsername": "old-user",
                "qbittorrentPassword": "old-password",
            },
        )
        store.save_encrypted(self.path, self.path.read_bytes(), original, updated)
        self.assertNotIn("canonical-password", run("list"))
        self.assertIn(
            "qbittorrent: SOPS qbittorrent/username, qbittorrent/password", run("list")
        )
        run(
            "sync",
            "qbittorrent",
            "--from",
            "homepage/qbittorrentUsername",
            "--from",
            "qbittorrent/password",
        )
        self.assertEqual(
            store.decrypt(self.path)["qbittorrent"],
            {"username": "old-user", "password": "canonical-password"},
        )
