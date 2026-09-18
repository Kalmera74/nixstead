import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from setup.app import (
    find_repo_root,
    healthcheck,
    offer_secrets,
    parser,
    read_system_state_version,
    run_application,
)
from setup.commands import SetupError
from setup.model import HostConfig


class StateVersionTests(unittest.TestCase):
    def test_explicit_version_does_not_require_etc_nixos(self):
        self.assertEqual(read_system_state_version("24.11"), "24.11")
        self.assertEqual(read_system_state_version("16.09"), "16.09")

    def test_configuration_in_another_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "host.nix"
            path.write_text('{ system.stateVersion = "23.11"; }')
            self.assertEqual(read_system_state_version(configuration=path), "23.11")

    def test_imported_version_and_comments_request_explicit_fallback(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "host.nix"
            path.write_text(
                '# system.stateVersion = "26.05";\n{ imports = [ ./base.nix ]; }'
            )
            with self.assertRaisesRegex(SetupError, "--state-version"):
                read_system_state_version(configuration=path)

    def test_invalid_explicit_versions_are_rejected(self):
        for version in ["latest", "26.5", "26.99", '24.11";']:
            with self.subTest(version=version), self.assertRaises(SetupError):
                read_system_state_version(version)

    def test_missing_version_fails_before_interview_or_runtime_preparation(self):
        with (
            patch(
                "setup.app.read_system_state_version",
                side_effect=SetupError("--state-version"),
            ),
            patch("setup.app.prepare_runtime") as runtime,
            patch("setup.app.run_wizard") as wizard,
            patch("setup.app.require"),
        ):
            with self.assertRaisesRegex(SetupError, "--state-version"):
                run_application(["--generate-only", "--skip-healthcheck"])
            runtime.assert_not_called()
            wizard.assert_not_called()

    def test_cli_exposes_both_fallbacks(self):
        args = parser().parse_args(
            ["--state-version", "24.11", "--configuration", "/srv/host.nix"]
        )
        self.assertEqual(args.state_version, "24.11")
        self.assertEqual(args.configuration, "/srv/host.nix")

    def test_cli_exposes_both_generation_modes(self):
        standalone = parser().parse_args(
            ["--output", "/srv/my-homelab", "--nixstead-url", "path:/src/nixstead"]
        )
        local = parser().parse_args(["--repo-local"])

        self.assertEqual(standalone.output, Path("/srv/my-homelab"))
        self.assertEqual(standalone.nixstead_url, "path:/src/nixstead")
        self.assertTrue(local.repo_local)

    def test_generation_modes_are_mutually_exclusive(self):
        with self.assertRaises(SystemExit):
            parser().parse_args(["--output", "/srv/my-homelab", "--repo-local"])

    def test_standalone_output_must_be_a_new_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(SetupError, "output already exists"):
                run_application(
                    [
                        "--output",
                        temporary,
                        "--state-version",
                        "24.11",
                        "--skip-healthcheck",
                    ]
                )

    def test_packaged_cli_repository_root_is_recognized(self):
        with patch.dict(
            "os.environ",
            {"NIXSTEAD_REPOSITORY_ROOT": "/srv/my-homelab"},
            clear=True,
        ):
            self.assertEqual(find_repo_root(), Path("/srv/my-homelab"))


class SetupIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.host = HostConfig(
            repo_root=self.root,
            secrets_dir=self.root / "secrets",
            host_name="fixture",
            target_name="fixture",
            user_uid=os.geteuid(),
            user_files_directory=self.root / "custom user files",
            user_sops_age_key_file=self.root / "custom user files/identity.txt",
            service_flags={"ENABLE_VAULTWARDEN": True, "ENABLE_HOMEPAGE": True},
        )
        self.registry = SimpleNamespace(
            services=[
                SimpleNamespace(variable="ENABLE_VAULTWARDEN", secrets=["vaultwarden"]),
                SimpleNamespace(variable="ENABLE_HOMEPAGE", secrets=["homepage"]),
            ]
        )

    def exercise_new_host(self, *, existing_secrets):
        def run_command(args, **kwargs):
            self.assertEqual(
                kwargs.get("env", {}).get("SOPS_AGE_KEY_FILE"),
                str(self.host.user_sops_age_key_file),
            )
            if args[:2] == ["sops", "decrypt"] and not existing_secrets:
                raise subprocess.CalledProcessError(1, args)
            return subprocess.CompletedProcess(args, 0)

        with (
            patch("setup.app.run", side_effect=run_command) as run,
            patch("setup.app.ensure_owned_directory"),
            patch("setup.app.UI") as ui,
        ):
            ui.return_value.yes_no.return_value = True
            offer_secrets(self.host, self.registry, self.root)
            self.assertEqual(healthcheck(self.host, False, self.root), "passed")
            generated = [
                call.args[0][1:]
                for call in run.call_args_list
                if Path(call.args[0][0]).name == "generate-credential-files.sh"
            ]
            self.assertEqual(
                generated,
                []
                if existing_secrets
                else [["vaultwarden"], ["--bootstrap", "homepage"]],
            )
            if existing_secrets:
                ui.assert_not_called()

    def test_new_identity_reaches_bootstrap_and_preflight_before_login(self):
        with patch.dict("os.environ", {}, clear=True):
            self.exercise_new_host(existing_secrets=False)
            self.assertNotIn("SOPS_AGE_KEY_FILE", os.environ)

    def test_selected_identity_overrides_inherited_key_for_existing_secrets(self):
        with patch.dict(
            "os.environ", {"SOPS_AGE_KEY_FILE": "/old/identity.txt"}, clear=True
        ):
            self.exercise_new_host(existing_secrets=True)
            self.assertEqual(os.environ["SOPS_AGE_KEY_FILE"], "/old/identity.txt")

    def test_existing_target_preserves_callers_identity(self):
        host = HostConfig(
            repo_root=self.root,
            secrets_dir=self.root / "secrets",
            host_name="existing",
            target_name="existing",
        )
        with (
            patch.dict(
                "os.environ", {"SOPS_AGE_KEY_FILE": "/admin/identity.txt"}, clear=True
            ),
            patch("setup.app.run", return_value=Mock(returncode=0)) as run,
        ):
            self.assertEqual(healthcheck(host, False, self.root), "passed")
            self.assertEqual(
                run.call_args.kwargs["env"]["SOPS_AGE_KEY_FILE"], "/admin/identity.txt"
            )
