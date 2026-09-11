import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "modules/services/vaultwarden-backup.sh"


@unittest.skipUnless(shutil.which("sqlite3"), "requires the SQLite CLI")
class VaultwardenBackupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "data"
        self.destination = self.root / "backup with spaces"
        self.staging = self.root / "local"
        for directory in (self.source, self.destination, self.staging):
            directory.mkdir()
        self.database = self.source / "db.sqlite3"
        self.connection = sqlite3.connect(self.database)
        self.addCleanup(self.connection.close)
        self.connection.execute("PRAGMA journal_mode=WAL")
        self.connection.execute("CREATE TABLE vault (value TEXT)")
        self.connection.execute("INSERT INTO vault VALUES ('committed in WAL')")
        self.connection.commit()
        (self.source / "attachments").mkdir()
        (self.source / "attachments/item").write_text("attachment")
        (self.source / "rsa_key.pem").write_text("fixture key")
        (self.source / ".metadata").write_text("hidden fixture")
        self.backup = self.destination / "db.sqlite3"
        self.backup.write_bytes(b"previous backup")
        self.env = {
            **os.environ,
            "DATA_FOLDER": str(self.source),
            "BACKUP_FOLDER": str(self.destination),
            "TMPDIR": str(self.staging),
        }

    def run_backup(self):
        return subprocess.run(
            ["bash", str(SCRIPT)],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=45,
        )

    def assert_preserved(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.backup.read_bytes(), b"previous backup")
        self.assertEqual(list(self.staging.iterdir()), [])
        self.assertEqual(list(self.destination.glob(".db.sqlite3.*")), [])

    def test_live_wal_snapshot_includes_payload(self):
        self.assertTrue(Path(str(self.database) + "-wal").stat().st_size)
        result = self.run_backup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with sqlite3.connect(self.backup) as backup:
            self.assertEqual(
                backup.execute("PRAGMA integrity_check").fetchone(), ("ok",)
            )
            self.assertEqual(
                backup.execute("SELECT value FROM vault").fetchone(),
                ("committed in WAL",),
            )
        for path in ("attachments/item", "rsa_key.pem", ".metadata"):
            self.assertEqual(
                (self.destination / path).read_bytes(),
                (self.source / path).read_bytes(),
            )
        self.assertFalse((self.destination / "db.sqlite3-wal").exists())
        self.assertEqual(list(self.staging.iterdir()), [])

    def test_does_not_open_destination_with_sqlite(self):
        self.backup.unlink()
        with sqlite3.connect(self.backup) as locked:
            locked.execute("CREATE TABLE old (value TEXT)")
            locked.commit()
            locked.execute("BEGIN EXCLUSIVE")
            result = self.run_backup()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_empty_database_preserves_previous_backup(self):
        self.connection.close()
        self.database.write_bytes(b"")
        self.assert_preserved(self.run_backup())

    def test_corrupt_database_preserves_previous_backup(self):
        self.connection.close()
        self.database.write_bytes(b"not a SQLite database")
        self.assert_preserved(self.run_backup())

    def test_locked_source_reports_failure(self):
        self.connection.close()
        with sqlite3.connect(self.database) as locked:
            locked.execute("PRAGMA journal_mode=DELETE")
            locked.execute("BEGIN EXCLUSIVE")
            self.assert_preserved(self.run_backup())

    def test_failed_copy_preserves_previous_backup(self):
        # Fault injection at the filesystem boundary: simulate a lost share
        # during the database copy, after a valid local snapshot exists.
        commands = self.root / "commands"
        commands.mkdir()
        cp = commands / "cp"
        cp.write_text(
            "#!/usr/bin/env bash\n"
            'if [[ "${!#}" == */.db.sqlite3.* ]]; then exit 1; fi\n'
            f'exec "{shutil.which("cp")}" "$@"\n'
        )
        cp.chmod(0o755)
        self.env["PATH"] = str(commands) + os.pathsep + self.env["PATH"]
        self.assert_preserved(self.run_backup())


if __name__ == "__main__":
    unittest.main()
