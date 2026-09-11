"""Existing Seerr connections: explicit field ownership and recovery."""

from copy import deepcopy
import json
from pathlib import Path
import runpy
import tempfile
import unittest
from urllib.parse import parse_qs, urlsplit

from test_arr import reconcile

ensure = runpy.run_path(
    str(Path(__file__).parents[1] / "modules/services/media/seerr_adapter.py")
)["ensure"]


class Seerr:
    def __init__(self, application):
        self.application = application
        self.key = "runtime-arr-key-123456789"
        self.servers = [
            {
                "id": 0,
                "name": "My server",
                "hostname": "192.0.2.20",
                "port": 443,
                "useSsl": True,
                "baseUrl": "/old",
                "apiKey": "old-key",
                "activeProfileId": 3,
                "activeDirectory": "/media/library",
                "activeProfileName": "My profile",
                "syncEnabled": True,
                "tags": [11],
                "isDefault": True,
                "is4k": False,
                "preventSearch": True,
            }
        ]
        self.writes = []
        self.tests = 0
        self.unavailable = False
        self.interrupt = False
        self.concurrent_edit = False

    def request(self, method, path, data=None):
        route = "/api/v1/settings/" + self.application
        if path == "/api/v1/user?take=1":
            return {"results": [{"id": 1}]}
        if method == "GET" and path == route:
            return deepcopy(self.servers)
        if method == "POST" and path == route + "/test":
            self.tests += 1
            if self.unavailable or data["apiKey"] != self.key:
                raise reconcile.ReconcileError("ARR connection unavailable")
            if self.concurrent_edit:
                self.concurrent_edit = False
                self.servers[0]["tags"].append(42)
            return {
                "profiles": [{"id": 3}],
                "rootFolders": [{"path": "/media/library"}],
            }
        if method == "PUT" and path.startswith(route + "/"):
            identity = int(path.rsplit("/", 1)[1])
            self.writes.append(deepcopy(data))
            self.servers = [
                dict(deepcopy(data), id=identity)
                if server["id"] == identity
                else server
                for server in self.servers
            ]
            if self.interrupt:
                self.interrupt = False
                raise OSError("Interrupted after the remote write")
            return deepcopy(
                next(server for server in self.servers if server["id"] == identity)
            )
        raise AssertionError((method, path))


class ExistingSeerrTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.state = Path(self.temp.name) / "ownership.json"
        self.app = Seerr("sonarr")
        self.destination = {
            "application": "sonarr",
            "existingServer": {},
            "endpoint": "http://127.0.0.1:8989",
        }
        self.dry_run = False

    def run_adapter(self):
        journal = reconcile.Reconciler(
            {"dryRun": self.dry_run}, self.state, None, None, {}
        )
        ensure(
            journal,
            self.app,
            {"destinations": [self.destination]},
            {self.app.application: self.app.key},
            reconcile.ReconcileError,
        )
        return journal.changes

    def test_repair_and_second_run_preserve_user_policy(self):
        before = deepcopy(self.app.servers[0])
        self.assertEqual(len(self.run_adapter()), 1)
        expected = dict(
            before,
            hostname="127.0.0.1",
            port=8989,
            useSsl=False,
            baseUrl="",
            apiKey=self.app.key,
        )
        self.assertEqual(self.app.servers[0], expected)
        self.app.writes.clear()
        self.assertEqual(self.run_adapter(), [])
        self.assertEqual(self.app.writes, [])
        self.assertGreaterEqual(self.app.tests, 3)

    def test_rotation_drift_and_redacted_dry_run(self):
        self.run_adapter()
        self.app.servers[0].update(hostname="wrong", name="Renamed in UI", tags=[25])
        self.app.key = "rotated-private-api-key"
        before = deepcopy(self.app.servers)
        self.dry_run = True
        changes = self.run_adapter()
        self.assertNotIn(self.app.key, json.dumps(changes))
        self.assertIn("apiKey", json.dumps(changes))
        self.assertEqual(before, self.app.servers)
        self.dry_run = False
        self.run_adapter()
        self.assertEqual(self.app.servers[0]["name"], "Renamed in UI")
        self.assertEqual(self.app.servers[0]["tags"], [25])
        self.assertEqual(self.app.servers[0]["apiKey"], self.app.key)

    def test_ambiguous_selection_requires_id_or_name(self):
        self.app.servers.append(
            dict(deepcopy(self.app.servers[0]), id=2, name="Other server")
        )
        untouched = deepcopy(self.app.servers[1])
        with self.assertRaisesRegex(reconcile.ReconcileError, "exactly one"):
            self.run_adapter()
        self.assertFalse(self.app.writes)
        self.destination["existingServer"] = {"id": 0, "name": "My server"}
        self.run_adapter()
        self.assertEqual(self.app.servers[1], untouched)

    def test_interrupted_update_recovers_the_recorded_id(self):
        self.app.interrupt = True
        with self.assertRaises(OSError):
            self.run_adapter()
        self.assertTrue(
            json.loads(self.state.read_text())["resources"]["seerr-existing-sonarr"][
                "pending"
            ]
        )
        self.app.servers.append(
            dict(deepcopy(self.app.servers[0]), id=1, name="Later user server")
        )
        self.app.writes.clear()
        self.assertEqual(self.run_adapter(), [])
        self.assertFalse(self.app.writes)
        self.assertFalse(
            json.loads(self.state.read_text())["resources"]["seerr-existing-sonarr"][
                "pending"
            ]
        )

    def test_missing_recorded_server_is_not_replaced(self):
        self.run_adapter()
        self.app.servers[0]["id"] = 9
        self.app.writes.clear()
        with self.assertRaises(reconcile.ReconcileError):
            self.run_adapter()
        self.assertFalse(self.app.writes)

    def test_unavailable_dependency_and_invalid_policy_stop_writes(self):
        self.app.unavailable = True
        with self.assertRaises(reconcile.ReconcileError):
            self.run_adapter()
        self.app.unavailable = False
        self.app.servers[0]["activeDirectory"] = "/missing"
        with self.assertRaisesRegex(reconcile.ReconcileError, "profile or root folder"):
            self.run_adapter()
        self.assertFalse(self.app.writes)

    def test_unchanged_settings_still_test_connectivity(self):
        self.run_adapter()
        self.app.writes.clear()
        self.app.unavailable = True
        with self.assertRaisesRegex(reconcile.ReconcileError, "connection unavailable"):
            self.run_adapter()
        self.assertFalse(self.app.writes)

    def test_concurrent_ui_edit_is_preserved_on_retry(self):
        self.app.concurrent_edit = True
        with self.assertRaisesRegex(reconcile.ReconcileError, "changed during"):
            self.run_adapter()
        self.assertFalse(self.app.writes)
        self.run_adapter()
        self.assertEqual(self.app.servers[0]["tags"], [11, 42])

    def test_radarr_uses_its_selected_existing_server(self):
        self.app = Seerr("radarr")
        self.destination.update(application="radarr", endpoint="http://127.0.0.1:7878")
        self.run_adapter()
        self.assertEqual(self.app.servers[0]["port"], 7878)
        self.assertEqual(self.app.servers[0]["name"], "My server")


class Jellyfin:
    def __init__(self):
        self.items = [
            {
                "Id": identity,
                "Name": identity.title(),
                "Type": "CollectionFolder",
                "CollectionType": kind,
            }
            for identity, kind in (
                ("tv", "tvshows"),
                ("movies", "movies"),
                ("mixed", ""),
                ("music", "music"),
            )
        ]
        self.unavailable = False
        self.calls = 0
        self.on_discover = lambda: None

    def request(self, method, path):
        assert (method, path) == ("GET", "/Library/MediaFolders")
        self.calls += 1
        if self.unavailable:
            raise reconcile.ReconcileError("Application credential drift")
        self.on_discover()
        return {"Items": deepcopy(self.items)}


class LibrarySeerr:
    def __init__(self, jellyfin):
        self.jellyfin = jellyfin
        self.settings = {
            "ip": "127.0.0.1",
            "port": 8096,
            "urlBase": "",
            "useSsl": False,
            "apiKey": "fixture-jellyfin-key",
            "libraries": [],
            "externalHostname": "https://watch.example.test",
            "serverId": "fixture-server",
        }
        self.admin = True
        self.writes = []
        self.interrupt = False

    def request(self, method, path, data=None):
        route = "/api/v1/settings/jellyfin"
        if path == "/api/v1/user?take=1":
            return {"results": [{"id": 1}] if self.admin else []}
        if method == "GET" and path == route:
            return deepcopy(self.settings)
        if method == "POST" and path == route:
            self.writes.append((method, path))
            self.settings.update(deepcopy(data))
            return deepcopy(self.settings)
        if method == "GET" and path.startswith(route + "/library?"):
            self.writes.append((method, path))
            query = parse_qs(urlsplit(path).query, keep_blank_values=True)
            enabled = query.get("enable", [""])[0].split(",")
            # Model the pinned server's refresh and selection in one save.
            self.settings["libraries"] = [
                {
                    "id": item["Id"],
                    "name": item["Name"],
                    "type": "movie" if item["CollectionType"] == "movies" else "show",
                    "enabled": item["Id"] in enabled,
                }
                for item in self.jellyfin.items
                if item["CollectionType"] != "music"
            ]
            if self.interrupt:
                self.interrupt = False
                raise OSError("Lost reply after saved library selection")
            return deepcopy(self.settings["libraries"])
        raise AssertionError((method, path))


class JellyfinLibraryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.state = Path(self.temp.name) / "ownership.json"
        self.jellyfin = Jellyfin()
        self.seerr = LibrarySeerr(self.jellyfin)
        self.connection = {
            "endpoint": "http://127.0.0.1:8096",
            "libraryPolicy": "auto",
            "libraries": [],
        }
        self.key = "fixture-jellyfin-key"
        self.dry_run = False

    def run_adapter(self):
        journal = reconcile.Reconciler(
            {"dryRun": self.dry_run}, self.state, None, None, {}
        )
        ensure(
            journal,
            self.seerr,
            {"destinations": [], "jellyfin": self.connection},
            {"jellyfin": self.key},
            reconcile.ReconcileError,
            jellyfin=self.jellyfin,
        )
        return journal.changes

    def enabled(self):
        return {
            item["id"] for item in self.seerr.settings["libraries"] if item["enabled"]
        }

    def test_fresh_auto_discovers_movie_tv_and_second_run_is_read_only(self):
        self.assertTrue(self.run_adapter())
        self.assertEqual(self.enabled(), {"tv", "movies"})
        self.assertEqual(len(self.seerr.settings["libraries"]), 3)
        self.seerr.writes.clear()
        self.assertEqual(self.run_adapter(), [])
        self.assertEqual(self.seerr.writes, [])
        self.assertEqual(self.jellyfin.calls, 2)

    def test_auto_preserves_existing_ui_choices_and_discovers_new_disabled_libraries(
        self,
    ):
        self.run_adapter()
        for item in self.seerr.settings["libraries"]:
            item["enabled"] = item["id"] == "mixed"
        self.jellyfin.items[0]["Name"] = "Renamed Shows"
        self.jellyfin.items.append(
            dict(self.jellyfin.items[0], Id="new-tv", Name="New Shows")
        )
        self.run_adapter()
        self.assertEqual(self.enabled(), {"mixed"})
        self.assertEqual(len(self.seerr.settings["libraries"]), 4)
        self.assertEqual(
            self.seerr.settings["externalHostname"], "https://watch.example.test"
        )
        self.assertEqual(self.run_adapter(), [])

    def test_auto_preserves_all_disabled_even_without_ownership_journal(self):
        self.run_adapter()
        for item in self.seerr.settings["libraries"]:
            item["enabled"] = False
        self.state.unlink(missing_ok=True)
        self.seerr.writes.clear()
        self.assertEqual(self.run_adapter(), [])
        self.assertEqual(self.enabled(), set())
        self.assertEqual(self.seerr.writes, [])

    def test_preserve_does_not_seed_an_empty_list(self):
        self.connection["libraryPolicy"] = "preserve"
        self.run_adapter()
        self.assertEqual(self.enabled(), set())
        self.assertTrue(self.seerr.settings["libraries"])
        self.assertEqual(self.run_adapter(), [])

    def test_movie_tv_policy_corrects_drift_and_includes_new_libraries(self):
        self.connection["libraryPolicy"] = "movies-and-tv"
        self.run_adapter()
        for item in self.seerr.settings["libraries"]:
            item["enabled"] = item["id"] == "mixed"
        self.jellyfin.items.append(
            dict(self.jellyfin.items[0], Id="new-tv", Name="New Shows")
        )
        self.run_adapter()
        self.assertEqual(self.enabled(), {"tv", "movies", "mixed", "new-tv"})
        self.assertEqual(self.run_adapter(), [])

    def test_explicit_selection_remains_supported_and_validated_before_writes(self):
        self.connection.pop("libraryPolicy")
        self.connection["libraries"] = ["tv"]
        self.run_adapter()
        self.assertEqual(self.enabled(), {"tv"})
        self.connection["libraries"] = ["missing"]
        self.seerr.settings["ip"] = "old-host"
        self.seerr.writes.clear()
        with self.assertRaisesRegex(reconcile.ReconcileError, "explicitly selected"):
            self.run_adapter()
        self.assertEqual(self.seerr.writes, [])

    def test_fresh_dry_run_and_key_rotation_are_redacted(self):
        self.key = "rotated-private-key"
        self.dry_run = True
        before = deepcopy(self.seerr.settings)
        changes = self.run_adapter()
        self.assertEqual(len(changes), 2)
        self.assertIn("apiKey", json.dumps(changes))
        self.assertNotIn(self.key, json.dumps(changes))
        self.assertEqual(self.seerr.settings, before)
        self.assertEqual(self.seerr.writes, [])
        self.assertFalse(self.state.exists())
        self.dry_run = False
        self.run_adapter()
        self.assertEqual(self.seerr.settings["apiKey"], self.key)
        self.assertEqual(self.run_adapter(), [])

    def test_dependency_failure_does_not_change_connection_or_selections(self):
        self.run_adapter()
        self.jellyfin.unavailable = True
        self.key = "invalid-key"
        self.seerr.writes.clear()
        before = deepcopy(self.seerr.settings)
        with self.assertRaisesRegex(reconcile.ReconcileError, "credential drift"):
            self.run_adapter()
        self.assertEqual(self.seerr.settings, before)
        self.assertEqual(self.seerr.writes, [])

    def test_empty_ambiguous_and_missing_enabled_discovery_fail_without_writes(self):
        self.run_adapter()
        items = deepcopy(self.jellyfin.items)
        for invalid in (
            [],
            [items[0], items[0]],
            [items[0]],
            [None],
            [dict(items[0], Id={})],
            [dict(items[0], CollectionType=[])],
        ):
            self.jellyfin.items = invalid
            self.seerr.writes.clear()
            before = deepcopy(self.seerr.settings)
            with self.assertRaises(reconcile.ReconcileError):
                self.run_adapter()
            self.assertEqual(self.seerr.settings, before)
            self.assertEqual(self.seerr.writes, [])

    def test_interrupted_fresh_library_write_is_idempotent(self):
        self.seerr.interrupt = True
        with self.assertRaises(OSError):
            self.run_adapter()
        self.assertEqual(self.enabled(), {"tv", "movies"})
        self.seerr.writes.clear()
        self.assertEqual(self.run_adapter(), [])
        self.assertEqual(self.seerr.writes, [])

    def test_concurrent_ui_edit_is_preserved_and_retried(self):
        self.jellyfin.on_discover = lambda: self.seerr.settings.update(
            externalHostname="https://changed.example.test"
        )
        with self.assertRaisesRegex(reconcile.ReconcileError, "changed during"):
            self.run_adapter()
        self.assertEqual(self.seerr.writes, [])
        self.jellyfin.on_discover = lambda: None
        self.run_adapter()
        self.assertEqual(
            self.seerr.settings["externalHostname"], "https://changed.example.test"
        )

    def test_admin_bootstrap_is_still_required(self):
        self.seerr.admin = False
        with self.assertRaisesRegex(
            reconcile.ReconcileError, "administrator bootstrap"
        ):
            self.run_adapter()
        self.assertEqual(self.jellyfin.calls, 0)
        self.assertEqual(self.seerr.writes, [])


if __name__ == "__main__":
    unittest.main()
