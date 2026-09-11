"""Integrity preflight must never mutate input or disclose stored secrets."""

from contextlib import closing
import importlib.util
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/lib/validate-state-file.py"
spec = importlib.util.spec_from_file_location("state_file_validation", SCRIPT)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class StateFileValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def cli(self, kind, path, *, valid, required_strings=None):
        before = {p.name: p.read_bytes() for p in self.root.iterdir() if p.is_file()}
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                kind,
                str(path),
                "--required-strings-json",
                json.dumps(required_strings if required_strings is not None else []),
            ],
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0 if valid else 1)
        self.assertNotIn(b"private-fixture-secret", result.stdout + result.stderr)
        self.assertEqual(
            before, {p.name: p.read_bytes() for p in self.root.iterdir() if p.is_file()}
        )
        return result

    def test_valid_json_and_no_mutation(self):
        path = self.root / "settings.json"
        path.write_text(
            '{"key":"private-fixture-secret","number":2,"nested":[true,null]}'
        )
        self.cli("json", path, valid=True)

    def test_json_corruption_nonstandard_constants_and_empty_file_refused(self):
        path = self.root / "settings.json"
        for value in (
            "",
            '{"private-fixture-secret":',
            '{"key":NaN}',
            '{"key":Infinity}',
            '{"key":-Infinity}',
            '{"private-fixture-secret":1} trailing',
        ):
            with self.subTest(value=value):
                path.write_text(value)
                self.cli("json", path, valid=False)

    def test_required_json_string_is_preserved_without_disclosure(self):
        path = self.root / "settings.json"
        path.write_text('{"encryptionKey":"private-fixture-secret"}')
        self.cli("json", path, valid=True, required_strings=["encryptionKey"])

    def test_missing_empty_or_wrong_type_json_string_is_refused(self):
        path = self.root / "settings.json"
        for value in [
            {},
            {"encryptionKey": ""},
            {"encryptionKey": " "},
            {"encryptionKey": None},
            {"encryptionKey": 42},
            ["private-fixture-secret"],
        ]:
            with self.subTest(value=value):
                path.write_text(json.dumps(value))
                self.cli("json", path, valid=False, required_strings=["encryptionKey"])

    def test_invalid_json_field_policy_is_refused(self):
        path = self.root / "settings.json"
        path.write_text('{"encryptionKey":"private-fixture-secret"}')
        for policy in ["encryptionKey", [None], [""], {"encryptionKey": True}]:
            with self.subTest(policy=policy):
                self.cli("json", path, valid=False, required_strings=policy)

    def test_missing_files_are_not_created(self):
        for kind in ("json", "sqlite"):
            path = self.root / kind
            self.cli(kind, path, valid=False)
            self.assertFalse(path.exists())

    def test_symlink_and_directory_refused(self):
        target = self.root / "source.json"
        target.write_text('{"key":"private-fixture-secret"}')
        link = self.root / "link"
        link.symlink_to(target)
        self.cli("json", link, valid=False)
        self.cli("json", self.root, valid=False)

    def database(self):
        path = self.root / "database.sqlite"
        with closing(sqlite3.connect(path)) as connection:
            connection.execute("CREATE TABLE records (value TEXT)")
            connection.execute("INSERT INTO records VALUES ('private-fixture-secret')")
            connection.commit()
        return path

    def test_valid_sqlite_and_no_mutation(self):
        self.cli("sqlite", self.database(), valid=True)

    def test_sqlite_empty_truncated_and_corrupt_refused(self):
        path = self.database()
        original = path.read_bytes()
        for data in (
            b"",
            b"private-fixture-secret",
            original[:120],
            original[:4096] + b"private-fixture-secret" + bytes(4096 - 22),
        ):
            with self.subTest(length=len(data)):
                path.write_bytes(data)
                self.cli("sqlite", path, valid=False)

    def test_uncheckpointed_wal_is_refused_without_touching_source_or_shm(self):
        path = self.database()
        connection = sqlite3.connect(path)
        self.addCleanup(connection.close)
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA wal_autocheckpoint=0")
        connection.execute(
            "INSERT INTO records VALUES ('another private-fixture-secret')"
        )
        connection.commit()
        self.assertTrue(Path(str(path) + "-wal").is_file())
        self.cli("sqlite", path, valid=False)

    def test_corrupt_wal_or_journal_is_not_silently_ignored(self):
        path = self.database()
        for suffix in ("-wal", "-journal"):
            companion = Path(str(path) + suffix)
            companion.write_bytes(b"private-fixture-secret")
            self.cli("sqlite", path, valid=False)
            companion.unlink()

    def test_empty_companions_are_allowed_without_mutation(self):
        path = self.database()
        for suffix in ("-wal", "-journal"):
            Path(str(path) + suffix).touch()
        self.cli("sqlite", path, valid=True)

    def test_symlink_wal_refused(self):
        path = self.database()
        other = self.root / "other"
        other.write_bytes(b"private-fixture-secret")
        Path(str(path) + "-wal").symlink_to(other)
        self.cli("sqlite", path, valid=False)


if __name__ == "__main__":
    unittest.main()
