"""Exercise the grouped public command interface."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "scripts/nixstead.sh"


class NixsteadCliTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.scripts = self.root / "scripts"
        self.scripts.mkdir()
        self.trace = self.root / "trace"
        self.env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("NIXSTEAD_", "NIXCONFIG_"))
        }
        self.env.update(
            NIXSTEAD_SCRIPT_ROOT=str(self.scripts),
            NIXSTEAD_REPOSITORY_ROOT=str(self.root),
            NIXSTEAD_MEDIA_ENABLED="true",
            TRACE=str(self.trace),
        )

    def stub(self, name, exit_status=0):
        path = self.scripts / name
        path.write_text(
            f"#!{shutil.which('bash')}\n"
            "set -euo pipefail\n"
            f"printf 'script=%s\\n' {name!r} >>\"$TRACE\"\n"
            'printf \'host=%s\\n\' "${NIXSTEAD_HOST:-}" >>"$TRACE"\n'
            'printf \'details=%s\\n\' "${NIXSTEAD_DETAILS_ONLY:-}" >>"$TRACE"\n'
            'printf \'arg=%s\\n\' "$@" >>"$TRACE"\n'
            f"exit {exit_status}\n"
        )
        path.chmod(0o755)

    def run_cli(self, *arguments, env=None):
        return subprocess.run(
            ["bash", str(CLI), *arguments],
            env=env or self.env,
            text=True,
            capture_output=True,
            timeout=10,
        )

    def test_runtime_check_uses_general_and_database_implementations(self):
        self.stub("health-homelab.sh")
        self.stub("dev-healthcheck.sh")

        result = self.run_cli("--host", "fixture", "check", "runtime")

        self.assertEqual(result.returncode, 0, result.stderr)
        trace = self.trace.read_text()
        self.assertIn("script=health-homelab.sh", trace)
        self.assertIn("script=dev-healthcheck.sh", trace)
        self.assertIn("host=fixture", trace)
        self.assertIn("details=true", trace)

    def test_runtime_check_runs_database_details_after_a_general_failure(self):
        self.stub("health-homelab.sh", exit_status=1)
        self.stub("dev-healthcheck.sh")

        result = self.run_cli("--host", "fixture", "check", "runtime")

        self.assertEqual(result.returncode, 1)
        trace = self.trace.read_text()
        self.assertIn("script=health-homelab.sh", trace)
        self.assertIn("script=dev-healthcheck.sh", trace)

    def test_images_injects_selected_host_after_options(self):
        self.stub("container-images.sh")

        result = self.run_cli(
            "--host",
            "fixture",
            "images",
            "set",
            "--dry-run",
            "romm",
            "application",
            "1.2.3",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [
                line
                for line in self.trace.read_text().splitlines()
                if line.startswith("arg=")
            ],
            [
                "arg=set",
                "arg=--dry-run",
                "arg=fixture",
                "arg=romm",
                "arg=application",
                "arg=1.2.3",
            ],
        )

    def test_media_group_refuses_when_not_installed(self):
        env = dict(self.env, NIXSTEAD_MEDIA_ENABLED="false")

        result = self.run_cli("media", "transcode", "/tmp/videos", env=env)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("media tools are not enabled", result.stderr)

    def test_each_leaf_group_has_help_without_requiring_a_host(self):
        for group in ("dns", "forge"):
            with self.subTest(group=group):
                result = self.run_cli(group, "--help")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Usage:", result.stdout)

    def test_configuration_checks_require_an_explicit_host(self):
        result = self.run_cli("check", "preflight")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("select a host", result.stderr)

    def test_plaintext_token_options_are_not_accepted(self):
        for script, option in (
            ("mirror-github-to-forgejo.sh", "--token"),
            ("sync-pihole-local-dns-from-nginx.sh", "--password"),
        ):
            with self.subTest(script=script):
                result = subprocess.run(
                    ["bash", str(ROOT / "scripts" / script), option, "secret"],
                    env=self.env,
                    text=True,
                    capture_output=True,
                    timeout=10,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unknown", (result.stdout + result.stderr).lower())


if __name__ == "__main__":
    unittest.main()
