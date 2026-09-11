import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from setup.app import find_repo_root, parser, read_system_state_version, run_application
from setup.commands import SetupError


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
