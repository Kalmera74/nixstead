import importlib.util
import os
from pathlib import Path
import tempfile
import unittest


SCRIPT = (
    Path(__file__).resolve().parents[1] / "scripts/lib/validate-mongodb-directory.py"
)
spec = importlib.util.spec_from_file_location("mongodb_directory", SCRIPT)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class MongoDBDirectoryBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.source.mkdir()
        (self.source / "data").write_bytes(b"original database bytes")
        self.copy = self.root / "copy"

    def test_copy_has_independent_bytes_and_preserves_input(self):
        validator.copy_source(self.source, self.copy)
        (self.copy / "data").write_bytes(b"native recovery changed its copy")
        self.assertEqual(
            (self.source / "data").read_bytes(), b"original database bytes"
        )

    def test_source_symlink_is_refused(self):
        link = self.root / "linked"
        link.symlink_to(self.source, target_is_directory=True)
        with self.assertRaises(ValueError):
            validator.copy_source(link, self.copy)
        self.assertFalse(self.copy.exists())

    def test_nested_symlink_cannot_reach_original_or_external_bytes(self):
        (self.source / "escape").symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            validator.copy_source(self.source, self.copy)
        self.assertFalse(self.copy.exists())

    def test_special_file_is_refused_before_copy(self):
        os.mkfifo(self.source / "pipe")
        with self.assertRaises(ValueError):
            validator.copy_source(self.source, self.copy)
        self.assertFalse(self.copy.exists())

    def test_policy_requires_absolute_executable_and_argument_vector(self):
        policy = {
            "executable": "/native/mongod",
            "ip": "/native/ip",
            "arguments": ["--auth"],
            "timeoutSeconds": 45,
        }
        validator.validate_policy(policy)
        for change in [
            {"executable": "mongod"},
            {"ip": "ip"},
            {"arguments": "mongod; other-command"},
            {"arguments": [None]},
            {"timeoutSeconds": 0},
            {"timeoutSeconds": 301},
        ]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                validator.validate_policy({**policy, **change})


if __name__ == "__main__":
    unittest.main()
