"""Snapshot-adapter protocol/refusal checks; no Elasticsearch runtime claim."""

import copy
import importlib.util
import io
import json
import os
import base64
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "elasticsearch_snapshot",
    Path(__file__).resolve().parents[1] / "scripts/lib/elasticsearch-snapshot.py",
)
SNAPSHOT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SNAPSHOT)


class Peer:
    def __init__(self):
        self.calls = []
        self.version = "8.19.0"
        self.snapshot = {
            "snapshot": "nixstead-" + "a" * 32,
            "version": self.version,
            "state": "SUCCESS",
            "indices": ["ta_config", "ta_channel", "ta_video", "ta_download"],
            "shards": {"total": 4, "successful": 4, "failed": 0},
            "include_global_state": False,
            "feature_states": [],
        }
        self.fail_restore = False
        self.fail_unregister = False

    def ready(self):
        self.calls.append(("ready",))
        return {"version": {"number": self.version}}

    def register(self, name, readonly=False):
        self.calls.append(("register", name, readonly))

    def unregister(self, name):
        self.calls.append(("unregister", name))
        if self.fail_unregister:
            raise SNAPSHOT.SnapshotError("repository busy")

    def remove_export(self, name):
        self.calls.append(("remove", name))

    def export(self, name, destination):
        self.calls.append(("export", name))
        (destination / "index-0").write_bytes(b"repository metadata")
        (destination / "indices").mkdir()
        (destination / "indices" / "data").write_bytes(b"populated index bytes")

    def import_repository(self, name, source):
        self.calls.append(("import", name))
        assert (source / "indices/data").read_bytes() == b"populated index bytes"

    def request(self, method, path, payload=None):
        self.calls.append((method, path, payload))
        if method == "PUT":
            self.snapshot["snapshot"] = path.split("/")[3].split("?")[0]
            return {"snapshot": self.snapshot}
        if method == "GET" and path.startswith("/_snapshot/"):
            return {"snapshots": [self.snapshot]}
        if method == "GET" and path.startswith("/_cat/"):
            return [
                {"index": name}
                for name in ["ta_config", "ta_video", "unrelated", "ta_unowned"]
            ]
        if method == "DELETE":
            return {"acknowledged": True}
        if method == "POST":
            if self.fail_restore:
                raise SNAPSHOT.SnapshotError("restore interrupted")
            return {"snapshot": {"shards": {"failed": 0, "successful": 4, "total": 4}}}
        raise AssertionError((method, path))


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.archive = self.root / "snapshot.tar"
        self.peer = Peer()
        SNAPSHOT.backup(self.peer, self.archive)

    def mutate_archive(self, mutate):
        with tarfile.open(self.archive) as archive:
            members = [
                (member.name, archive.extractfile(member).read()) for member in archive
            ]
        members = mutate(members)
        with tarfile.open(self.archive, "w") as archive:
            for name, data in members:
                member = tarfile.TarInfo(name)
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))

    def test_native_snapshot_is_complete_and_repository_unregistered_before_export(
        self,
    ):
        names = [call[0] for call in self.peer.calls]
        self.assertLess(names.index("unregister"), names.index("export"))
        manifest = SNAPSHOT.validate_archive(self.archive)
        self.assertEqual(manifest["indices"], sorted(self.peer.snapshot["indices"]))
        self.assertEqual(self.archive.stat().st_mode & 0o777, 0o600)
        request = next(call for call in self.peer.calls if call[0] == "PUT")
        self.assertEqual(request[2]["indices"], "ta_*")
        self.assertFalse(request[2]["include_global_state"])
        self.assertEqual(request[2]["feature_states"], ["none"])

    def test_restore_replaces_only_named_present_indices_and_preserves_unrelated(self):
        self.peer.calls.clear()
        SNAPSHOT.restore(self.peer, self.archive)
        deleted = [call[1] for call in self.peer.calls if call[0] == "DELETE"]
        self.assertEqual(deleted, ["/ta_config,ta_video"])
        request = next(call for call in self.peer.calls if call[0] == "POST")
        self.assertFalse(request[2]["include_global_state"])
        self.assertEqual(request[2]["feature_states"], ["none"])
        self.assertTrue(
            next(call for call in self.peer.calls if call[0] == "register")[2]
        )

    def test_missing_essential_file_refuses_before_contacting_live_cluster(self):
        self.mutate_archive(
            lambda members: [
                (name, data)
                for name, data in members
                if name != "repository/indices/data"
            ]
        )
        self.peer.calls.clear()
        with self.assertRaises(SNAPSHOT.SnapshotError):
            SNAPSHOT.restore(self.peer, self.archive)
        self.assertEqual(self.peer.calls, [])

    def test_corrupt_file_refuses_before_contacting_live_cluster(self):
        self.mutate_archive(
            lambda members: [
                (name, b"corrupt" if name == "repository/indices/data" else data)
                for name, data in members
            ]
        )
        self.peer.calls.clear()
        with self.assertRaises(SNAPSHOT.SnapshotError):
            SNAPSHOT.restore(self.peer, self.archive)
        self.assertEqual(self.peer.calls, [])

    def test_path_traversal_and_duplicate_members_are_refused(self):
        for name in (
            "../escape",
            "/tmp/escape",
            "repository/../escape",
            "manifest.json",
        ):
            with self.subTest(name=name):
                SNAPSHOT.backup(self.peer, self.archive)
                self.mutate_archive(lambda members: members + [(name, b"bad")])
                with self.assertRaises(SNAPSHOT.SnapshotError):
                    SNAPSHOT.validate_archive(self.archive)
        self.assertFalse((self.root / "escape").exists())

    def test_symlink_is_refused(self):
        with tarfile.open(self.archive, "a") as archive:
            member = tarfile.TarInfo("repository/link")
            member.type, member.linkname = tarfile.SYMTYPE, "/tmp"
            archive.addfile(member)
        with self.assertRaises(SNAPSHOT.SnapshotError):
            SNAPSHOT.validate_archive(self.archive)

    def test_version_mismatch_and_manifest_disagreement_never_delete_live_indices(self):
        for changed in ("version", "indices"):
            with self.subTest(changed=changed):
                self.peer.calls.clear()
                if changed == "version":
                    self.peer.version = "8.20.0"
                else:
                    self.peer.version = "8.19.0"
                    self.peer.snapshot["indices"].append("ta_extra")
                with self.assertRaises(SNAPSHOT.SnapshotError):
                    SNAPSHOT.restore(self.peer, self.archive)
                self.assertFalse(any(call[0] == "DELETE" for call in self.peer.calls))

    def test_incomplete_snapshot_preserves_prior_successful_archive(self):
        previous = self.archive.read_bytes()
        self.peer.snapshot["shards"]["failed"] = 1
        with self.assertRaises(SNAPSHOT.SnapshotError):
            SNAPSHOT.backup(self.peer, self.archive)
        self.assertEqual(self.archive.read_bytes(), previous)

    def test_failed_unregister_never_removes_registered_repository(self):
        self.peer.fail_unregister = True
        self.peer.calls.clear()
        with self.assertRaises(SNAPSHOT.SnapshotError):
            SNAPSHOT.backup(self.peer, self.archive)
        self.assertFalse(
            any(call[0] in ("export", "remove") for call in self.peer.calls)
        )

    def test_interrupted_restore_reports_failure_and_leaves_unrelated_indices_untouched(
        self,
    ):
        self.peer.calls.clear()
        self.peer.fail_restore = True
        with self.assertRaisesRegex(SNAPSHOT.SnapshotError, "restore interrupted"):
            SNAPSHOT.restore(self.peer, self.archive)
        self.assertEqual(
            [call[1] for call in self.peer.calls if call[0] == "DELETE"],
            ["/ta_config,ta_video"],
        )
        self.assertEqual(self.peer.calls[-1][0], "remove")

    def test_failed_command_diagnostics_do_not_contain_response_or_credentials(self):
        with patch.object(
            SNAPSHOT.subprocess,
            "run",
            side_effect=subprocess.CalledProcessError(
                1, ["docker"], stderr=b"private-password"
            ),
        ):
            with self.assertRaises(SNAPSHOT.SnapshotError) as result:
                SNAPSHOT.Elasticsearch("tubearchivist-es").request("GET", "/")
        self.assertNotIn("private-password", str(result.exception))

    def test_wrong_snapshot_identity_refuses_before_deleting_live_indices(self):
        self.peer.snapshot["snapshot"] = "nixstead-" + "b" * 32
        self.peer.calls.clear()
        with self.assertRaises(SNAPSHOT.SnapshotError):
            SNAPSHOT.restore(self.peer, self.archive)
        self.assertFalse(any(call[0] == "DELETE" for call in self.peer.calls))

    def test_malformed_api_response_is_refused_without_logging_body(self):
        with patch.object(SNAPSHOT, "execute", return_value=b'["private-body"]'):
            with self.assertRaises(SNAPSHOT.SnapshotError) as result:
                SNAPSHOT.Elasticsearch("tubearchivist-es").request("GET", "/")
        self.assertNotIn("private-body", str(result.exception))

    def test_readiness_waits_for_primary_shard_recovery(self):
        client = SNAPSHOT.Elasticsearch("tubearchivist-es")
        version = {"version": {"number": "8.19.0"}}
        with (
            patch.object(
                client,
                "request",
                side_effect=[
                    version,
                    {"status": "red", "timed_out": True},
                    version,
                    {"status": "yellow", "timed_out": False},
                ],
            ) as request,
            patch.object(SNAPSHOT.time, "sleep") as sleep,
        ):
            self.assertEqual(client.ready(), version)
        self.assertEqual(sleep.call_count, 1)
        self.assertIn("wait_for_no_initializing_shards=true", request.call_args.args[1])

    def test_runtime_request_omits_get_body_and_keeps_authentication_out_of_argv(self):
        with patch.object(SNAPSHOT, "execute", return_value=b"{}") as execute:
            SNAPSHOT.Elasticsearch("tubearchivist-es").request("GET", "/")
        self.assertEqual(execute.call_args.args[0][-1], "")
        commands = self.root / "bin"
        commands.mkdir()
        curl = commands / "curl"
        curl.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\nfrom pathlib import Path\nPath(os.environ['SNAPSHOT_CALL_LOG']).write_text(json.dumps({'argv': sys.argv[1:], 'stdin': sys.stdin.read()}))\nprint('{}')\n"
        )
        curl.chmod(0o755)
        secret = 'disposable\nquote"backslash\\password'
        log = self.root / "request.json"
        subprocess.run(
            ["sh", "-c", SNAPSHOT.REQUEST, "nixstead-snapshot", "GET", "/", ""],
            env={
                **os.environ,
                "PATH": str(commands) + os.pathsep + os.environ["PATH"],
                "ELASTIC_PASSWORD": secret,
                "SNAPSHOT_CALL_LOG": str(log),
            },
            check=True,
            capture_output=True,
        )
        request = json.loads(log.read_text())
        self.assertNotIn("--data-binary", request["argv"])
        self.assertNotIn(secret, str(request["argv"]))
        self.assertIn(
            base64.b64encode(("elastic:" + secret).encode()).decode(), request["stdin"]
        )

    def test_security_or_missing_application_indices_are_refused(self):
        for indices in (
            [".security-7"],
            ["ta_video"],
            ["ta_video", "ta_config", "ta_channel", "unrelated"],
        ):
            with self.subTest(indices=indices):
                snapshot = copy.deepcopy(self.peer.snapshot)
                snapshot["indices"] = indices
                with self.assertRaises(SNAPSHOT.SnapshotError):
                    SNAPSHOT.check_snapshot(snapshot)


if __name__ == "__main__":
    unittest.main()
