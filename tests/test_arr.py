"""Behavioral acceptance fixtures for the initial Sonarr/qBittorrent adapter."""

from copy import deepcopy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs


def load(name):
    spec = importlib.util.spec_from_file_location(
        name, Path(__file__).parents[1] / "modules/services/arr" / f"{name}.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reconcile = load("reconcile")
storage = load("storage")
credentials = load("credentials")


class Applications:
    def __init__(self):
        self.categories = {}
        self.roots = []
        self.clients = []
        self.torrents = []
        self.writes = []
        self.interrupt = None
        self.unavailable = False
        self.preferences = {
            "save_path": "/data/torrents/",
            "temp_path": "/data/torrents/incomplete/",
            "temp_path_enabled": True,
            "auto_tmm_enabled": True,
        }
        self.schema = {
            "name": "qBittorrent",
            "implementation": "QBittorrent",
            "priority": 1,
            "tags": [],
            "fields": [
                {"name": name, "value": value, "label": name}
                for name, value in {
                    "host": "localhost",
                    "port": 8080,
                    "useSsl": False,
                    "urlBase": "",
                    "username": "",
                    "password": "",
                    "tvCategory": "tv",
                    "recentTvPriority": 0,
                }.items()
            ],
        }

    def request(self, method, path, data=None, **_kwargs):
        if self.unavailable:
            raise reconcile.ReconcileError("Application unavailable")
        if method == "GET":
            if path == "/api/v2/app/preferences":
                return deepcopy(self.preferences)
            if path == "/api/v2/torrents/categories":
                return deepcopy(self.categories)
            if path.startswith("/api/v2/torrents/info"):
                return deepcopy(self.torrents)
            if path == "/api/v3/rootfolder":
                return deepcopy(self.roots)
            if path == "/api/v3/downloadclient":
                return deepcopy(self.clients)
            if path == "/api/v3/downloadclient/schema":
                return [deepcopy(self.schema)]
            raise AssertionError(path)
        if path == "/api/v3/downloadclient/test":
            return []
        self.writes.append((method, path, deepcopy(data)))
        result = None
        if path.endswith(("createCategory", "editCategory")):
            self.categories[data["category"]] = {
                "name": data["category"],
                "savePath": data["savePath"],
            }
        elif path == "/api/v3/rootfolder":
            result = dict(data, id=len(self.roots) + 1)
            self.roots.append(result)
        elif path == "/api/v3/downloadclient":
            result = dict(data, id=len(self.clients) + 1)
            self.clients.append(result)
        elif path.startswith("/api/v3/downloadclient/"):
            result = deepcopy(data)
            self.clients = [
                result if client["id"] == result["id"] else client
                for client in self.clients
            ]
        else:
            raise AssertionError(path)
        if self.interrupt == path:
            self.interrupt = None
            raise OSError("interrupted after remote write")
        return deepcopy(result)


class ReconciliationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state = Path(self.tmp.name) / "ownership.json"
        self.apps = Applications()
        self.config = {
            "dryRun": False,
            "storageToQbittorrent": True,
            "downloadClient": True,
            "categoryPath": "/data/torrents/tv",
            "rootFolder": "/data/media/tv",
            "torrentRoot": "/data/torrents",
            "incomplete": "/data/torrents/incomplete",
            "relocation": "refuse",
            "qbittorrentEndpoint": "http://127.0.0.1:8080",
        }
        self.secret = {"username": "test-user", "password": "private-password"}

    def runner(self):
        return reconcile.Reconciler(
            self.config, self.state, self.apps, self.apps, self.secret
        )

    def test_setup_and_noop(self):
        self.assertEqual(len(self.runner().run()), 3)
        self.apps.writes.clear()
        self.assertEqual(self.runner().run(), [])
        self.assertEqual(self.apps.writes, [])
        self.assertEqual(self.apps.roots[0]["path"], self.config["rootFolder"])

    def test_drift_preserves_unowned_fields_and_user_objects(self):
        self.runner().run()
        self.apps.clients[0]["name"] = "changed in UI"
        self.apps.clients[0]["priority"] = 17
        self.apps.clients[0]["tags"] = [42]
        self.apps.clients[0]["fields"][0]["value"] = "wrong-host"
        manual = dict(deepcopy(self.apps.clients[0]), id=99, name="My client")
        self.apps.clients.append(manual)
        self.runner().run()
        self.assertEqual(self.apps.clients[0]["priority"], 17)
        self.assertEqual(self.apps.clients[0]["tags"], [42])
        self.assertEqual(self.apps.clients[1], manual)
        self.assertEqual(reconcile.fields(self.apps.clients[0])["host"], "127.0.0.1")

    def test_rotation_and_redacted_dry_run(self):
        self.runner().run()
        before = deepcopy(self.apps.clients)
        self.config["dryRun"] = True
        self.secret["password"] = "rotated-secret"
        report = self.runner().run()
        self.assertNotIn("rotated-secret", json.dumps(report))
        self.assertIn("password", json.dumps(report))
        self.assertEqual(before, self.apps.clients)
        self.config["dryRun"] = False
        self.runner().run()
        self.assertEqual(
            reconcile.fields(self.apps.clients[0])["password"], "rotated-secret"
        )

    def test_dry_run_has_no_state_or_api_writes(self):
        self.config["dryRun"] = True
        self.assertEqual(len(self.runner().run()), 3)
        self.assertFalse(self.state.exists())
        self.assertEqual(self.apps.writes, [])

    def test_ambiguous_and_unowned_objects_rejected(self):
        self.runner().run()
        self.apps.clients.append(deepcopy(self.apps.clients[0]))
        with self.assertRaisesRegex(reconcile.ReconcileError, "Ambiguous"):
            self.runner().run()
        self.apps.clients.pop()
        state = json.loads(self.state.read_text())
        state["resources"].pop("sonarr-client")
        reconcile.write_json(self.state, state)
        with self.assertRaisesRegex(reconcile.ReconcileError, "Unowned"):
            self.runner().run()

    def test_changed_identity_is_not_adopted(self):
        self.runner().run()
        self.apps.clients[0]["id"] = 500
        with self.assertRaisesRegex(reconcile.ReconcileError, "identity changed"):
            self.runner().run()

    def test_interrupted_remote_posts_recover_without_duplicates(self):
        for path in ("/api/v2/torrents/createCategory", "/api/v3/downloadclient"):
            with self.subTest(path=path):
                self.state.unlink(missing_ok=True)
                self.apps = Applications()
                self.apps.interrupt = path
                with self.assertRaises(OSError):
                    self.runner().run()
                self.runner().run()
                self.assertEqual(len(self.apps.clients), 1)
                self.assertEqual(len(self.apps.categories), 1)
                self.assertEqual(self.runner().run(), [])

    def test_relocation_requires_explicit_choice(self):
        self.runner().run()
        self.config["categoryPath"] = "/data/torrents/changed"
        self.apps.torrents = [{"hash": "existing"}]
        with self.assertRaisesRegex(reconcile.ReconcileError, "relocation"):
            self.runner().run()
        self.config["relocation"] = "allow"
        self.runner().run()
        self.assertEqual(
            next(iter(self.apps.categories.values()))["savePath"],
            self.config["categoryPath"],
        )

    def test_unavailable_and_conflicting_preferences_do_not_mutate(self):
        self.apps.unavailable = True
        with self.assertRaises(reconcile.ReconcileError):
            self.runner().run()
        self.apps.unavailable = False
        self.apps.preferences["save_path"] = "/wrong"
        with self.assertRaisesRegex(reconcile.ReconcileError, "conflicts"):
            self.runner().run()
        self.assertEqual(self.apps.writes, [])

    def test_disabling_stops_management_without_deleting(self):
        self.runner().run()
        before = deepcopy((self.apps.clients, self.apps.categories))
        self.config.update(storageToQbittorrent=False, downloadClient=False)
        self.apps.writes.clear()
        self.runner().run()
        self.assertEqual(before, (self.apps.clients, self.apps.categories))
        self.assertEqual(self.apps.writes, [])

    def test_restored_empty_application_recreated(self):
        self.runner().run()
        self.apps = Applications()
        self.runner().run()
        self.assertEqual(len(self.apps.clients), 1)
        self.assertEqual(len(self.apps.categories), 1)


class StorageTests(unittest.TestCase):
    def test_normalized_paths(self):
        for path in (
            "relative",
            "/",
            "/data/../other",
            "/data//tv",
            "/data/./tv",
            "/data/",
        ):
            self.assertFalse(storage.normalized(path), path)
        self.assertTrue(storage.normalized("/data/media/tv"))

    def test_crud_and_hardlinks_clean_up(self):
        with tempfile.TemporaryDirectory() as path:
            storage.probe([path], [[path, path]], "require")
            self.assertEqual(list(Path(path).iterdir()), [])
            with patch.object(
                storage.os, "link", side_effect=OSError(95, "not supported")
            ):
                storage.probe([path], [[path, path]], "warn")
                with self.assertRaises(OSError):
                    storage.probe([path], [[path, path]], "require")
            self.assertEqual(list(Path(path).iterdir()), [])

    def test_missing_mount_does_not_create_paths(self):
        with tempfile.TemporaryDirectory() as path:
            with self.assertRaisesRegex(RuntimeError, "not mounted"):
                storage.verify_mounts([path])
            self.assertEqual(list(Path(path).iterdir()), [])


class QbittorrentStartupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ("username", "password"):
            (self.root / name).write_text("fixture")
        self.apps = Applications()
        self.requests = []
        self.reject_login = False
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                fixture.requests.append((self.command, self.path))
                if self.path == "/":
                    result = b"<html>Login</html>"
                elif self.path == "/api/v2/auth/login":
                    self.rfile.read(int(self.headers.get("Content-Length", 0)))
                    result = b"Fails." if fixture.reject_login else b"Ok."
                elif self.headers.get("Cookie") != "SID=fixture":
                    self.send_response(403)
                    self.end_headers()
                    return
                elif self.path == "/api/v2/app/version":
                    result = b"v5.2.3"
                else:
                    data = None
                    if self.command == "POST":
                        body = self.rfile.read(
                            int(self.headers.get("Content-Length", 0))
                        )
                        data = {
                            key: values[0]
                            for key, values in parse_qs(body.decode()).items()
                        }
                    result = json.dumps(
                        fixture.apps.request(self.command, self.path, data)
                    ).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(result)))
                if self.path == "/api/v2/auth/login" and not fixture.reject_login:
                    self.send_header("Set-Cookie", "SID=fixture; Path=/")
                self.end_headers()
                self.wfile.write(result)

            do_POST = do_GET

            def log_message(self, *_args):
                pass

        # Reserve the port without listening, modelling Type=simple while the
        # application is still restoring its session. No real delay is needed.
        self.server = ThreadingHTTPServer(
            ("127.0.0.1", 0), Handler, bind_and_activate=False
        )
        self.addCleanup(self.server.server_close)
        self.server.server_bind()
        self.started = False
        self.config = {
            "applications": [
                {
                    "application": "sonarr",
                    "dryRun": False,
                    "storageToQbittorrent": True,
                    "downloadClient": False,
                    "categoryPath": "/data/torrents/tv",
                    "torrentRoot": "/data/torrents",
                    "incomplete": "/data/torrents/incomplete",
                    "relocation": "refuse",
                }
            ],
            "qbittorrentEndpoint": f"http://127.0.0.1:{self.server.server_port}",
            "prowlarrApplications": [],
        }

    def start_webui(self, _delay=None):
        if not self.started:
            self.server.server_activate()
            threading.Thread(target=self.server.serve_forever, daemon=True).start()
            self.started = True
            self.addCleanup(self.server.shutdown)

    def run_configuration(self):
        with patch.dict(os.environ, CREDENTIALS_DIRECTORY=str(self.root)):
            return reconcile.run_configuration(self.config, self.root)

    def test_delayed_listener_recovers_before_authentication_and_writes(self):
        with patch.object(
            reconcile.time, "sleep", side_effect=self.start_webui
        ) as wait:
            self.assertEqual(len(self.run_configuration()), 1)
        self.assertEqual(wait.call_count, 1)
        self.assertEqual(
            self.requests[:3],
            [
                ("GET", "/"),
                ("POST", "/api/v2/auth/login"),
                ("GET", "/api/v2/app/version"),
            ],
        )
        self.apps.writes.clear()
        self.assertEqual(self.run_configuration(), [])
        self.assertEqual(self.apps.writes, [])

    def test_unavailable_listener_is_bounded_and_cannot_mutate(self):
        with patch.object(reconcile.time, "sleep") as wait:
            with self.assertRaisesRegex(reconcile.ReconcileError, "API unavailable"):
                self.run_configuration()
        self.assertEqual(wait.call_count, 5)
        self.assertFalse(self.apps.writes)
        self.assertFalse((self.root / "ownership.json").exists())

    def test_invalid_credentials_are_not_retried_as_startup_delay(self):
        self.reject_login = True
        self.start_webui()
        with patch.object(reconcile.time, "sleep") as wait:
            with self.assertRaisesRegex(reconcile.ReconcileError, "credential drift"):
                self.run_configuration()
        self.assertEqual(wait.call_count, 0)
        self.assertEqual(self.requests, [("GET", "/"), ("POST", "/api/v2/auth/login")])
        self.assertFalse(self.apps.writes)


class CredentialTests(unittest.TestCase):
    def test_padded_base64_keys_and_environment_syntax(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.json"
            for key in ("YWJjZGVmZ2hpamtsbW5vcA==", "a" * 16 + "+/="):
                path.write_text(json.dumps({"main": {"apiKey": key}}))
                self.assertEqual(credentials.extract(path, "seerr"), key)
                path.write_text(key)
                self.assertEqual(credentials.extract(path, "raw"), key)
            for suffix in ("\nINJECTED=value", '"', "'", "\\", " ", "==="):
                path.write_text(json.dumps({"main": {"apiKey": "a" * 32 + suffix}}))
                with self.subTest(suffix=suffix), self.assertRaises(ValueError):
                    credentials.extract(path, "seerr")

    def test_parsers_and_rotation_restrict_files(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.xml"
            key = "a" * 32
            path.write_text(f"<Config><ApiKey>{key}</ApiKey></Config>")
            self.assertEqual(credentials.extract(path, "xml"), key)
            output = Path(directory) / "runtime/api-key"
            config = {
                "document": str(Path(directory) / "deployed.yaml"),
                "service": "sonarr",
                "keys": {"api-key": {"file": str(Path(directory) / "sops-key")}},
                "outputs": [{"path": str(output), "key": "api-key"}],
                "consumers": ["test.service"],
            }
            Path(directory, "sops-key").write_text(key)
            with patch.object(credentials.subprocess, "run") as restart:
                credentials.publish(config)
                self.assertEqual(restart.call_count, 1)
                credentials.publish(config)
                self.assertEqual(restart.call_count, 1)
                Path(directory, "sops-key").write_text("b" * 32)
                credentials.publish(config)
                self.assertEqual(restart.call_count, 2)
            self.assertEqual(output.stat().st_mode & 0o777, 0o400)
            path.write_text("<broken")
            with self.assertRaises(credentials.ET.ParseError):
                credentials.extract(path, "xml")
            path.write_text("auth:\n  apikey: '" + key + "'\n")
            self.assertEqual(credentials.extract(path, "yaml"), key)
            path.write_text(
                f"__version__ = 19\n[misc]\napi_key = {key}\n[servers]\n[[fixture]]\npassword = ignored\n"
            )
            self.assertEqual(credentials.extract(path, "ini"), key)
            path.write_text(json.dumps({"main": {"apiKey": key}}))
            self.assertEqual(credentials.extract(path, "seerr"), key)
            path.write_text(key)
            self.assertEqual(credentials.extract(path, "raw"), key)
            path.write_text("line1\nline2")
            with self.assertRaises(ValueError):
                credentials.extract(path, "raw")


class ProcessStatusTests(unittest.TestCase):
    def test_interrupted_request_cannot_advertise_previous_success(self):
        with tempfile.TemporaryDirectory() as directory, socket.socket() as listener:
            root = Path(directory)
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            state = root / "state"
            state.mkdir()
            status_path = state / "status.json"
            status_path.write_text(json.dumps({"success": True, "lastSuccess": 123}))
            for name in ("username", "password"):
                (root / name).write_text("disposable-fixture")
            configuration = root / "desired.json"
            configuration.write_text(
                json.dumps(
                    {
                        "dryRun": False,
                        "applications": [{}],
                        "qbittorrentEndpoint": f"http://127.0.0.1:{listener.getsockname()[1]}",
                        "metricsFile": str(root / "metrics/arr.prom"),
                    }
                )
            )
            process = subprocess.Popen(
                [
                    sys.executable,
                    reconcile.__file__,
                    str(configuration),
                    "--state-dir",
                    str(state),
                ],
                env=dict(os.environ, CREDENTIALS_DIRECTORY=str(root)),
            )
            try:
                # The HTTP peer deliberately never responds.
                for _ in range(100):
                    if (root / "metrics/arr.prom").exists():
                        break
                    time.sleep(0.02)
                self.assertTrue((root / "metrics/arr.prom").exists())
            finally:
                process.terminate()
                process.wait(timeout=5)
            status = json.loads(status_path.read_text())
            self.assertFalse(status["success"])
            self.assertEqual(status["lastSuccess"], 123)
            self.assertIn("has not completed", status["lastError"])
            self.assertIn(
                "reconciliation_success 0", (root / "metrics/arr.prom").read_text()
            )


if __name__ == "__main__":
    unittest.main()
