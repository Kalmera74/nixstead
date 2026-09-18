"""Host archive selection must not include neighbouring hosts or legacy backups."""

import fnmatch
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
LIBRARY = ROOT / "scripts/lib/nixstead.sh"


class BackupArchiveNamesTests(unittest.TestCase):
    def prefix(self, host):
        return subprocess.run(
            ["bash", "-c", 'source "$LIBRARY"; nixstead_backup_archive_prefix'],
            env=dict(os.environ, LIBRARY=str(LIBRARY), HOST_NAME=host),
            capture_output=True,
            text=True,
            timeout=10,
        )

    def test_host_prefixes_cannot_match_neighbours_or_legacy_archives(self):
        hosts = ["lab", "lab-prod", "lab--prod", "lab_prod", "lab1", "LAB"]
        prefixes = {}
        for host in hosts:
            result = self.prefix(host)
            self.assertEqual(result.returncode, 0, result.stderr)
            prefixes[host] = result.stdout
        archives = {
            host: prefix + "2026-09-17_12-00-00" for host, prefix in prefixes.items()
        }
        for host, prefix in prefixes.items():
            with self.subTest(host=host):
                self.assertEqual(
                    [
                        owner
                        for owner, name in archives.items()
                        if fnmatch.fnmatchcase(name, prefix + "*")
                    ],
                    [host],
                )
                self.assertFalse(
                    fnmatch.fnmatchcase(
                        "service-data-2026-09-17_12-00-00", prefix + "*"
                    )
                )

    def test_empty_and_pattern_bearing_hosts_are_refused(self):
        for host in ("", "lab*", "lab?", "lab[12]", "lab.prod", "../lab", "lab\nprod"):
            with self.subTest(host=host):
                result = self.prefix(host)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")


@unittest.skipUnless(shutil.which("jq"), "requires jq")
class BackupArchiveSelectionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "calls.jsonl"
        self.registry = self.root / "registry.json"
        self.registry.write_text("{}")
        borg = self.bin / "borg"
        borg.write_text(
            f"#!{sys.executable}\n"
            "import fnmatch, json, os, sys\n"
            "from pathlib import Path\n"
            "args = sys.argv[1:]\n"
            "with Path(os.environ['CALLS']).open('a') as log:\n"
            "    log.write(json.dumps(args) + '\\n')\n"
            "if args[0] == 'list':\n"
            "    archives = json.loads(os.environ['ARCHIVES'])\n"
            "    if '--glob-archives' in args:\n"
            "        pattern = args[args.index('--glob-archives') + 1]\n"
            "        archives = [name for name in archives\n"
            "                    if fnmatch.fnmatchcase(name, pattern)]\n"
            "    for name in archives[-1:]:\n"
            "        print(name)\n"
            "elif args[0] not in ('check', 'extract'):\n"
            "    sys.exit(91)\n"
        )
        borg.chmod(0o755)
        self.env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("NIXSTEAD_", "NIXCONFIG_"))
        }
        self.env.update(
            PATH=str(self.bin) + os.pathsep + self.env["PATH"],
            CALLS=str(self.calls),
            NIXSTEAD_HOST="lab",
            NIXSTEAD_REGISTRY_FILE=str(self.registry),
            NIXSTEAD_BACKUP_REPOSITORY=str(self.root / "borg"),
        )

    def verify(self, archives, *args):
        return subprocess.run(
            ["bash", str(ROOT / "scripts/test-service-backup-restore.sh"), *args],
            env=dict(self.env, ARCHIVES=json.dumps(archives)),
            capture_output=True,
            text=True,
            timeout=10,
        )

    def test_automatic_verification_ignores_newer_foreign_and_legacy_archives(self):
        selected = "service-data-lab.2026-09-17_12-00-00"
        result = self.verify(
            [
                "service-data-lab.2026-09-16_12-00-00",
                selected,
                "service-data-lab-prod.2026-09-17_13-00-00",
                "service-data-other.2026-09-17_14-00-00",
                "service-data-2026-09-17_15-00-00",
            ]
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(calls[-1], ["extract", f"{self.root}/borg::{selected}"])

    def test_missing_host_archive_does_not_fall_back_to_another_archive(self):
        result = self.verify(
            [
                "service-data-other.2026-09-17_12-00-00",
                "service-data-2026-09-17_13-00-00",
            ]
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no service backup for host lab", result.stderr)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual([call[0] for call in calls], ["list"])

    def test_legacy_archive_can_still_be_verified_explicitly(self):
        legacy = "service-data-2026-09-16_12-00-00"
        self.env.pop("NIXSTEAD_HOST")
        result = self.verify([legacy], legacy)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual([call[0] for call in calls], ["check", "extract"])
        self.assertEqual(calls[-1][-1], f"{self.root}/borg::{legacy}")
